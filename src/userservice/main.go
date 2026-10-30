// El servidor del userservice: arranca, migra, conecta y sirve.
//
// Lo que hace CADA pieza y por que:
//   - Postgres guarda las cuentas y el contador de intentos (ADR 0021). Es el
//     estado que no se puede perder.
//   - Redis guarda las sesiones, que caducan solas. Decidido en la v2.1.0, al
//     final de schema.sql.
//   - El health check deja que Kubernetes sepa si el pod sirve. Responde
//     NOT_SERVING mientras la base no conteste, en vez de mentir y recibir
//     trafico que va a fallar.
//
// Todo lo configurable entra por el entorno, nada enterrado en el codigo.
package main

import (
	"context"
	"flag"
	"log"
	"net"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/status"

	// El paquete generado se llama 'hipstershop' (lo fija option go_package en
	// protos/user.proto, que apunta a la ruta de Google). El alias es
	// obligatorio: sin el, el compilador habla de un paquete que nadie nombro.
	pb "github.com/GoogleCloudPlatform/microservices-demo/src/userservice/genproto"
)

type configuracion struct {
	puerto          string
	urlPostgres     string
	direccionRedis  string
	intentosBase    int
	esperaBase      time.Duration
	duracionSesion  time.Duration
	maxIntentos     int
	duracionBloqueo time.Duration
	costeBcrypt     int
	reflexion       bool
}

// leerConfiguracion toma todo del entorno, con valores por defecto que sirven
// para correr en local contra los contenedores de desarrollo.
func leerConfiguracion() configuracion {
	return configuracion{
		puerto:          env("PORT", "8080"),
		urlPostgres:     env("DATABASE_URL", "postgres://postgres:local@localhost:5432/postgres"),
		direccionRedis:  env("REDIS_ADDR", "localhost:6379"),
		intentosBase:    envEntero("DB_INTENTOS", 30),
		esperaBase:      envDuracion("DB_ESPERA", 2*time.Second),
		duracionSesion:  envDuracion("SESION_TTL", 24*time.Hour),
		maxIntentos:     envEntero("LOGIN_MAX_INTENTOS", 5),
		duracionBloqueo: envDuracion("LOGIN_BLOQUEO", 15*time.Minute),
		costeBcrypt:     costeBcrypt(),
		// La reflexion deja que grpcurl descubra el servicio sin el .proto.
		// Comoda en local, cerrada por defecto: este es el servicio de
		// autenticacion y su superficie no tiene por que ser publica.
		reflexion: os.Getenv("GRPC_REFLEXION") == "1",
	}
}

// costeBcrypt decide cuanto cuesta hashear. Mas alto es mas dificil de romper
// por fuerza bruta y mas lento de verificar: el equilibrio se ajusta sin tocar
// el codigo. El minimo no se puede bajar por descuido ni por variable de
// entorno, porque un coste barato anula el hash entero.
func costeBcrypt() int {
	c := envEntero("BCRYPT_COSTE", bcrypt.DefaultCost)
	if c < bcrypt.DefaultCost {
		log.Printf("BCRYPT_COSTE=%d es demasiado bajo, uso el minimo %d", c, bcrypt.DefaultCost)
		c = bcrypt.DefaultCost
	}
	if c > bcrypt.MaxCost {
		c = bcrypt.MaxCost
	}
	return c
}

func env(clave, porDefecto string) string {
	if v := os.Getenv(clave); v != "" {
		return v
	}
	return porDefecto
}

func envEntero(clave string, porDefecto int) int {
	v := os.Getenv(clave)
	if v == "" {
		return porDefecto
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		log.Printf("%s=%q no es un numero, uso %d", clave, v, porDefecto)
		return porDefecto
	}
	return n
}

func envDuracion(clave string, porDefecto time.Duration) time.Duration {
	v := os.Getenv(clave)
	if v == "" {
		return porDefecto
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		log.Printf("%s=%q no es una duracion (ej. 30s, 15m), uso %s", clave, v, porDefecto)
		return porDefecto
	}
	return d
}

// servidor implementa el UserService. Embebe UnimplementedUserServiceServer a
// proposito: las llamadas que todavia no existen responden Unimplemented, que
// es un error honesto, en vez de impedir que el servicio compile.
type servidor struct {
	pb.UnimplementedUserServiceServer

	cfg   configuracion
	pool  *pgxpool.Pool
	redis *redisClient
}

func main() {
	soloMigrar := flag.Bool("solo-migrar", false,
		"aplica schema.sql y termina, sin levantar el servidor (para el Job de migracion)")
	flag.Parse()

	cfg := leerConfiguracion()

	ctx, parar := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer parar()

	pool, err := pgxpool.New(ctx, cfg.urlPostgres)
	if err != nil {
		log.Fatalf("no pude preparar el pool de Postgres: %v", err)
	}
	defer pool.Close()

	log.Printf("esperando a Postgres (hasta %d intentos cada %s)", cfg.intentosBase, cfg.esperaBase)
	if err := esperarBase(ctx, pool, cfg.intentosBase, cfg.esperaBase); err != nil {
		log.Fatalf("%v", err)
	}

	if err := aplicarEsquema(ctx, pool); err != nil {
		log.Fatalf("%v", err)
	}
	log.Print("esquema aplicado")

	if *soloMigrar {
		log.Print("--solo-migrar: listo, no levanto el servidor")
		return
	}

	srv := &servidor{
		cfg:   cfg,
		pool:  pool,
		redis: newRedisClient(cfg.direccionRedis),
	}

	lis, err := net.Listen("tcp", ":"+cfg.puerto)
	if err != nil {
		log.Fatalf("no pude escuchar en el puerto %s: %v", cfg.puerto, err)
	}

	grpcSrv := grpc.NewServer()
	pb.RegisterUserServiceServer(grpcSrv, srv)
	healthpb.RegisterHealthServer(grpcSrv, srv)

	if cfg.reflexion {
		reflection.Register(grpcSrv)
		log.Print("reflexion gRPC activada (GRPC_REFLEXION=1): solo para desarrollo")
	}

	// Apagado ordenado: al recibir SIGTERM, Kubernetes espera a que terminen
	// las llamadas en curso en vez de cortarlas a media escritura.
	go func() {
		<-ctx.Done()
		log.Print("apagando")
		grpcSrv.GracefulStop()
	}()

	log.Printf("userservice escuchando en :%s", cfg.puerto)
	if err := grpcSrv.Serve(lis); err != nil {
		log.Fatalf("el servidor termino con error: %v", err)
	}
}

// Check responde si el servicio puede atender. Mira la base, que es su
// dependencia dura: sin cuentas no hay nada que servir. Redis no se comprueba
// aqui a proposito: si Redis cae, el login falla pero el resto del servicio
// sigue en pie, y marcar el pod como caido empeoraria las cosas.
func (s *servidor) Check(ctx context.Context, _ *healthpb.HealthCheckRequest) (*healthpb.HealthCheckResponse, error) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	if err := s.pool.Ping(ctx); err != nil {
		return &healthpb.HealthCheckResponse{
			Status: healthpb.HealthCheckResponse_NOT_SERVING,
		}, nil
	}
	return &healthpb.HealthCheckResponse{
		Status: healthpb.HealthCheckResponse_SERVING,
	}, nil
}

func (s *servidor) Watch(_ *healthpb.HealthCheckRequest, _ healthpb.Health_WatchServer) error {
	return status.Errorf(codes.Unimplemented, "health check via Watch not implemented")
}
