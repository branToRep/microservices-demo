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

// La sesion de una cuenta en el frontend: el cliente del userservice, la cookie
// de sesion, la proteccion CSRF y el middleware que resuelve quien es quien.
// Las decisiones y sus limites estan en el ADR 0024.

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"net/http"
	"os"
	"time"

	"github.com/sirupsen/logrus"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/frontend/genproto"
)

const (
	cookieSesion = cookiePrefix + "sesion"
	cookieCSRF   = cookiePrefix + "csrf"
	campoCSRF    = "csrf_token"
)

var (
	// La marca Secure de las cookies de sesion y de CSRF. Apagada por defecto
	// porque la tienda se sirve por HTTP: una cookie Secure no viajaria y el
	// inicio de sesion fallaria sin ningun error visible. COOKIE_SEGURA=1 en
	// cuanto el balanceador tenga TLS (ADR 0024).
	cookieSegura = os.Getenv("COOKIE_SEGURA") == "1"

	// Cuanto se espera al userservice en cada llamada. withUser lo llama en
	// cada peticion que trae cookie de sesion, asi que un servicio lento no
	// puede dejar la tienda entera esperando.
	userSvcTimeout = duracionEnv("USER_SERVICE_TIMEOUT", 3*time.Second)

	// Lo mismo para entrar, registrarse, cambiar la contrasena y eliminar la
	// cuenta, que hacen bcrypt, LENTO A PROPOSITO (es lo que encarece un
	// ataque por fuerza bruta). Cambiar la contrasena hace dos. Medido en el
	// cluster con el limite de CPU de antes (200m): una operacion, entre 0,5 y
	// 1 s; cambiar la contrasena, 3,1 s, por encima de los 3 s del limite
	// general. Por eso van con su propio limite, mas holgado, y no con el de
	// cada pagina.
	userSvcTimeoutClaves = duracionEnv("USER_SERVICE_TIMEOUT_CLAVES", 10*time.Second)
)

func duracionEnv(clave string, porDefecto time.Duration) time.Duration {
	if v := os.Getenv(clave); v != "" {
		if d, err := time.ParseDuration(v); err == nil && d > 0 {
			return d
		}
	}
	return porDefecto
}

// ------------------------------------------------------- el cliente

// userSvc se arma en main(), como wishlistSvc, y es global por la misma razon:
// el middleware y los manejadores lo usan sin pasar por frontendServer.
var userSvc *usuarioClient

type usuarioClient struct {
	c pb.UserServiceClient
}

func newUserClient(conn *grpc.ClientConn) *usuarioClient {
	return &usuarioClient{c: pb.NewUserServiceClient(conn)}
}

func (u *usuarioClient) register(ctx context.Context, email, password, nombre, apellido string) (*pb.AuthResponse, error) {
	ctx, cancel := context.WithTimeout(ctx, userSvcTimeoutClaves)
	defer cancel()
	return u.c.CreateUser(ctx, &pb.CreateUserRequest{
		Email: email, Password: password, FirstName: nombre, LastName: apellido,
	})
}

func (u *usuarioClient) login(ctx context.Context, email, password string) (*pb.AuthResponse, error) {
	ctx, cancel := context.WithTimeout(ctx, userSvcTimeoutClaves)
	defer cancel()
	return u.c.Authenticate(ctx, &pb.AuthenticateRequest{Email: email, Password: password})
}

func (u *usuarioClient) validate(ctx context.Context, token string) (*pb.Session, error) {
	ctx, cancel := context.WithTimeout(ctx, userSvcTimeout)
	defer cancel()
	return u.c.ValidateSession(ctx, &pb.ValidateSessionRequest{SessionToken: token})
}

func (u *usuarioClient) logout(ctx context.Context, token string) error {
	ctx, cancel := context.WithTimeout(ctx, userSvcTimeout)
	defer cancel()
	_, err := u.c.Logout(ctx, &pb.LogoutRequest{SessionToken: token})
	return err
}

func (u *usuarioClient) get(ctx context.Context, userID string) (*pb.User, error) {
	ctx, cancel := context.WithTimeout(ctx, userSvcTimeout)
	defer cancel()
	return u.c.GetUser(ctx, &pb.GetUserRequest{UserId: userID})
}

func (u *usuarioClient) updateProfile(ctx context.Context, req *pb.UpdateProfileRequest) (*pb.User, error) {
	ctx, cancel := context.WithTimeout(ctx, userSvcTimeout)
	defer cancel()
	return u.c.UpdateProfile(ctx, req)
}

// changePassword conserva la sesion desde la que se cambia (conservar) y el
// servicio cierra todas las demas: es lo que espera quien cambia su contrasena
// porque cree que alguien mas la conoce.
func (u *usuarioClient) changePassword(ctx context.Context, userID, actual, nueva, conservar string) error {
	ctx, cancel := context.WithTimeout(ctx, userSvcTimeoutClaves)
	defer cancel()
	_, err := u.c.ChangePassword(ctx, &pb.ChangePasswordRequest{
		UserId: userID, CurrentPassword: actual, NewPassword: nueva, KeepSessionToken: conservar,
	})
	return err
}

// deleteUser borra la cuenta. Usa el plazo largo porque el servicio comprueba
// la contrasena con bcrypt antes de borrar nada.
func (u *usuarioClient) deleteUser(ctx context.Context, userID, contrasena string) error {
	ctx, cancel := context.WithTimeout(ctx, userSvcTimeoutClaves)
	defer cancel()
	_, err := u.c.DeleteUser(ctx, &pb.DeleteUserRequest{UserId: userID, Password: contrasena})
	return err
}

// ------------------------------------------------------- la sesion en la peticion

type ctxKeyUsuario struct{}
type ctxKeyCSRF struct{}

// sesionUsuario es lo que withUser deja en el contexto si la cookie es valida.
// No lleva nombre ni correo: solo la pagina de cuenta los necesita y los pide
// con GetUser. Asi cada peticion paga una llamada al servicio, no dos.
type sesionUsuario struct {
	ID    string
	Token string
}

// currentUser devuelve la cuenta de esta peticion, o nil si no hay sesion. Un
// puntero nil en una plantilla cuenta como falso, asi que {{ if $.user }} basta.
func currentUser(r *http.Request) *sesionUsuario {
	u, _ := r.Context().Value(ctxKeyUsuario{}).(*sesionUsuario)
	return u
}

func authToken(r *http.Request) string {
	c, err := r.Cookie(cookieSesion)
	if err != nil {
		return ""
	}
	return c.Value
}

// cartID es la llave del carrito: la cuenta si hay sesion, la sesion anonima si
// no.
func cartID(r *http.Request) string {
	if u := currentUser(r); u != nil {
		return u.ID
	}
	return sessionID(r)
}

// wishlistID es la llave de las listas de deseos, con la misma regla que el
// carrito. Hasta la 3.1.0 eran por navegador (sessionID), y dos cuentas que
// entraban desde el mismo navegador veian y tocaban las mismas listas.
func wishlistID(r *http.Request) string {
	return cartID(r)
}

// ------------------------------------------------------- las cookies

// rutaCookie fija la ruta en vez de dejar la del navegador por defecto, que es
// el directorio de la URL donde se puso: una cookie puesta en /account no se
// mandaria a la portada.
func rutaCookie() string {
	return baseUrl + "/"
}

func ponerCookieSesion(w http.ResponseWriter, s *pb.Session) {
	maxAge := int(s.GetExpiresAt() - time.Now().Unix())
	if maxAge <= 0 {
		maxAge = -1
	}
	http.SetCookie(w, &http.Cookie{
		Name:     cookieSesion,
		Value:    s.GetSessionToken(),
		Path:     rutaCookie(),
		MaxAge:   maxAge,
		HttpOnly: true, // ningun JavaScript de la pagina puede leer el token
		Secure:   cookieSegura,
		SameSite: http.SameSiteLaxMode, // no viaja en un POST desde otro sitio
	})
}

func borrarCookieSesion(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     cookieSesion,
		Value:    "",
		Path:     rutaCookie(),
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   cookieSegura,
		SameSite: http.SameSiteLaxMode,
	})
}

// ------------------------------------------------------- CSRF

// El patron es el de la cookie doble: un valor aleatorio en una cookie y el
// mismo valor en un campo oculto de cada formulario de cuentas. Otro sitio
// puede hacer que el navegador ENVIE la cookie, pero no puede LEERLA para
// copiarla en el formulario. No necesita ningun secreto del servidor.

func nuevoTokenCSRF() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// csrfFromRequest es el valor que las plantillas meten en el campo oculto.
func csrfFromRequest(r *http.Request) string {
	v, _ := r.Context().Value(ctxKeyCSRF{}).(string)
	return v
}

// csrfValido compara en tiempo constante, para no dar pistas por cuanto tarda.
func csrfValido(r *http.Request) bool {
	c, err := r.Cookie(cookieCSRF)
	if err != nil || c.Value == "" {
		return false
	}
	enviado := r.PostFormValue(campoCSRF)
	if enviado == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(c.Value), []byte(enviado)) == 1
}

// ------------------------------------------------------- el middleware

// withUser resuelve la cuenta de cada peticion y garantiza el token CSRF.
//
// El token tiene que existir en TODAS las paginas, no solo en las de cuentas:
// el formulario de "Salir" va en el encabezado.
//
// Si la cookie de sesion ya no vale (caducada o cerrada), se borra. Si el
// servicio no contesta, la peticion se sirve como anonima pero la cookie NO se
// borra: la sesion vuelve sola cuando vuelva el servicio.
func withUser(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		log, _ := ctx.Value(ctxKeyLog{}).(logrus.FieldLogger)

		token := ""
		if c, err := r.Cookie(cookieCSRF); err == nil && c.Value != "" {
			token = c.Value
		} else if t, err := nuevoTokenCSRF(); err == nil {
			token = t
			http.SetCookie(w, &http.Cookie{
				Name:     cookieCSRF,
				Value:    t,
				Path:     rutaCookie(),
				MaxAge:   cookieMaxAge,
				HttpOnly: true,
				Secure:   cookieSegura,
				SameSite: http.SameSiteLaxMode,
			})
		} else if log != nil {
			log.WithField("err", err).Warn("no se pudo generar el token CSRF")
		}
		ctx = context.WithValue(ctx, ctxKeyCSRF{}, token)

		if t := authToken(r); t != "" && userSvc != nil {
			s, err := userSvc.validate(ctx, t)
			switch status.Code(err) {
			case codes.OK:
				ctx = context.WithValue(ctx, ctxKeyUsuario{}, &sesionUsuario{ID: s.GetUserId(), Token: t})
			case codes.Unauthenticated, codes.InvalidArgument:
				borrarCookieSesion(w)
			default:
				if log != nil {
					log.WithField("err", err).Warn("no se pudo validar la sesion; se sirve como anonima")
				}
			}
		}

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
