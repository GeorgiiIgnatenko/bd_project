-- Automated reproduction, diagnostics and ordered-locking repair:
-- python3 -m experiments.concurrency
-- Live diagnostic query (run while a session waits):
SELECT pid, application_name, wait_event_type, wait_event,
       pg_blocking_pids(pid) AS blocked_by, state
FROM pg_stat_activity
WHERE datname = current_database() AND cardinality(pg_blocking_pids(pid)) > 0;
