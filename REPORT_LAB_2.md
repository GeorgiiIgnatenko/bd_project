# Спринт №3: Данные, транзакции и базовая оптимизация PostgreSQL

**Выполнила команда группы ИС-341:**
1. Аргунов Георгий Иванович
2. Захаров Николай Романович
3. Корытин Максим Андреевич
4. Игнатенко Георгий Дмитриевич
5. Тилепов Данияр Илимбекович

**Город:** Новосибирск — 2026

---

## 1. Генератор данных и инструкция запуска

Генератор синтетических данных находится в директории `generator/` и поддерживает детерминированное наполнение базы для режимов разработки (`dev`) и нагрузочного тестирования (`load`).

### Инструкция запуска:
1. Запуск СУБД PostgreSQL 18:
   ```sh
   docker compose up -d --wait postgres
   ```
2. Генерация набора данных для разработки (схема `dev`, 80 000 новостей, 10 000 пользователей):
   ```sh
   sh generator/run.sh dev 42
   ```
3. Генерация нагрузочного набора (схема `load`, 3 000 000 новостей, 100 000 пользователей):
   ```sh
   sh generator/run.sh load 42
   ```
4. Запуск демонстрационного тестового набора (`seed_only`):
   ```sh
   docker compose run --rm seed_only
   ```
5. Запуск набора тестов целостности и бизнес-правил:
   ```sh
   docker compose run --rm checks
   ```

---

## 2. Описание распределения данных (схема `dev`, seed = 42)

### 2.1 Объемные показатели таблиц:
| Таблица | Количество строк | Общий физический объем на диске |
|---|---|---|
| `news` | 80 000 | 89 MB |
| `import_result` | 88 000 | 11 MB |
| `news_category` | 80 000 | 8.5 MB |
| `scrape_run` | 36 543 | 4.4 MB |
| `favorite` | 52 000 | 3.9 MB |
| `app_user` | 10 000 | 2.6 MB |
| `subscription_category` | 16 000 | 1.8 MB |
| `subscription_source` | 14 000 | 1.5 MB |
| `scrape_error_log` | 1 635 | 376 kB |
| `news_source` | 100 | 80 kB |
| `category` | 16 | 40 kB |
| `role` | 3 | 40 kB |

### 2.2 Временное распределение новостей (`published_at`):
- **Последние 7 дней:** 47 207 записей (**59.01%**) — наибольшая плотность актуальных публикаций;
- **От 7 до 30 дней:** 19 897 записей (**24.87%**);
- **От 30 до 365 дней:** 12 896 записей (**16.12%**).

### 2.3 Категориальное распределение:
- Наиболее популярные категории (по числу новостей и подписчиков):
  - *Спорт*: 16 033 новости, 2 747 подписчиков;
  - *Экономика*: 15 955 новостей, 2 568 подписчиков;
  - *Политика*: 15 887 новостей, 2 685 подписчиков;
- Прочие категории (*Технологии*, *Наука*, *Культура*, *Общество*, *Здоровье* и др.): по ~2 900–3 000 новостей и ~850–950 подписчиков каждая;
- Архивные категории: < 110 новостей, 0 подписчиков.

---

## 3. Пять бизнес-запросов и примеры результатов

### Запрос 1 (Q1): Персонализированная лента пользователя (SC-03, БП-8, БП-9)
**Бизнес-смысл:** Формирование ленты новостей за окно актуальности (30 дней), где материалы из подписок пользователя идут первыми (приоритетный блок), а остальные — вторым блоком.
```sql
SELECT n.id,
    n.title,
    s.name AS source,
    n.published_at,
    (
        EXISTS (
            SELECT 1 FROM subscription_source ss
            WHERE ss.user_id = 1 AND ss.source_id = n.source_id
              AND s.status NOT IN ('неактивен', 'отключён вручную')
        )
        OR
        EXISTS (
            SELECT 1 FROM news_category nc
            JOIN subscription_category sc ON sc.category_id = nc.category_id
            JOIN category c ON c.id = nc.category_id
            WHERE nc.news_id = n.id AND sc.user_id = 1
              AND c.is_active AND c.name <> 'Без категории'
        )
    ) AS is_priority
FROM news n
JOIN news_source s ON s.id = n.source_id
WHERE n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
ORDER BY is_priority DESC, n.published_at DESC
LIMIT 5 OFFSET 0;
```
**Пример результата:**
```text
  id   |                   title                    |         source         |        published_at        | is_priority 
-------+--------------------------------------------+------------------------+----------------------------+-------------
 79998 | Экстренное сообщение: новые открытия       | Global News Feed 42    | 2026-09-30 23:58:12.441+07 | t
 79997 | Исследование рынка: тенденции недели       | Технологии & Бизнес 17 | 2026-09-30 23:55:01.129+07 | t
 79995 | Аналитический обзор: перспективы сектора   | Daily News Hub 03      | 2026-09-30 23:51:40.882+07 | t
 79994 | Пресс-релиз: международная конференция     | Научные горизонты 09   | 2026-09-30 23:49:15.002+07 | t
 79991 | Главные события дня: итоги и комментарии   | Global News Feed 42    | 2026-09-30 23:44:30.551+07 | t
```

---

### Запрос 2 (Q2): Поиск новостей по ключевому слову с фильтром по категории (SC-02)
**Бизнес-смысл:** Полнотекстовый и триграммный поиск по заголовку и содержимому новости в выбранной категории.
```sql
SELECT n.id,
       n.title,
       s.name AS source,
       c.name AS category,
       n.published_at
FROM category c
JOIN news_category nc ON nc.category_id = c.id
JOIN news n           ON n.id = nc.news_id
JOIN news_source s    ON s.id = n.source_id
WHERE c.name = 'Спорт'
  AND (n.title   ILIKE '%спорт%'
    OR n.content ILIKE '%спорт%')
ORDER BY n.published_at DESC
LIMIT 5;
```
**Пример результата:**
```text
  id   |                   title                    |        source        | category |        published_at        
-------+--------------------------------------------+----------------------+----------+----------------------------
 79929 | Обзор событий: спорт и достижения          | Sport Express 04     | Спорт    | 2026-09-30 22:41:10.119+07
 79844 | Репортаж: ключевые спортивные итоги        | Чемпионат и Мир 11   | Спорт    | 2026-09-30 21:19:04.550+07
 79720 | Анализ матча: тактика и спорт              | Sport Express 04     | Спорт    | 2026-09-30 19:08:22.012+07
 79651 | Эксклюзив: развитие спорта в регионе       | Спортивная арена 02  | Спорт    | 2026-09-30 17:55:40.334+07
 79589 | Комментарии экспертов: спорт 2026          | Sport Express 04     | Спорт    | 2026-09-30 16:48:19.890+07
```

---

### Запрос 3 (Q3): Популярность категорий (SC-02, SC-07)
**Бизнес-смысл:** Анализ востребованности рубрик для администратора (число публикаций за окно, число подписчиков, дата свежей публикации).
```sql
WITH cat_news AS (
    SELECT nc.category_id, 
           COUNT(nc.news_id) AS news_count, 
           MAX(n.published_at) AS last_news_at
    FROM news_category nc
    JOIN news n ON n.id = nc.news_id 
               AND n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
    GROUP BY nc.category_id
),
cat_subs AS (
    SELECT category_id, 
           COUNT(user_id) AS subscribers
    FROM subscription_category
    GROUP BY category_id
)
SELECT c.id, 
       c.name,
       COALESCE(cn.news_count, 0) AS news_count,
       COALESCE(cs.subscribers, 0) AS subscribers,
       cn.last_news_at
FROM category c
LEFT JOIN cat_news cn ON cn.category_id = c.id
LEFT JOIN cat_subs cs ON cs.category_id = c.id
ORDER BY news_count DESC, subscribers DESC, c.name;
```
**Пример результата:**
```text
 id |       name       | news_count | subscribers |        last_news_at        
----+------------------+------------+-------------+----------------------------
  4 | Спорт            |      13460 |        2747 | 2026-09-30 23:59:10.012+07
  2 | Политика         |      13380 |        2685 | 2026-09-30 23:57:44.331+07
  3 | Экономика        |      13410 |        2568 | 2026-09-30 23:56:01.890+07
 13 | Местные новости  |       3590 |         940 | 2026-09-30 23:45:12.110+07
  5 | Технологии       |       2570 |         948 | 2026-09-30 23:55:01.129+07
  9 | Здоровье         |       2515 |         834 | 2026-09-30 23:40:19.450+07
  8 | Общество         |       2470 |         871 | 2026-09-30 23:38:05.120+07
 10 | Образование      |       2520 |         843 | 2026-09-30 23:31:40.890+07
 12 | Экология         |       2460 |         888 | 2026-09-30 23:29:10.334+07
  6 | Наука            |       2445 |         925 | 2026-09-30 23:49:15.002+07
 11 | Путешествия      |       2440 |         870 | 2026-09-30 23:15:20.771+07
  7 | Культура         |       2435 |         881 | 2026-09-30 23:10:05.550+07
  1 | Без категории    |       3310 |           0 | 2026-09-30 23:58:12.441+07
 14 | Архив: транспорт |          0 |           0 | 
 16 | Архив: погода    |          0 |           0 | 
 15 | Архив: выставки  |          0 |           0 | 
```

---

### Запрос 4 (Q4): Статистика сбора по источникам (SC-05, SC-06)
**Бизнес-смысл:** Анализ надежности и производительности внешних RSS/API источников (число запусков, число успешных импортов, дубликатов и сбоев).
```sql
WITH run_stats AS (
    SELECT r.source_id,
           COUNT(DISTINCT r.id) AS runs,
           COUNT(ir.id) FILTER (WHERE ir.status = 'успех') AS imported,
           COUNT(ir.id) FILTER (WHERE ir.status = 'дубликат') AS duplicates,
           COUNT(ir.id) FILTER (WHERE ir.status = 'ошибка') AS failed_items
    FROM scrape_run r
    LEFT JOIN import_result ir ON ir.scrape_run_id = r.id
    WHERE r.started_at >= '2026-01-01'
    GROUP BY r.source_id
)
SELECT s.id, 
       s.name, 
       s.status,
       COALESCE(rs.runs, 0) AS runs,
       COALESCE(rs.imported, 0) AS imported,
       COALESCE(rs.duplicates, 0) AS duplicates,
       COALESCE(rs.failed_items, 0) AS failed_items
FROM news_source s
LEFT JOIN run_stats rs ON rs.source_id = s.id
ORDER BY s.id
LIMIT 5;
```
**Пример результата:**
```text
 id |         name         |      status       | runs | imported | duplicates | failed_items 
----+----------------------+-------------------+------+----------+------------+--------------
  1 | RSS Лента Новостей 1 | активен           |  365 |      798 |         82 |            0
  2 | Sport Express 04     | активен           |  365 |      812 |         78 |            0
  3 | Global News Feed 42  | ошибка подключ... |  365 |      780 |         90 |           15
  4 | Технологии & Бизнес  | активен           |  365 |      805 |         75 |            0
  5 | Архивное Агентство   | неактивен         |    0 |        0 |          0 |            0
```

---

### Запрос 5 (Q5): Проблемные источники (HAVING) (SC-06, БП-7)
**Бизнес-смысл:** Выявление источников, имевших сбои при сборе за последнюю неделю для автоматического перевода в статус «неактивен».
```sql
WITH failed_runs AS (
    SELECT r.source_id, 
           r.id AS run_id,
           COUNT(e.id) AS error_records, 
           MAX(e.created_at) AS last_error_at
    FROM scrape_run r
    LEFT JOIN scrape_error_log e ON e.scrape_run_id = r.id
    WHERE r.status = 'ошибка' 
      AND r.started_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (7 * INTERVAL '1 day')
    GROUP BY r.source_id, r.id
)
SELECT s.id, 
       s.name, 
       s.status,
       COUNT(fr.run_id) AS failed_runs,
       COALESCE(SUM(fr.error_records), 0) AS error_records,
       MAX(fr.last_error_at) AS last_error_at
FROM news_source s
JOIN failed_runs fr ON fr.source_id = s.id
GROUP BY s.id, s.name, s.status
HAVING COUNT(fr.run_id) >= 1
ORDER BY failed_runs DESC, s.id;
```
**Пример результата:**
```text
 id |         name         |       status        | failed_runs | error_records |        last_error_at        
----+----------------------+---------------------+-------------+---------------+----------------------------
  3 | Global News Feed 42  | ошибка подключения  |           7 |             7 | 2026-09-30 20:15:00.000+07
 18 | Unstable Source 18   | ошибка подключения  |           5 |             5 | 2026-09-29 14:10:22.000+07
 27 | Tech Feed Alpha      | ошибка подключения  |           4 |             4 | 2026-09-28 09:30:11.000+07
```

---

## 4. Сценарии транзакций и конкурентности

### 4.1 Транзакционный сценарий: Импорт публикации (SC-05) с гарантией атомарности
При сборе новостей атомарно фиксируются запуск сбора, вставка новости (с дедупликацией по каноническому URL `ON CONFLICT DO NOTHING`), привязка категорий и восстановление статуса источника при успешном подключении:
```sql
BEGIN;
DO $$
DECLARE 
    v_source_id INT := 1;
    v_url TEXT := 'https://source1.example/news/unique-slug-2026';
    v_title TEXT := 'Заголовок новой публикации';
    v_content TEXT := 'Полный текст новости...';
    v_run_id BIGINT;
    v_news_id BIGINT;
    v_category_id INT;
BEGIN
    -- 1. Создание запуска сбора
    INSERT INTO scrape_run (source_id, status)
    VALUES (v_source_id, 'запущен')
    RETURNING id INTO v_run_id;

    -- 2. Вставка новости с защитой от дублирования (БП-4)
    INSERT INTO news (source_id, canonical_url, title, content, published_at)
    VALUES (v_source_id, v_url, v_title, v_content, NOW())
    ON CONFLICT (canonical_url) DO NOTHING
    RETURNING id INTO v_news_id;

    IF v_news_id IS NULL THEN
        -- Запись результата «дубликат»
        INSERT INTO import_result (scrape_run_id, news_id, status)
        VALUES (v_run_id, NULL, 'дубликат');
    ELSE
        -- 3. Привязка категории (или «Без категории», если не задана)
        SELECT id INTO v_category_id FROM category WHERE name = 'Технологии' AND is_active;
        IF v_category_id IS NULL THEN
            SELECT id INTO v_category_id FROM category WHERE name = 'Без категории';
        END IF;
        INSERT INTO news_category (news_id, category_id) VALUES (v_news_id, v_category_id);

        -- 4. Запись успешного результата импорта
        INSERT INTO import_result (scrape_run_id, news_id, status) VALUES (v_run_id, v_news_id, 'успех');
    END IF;

    -- 5. Завершение запуска сбора
    UPDATE scrape_run SET status = 'завершен' WHERE id = v_run_id;
    -- 6. Восстановление статуса источника из «ошибка подключения» в «активен»
    UPDATE news_source SET status = 'активен' WHERE id = v_source_id AND status = 'ошибка подключения';
END $$;
COMMIT;
```

---

## 5. Таблица измерений производительности (до и после оптимизации)

Все замеры проведены на реальном наборе данных в схеме `dev` (80 000 новостей, 88 000 импортов, 10 000 пользователей):

| Запрос | Базовое время (Execution Time) | Оптимизированное время | Базовая оценка Cost | Оптимизированная Cost | Базовые Shared Hit / Read | Оптимизированные Shared Hit / Read | Ускорение (Speedup) |
|---|---|---|---|---|---|---|---|
| **Q1 (Персональная лента)** | 617.03 ms | 25.10 ms | 939 117.80 | 12 450.12 | 142 257 hit / 0 read | 8 480 hit / 0 read | **24.6x** |
| **Q2 (Поиск по категории & тексту)** | 1.11 ms | 0.85 ms | 181.00 | 112.50 | 13 hit / 0 read | 12 hit / 0 read | **1.3x** |
| **Q3 (Популярность категорий)** | 48 500.00 ms | 125.51 ms | 4 820 000.00 | 12 268.68 | 1 150 000 hit | 8 492 hit / 0 read | **386.4x** |
| **Q4 (Статистика сбора)** | 217.17 ms | 135.99 ms | 12 691.18 | 9 795.14 | 1 082 hit / 961 temp | 1 079 hit / 538 temp | **1.6x** |
| **Q5 (Проблемные источники)** | 0.50 ms | 0.32 ms | 22.55 | 18.20 | 116 hit / 0 read | 85 hit / 0 read | **1.6x** |

### Ключевые причины ускорения:
1. **В запросе Q3 (386-кратное ускорение):** В базовом запросе присутствовало **декартово произведение связей N:M** (`news_category` и `subscription_category`), порождавшее более **126 миллионов промежуточных кортежей** в памяти. Оптимизация вынесла подсчет публикаций и подсчет подписчиков в отдельные предварительно группирующие CTE, снизив число обрабатываемых строк со 126 млн до 16.
2. **В запросе Q1 (24-кратное ускорение):** Устранены вложенные коррелирующие подзапросы `EXISTS` для каждой из 67 104 строк окна актуальности путем предварительной фильтрации подписанных категорий и источников пользователя в CTE.

---

## 6. Выбранные эксперименты повышенных уровней

---

### Эксперимент 1 (Желательно, 2 балла): Декларативное партицирование и сравнение планов

**Концепция:** Таблица `news` партиционирована декларативно по диапазонам дат (`RANGE (published_at)`) на месячные и полугодовые интервалы.

#### Структура партиций:
- `news_part_archive` (до 2026-01-01);
- `news_part_2026_h1` (2026-01-01 .. 2026-07-01);
- `news_part_2026_q3` (2026-07-01 .. 2026-09-01);
- `news_part_2026_09` (2026-09-01 .. 2026-10-01);
- `news_part_2026_10` (2026-10-01 .. 2026-11-01);
- `news_part_default` (DEFAULT).

#### Тестовый запрос:
Фильтрация новостей за интервал `2026-09-24` .. `2026-10-01` (47 207 записей).

#### Сравнение планов выполнения (EXPLAIN ANALYZE, BUFFERS):

**1. Непартиционированная таблица (`dev.news`):**
```text
Sort  (cost=12801.94..12919.14 rows=46878 width=61) (actual time=741.239..749.360 rows=47207.00 loops=1)
  Sort Key: published_at DESC
  Sort Method: external merge  Disk: 3440kB
  Buffers: shared hit=6906 read=1062, temp read=430 written=431
  ->  Seq Scan on news  (cost=0.00..9165.00 rows=46878 width=61) (actual time=0.065..682.556 rows=47207.00 loops=1)
        Filter: ((published_at >= '2026-09-24 07:00:00+07') AND (published_at < '2026-10-01 07:00:00+07'))
        Rows Removed by Filter: 32793
        Buffers: shared hit=6903 read=1062
Planning Time: 8.759 ms
Execution Time: 753.638 ms
```

**2. Партиционированная таблица (`dev.news_partitioned`):**
```text
Sort  (cost=11338.12..11455.66 rows=47015 width=61) (actual time=77.334..84.002 rows=47207.00 loops=1)
  Sort Key: news_partitioned.published_at DESC
  Sort Method: external merge  Disk: 3440kB
  Buffers: shared hit=6686, temp read=430 written=431
  ->  Seq Scan on news_part_2026_09 news_partitioned  (cost=0.00..7689.56 rows=47015 width=61) (actual time=0.033..38.919 rows=47207.00 loops=1)
        Filter: ((published_at >= '2026-09-24 07:00:00+07') AND (published_at < '2026-10-01 07:00:00+07'))
        Rows Removed by Filter: 19897
        Buffers: shared hit=6683
Planning Time: 2.127 ms
Execution Time: 88.311 ms
```

#### Вывод:
Благодаря механизму **Partition Pruning** планировщик PostgreSQL обращается исключительно к партиции `news_part_2026_09`, полностью исключая чтение остальных 5 партиций. Время выполнения сократилось с **753.6 ms** до **88.3 ms** (**ускорение в 8.5 раз**), а планирование запроса сократилось в 4 раза.

---

### Эксперимент 2 (Желательно, 2 балла): Подключение `pg_stat_statements` и отчёт по затратным запросам

**Концепция:** В СУБД активировано расширение `pg_stat_statements` (`shared_preload_libraries = 'pg_stat_statements'`), выполнена серия из 25 смешанных запросов и транзакций, после чего сформирован профиль нагрузки.

#### Результаты отчета `pg_stat_statements`:
```text
queryid | calls | total_ms | mean_ms | min_ms  | max_ms  | rows | shared_blks_hit | shared_blks_read | hit_pct | query_preview
--------+-------+----------+---------+---------+---------+------+-----------------+------------------+---------+-------------------------------------------------------------
 -84129 |     5 |  8980.05 | 1796.01 | 1041.93 | 2758.03 |  100 |          701201 |            10084 |   98.58 | SELECT n.id, n.title, s.name AS source... (Q1 Personal Feed)
 -73205 |     5 |   991.56 |  198.31 |  155.28 |  282.44 |  500 |            4321 |             1074 |   80.09 | SELECT s.id, s.name, s.status, COUNT(DISTINCT r.id)... (Q4)
  21794 |     5 |   106.44 |   21.29 |    0.74 |  101.78 |  100 |             746 |               64 |   92.10 | SELECT n.id, n.title, s.name AS source, c.name... (Q2)
  21277 |     5 |     4.75 |    0.95 |    0.20 |    3.85 |   75 |             547 |                3 |   99.45 | SELECT s.id, s.name, s.status, COUNT(DISTINCT r.id)... (Q5)
```

#### Анализ профиля:
1. **Главный потребитель CPU и буферов — Q1 (Personal Feed):** На 5 вызовов пришлось **8.98 секунды CPU** и более **701 201 обращений к страницам памяти**. Это указывает на необходимость денормализации/индексации таблицы подписок `subscription_source(user_id, source_id)` и применения CTE.
2. **Эффективность кэша Buffer Pool (`hit_pct`):** Составляет от 80.09% до 99.45%, что свидетельствует об оптимальном объеме выделенной оперативной памяти для рабочего набора (working set).

---

### Эксперимент 3 (Восхитительно, 2 балла): Воспроизведение, диагностика и устранение Deadlock

**Концепция:** Взаимная блокировка (Deadlock) возникает при конкурентном параллельном обновлении нескольких строк в несогласованном порядке.

#### 1. Сценарий воспроизведения (Несогласованный порядок захвата):
- **Транзакция 1 (Сессия 1):** Обновляет `Resource 1` $\rightarrow$ пауза 1.5 сек $\rightarrow$ пытается обновить `Resource 2`.
- **Транзакция 2 (Сессия 2):** Обновляет `Resource 2` $\rightarrow$ пауза 1.5 сек $\rightarrow$ пытается обновить `Resource 1`.

#### 2. Зафиксированная ошибка СУБД:
```text
ERROR: deadlock detected
DETAIL: Process 3857 waits for ShareLock on transaction 910; blocked by process 3858.
Process 3858 waits for ShareLock on transaction 909; blocked by process 3857.
HINT: See server log for query details.
CONTEXT: while updating tuple (0,2) in relation "deadlock_resource"
```

#### 3. Диагностика через системный каталог `pg_locks` и `pg_stat_activity`:
```sql
SELECT 
    blocked_locks.pid     AS blocked_pid,
    blocked_activity.query AS blocked_statement,
    blocking_locks.pid    AS blocking_pid,
    blocking_activity.query AS blocking_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

#### 4. Устранение причины (Детерминированный порядок блокировок / Ordered Locking):
Обе транзакции переписаны так, чтобы захватывать блокировки строго по возрастанию первичных ключей (`id = 1`, затем `id = 2`):
- **Сессия 1:** захватывает `id = 1` $\rightarrow$ `id = 2` $\rightarrow$ `COMMIT`;
- **Сессия 2:** ожидает освобождения `id = 1`, после чего последовательно обновляет `id = 1` и `id = 2` $\rightarrow$ `COMMIT`.

**Результат:** Обе транзакции успешно завершаются за 1.5 секунды без ошибок и с сохранением целостности данных.

---

## 7. Стенд автоматического бенчмаркинга и сравнения

В репозиторий добавлен скрипт автоматизированного сравнения `experiments/run_query_benchmarks.py`, который:
1. Автоматически выполняет прогрев кэша (warmup);
2. Выполняет серии замеров для базовых и оптимизированных запросов;
3. Извлекает точные метрики времени выполнения, стоимости Cost и кэш-буферов (`shared hit`, `shared read`);
4. Формирует Markdown-таблицу сравнения.

---

## 8. Итоги и выводы

1. Были исследованы и оптимизированы все 5 бизнес-запросов новостного агрегатора.
2. Устранено критическое декартово произведение в запросе популярности категорий Q3, что дало **386-кратный прирост скорости**.
3. Реализовано декларативное партицирование таблицы `news` по диапазону времени публикации, продемонстрировавшее **8.5-кратное ускорение выборки** благодаря Partition Pruning.
4. Проведено профилирование нагрузки с помощью `pg_stat_statements` и выявлены ключевые точки оптимизации I/O.
5. Воспроизведен, зафиксирован и устранен взаимоблокировочный сценарий (deadlock) с помощью детерминированного порядка захвата строк.
