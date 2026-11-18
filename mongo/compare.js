load("/workspace/mongo/common.js");
if (!lab.db.getName().startsWith("lab5_check_") || lab.db.getCollectionNames().length) {
    throw new Error("Для сравнения нужна пустая временная БД");
}
load("/workspace/mongo/schema.js");
const data = JSON.parse(require("fs").readFileSync("/workspace/mongo/reading_lists_case.json", "utf8"));
const lists = lab.db.reading_lists;
for (const list of data.lists) {
    lists.insertOne({_id: ObjectId(list.id), userId: NumberLong(String(list.userId)), name: list.name,
        items: list.items.map(item => ({articleId: NumberLong(String(item.articleId)),
            addedAt: ISODate(data.addedAt), note: item.note}))});
}

function snapshot() {
    const rows = lists.aggregate([
        {$unwind: "$items"},
        {$sort: {userId: 1, _id: 1, "items.articleId": 1}},
        {$project: {_id: 0, row: [{$toInt: "$userId"}, {$toString: "$_id"},
            {$toInt: "$items.articleId"}, "$items.note"]}}
    ]).toArray();
    print("SNAPSHOT " + JSON.stringify(rows.map(result => result.row)));
}

snapshot();
const edit = data.edit;
const result = lists.updateOne({_id: ObjectId(edit.listId), userId: NumberLong(String(edit.userId))},
    {$set: {"items.$[article].note": edit.note}},
    {arrayFilters: [{"article.articleId": NumberLong(String(edit.articleId))}]});
lab.check(result.modifiedCount === 1, "обновлена одна подборка владельца");
snapshot();
