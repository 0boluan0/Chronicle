#include "SQLiteBinding.h"

int ChronicleSQLiteBindTransientText(sqlite3_stmt *statement, int index, const char *value, int byteCount) {
    return sqlite3_bind_text(statement, index, value, byteCount, SQLITE_TRANSIENT);
}
