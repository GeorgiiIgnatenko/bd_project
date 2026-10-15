-- ==============================================================================
-- 3. ВОСПРОИЗВЕДЕНИЕ, ДИАГНОСТИКА И УСТРАНЕНИЕ DEADLOCK
-- ==============================================================================

SET search_path TO dev, pg_catalog;

-- 1. Подготовка тестовой таблицы с ресурсами
DROP TABLE IF EXISTS deadlock_resource CASCADE;
CREATE TABLE deadlock_resource (
    id INT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    balance NUMERIC NOT NULL DEFAULT 1000
);
INSERT INTO deadlock_resource (id, name, balance) VALUES 
(1, 'Ресурс А (Источник 1)', 1000), 
(2, 'Ресурс Б (Источник 2)', 2000);

-- ==============================================================================
-- 2. СЦЕНАРИЙ ВОЗНИКНОВЕНИЯ DEADLOCK (Несогласованный порядок блокировок)
-- ==============================================================================
-- СЕССИЯ 1:
-- BEGIN;
-- UPDATE deadlock_resource SET balance = balance + 10 WHERE id = 1; -- Захват ресурса 1
-- SELECT pg_sleep(2);
-- UPDATE deadlock_resource SET balance = balance + 10 WHERE id = 2; -- Ожидание ресурса 2 -> DEADLOCK ERROR!
-- COMMIT;

-- СЕССИЯ 2 (запускается параллельно через 0.5 сек):
-- BEGIN;
-- UPDATE deadlock_resource SET balance = balance - 20 WHERE id = 2; -- Захват ресурса 2
-- SELECT pg_sleep(2);
-- UPDATE deadlock_resource SET balance = balance - 20 WHERE id = 1; -- Ожидание ресурса 1 -> Конфликт!
-- COMMIT;

-- ==============================================================================
-- 3. ДИАГНОСТИЧЕСКИЙ ЗАПРОС ДЛЯ ВЫЯВЛЕНИЯ БЛОКИРОВОК И ОЖИДАНИЙ В POSTGRESQL
-- ==============================================================================
SELECT 
    blocked_locks.pid     AS blocked_pid,
    blocked_activity.usename  AS blocked_user,
    blocking_locks.pid    AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query    AS blocked_statement,
    blocking_activity.query   AS blocking_statement,
    blocked_activity.state    AS blocked_state,
    blocking_activity.state   AS blocking_state
FROM  pg_catalog.pg_locks         blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks         blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- ==============================================================================
-- 4. РЕШЕНИЕ DEADLOCK: ДЕТЕРМИНИРОВАННЫЙ ПОРЯДОК ЗАХВАТА БЛОКИРОВОК (ORDERED LOCKING)
-- ==============================================================================
-- Все транзакции должны захватывать ресурсы строго в одном и том же порядке (по возрастанию ID):
-- СЕССИЯ 1 (исправленная):
-- BEGIN;
-- UPDATE deadlock_resource SET balance = balance + 10 WHERE id = 1;
-- UPDATE deadlock_resource SET balance = balance + 10 WHERE id = 2;
-- COMMIT;

-- СЕССИЯ 2 (исправленная):
-- BEGIN;
-- UPDATE deadlock_resource SET balance = balance - 20 WHERE id = 1; -- Ждет завершения сессии 1, без deadlock!
-- UPDATE deadlock_resource SET balance = balance - 20 WHERE id = 2;
-- COMMIT;
