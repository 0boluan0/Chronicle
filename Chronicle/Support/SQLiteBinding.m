//
//  SQLiteBinding.m
//  Chronicle
//

#include "SQLiteBinding.h"
#include <sys/file.h>

int ChronicleSQLiteBindTransientText(sqlite3_stmt *statement, int index, const char *text, int length) {
    return sqlite3_bind_text(statement, index, text, length, SQLITE_TRANSIENT);
}

int ChronicleFileLockExclusive(int descriptor) {
    return flock(descriptor, LOCK_EX);
}

int ChronicleFileLockSharedNonBlocking(int descriptor) {
    return flock(descriptor, LOCK_SH | LOCK_NB);
}

int ChronicleFileLockExclusiveNonBlocking(int descriptor) {
    return flock(descriptor, LOCK_EX | LOCK_NB);
}

int ChronicleFileUnlock(int descriptor) {
    return flock(descriptor, LOCK_UN);
}
