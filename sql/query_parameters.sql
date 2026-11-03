-- Override defaults with psql -v; fixed as_of makes examples reproducible.
\if :{?as_of}
\else
  SELECT now()::text AS as_of \gset
\endif
\if :{?user_id}
\else
  \set user_id 1
\endif
\if :{?window_days}
\else
  \set window_days 30
\endif
\if :{?page_size}
\else
  \set page_size 20
\endif
\if :{?page_offset}
\else
  \set page_offset 0
\endif
\if :{?search_text}
\else
  \set search_text матч
\endif
\if :{?category_name}
\else
  \set category_name Спорт
\endif
\if :{?date_from}
\else
  \set date_from '2026-01-01 00:00:00+00'
\endif
\if :{?days}
\else
  \set days 7
\endif
\if :{?min_failed_runs}
\else
  \set min_failed_runs 1
\endif
\if :{?top_ranks}
\else
  \set top_ranks 3
\endif
\if :{?source_id}
\else
  \set source_id 1
\endif
