let loginToken = null;
const form = document.getElementById("login-form")
const totpForm = document.getElementById("totp-form")
const setupForm = document.getElementById("setup-form");
const confirmForm = document.getElementById("confirm-form");
const profilePanel = document.getElementById("profile-panel");

form.addEventListener("submit",function (event) {
    event.preventDefault();
    loginToken = null;
    totpForm.hidden = true;
    setupForm.hidden=true;
    confirmForm.hidden = true;
    const username = document.getElementById("username").value;
    const password = document.getElementById("password").value;
    const data = {
        username: username,
        password: password
    };
    const jsonData = JSON.stringify(data);
    fetch('/login', {
    method: 'POST',
    headers: {
        'Content-Type': 'application/json'
    },
    body: jsonData
})
.then(function(response) {
    return response.json().then(function(serverData) {
        return {
            ok: response.ok,
            data: serverData
        };
    });
})
.then(function(result) {
    const message = document.getElementById("login-message");

    if (result.ok) {
        loginToken=result.data.login_token;
        if (result.data.next_step === "totp_required") {
            message.textContent = "введите код 2фа";
            totpForm.hidden = false;
        }
        else if (result.data.next_step === "totp_setup_required") {
            message.textContent = "необходимо вкл 2фа";
            setupForm.hidden=false;
        }
        message.style.color = "green";
    } else {
        if (Array.isArray(result.data.detail)) {
            message.textContent = result.data.detail
                .map(error => error.msg)
                .join("; ");
        } else {
            message.textContent = result.data.detail;
        }

        message.style.color = "red";
    }
})
.catch(function(error) {
    console.error('Ошибка запроса:', error);
});

});

totpForm.addEventListener("submit", function (event) {
    event.preventDefault();
    const totp_code = document.getElementById("totp-code").value;
    const totpData = {
        login_token: loginToken,
        code: totp_code
    };
    const jsonTotpData = JSON.stringify(totpData);
    fetch("/login/totp", {
        method: "POST",
        headers: {
            "Content-Type": "application/json"
        },
        body: jsonTotpData
    })
    .then(function (response) {
        return response.json().then(function (serverData) {
            return {
                ok: response.ok,
                data: serverData
            };
        });
    })
    .then(function (result) {
        const message = document.getElementById("login-message");
        if (result.ok) {
            message.textContent = result.data.message;
            message.style.color = "green";
            sessionToken = result.data.session_token;
            fetch("/profile", {
    method: "GET",
    credentials: "same-origin"
})
.then(function(response) {
    if (!response.ok) {
        throw new Error("Ошибка доступа: " + response.status);
    }
    return response.json();
})
.then(function(data) {
    profilePanel.hidden = false;
    form.hidden = true;
    document.getElementById("welcome-title").hidden = true;
    document.getElementById("register-link").hidden = true;
    document.getElementById("login-message").hidden = true;
    const element = document.getElementById("profile-info");
    element.textContent = data.message + ". ID пользователя: " + data.user_id;
})
.catch(function(error) {
    console.error("Ошибка получения профиля:", error.message);
});
            loginToken = null;
            totpForm.hidden = true;
        } else {
            if (Array.isArray(result.data.detail)) {
                message.textContent = result.data.detail
                    .map(error => error.msg)
                    .join("; ");
            } else {
                message.textContent = result.data.detail;
            }
            message.style.color = "red";
        }
    })
    .catch(function (error) {
        const message = document.getElementById("login-message");
        message.textContent = "Не удалось связаться с сервером";
        message.style.color = "red";
        console.error("Ошибка запроса:", error);
    });
});

setupForm.addEventListener("submit", function(event) {
    event.preventDefault();

    const setupData = {
        login_token: loginToken
    };

    const jsonSetupData = JSON.stringify(setupData);

    const message = document.getElementById("setup-message");
    const container = document.getElementById("qr-code");

    container.hidden = true;
    container.replaceChildren();

    fetch("/2fa/setup", {
        method: "POST",
        headers: {
            "Content-Type": "application/json"
        },
        body: jsonSetupData
    })
    .then(function(response) {
        if (!response.ok) {
            throw new Error("Ошибка HTTP: " + response.status);
        }

        return response.json();
    })
    .then(function(data) {
        message.textContent = data.message;
        message.style.color = "green";

        const otpauthUri = data.otpauth_uri;

        if (!otpauthUri) {
            throw new Error("Сервер не вернул otpauth_uri");
        }

        new QRCode(container, {
            text: otpauthUri,
            width: 200,
            height: 200
        });

        container.hidden = false;

        confirmForm.hidden = false;
    })
    .catch(function(error) {
        message.textContent = "Не удалось подключить 2FA: " + error.message;
        message.style.color = "red";

        container.hidden = true;
        console.error("Ошибка подключения 2FA:", error.message);
    });
});

confirmForm.addEventListener("submit", function (event) {
    event.preventDefault();
    const confirmCode = document.getElementById("confirm-code").value;
    const data = {
        login_token: loginToken,
        code: confirmCode
    };
    const jsonConfirmData = JSON.stringify(data);
    fetch('/2fa/confirm', {
    method: 'POST',
    headers: {
        'Content-Type': 'application/json'
    },
    body: jsonConfirmData
}).then(function(response) {
    return response.json().then(function(serverData) {
        return {
            ok: response.ok,
            data: serverData
        };
    });
})
.then(function(result) {
    const message = document.getElementById("confirm-message");

    if (result.ok) {
        loginToken = null;

        setupForm.hidden = true;
        confirmForm.hidden = true;
        const loginMessage = document.getElementById("login-message");
        loginMessage.textContent = "2FA успешно подключена! Войдите заново.";
        loginMessage.style.color = "green";

    } else {
        if (Array.isArray(result.data.detail)) {
            message.textContent = result.data.detail
                .map(error => error.msg)
                .join("; ");
        } else {
            message.textContent = result.data.detail;
        }

        message.style.color = "red";
    }
})
.catch(function(error) {
    const message = document.getElementById("confirm-message");
    message.textContent = "Не удалось связаться с сервером";
    message.style.color = "red";
    console.error("Ошибка подтверждения:", error);
});
});

const logoutButton = document.getElementById("logout-button");

logoutButton.addEventListener("click", function() {
    fetch("/logout", {
        method: "POST",
        credentials: "same-origin"
    })
    .then(function(response) {
        return response.json().then(function(data) {
            return {
                ok: response.ok,
                data: data
            };
        });
    })
    .then(function(result) {
        if (result.ok) {
            sessionToken = null;
            loginToken = null;

            profilePanel.hidden = true;

            form.hidden = false;
            totpForm.hidden = true;
            setupForm.hidden = true;
            confirmForm.hidden = true;

            document.getElementById("welcome-title").hidden = false;
            document.getElementById("register-link").hidden = false;

            const message = document.getElementById("login-message");
            message.hidden = false;
            message.textContent = "Вы успешно вышли из аккаунта";
            message.style.color = "green";

            form.reset();
            totpForm.reset();
            confirmForm.reset();

        } else {
            const info = document.getElementById("profile-info");
            info.textContent = "Ошибка выхода: " + result.data.detail;
            info.style.color = "red";
        }
    })
    .catch(function(error) {
        const info = document.getElementById("profile-info");
        info.textContent = "Не удалось связаться с сервером. Сессия может оставаться активной.";
        info.style.color = "red";
        console.error("Ошибка выхода:", error);
    });
});

fetch("/profile", {
    method: "GET",
    credentials: "same-origin"
})
.then(function(response) {
    return response.json().then(function(data) {
        return {
            ok: response.ok,
            data: data
        };
    });
})
.then(function(result) {
    if (result.ok) {
        profilePanel.hidden = false;
        form.hidden = true;
        totpForm.hidden = true;
        setupForm.hidden = true;
        confirmForm.hidden = true;

        document.getElementById("welcome-title").hidden = true;
        document.getElementById("register-link").hidden = true;
        document.getElementById("login-message").hidden = true;

        const profileInfo = document.getElementById("profile-info");

        profileInfo.textContent =
            result.data.message + ". ID пользователя: " + result.data.user_id;

    } else {
        console.log("Пользователь не авторизован");
    }
})
.catch(function(error) {
    console.error("Не удалось проверить сессию:", error);
});