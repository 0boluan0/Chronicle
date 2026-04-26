#ifndef SQLiteBinding_h
#define SQLiteBinding_h

#include <sqlite3.h>

int ChronicleSQLiteBindTransientText(sqlite3_stmt *statement, int index, const char *value, int byteCount);

#endif
