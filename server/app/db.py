import psycopg
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
import secrets
import base64
import qrcode
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from datetime import datetime, timedelta, timezone
import os


issuer="totp-2fa-system"

def load_aes_key() -> bytes:
    encoded_key = os.environ.get("TOTP_AES_KEY")
    if encoded_key is None:
        raise ValueError("TOTP_AES_KEY не задан")
    aes_key = base64.b64decode(encoded_key, validate=True)
    if len(aes_key)==32:
        return aes_key
    else:
        raise ValueError("AES-ключ должен содержать 32 байта")

def select_all(conn):
    with conn.cursor() as cursor:
        cursor.execute("SELECT * FROM users")
        for record in cursor:
            print(record)


def register_user(conn, username, password):
    with conn.cursor() as cursor:
        ph = PasswordHasher()
        password_hash = ph.hash(password)
        cursor.execute("INSERT INTO users (username, password_hash) VALUES (%s, %s)", (username, password_hash))
        print(f"User {username} added successfully!")

def get_user(conn, username):
    with conn.cursor() as cursor:
        cursor.execute("SELECT id, password_hash, two_factor_enabled FROM USERS WHERE username=%s", (username,))
        return cursor.fetchone()

def verify_password(password_hash, password):
    ph = PasswordHasher()
    try:
        ph.verify(password_hash, password)
        return True
    except VerifyMismatchError:
        return False

def generate_totp_secret():
    secret = secrets.token_bytes(20)
    encoded = base64.b32encode(secret)
    return encoded.decode("ascii")

def generate_otpauth_uri(username, secret):
    otpauth = f"otpauth://totp/{issuer}:{username}?secret={secret}&issuer={issuer}&algorithm=SHA1&digits=6&period=30"
    return otpauth

def generate_aes_key() -> bytes:
    return AESGCM.generate_key(bit_length=256)

def encrypt_totp_secret(key, secret):
    secret_bytes = base64.b32decode(secret)
    aesgcm = AESGCM(key)
    nonce = secrets.token_bytes(12)
    ciphertext = aesgcm.encrypt(nonce, secret_bytes, None)
    return (ciphertext,nonce)

def decrypt_totp_secret(key, ciphertext, nonce) -> bytes:
    aesgcm = AESGCM(key)
    ciphertext = aesgcm.decrypt(nonce, ciphertext, None)
    return ciphertext

def save_pending_totp(conn, user_id, ciphertext, nonce):
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
    with conn.cursor() as cursor:
        cursor.execute("INSERT INTO pending_totp_enrollments (user_id, secret_ciphertext, secret_nonce, expires_at) VALUES (%s, %s, %s, %s)",(user_id,ciphertext,nonce,expires_at))


with psycopg.connect("dbname=totp_2fa_system user=developer password=password") as conn:
    print("Connected to database!")
    password='020220071'
    user = get_user(conn, "whoamin")
    if user is None:
        print("Неверный логин или пароль")
    else:
        if (verify_password(user[1], password)):
            print("Первый фактор пройден!")
            if user[2]:
                print("Требуется TOTP")
            else:
                print("TOTP не подключён")
                id = user[0]
                secret=generate_totp_secret()
                aes=generate_aes_key()
                en_totp=encrypt_totp_secret(aes,secret)
                save_pending_totp(conn,id,en_totp[0],en_totp[1])
        else:
            print("Неверный логин или пароль")

# secret=generate_totp_secret()
# username="whoamin"
# uri=generate_otpauth_uri(username,secret)
# if (uri.startswith("otpauth://totp/")):
#     img = qrcode.make(uri)
#     img.save(f'{username}.png')