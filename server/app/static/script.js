const form = document.getElementById("register-form")

form.addEventListener("submit",function (event) {
    event.preventDefault();
    const username = document.getElementById("username").value;
    const password = document.getElementById("password").value;
    const data = {
        username: username,
        password: password
    };
    const jsonData = JSON.stringify(data);
    fetch('/register', {
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
    const message = document.getElementById("register-message");

    if (result.ok) {
        message.textContent = result.data.message;
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