-- Запуск через python3 -m scripts.mongo compare, входной fixture задаёт psql.
BEGIN;
SET LOCAL search_path TO pg_temp;
CREATE TEMP TABLE lists (id text PRIMARY KEY, owner_id bigint NOT NULL, name text NOT NULL);
CREATE TEMP TABLE items (
    list_id text REFERENCES lists(id), article_id bigint, added_at timestamptz NOT NULL,
    note text NOT NULL, PRIMARY KEY (list_id, article_id)
);
INSERT INTO lists
SELECT l->>'id', (l->>'userId')::bigint, l->>'name'
FROM jsonb_array_elements(:'fixture'::jsonb->'lists') l;
INSERT INTO items
SELECT l->>'id', (i->>'articleId')::bigint, (:'fixture'::jsonb->>'addedAt')::timestamptz, i->>'note'
FROM jsonb_array_elements(:'fixture'::jsonb->'lists') l
CROSS JOIN LATERAL jsonb_array_elements(l->'items') i;

CREATE TEMP VIEW notes AS
SELECT jsonb_agg(jsonb_build_array(l.owner_id, l.id, i.article_id, i.note)
                 ORDER BY l.owner_id, l.id, i.article_id) AS snapshot
FROM lists l JOIN items i ON i.list_id = l.id;
SELECT snapshot FROM notes;

WITH edit AS (SELECT :'fixture'::jsonb->'edit' AS e)
UPDATE items i SET note = e->>'note'
FROM lists l, edit
WHERE l.id = e->>'listId' AND l.owner_id = (e->>'userId')::bigint
  AND i.list_id = l.id AND i.article_id = (e->>'articleId')::bigint;
SELECT snapshot FROM notes;
ROLLBACK;
