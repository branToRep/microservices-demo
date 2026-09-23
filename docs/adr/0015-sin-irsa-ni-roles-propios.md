# 0015 · Se usa el LabRole; no se crean roles de IAM

- **Estado:** aceptada
- **Issues:** #40, #41, #45

## Contexto
La cuenta del laboratorio (rol `voclabs`) no permite crear roles de IAM. El
`LabRole` que ya existe confia en `eks.amazonaws.com` y lleva adjuntas
`AmazonEKSClusterPolicy` y `AmazonEKSWorkerNodePolicy`.

## Decision
El plano de control y el grupo de nodos usan el `LabRole` existente, obtenido
con `data "aws_iam_role" "lab"`. No se crea ningun rol.

Como IRSA consiste en crear un rol por ServiceAccount, el AWS Load Balancer
Controller queda descartado: el frontend se expone con un Service de tipo
LoadBalancer, que usa el permiso de `elasticloadbalancing` del LabRole.

## Alternativas descartadas
- Crear roles con minimo privilegio, uno para el cluster y otro para los nodos:
  es lo correcto en una cuenta normal, e imposible aqui.

## Consecuencias
Los nodos y el plano de control comparten un rol mas amplio de lo necesario.
Ademas el `LabRole` NO lleva `AmazonEKS_CNI_Policy`: si los pods se quedan en
`ContainerCreating`, la causa es esa y no se puede corregir desde el proyecto.
