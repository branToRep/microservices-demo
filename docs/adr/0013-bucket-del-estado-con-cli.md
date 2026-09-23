# 0013 · El bucket del estado se crea con la CLI, no con Terraform

- **Estado:** aceptada
- **Issue:** #37

## Contexto
La organizacion del laboratorio aplica una SCP que deniega
`s3:GetBucketObjectLockConfiguration`. El proveedor de AWS relee el bucket tras
crearlo e incluye esa consulta, asi que `terraform apply` falla aunque el bucket
se haya creado correctamente.

## Decision
El bucket del estado se crea con `aws s3api` mediante
`infra/aws/bootstrap/crear-bucket-estado.sh`. Terraform no lo gestiona.

## Alternativas descartadas
- Gestionarlo con Terraform: imposible con esta SCP.
- Usar HCP Terraform para el estado: evitaria S3, pero anade un servicio externo
  al alcance del proyecto.

## Consecuencias
El bucket queda fuera del ciclo de vida de Terraform: no se destruye con
`terraform destroy`. A cambio, el resto del proyecto no pelea con la politica
del laboratorio.
