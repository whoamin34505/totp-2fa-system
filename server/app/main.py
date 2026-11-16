from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
from db import *
from psycopg.errors import UniqueViolation

class RegistrationData(BaseModel):
    username: str = Field(min_length=3,max_length=50)
    password: str = Field(min_length=8)

class RegistrationResponse(BaseModel):
    username: str
    message: str

class LoginData(BaseModel):
    username: str
    password: str

class TotpLoginData(BaseModel):
    login_token: str
    code: str

class TotpSetupData(BaseModel):
    login_token: str

class TotpConfirmData(BaseModel):
    login_token: str
    code: str


bearer = HTTPBearer()

app = FastAPI()

@app.get("/status")
def get_status():
    return {"application": "totp-2fa-system", "status": "running"}

@app.post("/register", response_model=RegistrationResponse, status_code=201)
def register(data: RegistrationData):
    try:
        with get_connection() as conn:
            register_user(conn, data.username, data.password)
    except UniqueViolation:
        raise HTTPException(status_code=409, detail="Пользователь с таким логином уже существует")
    return {"username": data.username, "message": "Пользователь успешно добавлен"}

@app.post("/login", status_code=200)
def login(data: LoginData):
    with get_connection() as conn:
        user = get_user(conn, data.username)
        if user is None:
            raise HTTPException(status_code=401,detail="Неверный логин или пароль")
        else:
            if (verify_password(user[1], data.password)):
                token = generate_login_token()
                token_hash = hash_login_token(token)
                save_login_attempt(conn, user[0], token_hash)
                if user[2]:
                    return {"next_step": "totp_required", "login_token":token}
                else:
                    return  {"next_step": "totp_setup_required", "login_token":token}
            else:
                raise HTTPException(status_code=401, detail="Неверный логин или пароль")

@app.post("/login/totp", status_code=200)
def login_totp(data: TotpLoginData):
    with get_connection() as conn:
        token_hash = hash_login_token(data.login_token)
        get_attempt = get_login_attempt(conn, token_hash)
        check_attempt = check_login_attempt(get_attempt)
        if check_attempt is False:
            raise HTTPException(status_code=401, detail="Недействительный или просроченный токен")
        else:
            user_id = get_attempt[0]
            check_totp = verify_totp(get_active_totp_secret(conn,user_id),data.code)
            if check_totp is None:
                increment_login_attempts(conn, token_hash)
                conn.commit()
                raise HTTPException(status_code=401, detail="Недействительный ТОТП")
            else:
                protection_replay = protection_replay_attack(conn, user_id, check_totp)
                if protection_replay:
                    consume_token = consume_login_token(conn, token_hash)
                    if consume_token:
                        session_token = generate_session_token()
                        session_hash = hash_session_token(session_token)
                        save_session(conn, user_id, session_hash)
                        return {"message":"Авторизация успешна", "session_token":session_token}
                    else:
                        raise HTTPException(status_code=401, detail="Бурмалда")
                else:
                    raise HTTPException(status_code=401, detail="Бурмалда")

@app.get("/profile")
def profile(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    token = credentials.credentials
    hash_token = hash_session_token(token)
    with get_connection() as conn:
        session = get_session(conn, hash_token)
        if check_session(session):
            return {"user_id":session[0], "message":"Доступ разрешен"}
        else:
            raise HTTPException(status_code=401, detail="Недействительная или просроченная сессия")

@app.post("/logout")
def logout(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    token = credentials.credentials
    hash_token = hash_session_token(token)
    with get_connection() as conn:
        session = get_session(conn, hash_token)
        if check_session(session):
            revoke = revoke_session(conn, hash_token)
            if revoke:
                return {"user_id":session[0], "message":"Выход выполнен"}
            else:
                raise HTTPException(status_code=401, detail="Ошибка выхода")
        else:
            raise HTTPException(status_code=401, detail="Недействительная или просроченная сессия")

@app.post("/2fa/setup")
def setup2fa(data: TotpSetupData):
    token = data.login_token
    token_hash = hash_login_token(token)
    with get_connection() as conn:
        login_attempt = get_login_attempt(conn, token_hash)
        check_attempt = check_login_attempt(login_attempt)
        if check_attempt:
            user_id = login_attempt[0]
            get_2fa = get_user_2fa(conn, user_id)
            if get_2fa is True:
                raise HTTPException(status_code=409, detail="2FA уже подключен")
            elif get_2fa is None:
                raise HTTPException(status_code=404, detail="Пользователь не найден")
            elif get_2fa is False:
                secret = generate_totp_secret()
                print("Ключ для добавления в приложение: ",secret)
                encrypted_secret = encrypt_totp_secret(load_aes_key(),secret)
                save_pending_totp(conn, user_id, encrypted_secret[0], encrypted_secret[1])
                username=get_username_by_id(conn, user_id)
                if username is None:
                    raise HTTPException(status_code=404, detail="Пользователь не найден")
                uri = generate_otpauth_uri(username,secret)
                print(uri)
                return {
                    "message": "Ожидается подтверждение 2FA",
                    "otpauth_uri": uri
                }
        else:
            raise HTTPException(status_code=401, detail="Недействительный или просроченный токен")

@app.post("/2fa/confirm")
def confirm2fa(data: TotpConfirmData):
    token = data.login_token
    token_hash = hash_login_token(token)
    with get_connection() as conn:
        login_attempt = get_login_attempt(conn, token_hash)
        check_attempt = check_login_attempt(login_attempt)
        if check_attempt:
            user_id = login_attempt[0]
            get_totp = get_pending_totp(conn, user_id)
            if get_totp is None:
                raise HTTPException(status_code=404, detail="Подключение 2FA не начато")
            get_expires_at = get_totp[2]
            check_expires = check_expires_at(get_expires_at)
            if not check_expires:
                raise HTTPException(status_code=401, detail="Время подключения 2FA истекло")
            decrypted_secret = decrypt_totp_secret(load_aes_key(),get_totp[0],get_totp[1])
            verified_totp = verify_totp(decrypted_secret,data.code)
            if verified_totp is None:
                raise HTTPException(status_code=401, detail="Недействительный TOTP код")
            return {"message": "TOTP-код подтверждён"}
        else:
            raise HTTPException(status_code=401, detail="Недействительный или просроченный токен")