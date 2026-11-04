// Единственный источник настроек коллекций. Только для новой учебной БД.
const nonblank = {bsonType: "string", pattern: "\\S"};
const longId = {bsonType: "long", minimum: 1};
const intId = {bsonType: "int", minimum: 1};
const namedReference = {
    bsonType: "object", required: ["id", "name"], additionalProperties: false,
    properties: {id: intId, name: {...nonblank, maxLength: 255}}
};
const itemSchema = {
    bsonType: "object", required: ["articleId", "addedAt"], additionalProperties: false,
    properties: {
        articleId: longId,
        addedAt: {bsonType: "date"},
        note: {bsonType: "string", maxLength: 1000}
    }
};

const validators = {
    articles: {$jsonSchema: {
        bsonType: "object", additionalProperties: false,
        required: ["_id", "canonicalUrl", "title", "content", "publishedAt", "source", "categories", "deletedAt"],
        properties: {
            _id: longId,
            canonicalUrl: {...nonblank, maxLength: 500, pattern: "^https?://\\S+$"},
            title: nonblank,
            content: nonblank,
            publishedAt: {bsonType: "date"},
            source: namedReference,
            categories: {bsonType: "array", minItems: 1, items: namedReference},
            deletedAt: {bsonType: ["date", "null"]}
        }
    }},
    article_events: {$jsonSchema: {
        bsonType: "object", additionalProperties: false,
        required: ["_id", "articleId", "userId", "type", "at"],
        properties: {
            _id: {bsonType: "objectId"},
            articleId: longId,
            userId: {bsonType: ["long", "null"], minimum: 1},
            type: {enum: ["view", "click"]},
            at: {bsonType: "date"},
            details: {bsonType: "object"}
        }
    }},
    import_payloads: {$jsonSchema: {
        bsonType: "object", additionalProperties: false,
        required: ["_id", "scrapeRunId", "sourceId", "format", "receivedAt", "raw"],
        properties: {
            _id: {bsonType: "objectId"},
            scrapeRunId: longId,
            sourceId: intId,
            format: {enum: ["json_api", "rss"]},
            receivedAt: {bsonType: "date"},
            raw: {bsonType: ["object", "string"]}
        },
        // БП-3: формат ответа определяет структуру raw.
        oneOf: [
            {properties: {format: {enum: ["json_api"]}, raw: {bsonType: "object"}}},
            {properties: {format: {enum: ["rss"]}, raw: {...nonblank}}}
        ]
    }},
    reading_lists: {$and: [
        {$jsonSchema: {
            bsonType: "object", additionalProperties: false,
            required: ["_id", "userId", "name", "items"],
            properties: {
                _id: {bsonType: "objectId"},
                userId: longId,
                name: {...nonblank, maxLength: 100},
                // БП-1: не более 200 элементов, пустой список разрешён.
                items: {bsonType: "array", maxItems: 200, items: itemSchema}
            }
        }},
        // БП-2: сравниваем ID, а не целые элементы с разными note/addedAt.
        {$expr: {$cond: [
            {$isArray: "$items"},
            {$eq: [
                {$size: "$items"},
                {$size: {$setUnion: [
                    {$map: {input: "$items", as: "item", in: "$$item.articleId"}}, []
                ]}}
            ]},
            false
        ]}}
    ]}
};

for (const [name, validator] of Object.entries(validators)) {
    lab.db.createCollection(name, {
        validator, validationLevel: "strict", validationAction: "error"
    });
}
// Уникальность URL наследуется от источника истины PostgreSQL.
lab.db.articles.createIndex({canonicalUrl: 1}, {unique: true});
lab.db.article_events.createIndex({articleId: 1, at: -1});
lab.db.import_payloads.createIndex({scrapeRunId: 1, receivedAt: 1});
lab.db.reading_lists.createIndex({userId: 1});
lab.db.reading_lists.createIndex({"items.articleId": 1});
lab.check(lab.db.getCollectionNames().length === 4, "созданы четыре коллекции");
