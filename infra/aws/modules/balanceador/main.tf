# -----------------------------------------------------------------------------
# El balanceador del frontend, declarado por nosotros.
#
# POR QUE NO LO HACE KUBERNETES:
# Un Service de tipo LoadBalancer normalmente hace que el controlador de la nube
# cree el ELB, lo mantenga y lo borre. En este laboratorio NO puede: el LabRole
# no le da permisos de escritura sobre ELB ni sobre grupos de seguridad. El
# sintoma fue un ELB creado una sola vez, con la comprobacion de salud apuntando
# a un nodePort viejo, que ni se actualizaba ni se borraba al borrar el Service.
#
# Asi que el Service pasa a ser NodePort con un puerto FIJO, y el balanceador lo
# declara Terraform. Es mas codigo, y a cambio es reproducible: destruir y
# recrear el entorno da exactamente lo mismo.
#
# COSTE: un ELB clasico son ~0,025 USD/hora. Se destruye con terraform destroy.
# -----------------------------------------------------------------------------

resource "aws_security_group" "elb" {
  name_prefix = "${var.proyecto}-elb-"
  description = "Entrada HTTP publica al frontend"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP desde internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Hacia los nodos"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.proyecto}-elb" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elb" "frontend" {
  name            = "${var.proyecto}-frontend"
  subnets         = var.subredes_publicas
  security_groups = [aws_security_group.elb.id]

  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = var.nodeport_frontend
    instance_protocol = "http"
  }

  # La comprobacion apunta al MISMO puerto fijo que el listener. Aqui estaba el
  # fallo de la version gestionada por Kubernetes: comprobaba un puerto que ya
  # no existia.
  health_check {
    target              = "TCP:${var.nodeport_frontend}"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 6
  }

  # Los dos nodos estan en zonas distintas y el frontend puede correr en
  # cualquiera: sin esto, la mitad del trafico iria a una zona sin pod.
  cross_zone_load_balancing = true
  idle_timeout              = 60

  tags = { Name = "${var.proyecto}-frontend" }
}

# Registra los nodos automaticamente, ahora y cuando el grupo escale o los
# reemplace. Es lo que hace que apagar y encender no exija tocar nada.
resource "aws_autoscaling_attachment" "nodos" {
  autoscaling_group_name = var.asg_nodos
  elb                    = aws_elb.frontend.id
}
