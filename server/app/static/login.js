const loginForm = document.getElementById("login-form");
const totpForm = document.getElementById("totp-form");
const confirmForm = document.getElementById("confirm-form");
const qrCode = document.getElementById("qr-code");
const qrInstructions = document.getElementById("qr-instructions");
const manualSecret = document.getElementById("manual-secret");
const successTitle = document.getElementById("success-title");
const profileInfo = document.getElementById("profile-info");

let loginToken = null;
const loadingScreen = document.getElementById("loading");
let currentScreen = loadingScreen;

function showScreen(id) {
    const oldScreen = currentScreen;
    oldScreen.hidden = true;
    currentScreen = document.getElementById(id);
    currentScreen.hidden = false;
    showMessage();

    clearInputs(oldScreen);

    if (oldScreen.id === "confirm") {
        qrCode.replaceChildren();
        qrCode.hidden = true;
        qrInstructions.hidden = true;
        manualSecret.textContent = "";
    }
}

async function loadProfile() {
    const profile = await requestJson("/profile");
    profileInfo.textContent = "ID пользователя: " + profile.user_id;
    showScreen("profile");
}

async function submitLogin() {
    const result = await requestJson("/login", {
        username: loginForm.elements.username.value,
        password: loginForm.elements.password.value
    });

    loginToken = result.login_token;
    if (result.next_step === "totp_required") {
        showScreen("totp");
    } else {
        showScreen("setup");
    }
}

handleForm(loginForm, submitLogin);

async function submitTotp() {
    const code = totpForm.elements.code.value;
    await requestJson("/login/totp", { login_token: loginToken, code: code });
    loginToken = null;

    try {
        await loadProfile();
    } catch (error) {
        successTitle.textContent = "Вход выполнен";
        showScreen("success");
        showMessage(error.message, true);
    }
}

handleForm(totpForm, submitTotp);

async function setupTotp() {
    const result = await requestJson("/2fa/setup", { login_token: loginToken });
    const url = new URL(result.otpauth_uri);
    const secret = url.searchParams.get("secret");
    if (!secret) {
        throw new Error("Не удалось получить ключ. Попробуйте ещё раз.");
    }

    manualSecret.textContent = secret;
    try {
        new QRCode(qrCode, { text: result.otpauth_uri, width: 184, height: 184 });
        qrCode.hidden = false;
        qrInstructions.hidden = false;
    } catch {
        qrCode.replaceChildren();
    }

    showScreen("confirm");
}

const setupButton = document.getElementById("setup-button");
setupButton.addEventListener("click", function () {
    runAction(setupButton, setupTotp);
});

async function copySecret() {
    const secret = manualSecret.textContent;
    let copied;
    try {
        await navigator.clipboard.writeText(secret);
        copied = true;
    } catch {
        copied = false;
    }

    if (currentScreen.id !== "confirm" || manualSecret.textContent !== secret) {
        return;
    }

    if (copied) {
        showMessage("Ключ скопирован.");
        return;
    }

    const selection = window.getSelection();
    selection.selectAllChildren(manualSecret);
    showMessage("Ключ выделен. Скопируйте его вручную.");
}

document.getElementById("copy-secret").addEventListener("click", copySecret);

async function confirmTotp() {
    const code = confirmForm.elements.code.value;
    await requestJson("/2fa/confirm", { login_token: loginToken, code: code });

    loginToken = null;
    successTitle.textContent = "2FA подключена";
    showScreen("success");
}

handleForm(confirmForm, confirmTotp);

function startOver() {
    loginToken = null;
    showScreen("login");
}

const startOverButtons = document.querySelectorAll(".start-over");
for (const button of startOverButtons) {
    button.addEventListener("click", startOver);
}

const openProfileButton = document.getElementById("open-profile");
openProfileButton.addEventListener("click", function () {
    runAction(openProfileButton, loadProfile);
});

async function logout() {
    try {
        await requestJson("/logout", {});
    } catch (error) {
        if (error.status !== 401) {
            throw error;
        }
    }

    profileInfo.textContent = "";
    startOver();
    showMessage("Вы вышли из аккаунта.");
}

const logoutButton = document.getElementById("logout");
logoutButton.addEventListener("click", function () {
    runAction(logoutButton, logout);
});

async function checkSession() {
    const loadingTimer = setTimeout(function () {
        loadingScreen.hidden = false;
    }, 250);

    try {
        await loadProfile();
    } catch (error) {
        showScreen("login");
        if (error.status !== 401) {
            showMessage(error.message, true);
        }
    } finally {
        clearTimeout(loadingTimer);
    }
}

checkSession();
