# -----------------------------------------------------------------------------
# Cablea los modulos. La salida de uno es la entrada del siguiente, y ese es el
# unico orden posible: Terraform se niega a construirlo de otra forma.
#
#   red  ->  cluster
# -----------------------------------------------------------------------------

module "red" {
  source = "../../modules/red"

  proyecto  = var.proyecto
  cidr_vpc  = var.cidr_vpc
  crear_nat = var.crear_nat
}

# -----------------------------------------------------------------------------
# El cluster de EKS (ticket #40).
#
# COSTE: el plano de control cobra 0,10 USD/hora desde que existe, se use o no,
# mas los dos nodos. Destruir al terminar cada sesion.
# -----------------------------------------------------------------------------
module "cluster" {
  source = "../../modules/cluster"

  proyecto           = var.proyecto
  version_kubernetes = var.version_kubernetes
  tipo_instancia     = var.tipo_instancia
  numero_nodos       = var.numero_nodos

  # Si no hay NAT, los nodos viven en las publicas. Si lo hay, en las privadas.
  subredes_cluster = module.red.subredes_publicas
  subredes_nodos   = var.crear_nat ? module.red.subredes_privadas : module.red.subredes_publicas
}
