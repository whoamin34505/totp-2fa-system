from app.crypto_core import totp
import pytest

SECRET = b"12345678901234567890"
RFC6238_VECTORS = [
    (59, "94287082"),
    (1111111109, "07081804"),
    (1111111111, "14050471"),
    (1234567890, "89005924"),
    (2000000000, "69279037"),
    (20000000000, "65353130"),
]

@pytest.mark.parametrize("timestamp, expected_otp", RFC6238_VECTORS)
def test_totp_rfc6238(timestamp, expected_otp):
    result = totp(SECRET, timestamp, 8)
    assert result == expected_otp

def test_totp_six_digits():
    assert totp(b"12345678901234567890",59,6) == "287082"