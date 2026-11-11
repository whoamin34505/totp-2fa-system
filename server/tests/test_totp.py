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

@pytest.mark.parametrize("counter, expected_otp", RFC6238_VECTORS)
def test_hotp_rfc6238(counter, expected_otp):
    result = totp(SECRET, counter, 8)
    assert result == expected_otp