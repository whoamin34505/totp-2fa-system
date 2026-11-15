CREATE DATABASE totp_2fa_system;
CREATE ROLE developer WITH LOGIN PASSWORD 'password';
GRANT CONNECT ON DATABASE totp_2fa_system TO developer;

CREATE TABLE IF NOT EXISTS users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    two_factor_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    totp_secret_ciphertext BYTEA,
    totp_secret_nonce BYTEA,
    last_accepted_step BIGINT
);

CREATE TABLE IF NOT EXISTS pending_totp_enrollments (
    user_id BIGINT PRIMARY KEY REFERENCES users(id),
    secret_ciphertext BYTEA NOT NULL,
    secret_nonce BYTEA NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS pending_login_attempts (
    token_hash BYTEA PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used BOOL NOT NULL DEFAULT FALSE,
    attempts INT DEFAULT 0 NOT NULL
);

GRANT USAGE ON SCHEMA public TO developer;
GRANT SELECT, INSERT, UPDATE ON users TO developer;
GRANT SELECT, INSERT, UPDATE, DELETE ON pending_totp_enrollments TO developer;
