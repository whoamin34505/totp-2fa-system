async function requestJson(url, body) {
    const options = {};
    if (body !== undefined) {
        options.method = "POST";
        options.headers = { "Content-Type": "application/json" };
        options.body = JSON.stringify(body);
    }

    let response;
    try {
        response = await fetch(url, options);
    } catch {
        throw new Error("Не удалось связаться с сервером. Попробуйте ещё раз.");
    }

    let responseData;
    try {
        responseData = await response.json();
    } catch {
        responseData = null;
    }

    if (response.ok && responseData) {
        return responseData;
    }

    let errorMessage = "Не удалось выполнить запрос. Попробуйте ещё раз.";
    if (responseData && typeof responseData.detail === "string") {
        errorMessage = responseData.detail;
    }

    const error = new Error(errorMessage);
    error.status = response.status;
    throw error;
}

function showMessage(text = "", isError = false) {
    const message = document.getElementById("message");
    message.textContent = text;
    message.className = "message";
    if (isError) {
        message.classList.add("error");
    }
}

async function runAction(button, action) {
    if (button.disabled) {
        return;
    }

    const buttons = button.closest("section").querySelectorAll("button:enabled");
    for (const control of buttons) {
        control.disabled = true;
    }

    try {
        await action();
    } catch (error) {
        showMessage(error.message, true);
    } finally {
        for (const control of buttons) {
            control.disabled = false;
        }
    }
}

function handleForm(form, action) {
    const button = form.querySelector('button[type="submit"]');
    form.addEventListener("submit", function (event) {
        event.preventDefault();
        runAction(button, action);
    });
}

function clearInputs(container) {
    for (const input of container.querySelectorAll("input")) {
        input.value = "";
    }
}
