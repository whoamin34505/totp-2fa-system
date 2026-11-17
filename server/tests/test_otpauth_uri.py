from importlib import import_module
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit


def test_otpauth_uri_encodes_special_characters(monkeypatch):
    app_dir = Path(__file__).resolve().parents[1] / "app"
    monkeypatch.syspath_prepend(str(app_dir))
    db = import_module("db")
    issuer = "Мой сервис & Co"
    username = "user/?#&+ name"
    secret = "JBSWY3DPEHPK3PXP"
    monkeypatch.setenv("TOTP_ISSUER", issuer)

    uri = urlsplit(db.generate_otpauth_uri(username, secret))
    issuer_label, username_label = uri.path.lstrip("/").split(":", 1)

    assert uri.scheme == "otpauth"
    assert uri.netloc == "totp"
    assert unquote(issuer_label) == issuer
    assert unquote(username_label) == username
    assert uri.fragment == ""
    assert parse_qs(uri.query) == {
        "secret": [secret],
        "issuer": [issuer],
        "algorithm": ["SHA1"],
        "digits": ["6"],
        "period": ["30"],
    }
