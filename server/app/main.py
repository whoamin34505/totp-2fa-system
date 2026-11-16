from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from db import get_connection, register_user, get_user, verify_password
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
                if user[2]:
                    return {"next_step": "totp_required"}
                else:
                    return  {"next_step": "totp_setup_required"}
            else:
                raise HTTPException(status_code=401, detail="Неверный логин или пароль")