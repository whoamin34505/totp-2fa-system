from contextlib import nullcontext
from importlib import import_module
from pathlib import Path
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def enrollment(monkeypatch):
    app_dir = Path(__file__).resolve().parents[1] / "app"
    monkeypatch.chdir(app_dir)
    monkeypatch.syspath_prepend(str(app_dir))
    main = import_module("main")
    conn = Mock()
    monkeypatch.setattr(main, "get_connection", lambda: nullcontext(conn))
    monkeypatch.setattr(main, "hash_login_token", lambda token: b"login-hash")
    monkeypatch.setattr(main, "get_login_attempt", lambda *args: (123,))
    monkeypatch.setattr(main, "check_login_attempt", lambda attempt: True)
    monkeypatch.setattr(main, "create_totp_rate_limit", Mock())
    monkeypatch.setattr(main, "get_totp_rate_limit", Mock())
    monkeypatch.setattr(main, "check_totp_rate_limit", lambda limit: True)
    monkeypatch.setattr(main, "confirm_totp_enrollment", Mock(return_value=True))
    monkeypatch.setattr(main, "consume_login_token", Mock(return_value=True))
    monkeypatch.setattr(main, "generate_session_token", lambda: "session-value")
    monkeypatch.setattr(main, "hash_session_token", lambda token: b"session-hash")
    monkeypatch.setattr(main, "save_session", Mock())
    monkeypatch.setattr(main, "reset_totp_rate_limit", Mock())
    monkeypatch.setattr(main, "record_failed_totp_attempt", Mock())
    monkeypatch.setattr(main, "increment_login_attempts", Mock())
    with TestClient(main.app) as client:
        yield client, main, conn


def test_confirm_creates_session(enrollment):
    client, main, conn = enrollment
    response = client.post("/2fa/confirm", json={"login_token": "login", "code": "123456"})
    assert response.status_code == 200
    main.confirm_totp_enrollment.assert_called_once_with(conn, 123, "123456")
    main.consume_login_token.assert_called_once_with(conn, b"login-hash")
    main.save_session.assert_called_once_with(conn, 123, b"session-hash")
    cookie = response.headers["set-cookie"].lower()
    assert "session=session-value" in cookie
    assert "httponly" in cookie and "samesite=strict" in cookie


@pytest.mark.parametrize("path", ["/2fa/confirm", "/login/totp"])
@pytest.mark.parametrize("secure", ["true", "false"])
def test_session_cookie_uses_configured_secure_flag(enrollment, monkeypatch, path, secure):
    client, main, conn = enrollment
    monkeypatch.setenv("SESSION_COOKIE_SECURE", secure)
    monkeypatch.setattr(main, "get_active_totp_secret", lambda *args: b"secret")
    monkeypatch.setattr(main, "verify_totp", lambda *args: 12345)
    monkeypatch.setattr(main, "protection_replay_attack", lambda *args: True)

    response = client.post(path, json={"login_token": "login", "code": "123456"})
    assert response.status_code == 200
    assert ("; secure" in response.headers["set-cookie"].lower()) == (secure == "true")


def test_invalid_code_does_not_create_session(enrollment):
    client, main, conn = enrollment
    main.confirm_totp_enrollment.side_effect = main.InvalidTotpCodeError("invalid")
    response = client.post("/2fa/confirm", json={"login_token": "login", "code": "000000"})
    assert response.status_code == 401
    main.save_session.assert_not_called()
    assert "set-cookie" not in response.headers


def test_used_login_token_does_not_create_session(enrollment):
    client, main, conn = enrollment
    main.consume_login_token.return_value = False
    response = client.post("/2fa/confirm", json={"login_token": "login", "code": "123456"})
    assert response.status_code == 401
    main.save_session.assert_not_called()
    assert "set-cookie" not in response.headers


def test_login_rejects_reused_totp(enrollment, monkeypatch):
    client, main, conn = enrollment
    monkeypatch.setattr(main, "get_active_totp_secret", lambda *args: b"secret")
    monkeypatch.setattr(main, "verify_totp", lambda *args: 12345)
    monkeypatch.setattr(main, "protection_replay_attack", lambda *args: False)
    response = client.post("/login/totp", json={"login_token": "login", "code": "123456"})
    assert response.status_code == 401
    assert "уже использован" in response.json()["detail"]
    main.save_session.assert_not_called()
    assert "set-cookie" not in response.headers
