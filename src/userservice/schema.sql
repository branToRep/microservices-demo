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

-- Las sesiones NO viven aqui: viven en Redis, que expira solo. Una sesion
-- perdida obliga a volver a entrar; una cuenta perdida deja a alguien fuera
-- para siempre. Por eso cada cosa esta donde le corresponde.
