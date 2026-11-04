load("/workspace/mongo/common.js");
load("/workspace/mongo/scenario.js");

// Проверяем реальное поведение сервера, а не только наличие файлов схемы.
function rejectInsert(name, document, label, code = 121) {
    const collection = lab.db.getCollection(name);
    const before = collection.countDocuments({});
    lab.expectError(() => collection.insertOne(document), label, code);
    lab.check(collection.countDocuments({}) === before, `${label}: вставка не сохранилась`);
}

function rejectUpdate(name, id, update, label, code = 121) {
    const collection = lab.db.getCollection(name);
    const before = lab.json(collection.findOne({_id: id}));
    lab.expectError(() => collection.updateOne({_id: id}, update), label, code);
    lab.check(lab.json(collection.findOne({_id: id})) === before, `${label}: документ не изменился`);
}

for (const info of lab.db.getCollectionInfos()) {
    lab.check(info.options.validationLevel === "strict" && info.options.validationAction === "error",
        `${info.name}: strict/error действительно включены`);
}

// В каждой коллекции все предметные обязательные поля проверяются и на insert, и на update.
const requiredCases = [
    ["articles", () => fixture.article("9000"), NumberLong("1000"),
        ["canonicalUrl", "title", "content", "publishedAt", "source", "categories", "deletedAt"]],
    ["article_events", () => fixture.event(), lab.db.article_events.findOne()._id,
        ["articleId", "userId", "type", "at"]],
    ["import_payloads", () => fixture.payload(), lab.db.import_payloads.findOne()._id,
        ["scrapeRunId", "sourceId", "format", "receivedAt", "raw"]],
    ["reading_lists", () => fixture.list(), fixture.listA, ["userId", "name", "items"]]
];
for (const [name, factory, id, fields] of requiredCases) {
    for (const field of fields) {
        const document = factory();
        delete document[field];
        rejectInsert(name, document, `${name}: отсутствует ${field}`);
        rejectUpdate(name, id, {$unset: {[field]: ""}}, `${name}: удаление обязательного ${field}`);
    }
}

const typeCases = [
    ["articles", () => fixture.article("9000"), NumberLong("1000"), "publishedAt", "2026-10-01"],
    ["articles", () => fixture.article("9000"), NumberLong("1000"), "source", {id: "2", name: "Источник"}],
    ["article_events", () => fixture.event(), lab.db.article_events.findOne()._id, "articleId", NumberInt(1000)],
    ["import_payloads", () => fixture.payload(), lab.db.import_payloads.findOne()._id, "sourceId", "2"],
    ["reading_lists", () => fixture.list(), fixture.listA, "userId", "1"],
    ["reading_lists", () => fixture.list(), fixture.listA, "items", {}],
    ["reading_lists", () => fixture.list(), fixture.listA, "items", [{articleId: "1000", addedAt: new Date()}]],
    ["reading_lists", () => fixture.list(), fixture.listA, "items", [{articleId: NumberLong("1000")}]],
    ["reading_lists", () => fixture.list(), fixture.listA, "name", "   "]
];
for (const [name, factory, id, field, value] of typeCases) {
    rejectInsert(name, {...factory(), [field]: value}, `${name}: неверное значение ${field}`);
    rejectUpdate(name, id, {$set: {[field]: value}}, `${name}: обновление на неверное ${field}`);
}
rejectInsert("articles", {...fixture.article("9000"), _id: NumberInt(9000)}, "articles: _id должен быть long");
rejectInsert("article_events", {...fixture.event(), type: "unknown"}, "article_events: неизвестный тип события");
rejectInsert("reading_lists", {...fixture.list(), unexpected: true}, "reading_lists: неизвестное поле");
rejectInsert("reading_lists", {...fixture.list(), items: [fixture.item("1000", "я".repeat(1001))]}, "reading_lists: заметка длиннее 1000 символов");

// БП-1: 0 и 200 допустимы; 201 запрещено. Для границы создаём реальные учебные ссылки.
const boundaryArticles = Array.from({length: 200}, (_, i) => fixture.article(String(2000 + i)));
lab.db.articles.insertMany(boundaryArticles);
const boundaryItems = boundaryArticles.map(article => fixture.item(article._id.toString(), "я".repeat(1000)));
const emptyId = lab.db.reading_lists.insertOne({...fixture.list(), name: "я".repeat(100), items: []}).insertedId;
lab.check(lab.db.reading_lists.findOne({_id: emptyId}).items.length === 0, "БП-1: пустая подборка разрешена");
lab.db.reading_lists.updateOne({_id: emptyId}, {$set: {items: boundaryItems}});
lab.check(lab.db.reading_lists.findOne({_id: emptyId}).items.length === 200, "БП-1: обновление до 200 разрешено");
const fullId = lab.db.reading_lists.insertOne({...fixture.list(), items: boundaryItems}).insertedId;
lab.check(lab.db.reading_lists.findOne({_id: fullId}).items.length === 200, "БП-1: вставка 200 разрешена");
const bsonBytes = lab.db.reading_lists.aggregate([
    {$match: {_id: emptyId}}, {$project: {_id: 0, bytes: {$bsonSize: "$$ROOT"}}}
]).toArray()[0].bytes;
lab.check(bsonBytes < 1024 * 1024, "ограниченная подборка с 200 длинными заметками меньше 1 МиБ");
print(`MEASURE: BSON reading_list, 200 элементов, note=1000 кириллических символов: ${bsonBytes} байт`);
rejectInsert("reading_lists", {...fixture.list(), items: [...boundaryItems, fixture.item()]}, "БП-1: вставка 201 элемента");
rejectUpdate("reading_lists", emptyId, {$push: {items: fixture.item()}}, "БП-1: добавление 201-го элемента");

// БП-2: отличаются note/addedAt, но совпадает идентификатор статьи.
const duplicateItem = {...fixture.item("1000", "Другая заметка"), addedAt: ISODate("2026-10-03T00:00:00Z")};
rejectInsert("reading_lists", {...fixture.list(), items: [fixture.item(), duplicateItem]}, "БП-2: повторный articleId при вставке");
rejectUpdate("reading_lists", fixture.listA, {$push: {items: duplicateItem}}, "БП-2: повторный articleId при обновлении");

// БП-3: проверяются оба направления условного правила и корректная смена пары полей.
const savedPayloadId = lab.db.import_payloads.findOne()._id;
rejectInsert("import_payloads", {...fixture.payload(), raw: "<rss/>"}, "БП-3: json_api со строкой");
rejectInsert("import_payloads", {...fixture.payload(), format: "rss"}, "БП-3: rss с объектом");
rejectUpdate("import_payloads", savedPayloadId, {$set: {raw: "<rss/>"}}, "БП-3: смена raw без format");
rejectUpdate("import_payloads", savedPayloadId, {$set: {format: "rss"}}, "БП-3: смена format без raw");
lab.db.import_payloads.updateOne({_id: savedPayloadId}, {$set: {format: "rss", raw: "<rss/>"}});
lab.check(lab.db.import_payloads.findOne({_id: savedPayloadId}).raw === "<rss/>", "БП-3: согласованное обновление format/raw разрешено");
lab.db.import_payloads.updateOne({_id: savedPayloadId}, {$set: {format: "json_api", raw: fixture.payload().raw}});

// Уникальный URL: код 11000 отличаем от отказа schema validation 121.
rejectInsert("articles", {...fixture.article("9000"), canonicalUrl: fixture.article().canonicalUrl}, "уникальность canonicalUrl", 11000);
rejectUpdate("articles", NumberLong("1001"), {$set: {canonicalUrl: fixture.article().canonicalUrl}}, "уникальность canonicalUrl при обновлении", 11000);

lab.db.reading_lists.deleteMany({_id: {$in: [emptyId, fullId]}});
lab.db.articles.deleteMany({_id: {$in: boundaryArticles.map(article => article._id)}});
lab.check(lab.db.articles.countDocuments({}) === 2 && lab.db.reading_lists.countDocuments({}) === 2
    && lab.db.article_events.countDocuments({}) === 2 && lab.db.import_payloads.countDocuments({}) === 1,
    "после проверок остался только согласованный демонстрационный набор");
print(`PASS: MongoDB CRUD/embedding/reference/validation, ${lab.checks} утверждений`);
