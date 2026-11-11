import hashlib
import time

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
    hs = hmac_sha1(key, counter)
    last_byte = hs[-1]
    offset = last_byte & 0x0F
    selected_bytes = hs[offset:offset + 4]
    first_byte = selected_bytes[0] & 0x7F
    binary_code = (first_byte << 24) | (selected_bytes[1] << 16) | (selected_bytes[2] << 8) | selected_bytes[3]
    HOTP = binary_code % 10**digits
    return(f"{HOTP:0{digits}d}")

def totp(key: bytes, timestamp: int, digits: int = 6) -> str:
    T = timestamp//30
    return hotp(key,T, digits)







