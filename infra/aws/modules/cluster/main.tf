# -----------------------------------------------------------------------------
# El cluster de EKS.
#
# RESTRICCION DEL LABORATORIO: no se pueden crear roles de IAM. Por eso aqui NO
# hay ningun aws_iam_role: se reutiliza el LabRole que la cuenta ya trae, que
# lleva adjuntas AmazonEKSClusterPolicy y AmazonEKSWorkerNodePolicy. En una
# cuenta normal se crearian dos roles separados, uno para el plano de control y
# otro para los nodos, con el minimo privilegio de cada uno.
#
# COSTE: el plano de control cobra 0,10 USD/hora desde que existe, se use o no.
# A partir de aqui, destruir al terminar cada sesion.
# -----------------------------------------------------------------------------

data "aws_iam_role" "lab" {
  name = "LabRole"
}

resource "aws_eks_cluster" "este" {
  name     = var.proyecto
  version  = var.version_kubernetes
  role_arn = data.aws_iam_role.lab.arn

  vpc_config {
    subnet_ids              = var.subredes_cluster
    endpoint_public_access  = true # para poder usar kubectl desde el portatil
    endpoint_private_access = true
  }

  # Sin esto no hay forma de investigar por que algo no arranca.
  enabled_cluster_log_types = ["api", "audit"]

  # Deja que quien crea el cluster (tu) tenga acceso automatico, y permite
  # anadir a mas gente con aws_eks_access_entry (ticket #43).
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
}

resource "aws_eks_node_group" "principal" {
  cluster_name    = aws_eks_cluster.este.name
  node_group_name = "${var.proyecto}-nodos"
  node_role_arn   = data.aws_iam_role.lab.arn
  subnet_ids      = var.subredes_nodos

  # SPOT cuesta ~70 % menos y AWS puede retirarte la maquina con dos minutos de
  # aviso. Para servicios sin estado que Kubernetes reprograma solo, es casi
  # gratis. Si el laboratorio no permite SPOT, cambia a "ON_DEMAND".
  capacity_type  = "SPOT"
  instance_types = [var.tipo_instancia]

  scaling_config {
    desired_size = var.numero_nodos
    min_size     = 0 # 0 permite APAGAR sin destruir el cluster
    max_size     = 3 # el laboratorio limita a 9 instancias
  }

  update_config {
    max_unavailable = 1
  }

  # Sin esto, Terraform intenta crear los nodos antes de que el plano de control
  # este listo y falla de forma confusa.
  depends_on = [aws_eks_cluster.este]

  lifecycle {
    # Para que escalar a 0 a mano (apagar) no lo revierta el siguiente apply.
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ---------------------------------- addons -----------------------------------
# CoreDNS, kube-proxy y el CNI. Se declaran explicitamente para fijar que
# existen; sin service_account_role_arn usan el rol del nodo (el LabRole).
#
# OJO: el LabRole no lleva AmazonEKS_CNI_Policy. Si los nodos entran Ready pero
# los pods se quedan en ContainerCreating con errores de red, es eso. No se
# puede adjuntar la politica (no hay permiso de IAM): habria que comprobar si
# las politicas VocLab ya lo cubren.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.este.name
  addon_name   = "vpc-cni"
  depends_on   = [aws_eks_node_group.principal]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.este.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.principal]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.este.name
  addon_name   = "kube-proxy"
  depends_on   = [aws_eks_node_group.principal]
}

# -----------------------------------------------------------------------------
# Acceso del balanceador a los NodePort.
#
# Un Service de tipo LoadBalancer crea un ELB que reparte contra un puerto alto
# de cada nodo (el rango 30000-32767). Normalmente el controlador de Kubernetes
# anade esta regla al grupo de seguridad de los nodos cuando crea el balanceador;
# aqui NO puede, porque el LabRole no le deja modificar grupos de seguridad.
#
# Sin ella, el ELB se crea "internet-facing" y con buena pinta, pero sus
# comprobaciones de salud nunca llegan: los nodos salen OutOfService y la tienda
# devuelve 000. El sintoma no menciona en ningun momento los grupos de seguridad.
#
# Se abre al CIDR de la VPC y no a 0.0.0.0/0: el balanceador vive dentro de la
# VPC y ademas hace SNAT, asi que todo el trafico que llega a los nodos tiene
# origen interno. Es mas estrecho que abrirlo a internet y suficiente.
# -----------------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "nodeports_desde_elb" {
  security_group_id = aws_eks_cluster.este.vpc_config[0].cluster_security_group_id

  description = "NodePort para los Service de tipo LoadBalancer"
  ip_protocol = "tcp"
  from_port   = 30000
  to_port     = 32767
  cidr_ipv4   = var.cidr_vpc

  tags = { Name = "${var.proyecto}-nodeports" }
}
