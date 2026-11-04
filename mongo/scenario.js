// Общий сценарий: одна и та же реализация для демонстрации и проверки.
lab.check(lab.db.getCollectionNames().length === 0, "для сценария выбрана пустая учебная БД");
print(`MongoDB ${lab.db.version()}, mongosh ${version()}, БД ${lab.db.getName()}`);
load("/workspace/mongo/schema.js");
load("/workspace/mongo/fixtures.js");
load("/workspace/mongo/crud.js");
