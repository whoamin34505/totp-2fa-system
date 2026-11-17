# totp-2fa-system

## Настройка базы данных

Выполните команды из корня проекта от имени пользователя PostgreSQL с правами создания баз и ролей. Вместо `ИМЯ_АДМИНИСТРАТОРА` укажите его имя.

Сначала создайте базу и роль:

```bash
psql -U ИМЯ_АДМИНИСТРАТОРА -d postgres -v ON_ERROR_STOP=1 -f server/sql/setup.sql
```

Затем создайте таблицы в новой базе:

```bash
psql -U ИМЯ_АДМИНИСТРАТОРА -d totp_2fa_system -v ON_ERROR_STOP=1 -f server/sql/schema.sql
```
