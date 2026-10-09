# -----------------------------------------------------------------------------
# La maquina de Vault (ADR 0019 y 0020). Un solo modulo: red propia, grupo de
# seguridad, instancia e IP elastica.
#
# VIVE APARTE A PROPOSITO. apagar.sh destruye envs/dev en cada sesion; si Vault
# estuviera ahi, se perderian sus datos cada dia y habria que reinicializarla.
# Este entorno no lo toca ningun script: se crea una vez y se queda.
#
# COSTE mientras exista: la IP elastica (~0,005 USD/h) y el disco (~0,08 USD/GB
# al mes). La instancia solo cobra encendida, y el laboratorio la detiene al
# cerrar la sesion.
# -----------------------------------------------------------------------------

module "servidor_vault" {
  source = "../../modules/servidor-vault"

  proyecto         = var.proyecto
  cidr_vpc         = var.cidr_vpc
  tipo_instancia   = var.tipo_instancia
  perfil_instancia = var.perfil_instancia
  llave_publica    = file(pathexpand(var.ruta_llave_publica))
  disco_gb         = var.disco_gb
}
