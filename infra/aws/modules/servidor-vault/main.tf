# -----------------------------------------------------------------------------
# La maquina de Vault: red propia, grupo de seguridad, instancia e IP elastica.
#
# Terraform crea, Ansible configura. Aqui NO se instala nada: ni user_data ni
# scripts de arranque. Lo que corre dentro de la maquina lo pone el rol de
# Ansible, y asi se puede revisar, repetir y destruir sin miedo.
#
# Por que no se reutiliza modules/red: esa red tiene la forma que exige EKS (dos
# zonas, subredes privadas, etiquetas de balanceador). Una sola maquina necesita
# una subred y una ruta a internet. Reutilizarla traeria recursos y etiquetas que
# aqui no significan nada.
# -----------------------------------------------------------------------------

data "aws_availability_zones" "disponibles" {
  state = "available"
}

# Ubuntu 24.04 LTS, la ultima imagen publicada por Canonical (su cuenta oficial).
# La version del sistema queda fija (24.04); el parche del dia, no. Ver el
# lifecycle de la instancia: por que una imagen nueva NO reemplaza la maquina.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ----------------------------------- red -------------------------------------
resource "aws_vpc" "vault" {
  cidr_block           = var.cidr_vpc
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.proyecto}-vault-vpc" }
}

resource "aws_internet_gateway" "vault" {
  vpc_id = aws_vpc.vault.id
  tags   = { Name = "${var.proyecto}-vault-igw" }
}

# Una sola subred publica. Sin IP publica automatica: la direccion la pone la IP
# elastica, que es la que no cambia.
resource "aws_subnet" "vault" {
  vpc_id                  = aws_vpc.vault.id
  cidr_block              = cidrsubnet(var.cidr_vpc, 8, 0)
  availability_zone       = data.aws_availability_zones.disponibles.names[0]
  map_public_ip_on_launch = false

  tags = { Name = "${var.proyecto}-vault-publica" }
}

resource "aws_route_table" "vault" {
  vpc_id = aws_vpc.vault.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vault.id
  }

  tags = { Name = "${var.proyecto}-vault-rt" }
}

resource "aws_route_table_association" "vault" {
  subnet_id      = aws_subnet.vault.id
  route_table_id = aws_route_table.vault.id
}

# ----------------------------- grupo de seguridad ----------------------------
# UNA regla de entrada: 8200. Es lo que pide la lamina, y el ADR 0020 es lo que
# lo hace posible: a la maquina se entra por SSM, sin puerto 22.
#
# 8200 abierto a 0.0.0.0/0 porque quienes llaman cambian de IP: los nodos del
# cluster (se recrean cada sesion) y el operador desde su casa. Lo que protege el
# puerto es TLS mas autenticacion, no la red (ADR 0019).
resource "aws_security_group" "vault" {
  name_prefix = "${var.proyecto}-vault-"
  description = "Vault: solo 8200 de entrada; salida web para paquetes y SSM"
  vpc_id      = aws_vpc.vault.id

  tags = { Name = "${var.proyecto}-vault" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "api_y_ui" {
  security_group_id = aws_security_group.vault.id

  description = "API y UI de Vault, por TLS"
  ip_protocol = "tcp"
  from_port   = 8200
  to_port     = 8200
  cidr_ipv4   = "0.0.0.0/0"

  tags = { Name = "${var.proyecto}-vault-8200" }
}

# La salida se limita a web. Es todo lo que la maquina necesita:
#   443  agente de SSM, repositorio de HashiCorp, llaves del emisor OIDC de EKS
#   80   los espejos de paquetes de Ubuntu (apt va por http; firma con GPG)
# El DNS y la hora van al resolvedor y al reloj de Amazon dentro de la VPC, que
# los grupos de seguridad no filtran.
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.vault.id

  description = "HTTPS saliente"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.vault.id

  description = "HTTP saliente, para apt"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_ipv4   = "0.0.0.0/0"
}

# --------------------------------- maquina -----------------------------------
# La llave publica para el SSH que viaja dentro del tunel SSM. La privada no
# pasa nunca por Terraform: solo se lee la .pub.
resource "aws_key_pair" "vault" {
  key_name   = "${var.proyecto}-vault"
  public_key = var.llave_publica
}

resource "aws_instance" "vault" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.tipo_instancia
  subnet_id              = aws_subnet.vault.id
  vpc_security_group_ids = [aws_security_group.vault.id]
  key_name               = aws_key_pair.vault.key_name

  # El permiso de SSM le llega por aqui. Se referencia por nombre: el perfil ya
  # existe en la cuenta del laboratorio y no se puede crear otro (ADR 0015).
  iam_instance_profile = var.perfil_instancia

  # Solo IMDSv2: los metadatos de la instancia (incluidas sus credenciales
  # temporales) exigen un token de sesion. Cierra el robo de credenciales por
  # SSRF, que con IMDSv1 es una peticion GET.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Vault guarda sus datos en este disco (almacenamiento en archivo). Cifrado en
  # reposo con la llave que AWS gestiona para EBS.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.disco_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${var.proyecto}-vault" }

  lifecycle {
    # SIN ESTO SE PIERDE VAULT. data.aws_ami busca la imagen mas reciente, y
    # Canonical publica una nueva cada pocas semanas. Cambiar 'ami' obliga a
    # REEMPLAZAR la instancia, y con ella el disco donde viven los datos de
    # Vault. Un 'terraform apply' cualquiera borraria el secreto en silencio.
    #
    # Asi, la imagen se elige al crear y despues no se toca. Las actualizaciones
    # del sistema las aplica Ansible. Para cambiar de imagen a proposito:
    #   terraform apply -replace=module.servidor_vault.aws_instance.vault
    ignore_changes = [ami]
  }
}

# La direccion fija. Cuando el laboratorio detiene la maquina, la IP publica
# normal se pierde y al volver es otra: cambiarian VAULT_ADDR y el certificado.
resource "aws_eip" "vault" {
  domain   = "vpc"
  instance = aws_instance.vault.id

  tags = { Name = "${var.proyecto}-vault-eip" }

  depends_on = [aws_internet_gateway.vault]
}
