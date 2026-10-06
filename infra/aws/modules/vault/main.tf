# -----------------------------------------------------------------------------
# El servidor de HashiCorp Vault.
#
# POR QUE FUERA DEL CLUSTER: el cluster se destruye al acabar cada sesion
# (apagar.sh). Si Vault viviera dentro, cada tarde se perderian los secretos, las
# politicas y las llaves de Shamir. Aqui vive en su propia maquina y en su propio
# estado de Terraform, que apagar.sh no toca. Ver el ADR 0019.
#
# QUE SE ABRE A INTERNET: solo el 8200, y siempre con TLS. El 22 NO se abre:
# Ansible y las personas entran por AWS Systems Manager (Session Manager), que
# autentica con las credenciales de AWS y no con la IP. Asi funciona desde
# cualquier red sin tocar el grupo de seguridad.
#
# COSTE (us-east-1, aprox.): t3.small 0,021 USD/h + IP elastica 0,005 USD/h +
# 18 GB de gp3 ~1,5 USD/mes. Con el laboratorio cerrado la instancia se detiene
# y solo cuentan la IP y los discos.
# -----------------------------------------------------------------------------

# Amazon Linux 2023: trae el agente de SSM instalado y arrancado, que es lo unico
# imprescindible para entrar sin SSH. El id de una AMI publica no es secreto:
# insecure_value lo deja ver en el plan.
data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ------------------------------ grupo de seguridad ----------------------------
resource "aws_security_group" "vault" {
  name_prefix = "${var.proyecto}-vault-"
  description = "Vault: API y UI por 8200 con TLS. Sin SSH."
  vpc_id      = var.vpc_id

  tags = { Name = "${var.proyecto}-vault" }

  lifecycle {
    create_before_destroy = true
  }
}

# Una regla por recurso (y no bloques ingress{} en linea): se pueden anadir o
# quitar sin que Terraform reescriba el grupo entero.
resource "aws_vpc_security_group_ingress_rule" "api_vault" {
  for_each = toset(var.cidrs_api_vault)

  security_group_id = aws_security_group.vault.id
  description       = "API y UI de Vault (HTTPS)"
  ip_protocol       = "tcp"
  from_port         = 8200
  to_port           = 8200
  cidr_ipv4         = each.value

  tags = { Name = "${var.proyecto}-vault-8200" }
}

# Salida abierta: el agente de SSM, los repositorios de paquetes y el JWKS de
# GitHub (token.actions.githubusercontent.com) estan todos en internet.
resource "aws_vpc_security_group_egress_rule" "todo" {
  security_group_id = aws_security_group.vault.id
  description       = "SSM, paquetes y el JWKS de GitHub"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------- instancia ---------------------------------
resource "aws_instance" "vault" {
  ami                    = data.aws_ssm_parameter.ami.insecure_value
  instance_type          = var.tipo_instancia
  subnet_id              = var.subred
  vpc_security_group_ids = [aws_security_group.vault.id]

  # El laboratorio no deja crear roles (ADR 0015). LabInstanceProfile ya existe
  # y es el que permite que el agente de SSM de la instancia se registre. Se
  # pasa por nombre, sin data source, para no depender de permisos de lectura
  # de IAM.
  iam_instance_profile = var.perfil_instancia

  # Sin key_name a proposito: no hay llave SSH que repartir ni que perder.

  # IMDSv2 obligatorio: cierra el robo de credenciales del rol por SSRF.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = {
    # Name lo usa la consola; Rol, el inventario dinamico de Ansible para
    # encontrar la maquina.
    Name = "${var.proyecto}-vault"
    Rol  = "vault"
  }

  lifecycle {
    # El parametro de la AMI apunta a "la mas reciente". Sin esto, cada
    # publicacion de Amazon Linux reemplazaria la instancia. Los datos estan en
    # el disco aparte, pero no hay motivo para provocarlo.
    ignore_changes = [ami]
  }
}

# ------------------------------- disco de datos -------------------------------
# Los datos de Vault (almacenamiento Raft), sus certificados y la auditoria viven
# en un disco PROPIO. Si la instancia se reemplaza, el disco se vuelve a montar
# en la nueva y Vault sigue con los mismos secretos y las mismas llaves.
resource "aws_ebs_volume" "datos" {
  availability_zone = aws_instance.vault.availability_zone
  size              = var.tamano_disco_datos
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${var.proyecto}-vault-datos" }
}

resource "aws_volume_attachment" "datos" {
  # Ansible lo busca por el id del volumen, no por este nombre: en las
  # instancias Nitro el kernel lo llama /dev/nvme1n1 de todas formas.
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.datos.id
  instance_id = aws_instance.vault.id

  # Desmontar un disco con Vault escribiendo encima puede corromper Raft. Si
  # alguna vez hay que soltarlo, primero se detiene la instancia.
  stop_instance_before_detaching = true
}

# --------------------------------- IP elastica --------------------------------
# Sin ella, la IP publica cambia cada vez que el laboratorio detiene y arranca
# la instancia, y con ella VAULT_ADDR y el certificado TLS.
resource "aws_eip" "vault" {
  domain = "vpc"
  tags   = { Name = "${var.proyecto}-vault" }
}

resource "aws_eip_association" "vault" {
  instance_id   = aws_instance.vault.id
  allocation_id = aws_eip.vault.id
}
