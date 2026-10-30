// Las cuentas: alta, autenticacion, perfil y cambio de contrasena.
//
// Cuatro decisiones de seguridad gobiernan este archivo, y cada una esta
// comentada donde se aplica:
//
//  1. El correo se normaliza SIEMPRE antes de tocar la base, en el alta y en el
//     login. Si no, alguien se registra con "A@b.c" y no puede entrar con
//     "a@b.c".
//  2. Si la cuenta esta bloqueada NO se comprueba la contrasena. Comprobarla
//     regala trabajo y, sobre todo, informacion.
//  3. Correo inexistente y contrasena mala dan el MISMO error y tardan
//     parecido. Si no, el tiempo de respuesta revela que correos existen.
//  4. El hash es bcrypt, con coste configurable y un minimo por debajo del cual
//     el servicio se niega a arrancar barato.
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"golang.org/x/crypto/bcrypt"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/userservice/genproto"
)

// codigoUnico es el SQLSTATE que Postgres devuelve al violar un UNIQUE. Se
// comprueba el codigo y no el texto del error, que cambia con el idioma y la
// version del motor.
const codigoUnico = "23505"

// errCredenciales es el unico error que ven el alta fallida y el login fallido.
// Deliberadamente no dice si el fallo fue el correo o la contrasena.
var errCredenciales = status.Error(codes.Unauthenticated, "correo o contrasena incorrectos")

// hashSenuelo es un bcrypt valido contra el que se compara cuando el correo no
// existe. Sin el, el camino "usuario desconocido" seria mucho mas rapido que el
// camino "contrasena mala", y esa diferencia de tiempo es medible desde fuera:
// basta cronometrar respuestas para saber que correos estan registrados.
var (
	unaVezSenuelo sync.Once
	senuelo       []byte
)

func (s *servidor) hashSenuelo() []byte {
	unaVezSenuelo.Do(func() {
		h, err := bcrypt.GenerateFromPassword([]byte("senuelo-sin-uso"), s.cfg.costeBcrypt)
		if err != nil {
			// Con un coste valido esto no puede fallar; si fallara, comparar
			// contra un valor imposible sigue costando tiempo.
			h = []byte("$2a$10$invalido")
		}
		senuelo = h
	})
	return senuelo
}

// normalizarCorreo deja el correo como lo guarda la base. schema.sql dice que
// la columna va "ya normalizada en minusculas", y esa promesa se cumple aqui:
// el SQL no la impone.
func normalizarCorreo(correo string) string {
	return strings.ToLower(strings.TrimSpace(correo))
}

func validarContrasena(p string) error {
	if len(p) < 8 {
		return status.Error(codes.InvalidArgument, "la contrasena necesita al menos 8 caracteres")
	}
	if len(p) > 72 {
		// bcrypt ignora todo lo que pase de 72 bytes. Aceptarla en silencio
		// daria una falsa sensacion de seguridad con contrasenas largas.
		return status.Error(codes.InvalidArgument, "la contrasena no puede pasar de 72 caracteres")
	}
	return nil
}

// ---------------------------------------------------------------- CreateUser

func (s *servidor) CreateUser(ctx context.Context, req *pb.CreateUserRequest) (*pb.AuthResponse, error) {
	correo := normalizarCorreo(req.GetEmail())
	if correo == "" || !strings.Contains(correo, "@") {
		return nil, status.Error(codes.InvalidArgument, "correo invalido")
	}
	if err := validarContrasena(req.GetPassword()); err != nil {
		return nil, err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.GetPassword()), s.cfg.costeBcrypt)
	if err != nil {
		return nil, status.Error(codes.Internal, "no se pudo registrar la cuenta")
	}

	var id string
	var creado time.Time
	err = s.pool.QueryRow(ctx, `
		INSERT INTO users (email, password_hash, first_name, last_name)
		VALUES ($1, $2, $3, $4)
		RETURNING id, created_at`,
		correo, string(hash), req.GetFirstName(), req.GetLastName(),
	).Scan(&id, &creado)

	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == codigoUnico {
			// El correo ya existe. Aqui SI se dice, porque un formulario de
			// registro lo revela de todos modos: si devolvieramos exito sin
			// crear nada, la persona no podria entrar y no sabria por que.
			return nil, status.Error(codes.AlreadyExists, "ese correo ya tiene cuenta")
		}
		return nil, status.Error(codes.Internal, "no se pudo registrar la cuenta")
	}

	sesion, err := s.crearSesion(ctx, id)
	if err != nil {
		return nil, err
	}

	return &pb.AuthResponse{
		User: &pb.User{
			Id:        id,
			Email:     correo,
			FirstName: req.GetFirstName(),
			LastName:  req.GetLastName(),
			CreatedAt: creado.Unix(),
		},
		Session: sesion,
	}, nil
}

// -------------------------------------------------------------- Authenticate

func (s *servidor) Authenticate(ctx context.Context, req *pb.AuthenticateRequest) (*pb.AuthResponse, error) {
	correo := normalizarCorreo(req.GetEmail())
	if correo == "" {
		return nil, errCredenciales
	}

	// (2) El bloqueo se mira ANTES que nada. Si esta bloqueada no se comprueba
	// la contrasena: ni se gasta un bcrypt ni se le confirma a quien insiste
	// que acerto, que es lo que un ataque por fuerza bruta quiere saber.
	bloqueado, err := s.estaBloqueado(ctx, correo)
	if err != nil {
		return nil, status.Error(codes.Internal, "no se pudo verificar la cuenta")
	}
	if bloqueado {
		return nil, status.Error(codes.ResourceExhausted,
			"demasiados intentos fallidos, espera unos minutos")
	}

	var id, hash, nombre, apellido string
	var creado time.Time
	err = s.pool.QueryRow(ctx, `
		SELECT id, password_hash, first_name, last_name, created_at
		FROM users WHERE email = $1`, correo,
	).Scan(&id, &hash, &nombre, &apellido, &creado)

	existe := true
	if err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			return nil, status.Error(codes.Internal, "no se pudo verificar la cuenta")
		}
		existe = false
		hash = string(s.hashSenuelo()) // (3) mismo coste en tiempo
	}

	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(req.GetPassword())) != nil || !existe {
		// (3) El mismo error en los dos casos. El contador sube igual, para que
		// probar correos al azar tampoco salga gratis.
		if err := s.registrarFallo(ctx, correo); err != nil {
			return nil, status.Error(codes.Internal, "no se pudo verificar la cuenta")
		}
		return nil, errCredenciales
	}

	if err := s.limpiarIntentos(ctx, correo); err != nil {
		return nil, status.Error(codes.Internal, "no se pudo verificar la cuenta")
	}

	sesion, err := s.crearSesion(ctx, id)
	if err != nil {
		return nil, err
	}

	return &pb.AuthResponse{
		User: &pb.User{
			Id: id, Email: correo,
			FirstName: nombre, LastName: apellido,
			CreatedAt: creado.Unix(),
		},
		Session: sesion,
	}, nil
}

// ------------------------------------------------- el contador de intentos

// estaBloqueado dice si el correo esta en penalizacion ahora mismo. El filtro
// por locked_until va en la consulta: un bloqueo vencido no cuenta, y asi no
// hace falta borrarlo para que deje de surtir efecto.
func (s *servidor) estaBloqueado(ctx context.Context, correo string) (bool, error) {
	var bloqueado bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM login_attempts
			WHERE email = $1 AND locked_until IS NOT NULL AND locked_until > now()
		)`, correo).Scan(&bloqueado)
	return bloqueado, err
}

// registrarFallo suma uno y bloquea al llegar al limite. Se cuenta por correo
// EXISTA O NO la cuenta (ADR 0021): si solo contaramos los correos reales, el
// comportamiento distinto delataria cuales lo son.
func (s *servidor) registrarFallo(ctx context.Context, correo string) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO login_attempts (email, failures, updated_at)
		VALUES ($1, 1, now())
		ON CONFLICT (email) DO UPDATE SET
			failures = login_attempts.failures + 1,
			locked_until = CASE
				WHEN login_attempts.failures + 1 >= $2 THEN now() + $3::interval
				ELSE login_attempts.locked_until
			END,
			updated_at = now()`,
		correo, s.cfg.maxIntentos, fmt.Sprintf("%d seconds", int(s.cfg.duracionBloqueo.Seconds())))
	return err
}

// limpiarIntentos borra el registro tras un login correcto.
func (s *servidor) limpiarIntentos(ctx context.Context, correo string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM login_attempts WHERE email = $1`, correo)
	return err
}

// ------------------------------------------------------------------ GetUser

func (s *servidor) GetUser(ctx context.Context, req *pb.GetUserRequest) (*pb.User, error) {
	if req.GetUserId() == "" {
		return nil, status.Error(codes.InvalidArgument, "falta el id de usuario")
	}

	u := &pb.User{Address: &pb.UserAddress{}}
	var creado time.Time
	err := s.pool.QueryRow(ctx, `
		SELECT id, email, first_name, last_name,
		       street_address, city, state, country, zip_code, created_at
		FROM users WHERE id = $1`, req.GetUserId(),
	).Scan(&u.Id, &u.Email, &u.FirstName, &u.LastName,
		&u.Address.StreetAddress, &u.Address.City, &u.Address.State,
		&u.Address.Country, &u.Address.ZipCode, &creado)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, status.Error(codes.NotFound, "esa cuenta no existe")
		}
		return nil, status.Error(codes.Internal, "no se pudo leer la cuenta")
	}
	u.CreatedAt = creado.Unix()
	return u, nil
}

// ------------------------------------------------------------ UpdateProfile

func (s *servidor) UpdateProfile(ctx context.Context, req *pb.UpdateProfileRequest) (*pb.User, error) {
	if req.GetUserId() == "" {
		return nil, status.Error(codes.InvalidArgument, "falta el id de usuario")
	}
	dir := req.GetAddress()
	if dir == nil {
		dir = &pb.UserAddress{}
	}

	ct, err := s.pool.Exec(ctx, `
		UPDATE users SET
			first_name = $2, last_name = $3,
			street_address = $4, city = $5, state = $6, country = $7, zip_code = $8,
			updated_at = now()
		WHERE id = $1`,
		req.GetUserId(), req.GetFirstName(), req.GetLastName(),
		dir.GetStreetAddress(), dir.GetCity(), dir.GetState(),
		dir.GetCountry(), dir.GetZipCode())
	if err != nil {
		return nil, status.Error(codes.Internal, "no se pudo actualizar el perfil")
	}
	if ct.RowsAffected() == 0 {
		return nil, status.Error(codes.NotFound, "esa cuenta no existe")
	}

	// Se devuelve lo que quedo guardado, no lo que se pidio: si el motor
	// normalizo o recorto algo, quien llama ve la verdad.
	return s.GetUser(ctx, &pb.GetUserRequest{UserId: req.GetUserId()})
}

// ----------------------------------------------------------- ChangePassword

func (s *servidor) ChangePassword(ctx context.Context, req *pb.ChangePasswordRequest) (*pb.UserEmpty, error) {
	if req.GetUserId() == "" {
		return nil, status.Error(codes.InvalidArgument, "falta el id de usuario")
	}
	if err := validarContrasena(req.GetNewPassword()); err != nil {
		return nil, err
	}

	var hashActual string
	err := s.pool.QueryRow(ctx,
		`SELECT password_hash FROM users WHERE id = $1`, req.GetUserId()).Scan(&hashActual)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, status.Error(codes.NotFound, "esa cuenta no existe")
		}
		return nil, status.Error(codes.Internal, "no se pudo cambiar la contrasena")
	}

	// La actual se exige aunque la sesion ya este abierta: si alguien deja el
	// navegador sin bloquear, no deberia poder quedarse con la cuenta.
	if bcrypt.CompareHashAndPassword([]byte(hashActual), []byte(req.GetCurrentPassword())) != nil {
		return nil, status.Error(codes.Unauthenticated, "la contrasena actual no es correcta")
	}

	nuevo, err := bcrypt.GenerateFromPassword([]byte(req.GetNewPassword()), s.cfg.costeBcrypt)
	if err != nil {
		return nil, status.Error(codes.Internal, "no se pudo cambiar la contrasena")
	}
	if _, err := s.pool.Exec(ctx,
		`UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1`,
		req.GetUserId(), string(nuevo)); err != nil {
		return nil, status.Error(codes.Internal, "no se pudo cambiar la contrasena")
	}

	// Cambiar la contrasena cierra las demas sesiones: es lo que hace quien
	// sospecha que alguien entro en su cuenta. Se conserva la de quien lo pide
	// para no echarlo a el. Si falla, la contrasena YA cambio y el cambio vale;
	// por eso no se devuelve error, solo queda registrado.
	if err := s.revocarOtrasSesiones(ctx, req.GetUserId(), req.GetKeepSessionToken()); err != nil {
		log.Printf("aviso: no se pudieron cerrar las otras sesiones de %s: %v", req.GetUserId(), err)
	}

	return &pb.UserEmpty{}, nil
}
