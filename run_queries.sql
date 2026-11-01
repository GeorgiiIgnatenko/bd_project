\set ON_ERROR_STOP on
\ir sql/query_parameters.sql
BEGIN READ ONLY;
SET LOCAL app.current_user_id TO :'user_id';

\echo  'q1: персонализированная лента'
\ir sql/queries/q1_personal_feed.sql

\echo 'q2: поиск по категории'
\ir sql/queries/q2_search_by_category.sql

\echo 'q3: популярность категорий'
\ir sql/queries/q3_category_popularity.sql

\echo 'q4: статистика сбора'
\ir sql/queries/q4_source_import_stats.sql

\echo 'q5: проблемные источники'
\ir sql/queries/q5_problem_sources.sql
\echo 'All queries completed successfully'
COMMIT;
