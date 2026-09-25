# -----------------------------------------------------------------------------
# La red. Dos zonas de disponibilidad porque EKS lo exige: con una sola, la
# creacion del cluster falla.
#
# Las etiquetas kubernetes.io/role/elb NO son decorativas: son como el
# controlador de balanceadores descubre en que subredes puede crear un ELB.
# Sin ellas, un Service de tipo LoadBalancer se queda en <pending> para siempre
# y el error no dice por que.
# -----------------------------------------------------------------------------

data "aws_availability_zones" "disponibles" {
  state = "available"
}

resource "aws_vpc" "esta" {
  cidr_block           = var.cidr_vpc
  enable_dns_hostnames = true # EKS lo necesita
  enable_dns_support   = true

  tags = { Name = "${var.proyecto}-vpc" }
}

resource "aws_internet_gateway" "esta" {
  vpc_id = aws_vpc.esta.id
  tags   = { Name = "${var.proyecto}-igw" }
}

# ---------------------------- subredes publicas ------------------------------
resource "aws_subnet" "publica" {
  count = 2

  vpc_id                  = aws_vpc.esta.id
  cidr_block              = cidrsubnet(var.cidr_vpc, 8, count.index)
  availability_zone       = data.aws_availability_zones.disponibles.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.proyecto}-publica-${count.index}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.esta.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.esta.id
  }

  tags = { Name = "${var.proyecto}-rt-publica" }
}

resource "aws_route_table_association" "publica" {
  count          = 2
  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

# ---------------------------- subredes privadas ------------------------------
# Se crean siempre (son gratis). Lo que cuesta dinero es el NAT, y ese solo
# aparece si crear_nat = true.
resource "aws_subnet" "privada" {
  count = 2

  vpc_id            = aws_vpc.esta.id
  cidr_block        = cidrsubnet(var.cidr_vpc, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.disponibles.names[count.index]

  tags = {
    Name                              = "${var.proyecto}-privada-${count.index}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# UN SOLO NAT, no uno por zona: un tercio del precio. Menos disponible, y para
# un entorno que se destruye cada tarde es la eleccion obvia.
resource "aws_eip" "nat" {
  count  = var.crear_nat ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${var.proyecto}-eip-nat" }
}

resource "aws_nat_gateway" "este" {
  count = var.crear_nat ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.publica[0].id
  depends_on    = [aws_internet_gateway.esta]

  tags = { Name = "${var.proyecto}-nat" }
}

resource "aws_route_table" "privada" {
  vpc_id = aws_vpc.esta.id

  dynamic "route" {
    for_each = var.crear_nat ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.este[0].id
    }
  }

  tags = { Name = "${var.proyecto}-rt-privada" }
}

resource "aws_route_table_association" "privada" {
  count          = 2
  subnet_id      = aws_subnet.privada[count.index].id
  route_table_id = aws_route_table.privada.id
}
