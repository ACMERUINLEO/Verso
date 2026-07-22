PRAGMA foreign_keys = ON;

CREATE TABLE grdb_migrations (
    identifier TEXT PRIMARY KEY NOT NULL
);
INSERT INTO grdb_migrations (identifier) VALUES ('v1');
INSERT INTO grdb_migrations (identifier) VALUES ('v2-sync-baseline');

CREATE TABLE workspaces (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    schema_version INTEGER NOT NULL,
    root_node_id TEXT NOT NULL,
    created_at REAL NOT NULL,
    modified_at REAL NOT NULL,
    default_time_zone_id TEXT NOT NULL,
    lifecycle_state TEXT NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1,
    deleted_at REAL
);

CREATE TABLE nodes (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    parent_id TEXT REFERENCES nodes(id),
    kind TEXT NOT NULL,
    display_name TEXT NOT NULL,
    rank TEXT NOT NULL,
    created_at REAL NOT NULL,
    modified_at REAL NOT NULL,
    deleted_at REAL,
    revision INTEGER NOT NULL DEFAULT 1,
    operation_id TEXT
);

CREATE UNIQUE INDEX nodes_single_root
ON nodes(workspace_id)
WHERE parent_id IS NULL AND deleted_at IS NULL;

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
);

CREATE INDEX outbox_jobs_claim
ON outbox_jobs(state, available_at, created_at);

CREATE TABLE operation_journal (
    id TEXT PRIMARY KEY NOT NULL,
    command_name TEXT NOT NULL,
    state TEXT NOT NULL,
    summary_json TEXT NOT NULL,
    created_at REAL NOT NULL,
    completed_at REAL
);

CREATE TABLE applied_operations (
    operation_id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    source_device_id TEXT NOT NULL,
    command_name TEXT NOT NULL,
    command_fingerprint TEXT NOT NULL,
    applied_at REAL NOT NULL
);

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
);

CREATE INDEX sync_outbox_claim
ON sync_outbox(state, available_at, created_at);

INSERT INTO workspaces VALUES (
    '33333333-3333-3333-3333-333333333331',
    'Fixture Synced',
    2,
    '33333333-3333-3333-3333-333333333332',
    1720000000,
    1720000200,
    'UTC',
    'closed',
    3,
    NULL
);

INSERT INTO nodes VALUES (
    '33333333-3333-3333-3333-333333333332',
    '33333333-3333-3333-3333-333333333331',
    NULL,
    'folder',
    'Fixture Synced',
    '0',
    1720000000,
    1720000000,
    NULL,
    1,
    '33333333-3333-3333-3333-333333333334'
);

INSERT INTO applied_operations VALUES (
    '33333333-3333-3333-3333-333333333334',
    '33333333-3333-3333-3333-333333333331',
    '33333333-3333-3333-3333-333333333335',
    'workspace.rename.v1',
    'fixture-synced',
    1720000200
);

INSERT INTO sync_outbox VALUES (
    '33333333-3333-3333-3333-333333333336',
    '33333333-3333-3333-3333-333333333334',
    '33333333-3333-3333-3333-333333333331',
    '33333333-3333-3333-3333-333333333335',
    'workspace',
    '33333333-3333-3333-3333-333333333331',
    'upsert',
    2,
    3,
    X'7B7D',
    'pending',
    0,
    1720000200,
    NULL,
    1720000200,
    NULL
);
