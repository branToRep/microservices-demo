# -----------------------------------------------------------------------------
# El entorno de Vault. Vive aparte del de dev para que apagar.sh no lo destruya.
#
#   red  ->  vault
#
# La red es el MISMO modulo que usa dev, con otro rango: 10.1.0.0/16 y no
# 10.0.0.0/16, para que las dos VPC se puedan emparejar algun dia sin chocar.
# Sin NAT: la instancia va en una subred publica, con IP elastica.
# -----------------------------------------------------------------------------
module "red" {
  source = "../../modules/red"

  proyecto  = "${var.proyecto}-vault"
  cidr_vpc  = var.cidr_vpc
  crear_nat = false
}

module "vault" {
  source = "../../modules/vault"

  proyecto           = var.proyecto
  vpc_id             = module.red.vpc_id
  subred             = module.red.subredes_publicas[0]
  tipo_instancia     = var.tipo_instancia
  tamano_disco_datos = var.tamano_disco_datos
  cidrs_api_vault    = var.cidrs_api_vault
}
