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

// Las rutas de cuentas: entrar, registrarse, ver y editar la cuenta, cambiar la
// contrasena, salir y eliminar la cuenta (v3.1.0). Llevan los nombres que dejo el cableado de pruebas que
// quito la 1.5.1 (ADR 0017), para que encajen con aquel mapa.
//
// Todo POST de cuentas exige el token CSRF (auth.go). Los errores que son de
// la persona (contrasena mala, correo repetido) vuelven al formulario con su
// mensaje y su codigo HTTP; los del sistema van a la pagina de error.

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/frontend/genproto"
)

// ------------------------------------------------------- utilidades

// respuestaCuenta traduce un error del userservice al mensaje que ve la persona
// y al codigo HTTP. Cada manejador da sus propios mensajes por codigo, porque el
// mismo Unauthenticated significa "correo o contrasena incorrectos" al entrar y
// "la contrasena actual no es correcta" al cambiarla. Lo que no traiga mensaje
// propio usa el del servicio. ok es false si el error es del sistema.
func respuestaCuenta(err error, mensajes map[codes.Code]string) (string, int, bool) {
	st, _ := status.FromError(err)
	codigo, esDeLaPersona := map[codes.Code]int{
		codes.InvalidArgument:   http.StatusBadRequest,
		codes.Unauthenticated:   http.StatusUnauthorized,
		codes.AlreadyExists:     http.StatusConflict,
		codes.ResourceExhausted: http.StatusTooManyRequests,
	}[st.Code()]
	if !esDeLaPersona {
		// Un servicio lento o caido no es un fallo de la pagina, y la persona
		// puede reintentar. Se le dice asi, con su formulario y un 503, en vez de
		// mandarla a la pagina de error con el detalle tecnico y perder lo que
		// escribio. (Lo encontro la prueba de punta a punta: un inicio de sesion
		// que supero USER_SERVICE_TIMEOUT devolvia un 500.)
		if st.Code() == codes.DeadlineExceeded || st.Code() == codes.Unavailable {
			return "El servicio de cuentas no responde ahora mismo. Inténtalo de nuevo en unos segundos.",
				http.StatusServiceUnavailable, true
		}
		return "", http.StatusInternalServerError, false
	}
	if m, ok := mensajes[st.Code()]; ok {
		return m, codigo, true
	}
	return st.Message(), codigo, true
}

func redirigir(w http.ResponseWriter, ruta string) {
	w.Header().Set("Location", baseUrl+ruta)
	w.WriteHeader(http.StatusFound)
}

// renderCuenta pinta una plantilla de cuentas con su codigo de estado y el
// contador del carrito del encabezado, como el resto de la tienda.
func (fe *frontendServer) renderCuenta(w http.ResponseWriter, r *http.Request, log logrus.FieldLogger, plantilla string, codigo int, datos map[string]interface{}) {
	if datos == nil {
		datos = map[string]interface{}{}
	}
	if cart, err := fe.getCart(r.Context(), cartID(r)); err == nil {
		datos["cart_size"] = cartSize(cart)
	}
	w.WriteHeader(codigo)
	if err := templates.ExecuteTemplate(w, plantilla, injectCommonTemplateData(r, datos)); err != nil {
		log.Error(err)
	}
}

func rechazarCSRF(log logrus.FieldLogger, w http.ResponseWriter, r *http.Request) {
	renderHTTPError(log, r, w, errors.New("el formulario no trae un token CSRF valido"), http.StatusForbidden)
}

// esCuentaInexistente dice si el userservice respondio que la cuenta no existe.
func esCuentaInexistente(err error) bool {
	return status.Code(err) == codes.NotFound
}

// sesionHuerfana atiende una sesion valida cuya cuenta ya no existe: GetUser o
// DeleteUser responden NotFound. Pasa si la cuenta se borro mientras habia otra
// sesion abriendose (ver DeleteUser en el userservice). Se trata como una
// sesion cerrada, y no como un error 500: se cierra en el servidor, se borra la
// cookie y se lleva a entrar.
func sesionHuerfana(w http.ResponseWriter, r *http.Request, log logrus.FieldLogger) {
	if t := authToken(r); t != "" {
		if err := userSvc.logout(r.Context(), t); err != nil {
			log.WithField("err", err).Warn("no se pudo cerrar una sesion sin cuenta")
		}
	}
	borrarCookieSesion(w)
	redirigir(w, "/login")
}

// abrirSesion pone la cookie, fusiona el carrito anonimo y lleva a la portada.
func (fe *frontendServer) abrirSesion(w http.ResponseWriter, r *http.Request, log logrus.FieldLogger, s *pb.Session) {
	ponerCookieSesion(w, s)
	fe.fusionarCarrito(r.Context(), log, sessionID(r), s.GetUserId())
	redirigir(w, "/")
}

// ------------------------------------------------------- entrar

func (fe *frontendServer) viewLoginHandler(w http.ResponseWriter, r *http.Request) {
	log := r.Context().Value(ctxKeyLog{}).(logrus.FieldLogger)
	if currentUser(r) != nil {
		redirigir(w, "/account")
		return
	}
	var datos map[string]interface{}
	if r.URL.Query().Get("ok") == "eliminada" {
		datos = map[string]interface{}{"message": "Tu cuenta se eliminó."}
	}
	fe.renderCuenta(w, r, log, "login", http.StatusOK, datos)
}

func (fe *frontendServer) loginHandler(w http.ResponseWriter, r *http.Request) {
	log := r.Context().Value(ctxKeyLog{}).(logrus.FieldLogger)
	if !csrfValido(r) {
		rechazarCSRF(log, w, r)
		return
	}
	correo := strings.TrimSpace(r.PostFormValue("email"))
	res, err := userSvc.login(r.Context(), correo, r.PostFormValue("password"))
	if err != nil {
		msg, codigo, ok := respuestaCuenta(err, map[codes.Code]string{
			codes.Unauthenticated:   "Correo o contraseña incorrectos.",
			codes.ResourceExhausted: "Demasiados intentos fallidos. Espera unos minutos y vuelve a intentarlo.",
		})
		if !ok {
			renderHTTPError(log, r, w, errors.Wrap(err, "no se pudo iniciar sesion"), codigo)
			return
		}
		fe.renderCuenta(w, r, log, "login", codigo, map[string]interface{}{"error": msg, "email": correo})
		return
	}
	fe.abrirSesion(w, r, log, res.GetSession())
}

// ------------------------------------------------------- registrarse

func (fe *frontendServer) viewRegisterHandler(w http.ResponseWriter, r *http.Request) {
	log := r.Context().Value(ctxKeyLog{}).(logrus.FieldLogger)
	if currentUser(r) != nil {
		redirigir(w, "/account")
		return
	}
	fe.renderCuenta(w, r, log, "register", http.StatusOK, nil)
}

func (fe *frontendServer) registerHandler(w http.ResponseWriter, r *http.Request) {
	log := r.Context().Value(ctxKeyLog{}).(logrus.FieldLogger)
	if !csrfValido(r) {
		rechazarCSRF(log, w, r)
		return
	}
	correo := strings.TrimSpace(r.PostFormValue("email"))
	nombre := strings.TrimSpace(r.PostFormValue("first_name"))
	apellido := strings.TrimSpace(r.PostFormValue("last_name"))
	datos := map[string]interface{}{"email": correo, "first_name": nombre, "last_name": apellido}

	clave := r.PostFormValue("password")
	if clave != r.PostFormValue("password_confirm") {
		datos["error"] = "Las contraseñas no coinciden."
		fe.renderCuenta(w, r, log, "register", http.StatusBadRequest, datos)
		return
	}
	res, err := userSvc.register(r.Context(), correo, clave, nombre, apellido)
	if err != nil {
		msg, codigo, ok := respuestaCuenta(err, map[codes.Code]string{
			codes.AlreadyExists: "Ya existe una cuenta con ese correo.",
		})
		if !ok {
			renderHTTPError(log, r, w, errors.Wrap(err, "no se pudo crear la cuenta"), codigo)
			return
		}
		datos["error"] = msg
		fe.renderCuenta(w, r, log, "register", codigo, datos)
		return
	}
	fe.abrirSesion(w, r, log, res.GetSession())
}

// ------------------------------------------------------- la cuenta

func (fe *frontendServer) viewAccountHandler(w http.ResponseWriter, r *http.Request) {
	log := r.Context().Value(ctxKeyLog{}).(logrus.FieldLogger)
	u := currentUser(r)
	if u == nil {
		redirigir(w, "/login")
		return
	}
	perfil, err := userSvc.get(r.Context(), u.ID)
	if esCuentaInexistente(err) {
		sesionHuerfana(w, r, log)
		return
	}
	if err != nil {
		renderHTTPError(log, r, w, errors.Wrap(err, "no se pudo leer la cuenta"), http.StatusInternalServerError)
		return
	}
	datos := map[string]interface{}{"profile": perfil}
	switch r.URL.Query().Get("ok") {
	case "perfil":
		datos["message"] = "Perfil guardado."
	case "contrasena":
		datos["message"] = "Contraseña cambiada. Las demás sesiones abiertas se cerraron."
	}
	fe.renderCuenta(w, r, log, "account", http.StatusOK, datos)
}

// cuentaConError vuelve a pintar la cuenta con un mensaje en el formulario que
// toca (campo), sin perder lo que la persona escribio en el de perfil.
func (fe *frontendServer) cuentaConError(w http.ResponseWriter, r *http.Request, log logrus.FieldLogger, u *sesionUsuario, escrito *pb.User, campo, msg string, codigo int) {
	perfil, err := userSvc.get(r.Context(), u.ID)
	if esCuentaInexistente(err) {
		sesionHuerfana(w, r, log)
		return
	}
	if err != nil {
		renderHTTPError(log, r, w, errors.Wrap(err, "no se pudo leer la cuenta"), http.StatusInternalServerError)
		return
	}
	if escrito != nil {
		perfil.FirstName = escrito.GetFirstName()
		perfil.LastName = escrito.GetLastName()
		perfil.Address = escrito.GetAddress()
	}
	fe.renderCuenta(w, r, log, "account", codigo, map[string]interface{}{"profile": perfil, campo: msg})
}

func (fe *frontendServer) updateAccountHandler(w http.ResponseWriter, r *http.Request) {
	log := r.Context().Value(ctxKeyLog{}).(logrus.FieldLogger)
	u := currentUser(r)
	if u == nil {
		redirigir(w, "/login")
		return
	}
	if !csrfValido(r) {
		rechazarCSRF(log, w, r)
		return
	}

	// UpdateProfile REEMPLAZA nombre y direccion enteros: una direccion que no
	// se mande se borra. Por eso el formulario lleva siempre todos los campos,
	// precargados con lo guardado, y aqui se reenvian todos.
	escrito := &pb.User{
		FirstName: strings.TrimSpace(r.PostFormValue("first_name")),
		LastName:  strings.TrimSpace(r.PostFormValue("last_name")),
		Address: &pb.UserAddress{
			StreetAddress: strings.TrimSpace(r.PostFormValue("street_address")),
			City:          strings.TrimSpace(r.PostFormValue("city")),
			State:         strings.TrimSpace(r.PostFormValue("state")),
			Country:       strings.TrimSpace(r.PostFormValue("country")),
		},
	}
	if cp := strings.TrimSpace(r.PostFormValue("zip_code")); cp != "" {
		n, err := strconv.ParseInt(cp, 10, 32)
		if err != nil || n < 0 {
			fe.cuentaConError(w, r, log, u, escrito, "error", "El código postal tiene que ser un número.", http.StatusBadRequest)
			return
		}
		escrito.Address.ZipCode = int32(n)
	}

	_, err := userSvc.updateProfile(r.Context(), &pb.UpdateProfileRequest{
		UserId:    u.ID,
		FirstName: escrito.GetFirstName(),
		LastName:  escrito.GetLastName(),
		Address:   escrito.GetAddress(),
	})
	if err != nil {
		msg, codigo, ok := respuestaCuenta(err, nil)
		if !ok {
			renderHTTPError(log, r, w, errors.Wrap(err, "no se pudo guardar el perfil"), codigo)
			return
		}
		fe.cuentaConError(w, r, log, u, escrito, "error", msg, codigo)
		return
	}
	redirigir(w, "/account?ok=perfil")
}

func (fe *frontendServer) changePasswordHandler(w http.ResponseWriter, r *http.Request) {
	log := r.Context().Value(ctxKeyLog{}).(logrus.FieldLogger)
	u := currentUser(r)
	if u == nil {
		redirigir(w, "/login")
		return
	}
	if !csrfValido(r) {
		rechazarCSRF(log, w, r)
		return
	}
	nueva := r.PostFormValue("new_password")
	if nueva != r.PostFormValue("new_password_confirm") {
		fe.cuentaConError(w, r, log, u, nil, "pwd_error", "Las contraseñas nuevas no coinciden.", http.StatusBadRequest)
		return
	}
	err := userSvc.changePassword(r.Context(), u.ID, r.PostFormValue("current_password"), nueva, u.Token)
	if err != nil {
		msg, codigo, ok := respuestaCuenta(err, map[codes.Code]string{
			codes.Unauthenticated: "La contraseña actual no es correcta.",
		})
		if !ok {
			renderHTTPError(log, r, w, errors.Wrap(err, "no se pudo cambiar la contrasena"), codigo)
			return
		}
		fe.cuentaConError(w, r, log, u, nil, "pwd_error", msg, codigo)
		return
	}
	redirigir(w, "/account?ok=contrasena")
}

// ------------------------------------------------------- salir

// logoutAccountHandler cierra la sesion EN EL SERVIDOR antes de borrar la
// cookie: si solo se borrara la cookie, el token seguiria valiendo en Redis
// hasta caducar, y quien lo hubiera copiado podria seguir usandolo.
func (fe *frontendServer) logoutAccountHandler(w http.ResponseWriter, r *http.Request) {
	log := r.Context().Value(ctxKeyLog{}).(logrus.FieldLogger)
	if !csrfValido(r) {
		rechazarCSRF(log, w, r)
		return
	}
	if t := authToken(r); t != "" {
		if err := userSvc.logout(r.Context(), t); err != nil {
			log.WithField("err", err).Warn("no se pudo cerrar la sesion en el servidor")
		}
	}
	borrarCookieSesion(w)
	redirigir(w, "/")
}

// ------------------------------------------------------- eliminar la cuenta

// deleteAccountHandler borra la cuenta. Pide dos cosas ademas del CSRF: la
// contrasena, que comprueba el userservice, y una casilla marcada, que se
// comprueba aqui aunque el formulario la marque como obligatoria (el atributo
// required lo aplica el navegador, y una peticion hecha a mano no lo trae).
//
// Despues de borrar vacia el carrito de la cuenta, que vive en redis-cart con
// el id como llave y nadie volveria a pedir. Si eso falla la cuenta YA se
// borro, asi que solo queda registrado. Las listas de deseos no se tocan: son
// del navegador, no de la cuenta (ADR 0024).
func (fe *frontendServer) deleteAccountHandler(w http.ResponseWriter, r *http.Request) {
	log := r.Context().Value(ctxKeyLog{}).(logrus.FieldLogger)
	u := currentUser(r)
	if u == nil {
		redirigir(w, "/login")
		return
	}
	if !csrfValido(r) {
		rechazarCSRF(log, w, r)
		return
	}
	if r.PostFormValue("confirmar") != "si" {
		fe.cuentaConError(w, r, log, u, nil, "del_error",
			"Marca la casilla para confirmar que quieres eliminar la cuenta.", http.StatusBadRequest)
		return
	}
	err := userSvc.deleteUser(r.Context(), u.ID, r.PostFormValue("password"))
	if esCuentaInexistente(err) {
		sesionHuerfana(w, r, log)
		return
	}
	if err != nil {
		msg, codigo, ok := respuestaCuenta(err, map[codes.Code]string{
			codes.Unauthenticated: "La contraseña no es correcta.",
		})
		if !ok {
			renderHTTPError(log, r, w, errors.Wrap(err, "no se pudo eliminar la cuenta"), codigo)
			return
		}
		fe.cuentaConError(w, r, log, u, nil, "del_error", msg, codigo)
		return
	}
	if err := fe.emptyCart(r.Context(), u.ID); err != nil {
		log.WithField("err", err).Warn("cuenta eliminada, pero no se pudo vaciar su carrito")
	}
	borrarCookieSesion(w)
	redirigir(w, "/login?ok=eliminada")
}
