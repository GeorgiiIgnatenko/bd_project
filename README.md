# Агрегатор новостей · лабораторные по PostgreSQL

Учебный SQL-проект: пользователи, новости, категории, подписки, избранное,
источники и история импорта. PostgreSQL 18, Docker Compose v2, Python 3.10+
(только стандартная библиотека). Веб-приложение и HTTP-сборщик не реализуются.

## Запуск

```sh
sh start.sh
docker compose run --rm seed_only   # один раз, для пустых предметных таблиц
docker compose run --rm queries
```

База доступна на `127.0.0.1:55432`. `start.sh` создаёт отсутствующий `.env`
со случайными паролями, настраивает роли и применяет недостающие миграции.
Повторный запуск сохраняет данные. Пароли не печатаются и не попадают в Git.

```sh
docker compose run --rm admin
docker compose run --rm app
docker compose run --rm analyst
```

В консоли: `\dn`, `\dt public.*`, `SELECT * FROM news LIMIT 5;`, выход `\q`.
Подробности: [роли, RLS, аудит и секреты](security/README.md).

## Проверки

Все команды выполнять из корня репозитория после `sh start.sh`.

```sh
python3 -m scripts.verify                 # миграции, ограничения, сценарии, запросы, роли, RLS/аудит
python3 -m scripts.verify_startup         # новый временный Compose-том, quickstart и restart
python3 -m experiments.concurrency        # два импорта одного URL, блокировка, deadlock и исправление
sh security/demo.sh                      # реальные TCP-входы, в том числе отказ bootstrap
bash tests/audit_rls_tests/run_rls_audit_tests.sh
```

Первые две команды создают отдельные БД и удаляют их в `finally`.
`docker compose run --rm checks` — быстрые 37 проверок лабораторной 2
в изолированной схеме с `ROLLBACK`. Негативные примеры намеренно выводят `ERROR`;
тест обязан проверить ожидаемый SQLSTATE и завершиться с кодом 0.
Отчёты сохраняются локально в `artifacts/` (каталог исключён из Git).
Неудачный тест не считается выполненным.

## Миграции

`migrations/001…007` содержат `up` и `down`. `python3 -m scripts.migrate`
применяет новые версии в одной транзакции под advisory lock. Таблица
`public.schema_migration` хранит имя и SHA-256 каждого применённого `up`.
Изменение уже применённого файла прерывает запуск: исправления добавлять новой миграцией.
`--target N` ограничивает применение вверх, не выполняет downgrade.

Тест проверяет установку с нуля, обновление 004 → 005 → текущая версия с сохранением
seed, повтор, изменение checksum, откат ошибки и всех `down`, полный `down/up`.
`down` для RLS/аудита не содержат собственного COMMIT: транзакцией управляет вызывающий код.
Откат 006 удаляет журнал аудита; 001 удаляет предметные данные.

Старый том без журнала версий автоматически не присваивается новой истории.
Для **ненужных учебных данных** разрешён полный сброс только этого проекта:

```sh
docker compose down --volumes
sh start.sh
docker compose run --rm seed_only
```

Эта команда удаляет `public`, `dev`, `load` и аудит. Для ценных данных нужен
отдельный проверенный план переноса; автоматического baseline по догадке нет.

## Генератор · лабораторная 3

```sh
sh generator/run.sh dev 42       # 80 000 новостей, крупнейшая таблица: 88 000
sh generator/run.sh load 42      # 3 000 000 новостей, крупнейшая: 3 300 000
python3 -m scripts.verify_generator --load
```

Каждый запуск атомарно заменяет только выбранную схему. Последняя команда
проверяет одинаковое содержимое всех 12 таблиц при повторном seed 42,
различия seed 43, отклонение неверных параметров без порчи набора и полный load.
Для load нужны несколько ГБ и несколько минут.

[Распределения, объёмы, бизнес-инварианты](generator/README.md).
Контрольная дата — `2026-10-01 00:00:00+00`, версия генератора 3.
Исторический набор нельзя сравнивать с текущим `now()` для воспроизводимых замеров.
Миграции RLS/аудита относятся к `public`; синтетические `dev/load` доступны
администратору и ограниченному аналитику, приложение к ним доступа не имеет.

```sh
docker compose run --rm -T admin -v mode=load -f /workspace/generator/verify.sql
```

## Пять бизнес-запросов

SQL хранится только в `sql/queries/`; настройки по умолчанию — `sql/query_parameters.sql`.
`psql -v` переопределяет их. `as_of` — исключающая верхняя граница временных окон.

| Запрос | Бизнес-вопрос | Параметры | Роль |
| --- | --- | --- | --- |
| Q1 | Какие новости приоритетны по подпискам пользователя? | user_id, as_of, window_days, page_size, page_offset | app с SET LOCAL; admin для проверки |
| Q2 | Какие публикации категории содержат текст? | search_text, category_name | app / analyst / admin |
| Q3 | Сколько новостей и подписчиков в категории? | as_of, window_days | admin: нужны все подписки |
| Q4 | Сколько запусков и результатов импорта у источника? | date_from, as_of | analyst / admin |
| Q5 | У каких источников >= N неудачных запусков за период? | as_of, days, min_failed_runs | analyst / admin |

Все пять используют JOIN; Q3/Q4/Q5 — агрегации, Q5 — HAVING. Число ошибок
за период не означает число последовательных ошибок и само не отключает источник.
Q3 агрегирует новости и подписчиков раздельно, чтобы не перемножать строки.
`queries` выполняется администратором: RLS приложения скрывает чужие подписки и
делает глобальную статистику Q3 неполной.

Пример поиска в public под аналитиком:

```sh
docker compose run --rm -T analyst -v search_text=матч -v category_name=Спорт \
  -f /workspace/sql/query_parameters.sql -f /workspace/sql/queries/q2_search_by_category.sql
```

Пример ленты под приложением (в консоли `app`, ID должен соответствовать авторизованному пользователю):

```sql
\set user_id 1
\ir /workspace/sql/query_parameters.sql
BEGIN READ ONLY;
SET LOCAL app.current_user_id TO :'user_id';
\ir /workspace/sql/queries/q1_personal_feed.sql
COMMIT;
```

Примеры результатов пяти запросов для dev/42 создаются локально в `artifacts/queries/`:

```sh
python3 -m experiments.examples
```

## Транзакции и конкуренция

```sh
docker compose run --rm -T app -f /workspace/sql/transactions/01_import_publication.sql
docker compose run --rm -T app -f /workspace/sql/transactions/02_rollback.sql
python3 -m experiments.concurrency
```

Нужен demo seed. Первый сценарий сохраняет запуск, новость, категорию, результат
и состояние источника одним COMMIT. Повтор создаёт только запись о дубликате.
Второй проверяет ожидаемую ошибку и отсутствие частично сохранённого запуска.
`import_body.sql` общий для демонстрации и конкурентного теста.
UNIQUE(canonical_url) + ON CONFLICT сериализуют конкурирующее сохранение URL.
Две сессии синхронизируются по фактически полученным блокировкам;
диагностика и SQLSTATE deadlock сохраняются в `artifacts/verification/concurrency.txt`.

## Планы и дополнительные эксперименты

После генерации dev, без параллельной массовой нагрузки:

```sh
python3 -m experiments.benchmark --repeats 3
python3 -m experiments.run_experiments
```

Стенд сравнивает Q3 и Q5, проверяет результаты через EXCEPT ALL, делает прогрев
и минимум три измерения, сохраняет JSON `EXPLAIN (ANALYZE, BUFFERS)` и медианы.
Время берётся из PostgreSQL Execution Time; ошибки SQL останавливают эксперимент.
Baseline SQL хранится только для двух сравниваемых запросов, версии после
оптимизации читаются непосредственно из `sql/queries/`. Для Q5 до оптимизации
индексы 007 временно удаляются в транзакции и восстанавливаются ROLLBACK.

Планы и таблица измерений создаются в `artifacts/benchmark/dev/`,
партицирование и pg_stat_statements — в `artifacts/experiments/`.
Партицирование сравнивает одинаковые проекции данных с одинаковыми индексами;
оно не заменяет модель с глобальной уникальностью URL. Статистика запросов
накопительная: скрипт не сбрасывает статистику всего кластера.

## OpenSpec и состояние лабораторных

OpenSpec и инструкции агента хранятся локально: `openspec/` и `AGENTS.md`
исключены из Git и не появятся при клонировании репозитория.

- `openspec/constitution.md`: принципы, границы проекта и проверки.
- `openspec/progress.md`: все пункты лабораторных и доказательства.
- `openspec/specs/`: действующие требования.
- `openspec/changes/`: планы, задачи, решения и результаты аудита.

Используется [OpenSpec](https://github.com/Fission-AI/OpenSpec), CLI 1.16.0.
Установка при отсутствии: `npm install -g @fission-ai/openspec@1.16.0`.
Инструкции для агента находятся в `AGENTS.md`; CLI и Markdown работают без
генерации глобальных slash-команд редактора.
Для отдельной локальной настройки после клонирования: `openspec init --tools none --language ru`.

```sh
openspec list
openspec new change <name>
openspec instructions proposal --change <name>
openspec validate --all --strict --no-interactive
# После реализации и проверки:
openspec archive <name> --yes
```

Порядок: proposal → design/specs/tasks → код → проверки → verification.md →
обновить progress → архивировать. Уже существующее разрешение на работу
не требует повторного согласования каждого шага.

Лаба 1 и внешний отчёт лабы 2 вне аудита. В лабе 4 пока только роли, секреты,
RLS и аудит. Backup/restore, primary/replica, эксперименты отказа и runbook
восстановления явно отложены.
