from app.crypto_core import totp
import base64
import time

print(totp(base64.b32decode(b'WV3UPYHZ6KPOERDS454CIGOJZDRFNNXS'),int(time.time()),6))