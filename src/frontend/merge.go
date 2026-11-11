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

// fusionarListas pasa a la cuenta las listas de deseos que este navegador hizo
// sin sesion, y despues borra las anonimas. Se llama al entrar y al registrarse,
// igual que fusionarCarrito, y con sus mismas reglas: de mejor esfuerzo, y una
// lista anonima solo se borra si TODOS sus productos llegaron a la cuenta.
//
// Una lista con el mismo nombre que una de la cuenta se junta con ella (los
// productos repetidos no se duplican: AddWishlistItem es idempotente). Si no,
// se crea con ese nombre.
func (fe *frontendServer) fusionarListas(ctx context.Context, log logrus.FieldLogger, anonimo, cuenta string) {
	if wishlistSvc == nil || anonimo == "" || cuenta == "" || anonimo == cuenta {
		return
	}
	if os.Getenv("ENABLE_SINGLE_SHARED_SESSION") == "true" {
		return
	}

	anonimas, err := wishlistSvc.lists(ctx, anonimo)
	if err != nil {
		log.WithField("err", err).Warn("no se pudieron leer las listas anonimas para fusionarlas")
		return
	}
	if len(anonimas) == 0 {
		return
	}
	propias, err := wishlistSvc.lists(ctx, cuenta)
	if err != nil {
		log.WithField("err", err).Warn("no se pudieron leer las listas de la cuenta para fusionar")
		return
	}
	porNombre := map[string]string{}
	for _, l := range propias {
		porNombre[l.GetName()] = l.GetId()
	}

	pasadas := 0
	for _, a := range anonimas {
		completa, err := wishlistSvc.get(ctx, anonimo, a.GetId())
		if err != nil {
			log.WithField("err", err).Warn("fusion de listas incompleta: la anonima se conserva")
			continue
		}
		destino, ok := porNombre[a.GetName()]
		if !ok {
			nueva, err := wishlistSvc.create(ctx, cuenta, a.GetName())
			if err != nil {
				log.WithField("err", err).Warn("no se pudo crear la lista en la cuenta: la anonima se conserva")
				continue
			}
			destino = nueva.GetId()
			porNombre[a.GetName()] = destino
		}
		todo := true
		for _, it := range completa.GetItems() {
			if err := wishlistSvc.addItem(ctx, cuenta, destino, it.GetProductId()); err != nil {
				log.WithField("err", err).Warn("fusion de listas incompleta: la anonima se conserva")
				todo = false
				break
			}
		}
		if !todo {
			continue
		}
		if err := wishlistSvc.remove(ctx, anonimo, a.GetId()); err != nil {
			log.WithField("err", err).Warn("lista fusionada, pero no se pudo borrar la anonima")
			continue
		}
		pasadas++
	}
	log.WithField("listas", pasadas).Info("listas anonimas fusionadas con las de la cuenta")
}

// borrarListas borra todas las listas de deseos de una cuenta. La usa eliminar
// la cuenta; de mejor esfuerzo, porque la cuenta ya no existe y nadie volveria a
// pedirlas (caducan solas en el wishlistservice).
func (fe *frontendServer) borrarListas(ctx context.Context, log logrus.FieldLogger, cuenta string) {
	if wishlistSvc == nil || cuenta == "" {
		return
	}
	listas, err := wishlistSvc.lists(ctx, cuenta)
	if err != nil {
		log.WithField("err", err).Warn("cuenta eliminada, pero no se pudieron leer sus listas")
		return
	}
	for _, l := range listas {
		if err := wishlistSvc.remove(ctx, cuenta, l.GetId()); err != nil {
			log.WithField("err", err).Warn("cuenta eliminada, pero no se pudo borrar una de sus listas")
		}
	}
}
