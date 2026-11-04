// Общие утверждения для mongosh. Любая ошибка останавливает файл с exit != 0.
const databaseName = process.env.LAB_MONGO_DB;
if (!/^lab5_(demo|check_[0-9a-f]{8})$/.test(databaseName || "")) {
    throw new Error("Запрещена неучебная БД: задайте LAB_MONGO_DB=lab5_demo или lab5_check_<8 hex>");
}

globalThis.lab = {
    db: db.getSiblingDB(databaseName),
    checks: 0,
    check(condition, label) {
        if (!condition) throw new Error(`FAIL: ${label}`);
        this.checks++;
        print(`PASS: ${label}`);
    },
    expectError(operation, label, expectedCode = 121) {
        let actualCode;
        try {
            operation();
        } catch (error) {
            actualCode = error.code;
            if (actualCode !== expectedCode) throw error;
        }
        this.check(actualCode === expectedCode, `${label}: ожидалась ошибка ${expectedCode}`);
    },
    json(value) {
        return EJSON.stringify(value, null, 2, {relaxed: false});
    }
};
