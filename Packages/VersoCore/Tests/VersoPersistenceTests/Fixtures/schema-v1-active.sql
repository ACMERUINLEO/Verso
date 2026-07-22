PRAGMA foreign_keys = ON;

CREATE TABLE grdb_migrations (
    identifier TEXT PRIMARY KEY NOT NULL
);
INSERT INTO grdb_migrations (identifier) VALUES ('v1');

CREATE TABLE workspaces (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    schema_version INTEGER NOT NULL,
    root_node_id TEXT NOT NULL,
    created_at REAL NOT NULL,
    modified_at REAL NOT NULL,
    default_time_zone_id TEXT NOT NULL,
    lifecycle_state TEXT NOT NULL
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
    deleted_at REAL
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

INSERT INTO workspaces VALUES (
    '11111111-1111-1111-1111-111111111111',
    'Fixture Active',
    1,
    '11111111-1111-1111-1111-111111111112',
    1700000000,
    1700000000,
    'UTC',
    'active'
);

INSERT INTO nodes VALUES (
    '11111111-1111-1111-1111-111111111112',
    '11111111-1111-1111-1111-111111111111',
    NULL,
    'folder',
    'Fixture Active',
    '0',
    1700000000,
    1700000000,
    NULL
);

INSERT INTO outbox_jobs VALUES (
    '11111111-1111-1111-1111-111111111113',
    'workspace.created',
    X'666978747572652D616374697665',
    'fixture-active:created',
    'pending',
    0,
    1700000000,
    NULL,
    1700000000,
    NULL
);
