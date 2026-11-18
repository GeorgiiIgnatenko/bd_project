// Запуск: python3 -m scripts.mongo growth. Одна новая БД на каждый эксперимент.
load("/workspace/mongo/common.js");
if (!lab.db.getName().startsWith("lab5_check_") || lab.db.getCollectionNames().length) {
    throw new Error("Для измерений нужна новая временная БД");
}
load("/workspace/mongo/schema.js");
const lists = lab.db.reading_lists;
const serverLimit = lab.db.adminCommand({hello: 1}).maxBsonObjectSize;
const addedAt = ISODate("2026-10-01T00:00:00Z");
print(`MongoDB ${lab.db.version()}, maxBsonObjectSize=${serverLimit}`);
print("профиль | элементов | байт BSON");
for (const [profile, note] of [
    ["короткая", "Прочитать"], ["кириллица", "я".repeat(1000)], ["4 байта", "😀".repeat(1000)]
]) {
    // Все поля фиксированного типа, имя тоже максимальной длины и ширины UTF-8.
    const id = lists.insertOne({userId: NumberLong("1"), name: "😀".repeat(100), items: []}).insertedId;
    let previousCount = 0;
    let previousBytes = 0;
    for (const count of [0, 1, 10, 50, 100, 150, 200]) {
        const extra = [];
        for (let i = previousCount + 1; i <= count; i++) {
            extra.push({articleId: NumberLong(String(i)), addedAt, note});
        }
        if (extra.length) lists.updateOne({_id: id}, {$push: {items: {$each: extra}}});
        const row = lists.aggregate([
            {$match: {_id: id}}, {$project: {count: {$size: "$items"}, bytes: {$bsonSize: "$$ROOT"}}}
        ]).toArray()[0];
        if (row.count !== count || row.bytes <= previousBytes || row.bytes >= serverLimit) {
            throw new Error("Неверное количество или размер подборки");
        }
        print(`${profile} | ${row.count} | ${row.bytes}`);
        previousCount = count;
        previousBytes = row.bytes;
    }
    const before = lab.json(lists.findOne({_id: id}));
    lab.expectError(() => lists.updateOne({_id: id}, {$push: {items: {
        articleId: NumberLong("201"), addedAt, note
    }}}), "201-й элемент отклонён");
    lab.check(lab.json(lists.findOne({_id: id})) === before, "предыдущее состояние сохранено");
}
