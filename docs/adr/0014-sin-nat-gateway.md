# 0014 · Los nodos van en subredes publicas, sin NAT Gateway

- **Estado:** aceptada
- **Issue:** #39

## Contexto
Un NAT Gateway cuesta ~33 USD/mes mas 0,045 USD/GB procesado: mas que las
propias instancias del cluster. El credito del laboratorio es limitado.

## Decision
`crear_nat = false`. Los nodos viven en subredes publicas con IP publica. Las
subredes privadas se crean igualmente (son gratis) por si se activa despues.

## Alternativas descartadas
- Un NAT por zona: el doble de caro, innecesario en un entorno efimero.
- Endpoints de VPC para ECR, S3 y CloudWatch: es la respuesta correcta en
  produccion y la mas laboriosa de configurar.

## Consecuencias
Los nodos quedan expuestos a internet, protegidos solo por grupos de seguridad.
NO es lo que se haria en produccion. Se acepta porque el entorno es efimero y
el ahorro es la mitad de la factura.
