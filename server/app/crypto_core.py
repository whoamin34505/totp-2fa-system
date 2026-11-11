import hashlib


def hmac_sha1(key: bytes, message: bytes) -> bytes:
    if len(key) > 64:
        key = hashlib.sha1(key).digest()
    if len(key) < 64:
        key = key + b"\x00" * (64-len(key))
    ipad = b"\x36" * 64
    opad = b"\x5C" * 64
    xor1 = []
    for i in range(64):
        xor1.append(key[i] ^ ipad[i])
    xor1 = bytes(xor1)
    xor2 = []
    for i in range(64):
        xor2.append(key[i] ^ opad[i])
    xor2 = bytes(xor2)
    inner_hash = hashlib.sha1(xor1 + message).digest()
    result = hashlib.sha1(xor2 + inner_hash).digest()
    return result

def hotp(key: bytes, counter: int, digits: int = 6) -> str:
    counter = counter.to_bytes(8, "big")
    print(counter)
    hs = hmac_sha1(key, counter)
    print(hs.hex())
    last_byte = hs[-1]
    print(last_byte)
    offset = last_byte & 0x0F
    print(offset)


hotp(b'1', 1)
import hmac
if hmac.digest(b"hello", b"test", "sha1") == hmac_sha1(b"hello", b"test"):
    print("OK")
else:
    print("FAIL")
if hmac.digest(b"A" * 64, b"test", "sha1") == hmac_sha1(b"A" * 64, b"test"):
    print("OK")
else:
    print("FAIL")
if hmac.digest(b"A" * 100, b"test", "sha1") == hmac_sha1(b"A" * 100, b"test"):
    print("OK")
else:
    print("FAIL")



