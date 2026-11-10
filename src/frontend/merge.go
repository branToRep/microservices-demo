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
	"os"

	"github.com/sirupsen/logrus"
)

// fusionarCarrito pasa al carrito de la cuenta lo que habia en el carrito
// anonimo de este navegador, y despues vacia el anonimo. Se llama al entrar y
// al registrarse.
//
// Las cantidades se SUMAN: AddItem de cartservice suma si el producto ya estaba
// en el carrito de la cuenta. Es lo que espera quien llena un carrito sin
// cuenta y luego entra.
//
// Es de mejor esfuerzo: un fallo aqui no impide entrar, solo se registra. Si
// pasar algun producto falla, el anonimo NO se vacia: es preferible que un
// producto quede repetido en los dos carritos a que se pierda.
func (fe *frontendServer) fusionarCarrito(ctx context.Context, log logrus.FieldLogger, anonimo, cuenta string) {
	if anonimo == "" || cuenta == "" || anonimo == cuenta {
		return
	}
	// Con ENABLE_SINGLE_SHARED_SESSION todos los anonimos comparten UN carrito:
	// fusionarlo daria a esta cuenta el carrito de todo el mundo.
	if os.Getenv("ENABLE_SINGLE_SHARED_SESSION") == "true" {
		return
	}

	items, err := fe.getCart(ctx, anonimo)
	if err != nil {
		log.WithField("err", err).Warn("no se pudo leer el carrito anonimo para fusionarlo")
		return
	}
	if len(items) == 0 {
		return
	}

	for _, it := range items {
		if err := fe.insertCart(ctx, cuenta, it.GetProductId(), it.GetQuantity()); err != nil {
			log.WithField("err", err).Warn("fusion del carrito incompleta: el anonimo se conserva")
			return
		}
	}
	if err := fe.emptyCart(ctx, anonimo); err != nil {
		log.WithField("err", err).Warn("carrito fusionado, pero no se pudo vaciar el anonimo")
		return
	}
	log.WithField("productos", len(items)).Info("carrito anonimo fusionado con el de la cuenta")
}
