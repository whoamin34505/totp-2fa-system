CREATE DATABASE totp_2fa_system;
CREATE ROLE developer WITH LOGIN PASSWORD 'password';
GRANT CONNECT ON DATABASE totp_2fa_system TO developer;
