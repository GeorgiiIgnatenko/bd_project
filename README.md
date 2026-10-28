# Агрегатор новостей

## Запуск базы

Нужны Docker с Compose v2 и Python 3 для подготовки `.env`.

```sh
sh start.sh
```

При первом запуске создаётся схема PostgreSQL 18. Данные и сценарии автоматически
не загружаются. База доступна на `127.0.0.1:55432`.

При отсутствии `.env` он создаётся из `.env.example` со случайными паролями.
Существующие значения сохраняются. Роли в старом томе обновляются автоматически.

## Доступы · четвёртая лабораторная

`news_admin` управляет схемой и данными; `news_app` выполняет операции приложения;
`news_analyst` только читает публикации и статистику. Все три роли без прав
суперпользователя. Пароли хранятся в локальном `.env`, который исключён из Git.

```sh
docker compose run --rm admin       # консоль администратора
docker compose run --rm app         # консоль приложения
docker compose run --rm analyst     # консоль аналитика
sh security/demo.sh                 # разрешённые и запрещённые операции
```

Права, обновление старой базы и работа с секретами: [security/README.md](security/README.md).

## RLS и аудит · четвёртая лабораторная

### RLS

Миграция `005_add_rls` включает Row-Level Security на `favorite`, `subscription_category` и `subscription_source`. Роль `news_app` видит и меняет только строки, где `user_id` равен `app.current_user_id`. Приложение задаёт его в начале транзакции:

```sql
SET LOCAL app.current_user_id = '<id из app_user>';
```

Без этой настройки `news_app` не видит строк и ничего не может добавить. `news_admin` владеет таблицами и RLS обходит, `news_analyst` личные таблицы не видит.

### Аудит

Миграция `006_add_audit` создаёт `audit_log` и триггеры на INSERT, UPDATE, DELETE таблиц `app_user`, `news_source`, `news`, `favorite`, `subscription_category`, `subscription_source`, `news_category`.

В журнал пишутся время, роль БД, `app.current_user_id`, таблица, операция, старая и новая строка. Хеш пароля не сохраняется, при его смене ставится флаг `password_changed`.

У `news_app` и `news_analyst` прав на `audit_log` нет, читает журнал только `news_admin`, а UPDATE, DELETE и TRUNCATE журнала запрещены триггером.

```sh
sh scripts/view_audit.sh   # последние 15 записей
```

### Проверка

```sh
bash tests/audit_rls_tests/run_rls_audit_tests.sh
```

Успех: 25 сообщений `PASS` и `ALL SECURITY TESTS PASSED`. Тест всё откатывает.

## Запуск тестов

```sh
docker compose run --rm checks
```

Тесты выполняются в отдельной схеме и не меняют основные данные.
Успешный результат: `passed_checks = 37` и код выхода 0.
Сообщения `ERROR` в негативных примерах ожидаемы и сопровождаются `PASS`.

## Загрузка тестовых данных

```sh
docker compose run --rm seed_only
```

Загружает демонстрационные данные в основную базу, необходимые для запуска бизнес-запросов.

## Запуск бизнес-запросов

```sh
docker compose run --rm queries
```

Выполняет бизнес-запросы из `sql/queries/`.

## Генерация данных

```sh
# Набор для разработки: схема dev, 80 000 новостей.
sh generator/run.sh dev 42

# Нагрузочный набор: схема load, 3 000 000 новостей.
sh generator/run.sh load 42
```

Генератор принимает ровно два аргумента: `dev` или `load` и seed — целое число
от 0 до 2147483647. Seed определяет сгенерированные значения: одинаковые режим
и seed дают одинаковые данные.

Каждый запуск удаляет выбранную схему вместе с её данными, создаёт её заново
и заполняет все 12 таблиц. Например, повторный `sh generator/run.sh load 123`
заменит набор в `load` данными с seed `123`. Схемы `dev` и `load` независимы;
основная схема `public` не меняется. При ошибке загрузки прежний набор восстанавливается.
Для `load` нужно несколько гигабайт свободного места.

Сервисы `seed_only` и `queries` рассчитаны на демонстрационный набор в `public`.
Сгенерированные наборы в `dev` и `load` можно прочитать запросами из раздела ниже.

Успешный запуск заканчивается сообщением `Generation committed in schema dev`
или `Generation committed in schema load`. Данные сохраняются в томе Docker
после завершения генератора и перезапуска контейнера.

## Посмотреть данные

Открыть консоль базы:

```sh
docker compose run --rm admin
```

Дальше команды выполняются внутри `psql`. Посмотреть схемы и таблицы:

```sql
\dn
\dt dev.*
```

Проверить количество строк в наборе для разработки:

```sql
SELECT count(*) AS news_count FROM dev.news;                  -- 80 000
SELECT count(*) AS import_count FROM dev.import_result;       -- 88 000
```

Если загружен нагрузочный набор, проверить его:

```sql
\dt load.*
SELECT count(*) AS news_count FROM load.news;                 -- 3 000 000
SELECT count(*) AS import_count FROM load.import_result;      -- 3 300 000
```

Выбрать схему, чтобы не писать её имя перед каждой таблицей:

```sql
SET search_path TO dev, pg_catalog;
-- Для нагрузочного набора: SET search_path TO load, pg_catalog;

SELECT id, source_id, title, published_at, left(content, 160) AS excerpt
FROM news
ORDER BY id
LIMIT 10;

SELECT n.id, n.title, s.name AS source, c.name AS category
FROM news n
JOIN news_source s ON s.id = n.source_id
JOIN news_category nc ON nc.news_id = n.id
JOIN category c ON c.id = nc.category_id
ORDER BY n.id
LIMIT 10;

SELECT status, count(*) AS rows
FROM import_result
GROUP BY status
ORDER BY status;
```

Выйти из консоли: `\q`.

## Что хранит import_result

`news` хранит сохранённые новости. `scrape_run` хранит запуски сбора новостей
из источников, а `import_result` — результат обработки каждого полученного материала
в рамках запуска:

| Статус | Что произошло | `news_id` |
| --- | --- | --- |
| `успех` | Новость сохранена в `news` | ID сохранённой новости |
| `дубликат` | Такой материал уже есть, новая новость не создаётся | `NULL` |
| `ошибка` | Материал не удалось сохранить, например нет заголовка | `NULL` |

Поэтому результатов обработки больше, чем новостей. В режиме `dev` это
80 000 успехов + 6 400 дубликатов + 1 600 ошибок = 88 000 строк.
Причины ошибок хранятся в `scrape_error_log`. Ошибка подключения к источнику
записывается в `scrape_run` и журнал; результатов обработки материалов у такого
запуска нет.

## Проверить данные и проект

Повторно проверить объёмы и бизнес-ограничения сгенерированного набора:

```sh
docker compose run --rm -T admin -v mode=dev -f /workspace/generator/verify.sql
```

Для нагрузочного набора замените `-v mode=dev` на `-v mode=load`.
Успех — сообщение `PASS: counts, classification, imports, source history, subscriptions and dates`
и код выхода 0. Проверка также выводит объёмы, статусы и распределения.

Подробные распределения данных: [generator/README.md](generator/README.md).

## Структура проекта

| Путь | Содержимое |
| --- | --- |
| `migrations/` | Изменения схемы: применение (`up`) и откат (`down`) |
| `docker/` | Инициализация базы при первом запуске |
| `sql/seed/` | Демонстрационные данные |
| `sql/scenarios/` | Жизненные циклы пользователя, источника и новости |
| `sql/negative/` | Примеры нарушений ограничений |
| `sql/queries/` | Бизнес-запросы |
| `sql/transactions/` | Многошаговая транзакция
| `tests/` | Автоматические проверки схемы, данных и сценариев |
| `generator/` | Генератор данных для третьей лабы и инструкция запуска |
| `security/` | Роли, права, инструкция по секретам и демонстрация доступов |
| `compose.yaml` | Сервисы PostgreSQL и проверок |
| `run_checks.sql` | Запуск тестов с откатом изменений |
| `run_demo.sql` | Загрузка данных и сценариев в основную базу |
| `.env.example` | Пример настроек подключения |
| `tests/audit_rls_tests/` | Тест RLS и аудита под реальными ролями |
| `scripts/` | Просмотр журнала аудита |
