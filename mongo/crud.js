// CRUD исполняется целиком; каждая операция подтверждается чтением результата.
// articles: моделируем применение нового снимка PostgreSQL к учебной копии.
const article = fixture.article("1002");
lab.db.articles.insertOne(article);
lab.check(lab.db.articles.findOne({_id: article._id}).title === "Новость 1002", "articles: Create + Read");
lab.check(lab.db.articles.updateOne({_id: article._id}, {$set: {title: "Уточнённый исходный заголовок"}}).modifiedCount === 1,
    "articles: применено обновление снимка");
lab.check(lab.db.articles.findOne({_id: article._id}).title === "Уточнённый исходный заголовок", "articles: Update подтверждён чтением");
lab.db.articles.updateOne({_id: article._id}, {$set: {deletedAt: ISODate("2026-10-03T00:00:00Z")}});
lab.check(lab.db.articles.countDocuments({_id: article._id, deletedAt: null}) === 0, "articles: удалённая в источнике новость скрыта");
lab.check(lab.db.articles.deleteOne({_id: article._id}).deletedCount === 1 && !lab.db.articles.findOne({_id: article._id}),
    "articles: Delete учебной копии");

// article_events: запись просмотра, чтение, обезличивание и удаление тестового события.
const eventId = lab.db.article_events.insertOne(fixture.event()).insertedId;
lab.check(lab.db.article_events.findOne({_id: eventId}).type === "view", "article_events: Create + Read");
lab.db.article_events.updateOne({_id: eventId}, {$set: {userId: null}});
lab.check(lab.db.article_events.findOne({_id: eventId}).userId === null, "article_events: Update — обезличивание");
lab.check(lab.db.article_events.deleteOne({_id: eventId}).deletedCount === 1 && !lab.db.article_events.findOne({_id: eventId}),
    "article_events: Delete");

// import_payloads: сохранить RSS, прочитать, исправить ошибочно записанный ответ, удалить.
const payloadId = lab.db.import_payloads.insertOne({...fixture.payload(), format: "rss", raw: "<rss/>"}).insertedId;
lab.check(lab.db.import_payloads.findOne({_id: payloadId}).raw === "<rss/>", "import_payloads: Create + Read");
lab.db.import_payloads.updateOne({_id: payloadId}, {$set: {raw: "<rss><channel/></rss>"}});
lab.check(lab.db.import_payloads.findOne({_id: payloadId}).raw === "<rss><channel/></rss>", "import_payloads: Update");
lab.check(lab.db.import_payloads.deleteOne({_id: payloadId}).deletedCount === 1 && !lab.db.import_payloads.findOne({_id: payloadId}),
    "import_payloads: Delete");

// reading_lists: элементы встроены, статья хранится отдельно; userId задаёт доверенный клиент.
const listId = lab.db.reading_lists.insertOne(fixture.list()).insertedId;
const ownedList = {_id: listId, userId: NumberLong("1")};
lab.check(lab.db.reading_lists.findOne(ownedList).items.length === 1, "reading_lists: Create + Read со встроенными items");
lab.check(lab.db.articles.countDocuments({_id: NumberLong("1001"), deletedAt: null}) === 1, "ссылка на добавляемую статью существует в учебном снимке");
lab.db.reading_lists.updateOne(ownedList, {$push: {items: fixture.item("1001")}});
lab.db.reading_lists.updateOne(ownedList, {$set: {"items.$[item].note": "Прочитано"}},
    {arrayFilters: [{"item.articleId": NumberLong("1001")}]});
const updatedList = lab.db.reading_lists.findOne(ownedList);
lab.check(updatedList.items.length === 2 && updatedList.items[1].note === "Прочитано", "reading_lists: Update вложенного элемента");
lab.check(lab.db.reading_lists.deleteOne({_id: listId, userId: NumberLong("2")}).deletedCount === 0,
    "фильтр владельца не удаляет чужую подборку (не самостоятельная аутентификация)");
lab.check(lab.db.reading_lists.deleteOne(ownedList).deletedCount === 1 && !lab.db.reading_lists.findOne({_id: listId}),
    "reading_lists: Delete");

// Reference и 1:N: события не встраиваются в растущий документ статьи.
const withEvents = lab.db.articles.aggregate([
    {$match: {_id: NumberLong("1000")}},
    {$lookup: {from: "article_events", localField: "_id", foreignField: "articleId", as: "events"}}
]).toArray()[0];
lab.check(withEvents.events.length === 2, "reference 1:N: одна статья и два события через $lookup");

// M:N: A содержит 1000/1001, B содержит 1000; тексты статей не дублируются в items.
const listsWithArticles = lab.db.reading_lists.aggregate([
    {$lookup: {from: "articles", localField: "items.articleId", foreignField: "_id", as: "articleCards"}},
    {$sort: {_id: 1}}
]).toArray();
lab.check(listsWithArticles.length === 2 && listsWithArticles[0].articleCards.length === 2
    && listsWithArticles[1].articleCards.length === 1
    && lab.db.reading_lists.countDocuments({"items.articleId": NumberLong("1000")}) === 2,
    "reference M:N: пересекающиеся подборки и чтение карточек через $lookup");
for (const name of ["articles", "article_events", "import_payloads", "reading_lists"]) {
    print(`Пример ${name}: ${lab.json(lab.db.getCollection(name).findOne())}`);
}
