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
    user_id BIGINT NOT NULL REFERENCES users(id),
    expires_at TIMESTAMPTZ NOT NULL,
    used BOOLEAN NOT NULL DEFAULT FALSE,
    attempts INT NOT NULL DEFAULT 0 CHECK (attempts >= 0)
);

CREATE TABLE IF NOT EXISTS user_sessions (
    token_hash BYTEA PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS totp_rate_limits (
    user_id BIGINT PRIMARY KEY REFERENCES users(id),
    failed_attempts INT NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
    blocked_until TIMESTAMPTZ
);

GRANT USAGE ON SCHEMA public TO developer;
GRANT SELECT, INSERT, UPDATE ON users TO developer;
GRANT SELECT, INSERT, UPDATE, DELETE ON pending_totp_enrollments TO developer;
GRANT SELECT, INSERT, UPDATE, DELETE ON pending_login_attempts TO developer;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_sessions TO developer;
GRANT SELECT, INSERT, UPDATE, DELETE ON totp_rate_limits TO developer;

CREATE INDEX IF NOT EXISTS idx_login_attempts_user ON pending_login_attempts(user_id);

CREATE INDEX IF NOT EXISTS idx_login_attempts_expires ON pending_login_attempts(expires_at);
