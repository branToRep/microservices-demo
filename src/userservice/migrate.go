// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"context"
	_ "embed"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// El esquema viaja DENTRO del binario. Asi la imagen no depende de que alguien
// copie el .sql al contenedor ni de que exista un volumen: lo que se despliega
// lleva su propia migracion. Ver src/userservice/schema.sql.
//
//go:embed schema.sql
var esquema string

// aplicarEsquema corre schema.sql contra la base. Es idempotente —todo es
// CREATE ... IF NOT EXISTS— asi que repetirlo no rompe nada, y por eso se puede
// llamar en cada arranque sin comprobar antes si ya se aplico.
//
// Con varias replicas puede correr dos veces a la vez. No es un problema: los
// CREATE IF NOT EXISTS son seguros, y el peor caso es que una de las dos reciba
// un error de "ya existe" que Postgres resuelve sin dejar nada a medias.
func aplicarEsquema(ctx context.Context, pool *pgxpool.Pool) error {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	if _, err := pool.Exec(ctx, esquema); err != nil {
		return fmt.Errorf("aplicando schema.sql: %w", err)
	}
	return nil
}

// esperarBase reintenta hasta que Postgres conteste. Al desplegar, el servicio
// y la base arrancan a la vez y la base casi siempre tarda mas: sin esto, el
// pod se caeria en bucle hasta que Kubernetes lo acertara por casualidad.
func esperarBase(ctx context.Context, pool *pgxpool.Pool, intentos int, espera time.Duration) error {
	var ultimo error
	for i := 1; i <= intentos; i++ {
		pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		ultimo = pool.Ping(pingCtx)
		cancel()
		if ultimo == nil {
			return nil
		}
		if i < intentos {
			select {
			case <-time.After(espera):
			case <-ctx.Done():
				return ctx.Err()
			}
		}
	}
	return fmt.Errorf("la base no responde tras %d intentos: %w", intentos, ultimo)
}
