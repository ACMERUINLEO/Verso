INSERT INTO grdb_migrations (identifier) VALUES ('v4-output-mainline');

CREATE TABLE outputs (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    purpose TEXT NOT NULL,
    audience TEXT NOT NULL,
    output_type TEXT NOT NULL,
    current_revision_id TEXT NOT NULL,
    structure_schema_version INTEGER NOT NULL,
    created_at REAL NOT NULL,
    modified_at REAL NOT NULL,
    deleted_at REAL,
    revision INTEGER NOT NULL,
    operation_id TEXT NOT NULL UNIQUE
);

CREATE TABLE output_revisions (
    id TEXT PRIMARY KEY NOT NULL,
    output_id TEXT NOT NULL REFERENCES outputs(id) ON DELETE CASCADE,
    parent_revision_id TEXT REFERENCES output_revisions(id),
    manifest_hash TEXT NOT NULL,
    created_by_actor_id TEXT NOT NULL REFERENCES actors(id),
    created_at REAL NOT NULL,
    snapshot_kind TEXT NOT NULL,
    operation_id TEXT NOT NULL,
    UNIQUE(operation_id, id)
);

CREATE TABLE output_revision_members (
    id TEXT PRIMARY KEY NOT NULL,
    output_revision_id TEXT NOT NULL REFERENCES output_revisions(id) ON DELETE CASCADE,
    target_kind TEXT NOT NULL,
    target_id TEXT NOT NULL,
    target_revision_id TEXT NOT NULL,
    role TEXT NOT NULL,
    rank INTEGER NOT NULL,
    UNIQUE(output_revision_id, target_kind, target_id)
);

CREATE TABLE contributions (
    id TEXT PRIMARY KEY NOT NULL,
    output_id TEXT NOT NULL REFERENCES outputs(id) ON DELETE CASCADE,
    base_output_revision_id TEXT NOT NULL REFERENCES output_revisions(id),
    title TEXT NOT NULL,
    intent TEXT NOT NULL,
    created_by_actor_id TEXT NOT NULL REFERENCES actors(id),
    status TEXT NOT NULL,
    revision INTEGER NOT NULL,
    created_at REAL NOT NULL,
    modified_at REAL NOT NULL,
    closed_at REAL,
    operation_id TEXT NOT NULL UNIQUE
);

CREATE TABLE change_sets (
    id TEXT PRIMARY KEY NOT NULL,
    contribution_id TEXT NOT NULL REFERENCES contributions(id) ON DELETE CASCADE,
    sequence INTEGER NOT NULL,
    base_output_revision_id TEXT NOT NULL REFERENCES output_revisions(id),
    proposed_snapshot_id TEXT NOT NULL REFERENCES output_revisions(id),
    submitted_by_actor_id TEXT NOT NULL REFERENCES actors(id),
    submitted_at REAL NOT NULL,
    status TEXT NOT NULL,
    operation_id TEXT NOT NULL UNIQUE,
    UNIQUE(contribution_id, sequence)
);

CREATE TABLE validation_runs (
    id TEXT PRIMARY KEY NOT NULL,
    change_set_id TEXT NOT NULL REFERENCES change_sets(id) ON DELETE CASCADE,
    policy_version INTEGER NOT NULL,
    status TEXT NOT NULL,
    started_at REAL NOT NULL,
    completed_at REAL,
    operation_id TEXT NOT NULL UNIQUE
);

CREATE TABLE validation_results (
    id TEXT PRIMARY KEY NOT NULL,
    run_id TEXT NOT NULL REFERENCES validation_runs(id) ON DELETE CASCADE,
    rule_id TEXT NOT NULL,
    rule_version INTEGER NOT NULL,
    severity TEXT NOT NULL,
    status TEXT NOT NULL,
    target_id TEXT,
    anchor_json TEXT,
    message TEXT NOT NULL,
    UNIQUE(run_id, rule_id, target_id)
);

CREATE TABLE reviews (
    id TEXT PRIMARY KEY NOT NULL,
    change_set_id TEXT NOT NULL REFERENCES change_sets(id) ON DELETE CASCADE,
    reviewer_actor_id TEXT NOT NULL REFERENCES actors(id),
    reviewer_kind TEXT NOT NULL,
    decision TEXT NOT NULL,
    reviewed_snapshot_id TEXT NOT NULL REFERENCES output_revisions(id),
    created_at REAL NOT NULL,
    operation_id TEXT NOT NULL UNIQUE
);

CREATE TABLE review_findings (
    id TEXT PRIMARY KEY NOT NULL,
    review_id TEXT NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
    severity TEXT NOT NULL,
    target_id TEXT,
    anchor_json TEXT,
    message TEXT NOT NULL,
    resolution_status TEXT NOT NULL
);

CREATE TABLE approvals (
    id TEXT PRIMARY KEY NOT NULL,
    change_set_id TEXT NOT NULL REFERENCES change_sets(id) ON DELETE CASCADE,
    snapshot_id TEXT NOT NULL REFERENCES output_revisions(id),
    approved_by_actor_id TEXT NOT NULL REFERENCES actors(id),
    created_at REAL NOT NULL,
    invalidated_at REAL,
    operation_id TEXT NOT NULL UNIQUE
);

CREATE TABLE merge_records (
    id TEXT PRIMARY KEY NOT NULL,
    contribution_id TEXT NOT NULL REFERENCES contributions(id),
    change_set_id TEXT NOT NULL REFERENCES change_sets(id),
    main_before_revision_id TEXT NOT NULL REFERENCES output_revisions(id),
    contribution_head_revision_id TEXT NOT NULL REFERENCES output_revisions(id),
    main_after_revision_id TEXT NOT NULL REFERENCES output_revisions(id),
    approval_id TEXT NOT NULL REFERENCES approvals(id),
    approved_by_actor_id TEXT NOT NULL REFERENCES actors(id),
    operation_id TEXT NOT NULL UNIQUE REFERENCES applied_operations(operation_id),
    merged_at REAL NOT NULL
);

UPDATE workspaces
SET schema_version = 4,
    name = 'Fixture Mainline';
