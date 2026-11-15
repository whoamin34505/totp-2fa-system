from fastapi import FastAPI, HTTPException, Depends
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

@app.post("/test")
def test_post():
    return {"message": "POST работает"}

@app.get("/users/{user_id}")
def get_user_by_user_id(user_id: int):
    if user_id==1:
        return {"user_id": user_id, "message": "информация о пользователе"}
    else:
        raise HTTPException(404, "Пользователь не найден")

@app.get("/search")
def search(username: str):
    return {"username": username, "message": "поиск пользователя"}

@app.post("/register-test", response_model=RegistrationResponse)
def register_test(data: RegistrationData):
    return {"username": data.username, "message": "Данные получены"}

def get_db(conn=Depends(get_connection)):
    try:
        yield conn
    finally:
        conn.close()

@app.post("/register", response_model=RegistrationResponse, status_code=201)
def register(data: RegistrationData, conn=Depends(get_db)):
    try:
        register_user(conn, data.username, data.password)
        conn.commit()
        return {"username": data.username, "message": "Пользователь успешно добавлен"}
    except UniqueViolation:
        raise HTTPException(status_code=409, detail="Пользователь с таким логином уже существует")

def get_version():
    return "1.0"

@app.get("/version")
def version(ver: str=Depends(get_version)):
    return {"version":ver}

def get_resource():
    print("Ресурс создан")
    try:
        yield "Мой ресурс"
    finally:
        print("Ресурс освобождён")

@app.get("/resource")
def resource(res: str=Depends(get_resource)):
    raise HTTPException(status_code=404)
    return {"resource":res}

@app.post("/login", status_code=200)
def login(data: LoginData, conn=Depends(get_db)):
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

