import GRDB

enum Migrations {
    static func migrate(_ writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // ── Watched folders ───────────────────────────────────────────────
            try db.execute(sql: """
                CREATE TABLE watched_folders (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    display_path    TEXT    NOT NULL,
                    bookmark_data   BLOB    NOT NULL,
                    added_at        REAL    NOT NULL,
                    is_active       INTEGER NOT NULL DEFAULT 1
                )
            """)

            // ── Screenshots ───────────────────────────────────────────────────
            try db.execute(sql: """
                CREATE TABLE screenshots (
                    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
                    file_path           TEXT    NOT NULL UNIQUE,
                    file_name           TEXT    NOT NULL,
                    file_size           INTEGER,
                    width               INTEGER,
                    height              INTEGER,
                    file_created_at     REAL    NOT NULL,
                    file_modified_at    REAL    NOT NULL,
                    indexed_at          REAL    NOT NULL,
                    ocr_text            TEXT,
                    ocr_confidence      REAL,
                    ocr_status          TEXT    NOT NULL DEFAULT 'pending',
                    spotlight_indexed   INTEGER NOT NULL DEFAULT 0,
                    source_app          TEXT,
                    source_window_title TEXT,
                    last_accessed_at    REAL,
                    has_sensitive_data  INTEGER NOT NULL DEFAULT 0,
                    thumbnail_path      TEXT
                )
            """)

            try db.execute(sql: "CREATE INDEX idx_screenshots_file_path    ON screenshots(file_path)")
            try db.execute(sql: "CREATE INDEX idx_screenshots_file_created ON screenshots(file_created_at DESC)")
            try db.execute(sql: "CREATE INDEX idx_screenshots_indexed       ON screenshots(indexed_at DESC)")
            try db.execute(sql: "CREATE INDEX idx_screenshots_ocr_status   ON screenshots(ocr_status)")
            try db.execute(sql: "CREATE INDEX idx_screenshots_source_app   ON screenshots(source_app)")

            // ── FTS5 virtual table (content-table backed) ─────────────────────
            try db.execute(sql: """
                CREATE VIRTUAL TABLE screenshots_fts USING fts5(
                    ocr_text,
                    content='screenshots',
                    content_rowid='id',
                    tokenize='porter unicode61'
                )
            """)

            // Triggers keep FTS index in sync with the content table
            try db.execute(sql: """
                CREATE TRIGGER screenshots_fts_ai AFTER INSERT ON screenshots BEGIN
                    INSERT INTO screenshots_fts(rowid, ocr_text) VALUES (new.id, new.ocr_text);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER screenshots_fts_ad AFTER DELETE ON screenshots BEGIN
                    INSERT INTO screenshots_fts(screenshots_fts, rowid, ocr_text)
                        VALUES ('delete', old.id, old.ocr_text);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER screenshots_fts_au AFTER UPDATE OF ocr_text ON screenshots BEGIN
                    INSERT INTO screenshots_fts(screenshots_fts, rowid, ocr_text)
                        VALUES ('delete', old.id, old.ocr_text);
                    INSERT INTO screenshots_fts(rowid, ocr_text) VALUES (new.id, new.ocr_text);
                END
            """)

            // ── Embeddings (v1.1) ─────────────────────────────────────────────
            try db.execute(sql: """
                CREATE TABLE embeddings (
                    screenshot_id   INTEGER PRIMARY KEY REFERENCES screenshots(id) ON DELETE CASCADE,
                    model_id        TEXT    NOT NULL,
                    vector          BLOB    NOT NULL,
                    computed_at     REAL    NOT NULL
                )
            """)

            // ── Tags (v1.2) ───────────────────────────────────────────────────
            try db.execute(sql: """
                CREATE TABLE tags (
                    id      INTEGER PRIMARY KEY AUTOINCREMENT,
                    name    TEXT    NOT NULL UNIQUE,
                    kind    TEXT    NOT NULL DEFAULT 'auto'
                )
            """)

            try db.execute(sql: """
                CREATE TABLE screenshot_tags (
                    screenshot_id   INTEGER NOT NULL REFERENCES screenshots(id) ON DELETE CASCADE,
                    tag_id          INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                    confidence      REAL    NOT NULL DEFAULT 1.0,
                    PRIMARY KEY (screenshot_id, tag_id)
                )
            """)

            // ── Clusters (v1.2) ───────────────────────────────────────────────
            try db.execute(sql: """
                CREATE TABLE clusters (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    label       TEXT    NOT NULL,
                    centroid    BLOB,
                    created_at  REAL    NOT NULL
                )
            """)

            try db.execute(sql: """
                CREATE TABLE screenshot_clusters (
                    screenshot_id   INTEGER NOT NULL REFERENCES screenshots(id) ON DELETE CASCADE,
                    cluster_id      INTEGER NOT NULL REFERENCES clusters(id) ON DELETE CASCADE,
                    distance        REAL,
                    PRIMARY KEY (screenshot_id, cluster_id)
                )
            """)
        }

        try migrator.migrate(writer)
    }
}
