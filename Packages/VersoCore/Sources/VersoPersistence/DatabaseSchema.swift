import GRDB

public enum DatabaseSchema {
    public static let currentVersion = 2

    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            try database.execute(sql: """
                CREATE TABLE workspaces (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    schema_version INTEGER NOT NULL,
                    root_node_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    modified_at REAL NOT NULL,
                    default_time_zone_id TEXT NOT NULL,
                    lifecycle_state TEXT NOT NULL
                )
                """)
            try database.execute(sql: """
                CREATE TABLE nodes (
                    id TEXT PRIMARY KEY NOT NULL,
                    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                    parent_id TEXT REFERENCES nodes(id),
                    kind TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    rank TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    modified_at REAL NOT NULL,
                    deleted_at REAL
                )
                """)
            try database.execute(sql: """
                CREATE UNIQUE INDEX nodes_single_root
                ON nodes(workspace_id)
                WHERE parent_id IS NULL AND deleted_at IS NULL
                """)
            try database.execute(sql: """
                CREATE TABLE outbox_jobs (
                    id TEXT PRIMARY KEY NOT NULL,
                    kind TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    idempotency_key TEXT NOT NULL UNIQUE,
                    state TEXT NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    available_at REAL NOT NULL,
                    last_error TEXT,
                    created_at REAL NOT NULL,
                    completed_at REAL
                )
                """)
            try database.execute(sql: """
                CREATE INDEX outbox_jobs_claim
                ON outbox_jobs(state, available_at, created_at)
                """)
            try database.execute(sql: """
                CREATE TABLE operation_journal (
                    id TEXT PRIMARY KEY NOT NULL,
                    command_name TEXT NOT NULL,
                    state TEXT NOT NULL,
                    summary_json TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    completed_at REAL
                )
                """)
        }
        migrator.registerMigration("v2-sync-baseline") { database in
            try database.execute(sql: """
                ALTER TABLE workspaces
                ADD COLUMN revision INTEGER NOT NULL DEFAULT 1
                """)
            try database.execute(sql: """
                ALTER TABLE workspaces
                ADD COLUMN deleted_at REAL
                """)
            try database.execute(sql: """
                ALTER TABLE nodes
                ADD COLUMN revision INTEGER NOT NULL DEFAULT 1
                """)
            try database.execute(sql: """
                ALTER TABLE nodes
                ADD COLUMN operation_id TEXT
                """)
            try database.execute(sql: """
                CREATE TABLE applied_operations (
                    operation_id TEXT PRIMARY KEY NOT NULL,
                    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                    source_device_id TEXT NOT NULL,
                    command_name TEXT NOT NULL,
                    command_fingerprint TEXT NOT NULL,
                    applied_at REAL NOT NULL
                )
                """)
            try database.execute(sql: """
                CREATE TABLE sync_outbox (
                    id TEXT PRIMARY KEY NOT NULL,
                    operation_id TEXT NOT NULL REFERENCES applied_operations(operation_id) ON DELETE CASCADE,
                    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                    source_device_id TEXT NOT NULL,
                    record_kind TEXT NOT NULL,
                    record_id TEXT NOT NULL,
                    mutation_kind TEXT NOT NULL,
                    base_revision INTEGER NOT NULL,
                    revision INTEGER NOT NULL,
                    payload BLOB NOT NULL,
                    state TEXT NOT NULL DEFAULT 'pending',
                    attempts INTEGER NOT NULL DEFAULT 0,
                    available_at REAL NOT NULL,
                    last_error TEXT,
                    created_at REAL NOT NULL,
                    completed_at REAL,
                    UNIQUE(operation_id, record_kind, record_id)
                )
                """)
            try database.execute(sql: """
                CREATE INDEX sync_outbox_claim
                ON sync_outbox(state, available_at, created_at)
                """)
            try database.execute(
                sql: "UPDATE workspaces SET schema_version = ?",
                arguments: [currentVersion]
            )
        }
        return migrator
    }
}
