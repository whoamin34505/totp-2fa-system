from fastapi import FastAPI, HTTPException
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
                    return {"message":"успех"}
                else:
                    raise HTTPException(status_code=401, detail="Бурмалда")