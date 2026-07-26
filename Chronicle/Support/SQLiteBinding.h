#ifndef SQLiteBinding_h
#define SQLiteBinding_h

#include <SQLCipher/sqlite3.h>

int ChronicleSQLiteBindTransientText(sqlite3_stmt *statement, int index, const char *value, int byteCount);
int ChronicleFileLockExclusive(int descriptor);
int ChronicleFileLockSharedNonBlocking(int descriptor);
int ChronicleFileLockExclusiveNonBlocking(int descriptor);
int ChronicleFileUnlock(int descriptor);

#endif
