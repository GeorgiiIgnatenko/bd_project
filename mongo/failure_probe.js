// Проверка обработки ошибок внешней обёрткой; выполняется только во временной БД.
load("/workspace/mongo/common.js");
if (!lab.db.getName().startsWith("lab5_check_")) throw new Error("Контроль отказа требует временную БД");
switch (process.env.LAB_MONGO_PROBE) {
    case "validation":
        lab.db.reading_lists.insertOne({name: "Нет обязательных полей"});
        break;
    case "unexpected_success":
        lab.expectError(() => lab.db.reading_lists.insertOne({
            userId: NumberLong("1"), name: "Корректный документ", items: []
        }), "контроль неожиданного успеха");
        break;
    default:
        throw new Error("Неизвестный контроль отказа");
}
