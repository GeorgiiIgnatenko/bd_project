# Краткий runbook восстановления

Команды из корня репозитория относятся только к учебному `bd-news-recovery`.
Для другого учебного проекта добавьте `--project bd-news-recovery-имя` перед
действием. В SQL-примерах используется стандартное имя БД `news_aggregator`;
если `POSTGRES_DB` изменён, подставьте его. Не выводите `.env`, `compose config`,
`inspect` с environment и содержимое passfile в открытый журнал.

## Диагностика

```sh
python3 -m scripts.recovery compose ps -a
python3 -m scripts.recovery compose logs --no-color --tail=30 postgres replica restore
python3 -m scripts.recovery compose exec -T postgres psql -X -w -U news_bootstrap -d news_aggregator \
  -c "SELECT application_name, state, sync_state FROM pg_stat_replication;"
python3 -m scripts.recovery compose exec -T replica psql -X -w -U news_bootstrap -d news_aggregator \
  -c "SELECT pg_is_in_recovery(); SELECT status, sender_host FROM pg_stat_wal_receiver;"
```

Ожидается одна строка `news_replica / streaming / async` на primary,
`pg_is_in_recovery = t` и `status = streaming` на replica. Не запрашивайте
`primary_conninfo`/conninfo целиком; для диагностики хватает полей выше.

| Признак | Диагностика | Восстановление | Проверка |
| --- | --- | --- | --- |
| Replica stopped, primary доступен | `ps -a`, отсутствие строки в pg_stat_replication, журнал replica | `compose start --wait replica` | recovery=t, streaming, недостающие маркеры появились |
| Primary stopped, клиент получает connection refused / DNS error | `ps -a`, журнал postgres, проба с --no-deps | `compose start --wait postgres` | новый клиент успешен, старые данные есть, replica догнала WAL |
| Replica запущена, но WAL не поступает | pg_stat_wal_receiver, сеть, HBA и сообщение об аутентификации | исправить локальный секрет/настройку; повторить up | streaming и новый маркер на replica |
| `requested WAL segment ... has already been removed` или неполный basebackup | журнал replica; убедиться, что primary здоров | новая копия только replica по процедуре ниже | recovery=t, streaming, таблицы/маркеры совпадают |
| Restore не проходит | код возврата и сообщение pg_restore, checksum, пустота целевой БД | не продолжать частичный restore; исправить причину, восстановить в пустой экземпляр | backup.json совпадает, FK/индексы проходят |

## Replica остановлена

Клиент продолжает работать с primary, синхронного ожидания replica нет.
При восстановлении достаточно запустить прежнюю replica с её томом:

```sh
python3 -m scripts.recovery compose start --wait replica
```

Подтвердить `streaming` и наличие маркера, созданного за время остановки, а не
ограничиваться `pg_isready`. Полный воспроизводимый эксперимент с проверками:

```sh
python3 -m scripts.recovery outages
```

## Primary остановлен

Новое подключение SQL-клиента завершается ошибкой; приложение не реализовано,
автоматического переключения нет. Replica остаётся standby. В этом сценарии
том primary сохранён — запустить **тот же** узел:

```sh
python3 -m scripts.recovery compose start --wait postgres
```

Проверить новые подключения, таблицы и журнал миграций; затем streaming и
поступление нового подтверждённого маркера на replica. Если реальный клиент
потерял связь в момент COMMIT, сначала выяснить результат по ключу операции:
автоматическое повторение без проверки может дублировать действие. В учебной
пробе отказ вызывается до установления нового соединения, её маркер отсутствует.

## Восстановление из backup

```sh
python3 -m scripts.recovery backup
python3 -m scripts.recovery restore
```

Первая команда нужна до потери данных. Если primary уже недоступен, используйте
сохранённые `.secrets/recovery/<project>/news.dump` и `artifacts/recovery/<project>/backup.json`;
новый backup не требуется. Restore не зависит от работающего primary, проверяет
checksum, поднимает отдельный пустой экземпляр и атомарно восстанавливает его.
Он сверяет данные/схему со снимком **на момент backup**. Изменения после backup
туда не входят; WAL-архив и PITR не настроены.

Для повторной демонстрации можно удалить **только ненужный учебный restore**:

```sh
python3 -m scripts.recovery compose stop restore
python3 -m scripts.recovery compose rm -f restore
docker volume rm bd-news-recovery_restore_data
python3 -m scripts.recovery restore
```

Это удаляет предыдущий восстановленный экземпляр. Для другого имени проекта
обязательно заменить префикс тома; перед удалением убедиться, что это нужный
одноразовый том. Основной `bd-news-labs_pgdata` не трогать.

## Повторная базовая копия replica

Только если прежняя replica не может догнать WAL или начальная копия прервалась,
и primary исправен. Replica в этом стенде не принимает уникальные записи:

```sh
python3 -m scripts.recovery compose stop replica
python3 -m scripts.recovery compose rm -f replica
docker volume rm bd-news-recovery_replica_data
python3 -m scripts.recovery up
```

Удаляется только копия replica; primary и backup сохраняются. Затем выполнить
диагностику и `outages` для подтверждения получения новых маркеров.

## Проверка целостности

```sh
python3 -m scripts.recovery compose exec -T postgres psql -X -w -v ON_ERROR_STOP=1 -U news_bootstrap -d news_aggregator \
  -f /workspace/recovery/integrity.sql
python3 -m scripts.recovery compose exec -T restore psql -X -w -v ON_ERROR_STOP=1 -U news_bootstrap -d news_aggregator \
  -f /workspace/recovery/integrity.sql
python3 -m scripts.recovery compose exec -T replica psql -X -w -v ON_ERROR_STOP=1 -U news_bootstrap -d news_aggregator \
  -c "SELECT label, actor FROM recovery_lab.probe ORDER BY label;"
```

Проверка FK читает фактические строки; также проверяются валидность индексов и
ограничений и наличие семи миграций. Полное сравнение таблиц/схемы/sequences
с backup выполняет команда `restore`; полный самостоятельный прогон — `verify`.
Сохранять UTC-время, действие, результат клиента, подтверждение streaming и
целостности. Готовый журнал: `artifacts/recovery/<project>/events.txt`.
