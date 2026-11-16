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
    if (result.ok) {
        console.log('Успех:', result.data.message);
    } else {
        console.log('Ошибка:', result.data.detail);
    }
})
.catch(function(error) {
    console.error('Ошибка запроса:', error);
});

});