# boutique-lectura — la del cluster (ADR 0019 y 0020).
#
# Minimo privilegio: LEER una sola ruta. Nada de listar, escribir ni borrar, y
# nada fuera de esa ruta. Si quien la usa se ve comprometido, lo unico que se
# lleva es la contrasena de Redis, que ya tenia.
path "secret/data/boutique/redis-cart" {
  capabilities = ["read"]
}
