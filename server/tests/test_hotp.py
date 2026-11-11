from app.crypto_core import hotp
import pytest

SECRET = b"12345678901234567890"
RFC4226_VECTORS = [
    (0, "755224"),
    (1, "287082"),
    (2, "359152"),
    (3, "969429"),
    (4, "338314"),
    (5, "254676"),
    (6, "287922"),
    (7, "162583"),
    (8, "399871"),
    (9, "520489"),
]

@pytest.mark.parametrize("counter, expected_otp", RFC4226_VECTORS)
def test_hotp_rfc4226(counter, expected_otp):
    result = hotp(SECRET, counter)
    assert result == expected_otp