-- Q5 filters failed runs by date and then joins the error log by run ID.
CREATE INDEX idx_failed_runs_started_at ON scrape_run (started_at, source_id)
WHERE status = 'ошибка';
CREATE INDEX idx_scrape_error_run ON scrape_error_log (scrape_run_id);
