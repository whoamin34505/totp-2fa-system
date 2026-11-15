# import os
# import psycopg
# import qrcode

# def check():
#     with conn:
#         print("Connected to database!")
#         password='020220071'
#         username="whoamin"
#         register_user(conn,username,password)
#         user = get_user(conn, username)
#         if user is None:
#             print("Неверный логин или пароль")
#         else:
#             if (verify_password(user[1], password)):
#                 print("Первый фактор пройден!")
#                 if user[2]:
#                     print("Требуется TOTP")
#                 else:
#                     print("TOTP не подключён")
#                     id = user[0]
#                     secret=generate_totp_secret()
#                     print(secret)
#                     uri = generate_otpauth_uri(username, secret)
#                     if (uri.startswith("otpauth://totp/")):
#                         img = qrcode.make(uri)
#                         img.save(f'{username}.png')
#                     aes=load_aes_key()
#                     en_totp=encrypt_totp_secret(aes,secret)
#                     save_pending_totp(conn,id,en_totp[0],en_totp[1])
#             else:
#                 print("Неверный логин или пароль")

# conn = psycopg.connect(
#     dbname=os.environ["DB_NAME"],
#     user=os.environ["DB_USER"],
#     password=os.environ["DB_PASSWORD"],
#     host=os.environ["DB_HOST"]
# )
#with conn:
    #print(verify_totp(decrypt_secret(conn,15),"999129"))
    #check()
    #print(verify_user_totp(conn, 16, decrypt_secret(conn, 16),"898120"))
    #confirm_totp_enrollment(conn,17,str(277516))
    #get_active_totp_secret(conn,17)
    #authenticate_user(conn, "whoamin","020220071",str(311664))





