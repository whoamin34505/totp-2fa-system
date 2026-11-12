import psycopg
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
import secrets
import base64
import qrcode

issuer="totp-2fa-system"

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

# with psycopg.connect("dbname=totp_2fa_system user=developer password=password") as conn:
#     secret = generate_totp_secret()
#     print(secret)
#     print("Connected to database!")
#     password='020220071'
#     user = get_user(conn, "whoamin")
#     if user is None:
#         print("Неверный логин или пароль")
#     else:
#         if (verify_password(user[1], password)):
#             print("Первый фактор пройден!")
#             if user[2]:
#                 print("Требуется TOTP")
#             else:
#                 print("TOTP не подключён")
#         else:
#             print("Неверный логин или пароль")

secret=generate_totp_secret()
username="whoamin"
uri=generate_otpauth_uri(username,secret)
if (uri.startswith("otpauth://totp/")):
    img = qrcode.make(uri)
    img.save(f'{username}.png')