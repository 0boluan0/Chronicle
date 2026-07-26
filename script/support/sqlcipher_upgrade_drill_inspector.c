#define SQLITE_HAS_CODEC 1
#include <sqlite3.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(sqlite3 *database, const char *message) {
    const char *detail = database == NULL ? "database unavailable" : sqlite3_errmsg(database);
    fprintf(stderr, "SQLCipher drill inspection failed: %s (%s)\n", message, detail);
    if (database != NULL) {
        sqlite3_close(database);
    }
    exit(1);
}

static sqlite3_int64 scalar_int64(sqlite3 *database, const char *sql) {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, sql, -1, &statement, NULL) != SQLITE_OK) {
        fail(database, "could not prepare an integer query");
    }

    const int step_result = sqlite3_step(statement);
    if (step_result != SQLITE_ROW) {
        sqlite3_finalize(statement);
        fail(database, "integer query returned no row");
    }
    const sqlite3_int64 value = sqlite3_column_int64(statement, 0);
    sqlite3_finalize(statement);
    return value;
}

static void scalar_text(sqlite3 *database, const char *sql, char *destination, size_t capacity) {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, sql, -1, &statement, NULL) != SQLITE_OK) {
        fail(database, "could not prepare a text query");
    }

    const int step_result = sqlite3_step(statement);
    if (step_result != SQLITE_ROW || sqlite3_column_text(statement, 0) == NULL) {
        sqlite3_finalize(statement);
        fail(database, "text query returned no value");
    }
    snprintf(destination, capacity, "%s", (const char *)sqlite3_column_text(statement, 0));
    sqlite3_finalize(statement);
}

static void require_equal(sqlite3 *database, const char *label, sqlite3_int64 actual, sqlite3_int64 expected) {
    if (actual != expected) {
        fprintf(stderr, "%s: expected %lld, got %lld\n", label, expected, actual);
        fail(database, "an exact preservation assertion failed");
    }
}

static void require_at_least(sqlite3 *database, const char *label, sqlite3_int64 actual, sqlite3_int64 minimum) {
    if (actual < minimum) {
        fprintf(stderr, "%s: expected at least %lld, got %lld\n", label, minimum, actual);
        fail(database, "a projection assertion failed");
    }
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s /absolute/path/to/activity.sqlite\n", argv[0]);
        return 2;
    }

    sqlite3 *database = NULL;
    const int open_result = sqlite3_open_v2(
        argv[1],
        &database,
        SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
        NULL
    );
    if (open_result != SQLITE_OK || database == NULL) {
        fail(database, "could not open the candidate archive");
    }

    /*
     * Match SQLCipherDatabase.applyKey exactly. Chronicle deliberately sends SQLCipher's
     * raw-key literal (x'<64 hex digits>') to sqlite3_key, not the 32 binary bytes.
     */
    const char isolated_ui_test_key_literal[] =
        "x'a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5'";
    if (sqlite3_key(
            database,
            isolated_ui_test_key_literal,
            (int)(sizeof(isolated_ui_test_key_literal) - 1)
        ) != SQLITE_OK) {
        fail(database, "could not apply the isolated UI-test key");
    }
    sqlite3_busy_timeout(database, 250);

    char cipher_version[128] = {0};
    char integrity_result[128] = {0};
    scalar_text(database, "PRAGMA cipher_version;", cipher_version, sizeof(cipher_version));
    scalar_text(database, "PRAGMA integrity_check;", integrity_result, sizeof(integrity_result));
    if (cipher_version[0] == '\0') {
        fail(database, "the linked database implementation did not report SQLCipher");
    }
    if (strcmp(integrity_result, "ok") != 0) {
        fail(database, "the encrypted archive failed integrity_check");
    }

    require_equal(
        database,
        "current schema migration row count",
        scalar_int64(database, "SELECT COUNT(*) FROM SchemaMigrations;"),
        11
    );
    require_equal(
        database,
        "required current schema migrations",
        scalar_int64(
            database,
            "SELECT COUNT(*) FROM SchemaMigrations WHERE name IN ("
            "'2026_01_add_bundle_id','2026_02_raw_events','2026_03_effective_tag_columns',"
            "'2026_04_rules_match_bundle_id','2026_05_app_mappings_tagging_mode',"
            "'2026_06_review_domain','2026_07_review_revision_leaf','2026_08_export_history',"
            "'2026_09_review_snapshot_tag_name','2026_10_activity_split_aliases',"
            "'2026_11_work_block_structural_edits');"
        ),
        11
    );
    require_equal(
        database,
        "candidate-only table count",
        scalar_int64(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%' AND name NOT IN ("
            "'Activities','Markers','MarkerSpans','Tags','Rules','AppMappings',"
            "'RawEvents','SchemaMigrations');"
        ),
        8
    );
    require_equal(
        database,
        "required candidate-only tables",
        scalar_int64(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ("
            "'ReviewSnapshots','WorkBlocks','WorkBlockOverrides','WorkBlockEvidence',"
            "'ReviewSnapshotBlocks','ExportRecords','ActivitySplitAliases',"
            "'WorkBlockStructuralEdits');"
        ),
        8
    );

    require_equal(database, "activity sentinel", scalar_int64(database,
        "SELECT COUNT(*) FROM Activities WHERE app_name='Chronicle Upgrade Drill' "
        "AND bundle_id='com.chronicle.upgrade-drill.sentinel' "
        "AND window_title='Release rehearsal sentinel';"), 1);
    require_equal(database, "marker sentinel", scalar_int64(database,
        "SELECT COUNT(*) FROM Markers WHERE text='Chronicle upgrade drill marker';"), 1);
    require_equal(database, "marker span sentinel", scalar_int64(database,
        "SELECT COUNT(*) FROM MarkerSpans WHERE text='Chronicle upgrade drill span';"), 1);
    require_equal(database, "tag sentinel", scalar_int64(database,
        "SELECT COUNT(*) FROM Tags WHERE name='Upgrade Drill' AND color='#123456';"), 1);
    require_equal(database, "rule sentinel", scalar_int64(database,
        "SELECT COUNT(*) FROM Rules WHERE name='Chronicle upgrade drill rule';"), 1);
    require_equal(database, "mapping sentinel", scalar_int64(database,
        "SELECT COUNT(*) FROM AppMappings WHERE bundle_id='com.chronicle.upgrade-drill.sentinel';"), 1);
    require_equal(database, "raw-event sentinel", scalar_int64(database,
        "SELECT COUNT(*) FROM RawEvents WHERE bundle_id='com.chronicle.upgrade-drill.sentinel' "
        "AND payload='{\"drill\":true}';"), 1);
    require_at_least(database, "projected work-block sentinel", scalar_int64(database,
        "SELECT COUNT(DISTINCT blocks.id) FROM WorkBlocks AS blocks "
        "JOIN WorkBlockEvidence AS evidence ON evidence.work_block_id=blocks.id "
        "JOIN Activities AS activities ON activities.id=evidence.activity_id "
        "WHERE activities.bundle_id='com.chronicle.upgrade-drill.sentinel';"), 1);

    printf("cipher_version=%s\n", cipher_version);
    printf("integrity_check=%s\n", integrity_result);
    printf("schema_migrations=11\n");
    printf("candidate_tables=8\n");
    printf("preserved_sentinels=7\n");
    printf("projected_work_blocks>=1\n");

    sqlite3_close(database);
    return 0;
}
