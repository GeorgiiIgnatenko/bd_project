-- q2 
-- Поиск новостей по ключевому слову с фильтром по категории (SC-02)
-- Бизнес-вопрос: какие новости выбранной категории содержат слово в заголовке или тексте?
-- Параметры: search_text, category_name

SELECT n.id,
       n.title,
       s.name AS source,
       c.name AS category,
       n.published_at
FROM news n
JOIN news_source s    ON s.id = n.source_id
JOIN news_category nc ON nc.news_id = n.id
JOIN category c       ON c.id = nc.category_id
WHERE c.name = :'category_name'
  AND (n.title   ILIKE '%' || :'search_text' || '%'
    OR n.content ILIKE '%' || :'search_text' || '%')
ORDER BY n.published_at DESC, n.id DESC;
