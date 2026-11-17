from contextlib import nullcontext
from importlib import import_module
from pathlib import Path
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def profile_client(monkeypatch):
    app_dir = Path(__file__).resolve().parents[1] / "app"
    monkeypatch.chdir(app_dir)
    monkeypatch.syspath_prepend(str(app_dir))
    main = import_module("main")
    conn = Mock()
    monkeypatch.setattr(main, "get_connection", lambda: nullcontext(conn))
    monkeypatch.setattr(main, "hash_session_token", lambda token: b"session-hash")
    monkeypatch.setattr(main, "get_session", lambda conn, token_hash: (123,))
    monkeypatch.setattr(main, "check_session", lambda session: True)
    monkeypatch.setattr(main, "get_user_profile", Mock(return_value=("kolya", True)))

    with TestClient(main.app) as client:
        yield client, main, conn


@pytest.mark.parametrize("enabled", [True, False])
def test_profile_returns_user_and_2fa_status(profile_client, enabled):
    client, main, conn = profile_client
    main.get_user_profile.return_value = ("kolya", enabled)
    client.cookies.set("session", "session-token")

    response = client.get("/profile")

    assert response.status_code == 200
    assert response.json() == {
        "user_id": 123,
        "username": "kolya",
        "two_factor_enabled": enabled,
        "message": "Доступ разрешен"
    }
    main.get_user_profile.assert_called_once_with(conn, 123)


def test_profile_requires_session(profile_client):
    client, main, _ = profile_client
    response = client.get("/profile")
    assert response.status_code == 401
    main.get_user_profile.assert_not_called()


def test_profile_rejects_invalid_session(profile_client, monkeypatch):
    client, main, _ = profile_client
    monkeypatch.setattr(main, "check_session", lambda session: False)
    client.cookies.set("session", "session-token")
    response = client.get("/profile")
    assert response.status_code == 401
    main.get_user_profile.assert_not_called()


def test_profile_rejects_missing_user(profile_client):
    client, main, _ = profile_client
    main.get_user_profile.return_value = None
    client.cookies.set("session", "session-token")
    response = client.get("/profile")
    assert response.status_code == 401
