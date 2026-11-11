import psycopg
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

username="whoamin"
password="020220071"
with psycopg.connect("dbname=totp_2fa_system user=developer password=password") as conn:
    print("Connected to database!")
    with conn.cursor() as cursor:
        cursor.execute("SELECT * FROM users")
        for record in cursor:
            print(record)
    with conn.cursor() as cursor:
        cursor.execute("SELECT COUNT(*) FROM users")
        print(cursor.fetchone()[0])
    #with conn.cursor() as cursor:
     #   ph = PasswordHasher()
      #  password_hash = ph.hash(password)
       # cursor.execute("INSERT INTO users (username, password_hash) VALUES (%s, %s)", (username, password_hash))
        #print(f"User {username} added successfully!")
    with conn.cursor() as cursor:
        ph = PasswordHasher()
        cursor.execute("SELECT id, password_hash, two_factor_enabled FROM USERS WHERE username=%s", (username,))
        result = cursor.fetchone()
        if result is None:
            print("Пользователь не найден")
        else:
            password_hash = result[1]
            try:
                ph.verify(password_hash, password)
                print("Пароль правильный")
                print(result[0], result[1], result[2])
            except VerifyMismatchError:
                print("Неверный пароль")
