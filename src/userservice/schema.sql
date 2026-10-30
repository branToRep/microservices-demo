-- Esquema del userservice. Lo aplica el Job de migracion antes de que el
-- servicio arranque. Todo es idempotente, asi que correrlo dos veces no rompe
-- nada: el Job se puede repetir sin miedo.

CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- El correo se guarda ya normalizado en minusculas. La restriccion UNIQUE
    -- la impone el motor, no la aplicacion: dos registros simultaneos con el
    -- mismo correo no pueden colarse aunque lleguen al mismo milisegundo.
    email           TEXT NOT NULL UNIQUE,

    -- Hash bcrypt. La contrasena en claro no se guarda nunca, ni siquiera en
    -- los registros de log.
    password_hash   TEXT NOT NULL,

    first_name      TEXT NOT NULL DEFAULT '',
    last_name       TEXT NOT NULL DEFAULT '',

    -- Perfil basico. Vacio es un estado valido: te puedes registrar sin dar
    -- direccion y llenarla despues.
    street_address  TEXT NOT NULL DEFAULT '',
    city            TEXT NOT NULL DEFAULT '',
    state           TEXT NOT NULL DEFAULT '',
    country         TEXT NOT NULL DEFAULT '',
    zip_code        INTEGER NOT NULL DEFAULT 0,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Intentos de login fallidos (ADR 0021). En Postgres y no en Redis a proposito:
-- un limite que se reinicia cuando se reinicia el pod no es un limite, basta
-- esperar un reinicio para recuperar todos los intentos.
CREATE TABLE IF NOT EXISTS login_attempts (
    -- Por correo, EXISTA O NO la cuenta. Si solo se contaran los intentos
    -- contra cuentas reales, el servicio responderia distinto segun el correo
    -- estuviera registrado o no, y eso revela que cuentas hay.
    email           TEXT PRIMARY KEY,

    failures        INTEGER NOT NULL DEFAULT 0,

    -- NULL mientras no haya bloqueo. Se filtra al leer (locked_until < now()):
    -- esto no caduca solo como una clave de Redis.
    locked_until    TIMESTAMPTZ,

    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Para el borrado periodico de bloqueos vencidos.
CREATE INDEX IF NOT EXISTS login_attempts_locked_until_idx
    ON login_attempts (locked_until)
    WHERE locked_until IS NOT NULL;

-- Las sesiones NO viven aqui: viven en Redis, que expira solo. Una sesion
-- perdida obliga a volver a entrar; una cuenta perdida deja a alguien fuera
-- para siempre. Por eso cada cosa esta donde le corresponde.
--
-- El contador de arriba es la excepcion deliberada, y por eso tiene su ADR: no
-- es estado desechable, es un control de seguridad. Ver docs/adr/0021.
