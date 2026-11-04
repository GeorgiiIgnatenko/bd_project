// Синтетический снимок для лабораторной, не выгрузка из действующего PostgreSQL.
globalThis.fixture = {
    listA: ObjectId("000000000000000000000001"),
    listB: ObjectId("000000000000000000000002"),
    article(id = "1000") {
        return {
            _id: NumberLong(id), canonicalUrl: `https://news.example/articles/${id}`,
            title: `Новость ${id}`, content: "Текст учебной публикации",
            publishedAt: ISODate("2026-10-01T10:00:00Z"),
            source: {id: NumberInt(2), name: "Спортивный источник"},
            categories: [{id: NumberInt(2), name: "Спорт"}], deletedAt: null
        };
    },
    item(id = "1000", note = "Прочитать вечером") {
        return {articleId: NumberLong(id), addedAt: ISODate("2026-10-02T09:00:00Z"), note};
    },
    list() {
        return {userId: NumberLong("1"), name: "Почитать позже", items: [this.item()]};
    },
    event() {
        return {
            articleId: NumberLong("1000"), userId: NumberLong("1"),
            type: "view", at: ISODate("2026-10-02T08:15:00Z")
        };
    },
    payload() {
        return {
            scrapeRunId: NumberLong("7"), sourceId: NumberInt(2), format: "json_api",
            receivedAt: ISODate("2026-10-01T10:00:02Z"),
            raw: {title: "Исходный заголовок", author: "Редакция", tags: ["спорт"]}
        };
    }
};

lab.db.articles.insertMany([fixture.article(), fixture.article("1001")]);
lab.db.article_events.insertMany([
    fixture.event(), {...fixture.event(), type: "click", userId: null}
]);
lab.db.import_payloads.insertOne(fixture.payload());
lab.db.reading_lists.insertMany([
    {...fixture.list(), _id: fixture.listA, items: [fixture.item(), fixture.item("1001")]},
    {...fixture.list(), _id: fixture.listB, userId: NumberLong("2"), name: "Спортивные новости"}
]);
