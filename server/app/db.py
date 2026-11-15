import psycopg
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
import secrets
import base64
import qrcode
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from datetime import datetime, timedelta, timezone
from dotenv import load_dotenv
import os
from crypto_core import totp
import time
load_dotenv()

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
    #expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=500)
    with conn.cursor() as cursor:
        cursor.execute("INSERT INTO pending_totp_enrollments (user_id, secret_ciphertext, secret_nonce, expires_at) VALUES (%s, %s, %s, %s)",(user_id,ciphertext,nonce,expires_at))

def get_pending_totp(conn, user_id):
    with conn.cursor() as cursor:
        cursor.execute("SELECT secret_ciphertext, secret_nonce, expires_at FROM pending_totp_enrollments WHERE user_id=%s FOR UPDATE",(user_id,))
        return cursor.fetchone()

def check_expires_at(expires_at):
    now = datetime.now(timezone.utc)
    if now<expires_at:
        return True
    else:
        return False

def decrypt_secret(conn,user_id) -> bytes:
    pending_totp = get_pending_totp(conn,user_id)
    if (pending_totp is None):
        raise ValueError("Нет информации в БД")
    check_time = check_expires_at(pending_totp[2])
    if (check_time):
        secret = decrypt_totp_secret(load_aes_key(),pending_totp[0],pending_totp[1])
        return secret
    else:
        raise ValueError("Срок привязки истёк")

def verify_totp(secret, code):
    now = int(time.time())
    server_totp = totp(secret, now)
    server_totp_minus = totp(secret, now-30)
    server_totp_plus = totp(secret, now+30)
    if (server_totp==code):
        return now//30
    elif (server_totp_minus==code):
        return (now-30)//30
    elif (server_totp_plus==code):
        return (now+30)//30
    else:
        return None

def protection_replay_attack(conn, user_id, step):
    with conn.cursor() as cursor:
        cursor.execute("UPDATE users SET last_accepted_step = %s WHERE (last_accepted_step < %s OR last_accepted_step IS NULL) AND id = %s",(step,step,user_id))
        if cursor.rowcount==1:
            return True
        else:
            return False

def verify_user_totp(conn, user_id, secret, code):
    step = verify_totp(secret, code)
    if (step is not None and protection_replay_attack(conn, user_id, step)):
        return True
    else:
        return False

def confirm_totp_enrollment(conn, user_id, code):
    get_pending_code = get_pending_totp(conn, user_id)
    if (get_pending_code is None):
        raise ValueError("Нет существующей привязки")
    if (check_expires_at(get_pending_code[2]) == False):
        raise ValueError("Время просрочено")
    decrypted_secret = decrypt_totp_secret(load_aes_key(),get_pending_code[0],get_pending_code[1])
    with conn.cursor() as cursor:
        user_totp = verify_user_totp(conn, user_id, decrypted_secret, code)
        if (user_totp == False):
            raise ValueError("Неправильный код")
        cursor.execute("UPDATE users SET two_factor_enabled=true, totp_secret_ciphertext=%s, totp_secret_nonce=%s WHERE id=%s AND two_factor_enabled=false",(get_pending_code[0],get_pending_code[1],user_id))
        if cursor.rowcount==1:
            cursor.execute("DELETE FROM pending_totp_enrollments WHERE user_id=%s",(user_id,))
            if cursor.rowcount==1:
                return True
            else:
                raise ValueError("Ошибка операции")
        else:
            raise ValueError("ошибка операции")


def get_active_totp_secret(conn, user_id) -> bytes:
    with conn.cursor() as cursor:
        cursor.execute("SELECT two_factor_enabled, totp_secret_ciphertext, totp_secret_nonce FROM users WHERE id=%s",(user_id,))
        status = cursor.fetchone()
        if status is not None:
            if status[0]:
                if status[1] is not None and status[2] is not None:
                    totp_secret_ciphertext=status[1]
                    totp_secret_nonce=status[2]
                    totp_secret=decrypt_totp_secret(load_aes_key(),totp_secret_ciphertext,totp_secret_nonce)
                    return totp_secret
                else:
                    raise ValueError("Отсутствуют данные для дешифрования")
            else:
                raise ValueError("У пользователя отключена 2FA")
        else:
            raise ValueError("Нет такого пользователя")




def check():
    with conn:
        print("Connected to database!")
        password='020220071'
        username="whoamin"
        register_user(conn,username,password)
        user = get_user(conn, username)
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
                    print(secret)
                    uri = generate_otpauth_uri(username, secret)
                    if (uri.startswith("otpauth://totp/")):
                        img = qrcode.make(uri)
                        img.save(f'{username}.png')
                    aes=load_aes_key()
                    en_totp=encrypt_totp_secret(aes,secret)
                    save_pending_totp(conn,id,en_totp[0],en_totp[1])
            else:
                print("Неверный логин или пароль")

conn = psycopg.connect(
    dbname=os.environ["DB_NAME"],
    user=os.environ["DB_USER"],
    password=os.environ["DB_PASSWORD"],
    host=os.environ["DB_HOST"]
)
with conn:
    #print(verify_totp(decrypt_secret(conn,15),"999129"))
    #check()
    #print(verify_user_totp(conn, 16, decrypt_secret(conn, 16),"898120"))
    #confirm_totp_enrollment(conn,17,str(277516))
    get_active_totp_secret(conn,17)





