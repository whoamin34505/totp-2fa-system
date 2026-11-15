from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

class RegistrationData(BaseModel):
    username: str = Field(min_length=3,max_length=50)
    password: str = Field(min_length=8)

class RegistrationResponse(BaseModel):
    username: str
    message: str

app = FastAPI()

@app.get("/status")
def get_status():
    return {"application": "totp-2fa-system", "status": "running"}

@app.post("/test")
def test_post():
    return {"message": "POST работает"}

@app.get("/users/{user_id}")
def get_user(user_id: int):
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





