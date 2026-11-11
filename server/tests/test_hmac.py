import hmac
from app.crypto_core import hmac_sha1

def test_less64bytes():
    assert hmac.digest(b"hello", b"test", "sha1") == hmac_sha1(b"hello", b"test")

def test_64bytes():
    assert hmac.digest(b"A" * 64, b"test", "sha1") == hmac_sha1(b"A" * 64, b"test")

def test_more64bytes():
    assert hmac.digest(b"A" * 100, b"test", "sha1") == hmac_sha1(b"A" * 100, b"test")
