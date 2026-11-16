from contextlib import nullcontext
from importlib import import_module
from pathlib import Path
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def logout_client(monkeypatch):
    app_dir = Path(__file__).resolve().parents[1] / "app"
    monkeypatch.chdir(app_dir)
    monkeypatch.syspath_prepend(str(app_dir))
    main = import_module("main")

    revoke = Mock(return_value=True)
    connection = Mock()
    monkeypatch.setattr(main, "get_connection", Mock(return_value=nullcontext(connection)))
    monkeypatch.setattr(main, "hash_session_token", lambda token: "hashed-token")
    monkeypatch.setattr(main, "get_session", lambda conn, token_hash: (123,))
    monkeypatch.setattr(main, "check_session", lambda session: True)
    monkeypatch.setattr(main, "revoke_session", revoke)

    with TestClient(main.app) as client:
        yield client, revoke


@pytest.mark.parametrize("origin", [None, "http://evil.example", "null", "http://127.0.0.1:8001"])
def test_logout_rejects_untrusted_origin(logout_client, origin):
    client, revoke = logout_client
    headers = {} if origin is None else {"Origin": origin}
    client.cookies.set("session", "test-token")
    response = client.post("/logout", headers=headers)

    assert response.status_code == 403
    revoke.assert_not_called()


def test_logout_allows_trusted_origin(logout_client):
    client, revoke = logout_client
    client.cookies.set("session", "test-token")
    response = client.post(
        "/logout",
        headers={"Origin": "http://127.0.0.1:8000"},
    )

    assert response.status_code == 200
    revoke.assert_called_once()
    assert "session=" in response.headers["set-cookie"]
    assert "max-age=0" in response.headers["set-cookie"].lower()


def test_logout_requires_session_for_trusted_origin(logout_client):
    client, revoke = logout_client
    response = client.post("/logout", headers={"Origin": "http://127.0.0.1:8000"})

    assert response.status_code == 401
    revoke.assert_not_called()
