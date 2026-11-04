load("/workspace/mongo/common.js");
if (lab.db.getName() !== "lab5_demo") throw new Error("Демонстрация разрешена только в lab5_demo");
// Команда demo явно пересоздаёт только эту учебную БД в отдельном контейнере.
lab.db.dropDatabase();
load("/workspace/mongo/scenario.js");
print(`PASS: демонстрация завершена, ${lab.checks} проверок; данные оставлены в lab5_demo`);
