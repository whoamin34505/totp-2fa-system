const registerForm = document.getElementById("register-form");

async function register() {
    await requestJson("/register", {
        username: registerForm.elements.username.value,
        password: registerForm.elements.password.value
    });

    document.getElementById("registration").hidden = true;
    document.getElementById("registered").hidden = false;
    clearInputs(registerForm);
    showMessage();
}

handleForm(registerForm, register);
