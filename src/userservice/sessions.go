// Las sesiones viven en Redis, no en Postgres. Lo decidio la v2.1.0 y esta
// escrito al final de schema.sql: una sesion perdida obliga a volver a entrar,
// una cuenta perdida deja a alguien fuera para siempre. El ADR 0021 explica por
// que el contador de intentos si va en Postgres.
//
// Dos claves por sesion:
//
//	sesion:<token>            -> el id del usuario, con caducidad propia
//	usuario:<id>:sesiones     -> conjunto de tokens de esa persona
//
// El conjunto existe por ChangePassword: al cambiar la contrasena hay que
// cerrar las demas sesiones, y sin un indice no habria forma de saber cuales
// son. Puede contener tokens ya caducados; se limpian al leerlo.
package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"strconv"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/userservice/genproto"
)

const (
	prefijoSesion  = "sesion:"
	sufijoConjunto = ":sesiones"
	prefijoUsuario = "usuario:"
	bytesDelToken  = 32 // 256 bits: no se adivina por fuerza bruta
	margenConjunto = 24 * time.Hour
)

func claveSesion(token string) string { return prefijoSesion + token }

func claveConjunto(idUsuario string) string {
	return prefijoUsuario + idUsuario + sufijoConjunto
}

// nuevoToken genera el identificador opaco que viaja en la cookie. Opaco quiere
// decir que no lleva informacion dentro: solo sirve para buscarlo en Redis. Sale
// de crypto/rand —el generador criptografico— y no de math/rand, que es
// predecible y convertiria la sesion en algo adivinable.
func nuevoToken() (string, error) {
	b := make([]byte, bytesDelToken)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generando el token de sesion: %w", err)
	}
	// Sin relleno y seguro en URL: la cookie no necesita escaparse.
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// crearSesion abre una sesion para ese usuario y devuelve lo que el frontend
// guardara en la cookie.
func (s *servidor) crearSesion(ctx context.Context, idUsuario string) (*pb.Session, error) {
	token, err := nuevoToken()
	if err != nil {
		return nil, status.Error(codes.Internal, "no se pudo abrir la sesion")
	}

	segundos := int(s.cfg.duracionSesion.Seconds())
	if _, err := s.redis.do("SET", claveSesion(token), idUsuario, "EX", strconv.Itoa(segundos)); err != nil {
		return nil, status.Error(codes.Unavailable, "el almacen de sesiones no responde")
	}

	// El indice se actualiza despues de la sesion y su fallo no la invalida: una
	// sesion que funciona y no figura en el indice es un inconveniente; una
	// entrada en el indice sin sesion detras seria basura.
	clave := claveConjunto(idUsuario)
	if _, err := s.redis.do("SADD", clave, token); err == nil {
		// El conjunto vive un poco mas que la sesion mas larga para que no
		// desaparezca antes que los tokens que indexa.
		_, _ = s.redis.do("EXPIRE", clave, strconv.Itoa(segundos+int(margenConjunto.Seconds())))
	}

	return &pb.Session{
		SessionToken: token,
		UserId:       idUsuario,
		ExpiresAt:    time.Now().Add(s.cfg.duracionSesion).Unix(),
	}, nil
}

// ValidateSession traduce un token a una identidad, que es lo que el frontend
// hace en cada peticion autenticada.
func (s *servidor) ValidateSession(ctx context.Context, req *pb.ValidateSessionRequest) (*pb.Session, error) {
	token := req.GetSessionToken()
	if token == "" {
		return nil, status.Error(codes.InvalidArgument, "falta el token de sesion")
	}

	res, err := s.redis.do("GET", claveSesion(token))
	if err != nil {
		return nil, status.Error(codes.Unavailable, "el almacen de sesiones no responde")
	}
	if res == nil || res.null || res.str == "" {
		// Caducada o inventada: desde fuera son indistinguibles a proposito.
		return nil, status.Error(codes.Unauthenticated, "sesion invalida")
	}
	idUsuario := res.str

	// Cuanto le queda. Se pregunta en vez de guardarlo para que la respuesta
	// refleje la caducidad real de Redis y no una copia que pueda desviarse.
	expira := time.Now().Add(s.cfg.duracionSesion).Unix()
	if ttl, err := s.redis.do("TTL", claveSesion(token)); err == nil && ttl != nil && ttl.num > 0 {
		expira = time.Now().Add(time.Duration(ttl.num) * time.Second).Unix()
	}

	return &pb.Session{SessionToken: token, UserId: idUsuario, ExpiresAt: expira}, nil
}

// Logout cierra la sesion en el servidor. Borrar la cookie en el navegador no
// basta: un token robado seguiria sirviendo hasta caducar.
func (s *servidor) Logout(ctx context.Context, req *pb.LogoutRequest) (*pb.UserEmpty, error) {
	token := req.GetSessionToken()
	if token == "" {
		return nil, status.Error(codes.InvalidArgument, "falta el token de sesion")
	}

	// Se mira primero de quien es, para poder sacarlo tambien del indice.
	var idUsuario string
	if res, err := s.redis.do("GET", claveSesion(token)); err == nil && res != nil && !res.null {
		idUsuario = res.str
	}

	if _, err := s.redis.do("DEL", claveSesion(token)); err != nil {
		return nil, status.Error(codes.Unavailable, "el almacen de sesiones no responde")
	}
	if idUsuario != "" {
		_, _ = s.redis.do("SREM", claveConjunto(idUsuario), token)
	}

	// Cerrar una sesion que ya no existe no es un error: el resultado que pedia
	// quien llama —que ese token no valga— se cumple igual.
	return &pb.UserEmpty{}, nil
}

// revocarOtrasSesiones cierra todas las de un usuario menos la que se indique.
// La usa ChangePassword: quien cambia su contrasena espera que las sesiones
// abiertas en otros sitios dejen de valer, pero no que lo echen de la suya.
func (s *servidor) revocarOtrasSesiones(ctx context.Context, idUsuario, conservar string) error {
	clave := claveConjunto(idUsuario)
	res, err := s.redis.do("SMEMBERS", clave)
	if err != nil {
		return err
	}
	for _, token := range res.strings() {
		if token == conservar {
			continue
		}
		if _, err := s.redis.do("DEL", claveSesion(token)); err != nil {
			return err
		}
		_, _ = s.redis.do("SREM", clave, token)
	}
	return nil
}
