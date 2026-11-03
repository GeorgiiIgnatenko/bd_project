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

\echo 'q6: рейтинг источников внутри категорий'
\ir sql/queries/q6_category_source_ranking.sql

\echo 'q7: интервалы между публикациями источников'
\ir sql/queries/q7_source_publication_gaps.sql

\echo 'q8: ежедневная динамика публикаций источника'
\ir sql/queries/q8_source_daily_trend.sql
\echo 'All queries completed successfully'
COMMIT;
