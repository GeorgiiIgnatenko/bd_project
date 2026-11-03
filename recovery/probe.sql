\set ON_ERROR_STOP on
BEGIN;
SELECT current_user, count(*) AS news_count FROM public.news;
INSERT INTO recovery_lab.probe(label) VALUES (:'label') RETURNING label, actor;
COMMIT;
