from fastapi import FastAPI, HTTPException, Depends, Response, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
from db import *
from psycopg.errors import UniqueViolation
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os

def session_cookie_secure():
    value = os.environ.get("SESSION_COOKIE_SECURE", "false").lower()
    if value not in ("true", "false"):
        raise ValueError("SESSION_COOKIE_SECURE должен быть true или false")
    return value == "true"

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

app.mount(
    "/static",
    StaticFiles(directory="static"),
    name="static"
)

@app.get("/")
def get_index():
    return FileResponse("templates/index.html")

@app.get("/register")
def get_register():
    return FileResponse("templates/register.html")

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
def login_totp(data: TotpLoginData, response: Response):
    with get_connection() as conn:
        token_hash = hash_login_token(data.login_token)
        get_attempt = get_login_attempt(conn, token_hash)
        check_attempt = check_login_attempt(get_attempt)
        if check_attempt is False:
            raise HTTPException(status_code=401, detail="Недействительный или просроченный токен")
        else:
            user_id = get_attempt[0]
            create_totp_rate_limit(conn, user_id)
            rate_limit = get_totp_rate_limit(conn, user_id)
            if not check_totp_rate_limit(rate_limit):
                raise HTTPException(status_code=429, detail="Слишком много попыток. Попробуйте позже")
            check_totp = verify_totp(get_active_totp_secret(conn,user_id),data.code)
            if check_totp is None:
                increment_login_attempts(conn, token_hash)
                record_failed_totp_attempt(conn, user_id)
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
                        reset_totp_rate_limit(conn, user_id)
                        response.set_cookie(
                            key="session",
                            value=session_token,
                            httponly=True,
                            secure=session_cookie_secure(),
                            samesite="strict",
                            max_age=86400,
                            path="/"
                        )
                        return {"message":"Авторизация успешна"}
                    else:
                        raise HTTPException(status_code=401, detail="Недействительный или просроченный токен. Войдите заново")
                else:
                    raise HTTPException(status_code=401, detail="Код уже использован. Дождитесь нового кода")

@app.get("/profile")
def profile(request: Request):
    token = request.cookies.get("session")
    if token is None:
        raise HTTPException(status_code=401, detail="Недействительная или просроченная сессия")
    hash_token = hash_session_token(token)
    with get_connection() as conn:
        session = get_session(conn, hash_token)
        if check_session(session):
            return {"user_id":session[0], "message":"Доступ разрешен"}
        else:
            raise HTTPException(status_code=401, detail="Недействительная или просроченная сессия")

@app.post("/logout")
def logout(request: Request, response: Response):
    origin = request.headers.get("Origin")
    allowed_origin = os.environ.get("APP_ORIGIN", "http://127.0.0.1:8000")
    if origin != allowed_origin:
        raise HTTPException(status_code=403, detail="Недопустимый источник запроса")

    token = request.cookies.get("session")
    if token is None:
        raise HTTPException(status_code=401, detail="Недействительная или просроченная сессия")
    hash_token = hash_session_token(token)
    with get_connection() as conn:
        session = get_session(conn, hash_token)
        if check_session(session):
            revoke = revoke_session(conn, hash_token)
            if revoke:
                response.delete_cookie(
                    key="session",
                    path="/",
                    secure=session_cookie_secure(),
                    samesite="strict"
                )
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
            create_totp_rate_limit(conn, user_id)
            rate_limit = get_totp_rate_limit(conn, user_id)
            if not check_totp_rate_limit(rate_limit):
                raise HTTPException(status_code=429,detail="Слишком много попыток. Попробуйте позже")
            get_2fa = get_user_2fa(conn, user_id)
            if get_2fa is True:
                raise HTTPException(status_code=409, detail="2FA уже подключен")
            elif get_2fa is None:
                raise HTTPException(status_code=404, detail="Пользователь не найден")
            elif get_2fa is False:
                secret = generate_totp_secret()
                encrypted_secret = encrypt_totp_secret(load_aes_key(),secret)
                save_pending_totp(conn, user_id, encrypted_secret[0], encrypted_secret[1])
                username=get_username_by_id(conn, user_id)
                if username is None:
                    raise HTTPException(status_code=404, detail="Пользователь не найден")
                uri = generate_otpauth_uri(username,secret)
                return {
                    "message": "Ожидается подтверждение 2FA",
                    "otpauth_uri": uri
                }
        else:
            raise HTTPException(status_code=401, detail="Недействительный или просроченный токен")


@app.post("/2fa/confirm")
def confirm2fa(data: TotpConfirmData, response: Response):
    token = data.login_token
    token_hash = hash_login_token(token)
    with get_connection() as conn:
        login_attempt = get_login_attempt(conn, token_hash)
        check_attempt = check_login_attempt(login_attempt)
        if check_attempt:
            user_id = login_attempt[0]
            create_totp_rate_limit(conn, user_id)
            rate_limit = get_totp_rate_limit(conn, user_id)
            if not check_totp_rate_limit(rate_limit):
                raise HTTPException(status_code=429,detail="Слишком много попыток. Попробуйте позже")
            try:
                confirmed = confirm_totp_enrollment(conn, user_id, data.code)
                if confirmed:
                    check_2fa = consume_login_token(conn, token_hash)
                    if check_2fa is False:
                        raise HTTPException(status_code=401, detail="Не удалось подтвердить 2FA")
                    session_token = generate_session_token()
                    save_session(conn, user_id, hash_session_token(session_token))
                    reset_totp_rate_limit(conn, user_id)
                    response.set_cookie(
                        key="session",
                        value=session_token,
                        httponly=True,
                        secure=session_cookie_secure(),
                        samesite="strict",
                        max_age=86400,
                        path="/"
                    )
                    return {"message": "2FA успешно подключена"}
                raise HTTPException(status_code=401, detail="Не удалось подтвердить 2FA")
            except InvalidTotpCodeError:
                conn.rollback()
                record_failed_totp_attempt(conn, user_id)
                increment_login_attempts(conn, token_hash)
                conn.commit()
                raise HTTPException(status_code=401, detail="Не удалось подтвердить 2FA")
            except ValueError:
                raise HTTPException(status_code=400, detail="Не удалось подтвердить 2FA")

        else:
            raise HTTPException(status_code=401, detail="Недействительный или просроченный токен")
