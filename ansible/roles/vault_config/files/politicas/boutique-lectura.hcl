# boutique-lectura - la del cluster (ADR 0019 y 0020).
#
# Minimo privilegio: LEER, y solo las rutas que estan aqui. Nada de listar,
# escribir ni borrar, y nada fuera de esas rutas. Si quien la usa se ve
# comprometido, lo unico que se lleva son los valores que ya tenia en memoria.
#
# Una ruta por secreto, enumeradas: un comodin (secret/data/boutique/*) seria
# una linea menos y daria acceso a todo lo que se guarde ahi en el futuro, que
# es exactamente lo que esta politica existe para evitar.
#
# Cada ruta tiene que estar tambien en charts/boutique/values.yaml
# (vault.secretos), o el Secret de Kubernetes no se crea.

# La contrasena de redis-cart.
path "secret/data/boutique/redis-cart" {
  capabilities = ["read"]
}

# La contrasena del Redis de sesiones.
path "secret/data/boutique/redis-sessions" {
  capabilities = ["read"]
}

# La contrasena de la base del userservice.
path "secret/data/boutique/postgres" {
  capabilities = ["read"]
}
