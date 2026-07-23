import GRDB

public enum DatabaseSchema {
    public static let currentVersion = 4

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
        migrator.registerMigration("v3-knowledge-assets") { database in
            try database.execute(sql: """
                CREATE TABLE actors (
                    id TEXT PRIMARY KEY NOT NULL,
                    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    modified_at REAL NOT NULL,
                    revision INTEGER NOT NULL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
                CREATE TABLE creator_profiles (
                    id TEXT PRIMARY KEY NOT NULL,
                    actor_id TEXT NOT NULL REFERENCES actors(id) ON DELETE CASCADE,
                    biography TEXT NOT NULL DEFAULT '',
                    website_url TEXT,
                    revision INTEGER NOT NULL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
                CREATE TABLE documents (
                    id TEXT PRIMARY KEY NOT NULL,
                    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                    title TEXT NOT NULL,
                    current_revision_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    modified_at REAL NOT NULL,
                    revision INTEGER NOT NULL,
                    deleted_at REAL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
                CREATE TABLE document_revisions (
                    id TEXT PRIMARY KEY NOT NULL,
                    document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
                    parent_revision_id TEXT REFERENCES document_revisions(id),
                    content_hash TEXT NOT NULL,
                    content_relative_path TEXT NOT NULL,
                    author_actor_id TEXT NOT NULL REFERENCES actors(id),
                    created_at REAL NOT NULL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
                CREATE TABLE source_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    canonical_url TEXT,
                    title TEXT NOT NULL,
                    original_creator TEXT,
                    captured_at REAL NOT NULL,
                    content_hash TEXT,
                    source_asset_id TEXT,
                    snapshot_revision_id TEXT REFERENCES document_revisions(id),
                    license_hint TEXT,
                    created_by_actor_id TEXT NOT NULL REFERENCES actors(id),
                    revision INTEGER NOT NULL,
                    deleted_at REAL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
                CREATE TABLE publication_policies (
                    id TEXT PRIMARY KEY NOT NULL,
                    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                    visibility TEXT NOT NULL,
                    ownership_basis TEXT NOT NULL,
                    commercial_use TEXT NOT NULL,
                    attribution_required INTEGER NOT NULL,
                    attribution_text TEXT,
                    verification_status TEXT NOT NULL,
                    sensitivity TEXT NOT NULL,
                    revision INTEGER NOT NULL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
                CREATE TABLE knowledge_concepts (
                    id TEXT PRIMARY KEY NOT NULL,
                    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                    document_id TEXT NOT NULL REFERENCES documents(id),
                    type TEXT NOT NULL,
                    title TEXT NOT NULL,
                    description TEXT NOT NULL,
                    resource_uri TEXT,
                    creator_actor_id TEXT NOT NULL REFERENCES actors(id),
                    lifecycle_state TEXT NOT NULL,
                    current_revision_id TEXT NOT NULL,
                    publication_policy_id TEXT NOT NULL REFERENCES publication_policies(id),
                    created_at REAL NOT NULL,
                    modified_at REAL NOT NULL,
                    deleted_at REAL,
                    revision INTEGER NOT NULL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
                CREATE TABLE knowledge_concept_revisions (
                    id TEXT PRIMARY KEY NOT NULL,
                    concept_id TEXT NOT NULL REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
                    document_revision_id TEXT NOT NULL REFERENCES document_revisions(id),
                    metadata_json TEXT NOT NULL,
                    parent_revision_id TEXT REFERENCES knowledge_concept_revisions(id),
                    author_actor_id TEXT NOT NULL REFERENCES actors(id),
                    content_hash TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
                CREATE TABLE knowledge_references (
                    id TEXT PRIMARY KEY NOT NULL,
                    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                    source_kind TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    source_revision_id TEXT,
                    target_kind TEXT NOT NULL,
                    target_id TEXT NOT NULL,
                    target_revision_id TEXT,
                    relation TEXT NOT NULL,
                    anchor_json TEXT,
                    created_at REAL NOT NULL,
                    deleted_at REAL,
                    operation_id TEXT NOT NULL,
                    UNIQUE(operation_id, source_id, target_id, relation)
                )
                """)
            try database.execute(sql: """
                CREATE TABLE bundles (
                    id TEXT PRIMARY KEY NOT NULL,
                    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                    creator_actor_id TEXT NOT NULL REFERENCES actors(id),
                    title TEXT NOT NULL,
                    lifecycle_state TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    modified_at REAL NOT NULL,
                    revision INTEGER NOT NULL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
                CREATE TABLE bundle_drafts (
                    id TEXT PRIMARY KEY NOT NULL,
                    bundle_id TEXT NOT NULL REFERENCES bundles(id) ON DELETE CASCADE,
                    revision INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    modified_at REAL NOT NULL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
                CREATE TABLE bundle_draft_members (
                    draft_id TEXT NOT NULL REFERENCES bundle_drafts(id) ON DELETE CASCADE,
                    target_kind TEXT NOT NULL,
                    target_id TEXT NOT NULL,
                    target_revision_id TEXT NOT NULL,
                    export_path TEXT NOT NULL,
                    role TEXT NOT NULL,
                    rank INTEGER NOT NULL,
                    publication_policy_id TEXT NOT NULL REFERENCES publication_policies(id),
                    PRIMARY KEY(draft_id, target_kind, target_id)
                )
                """)
            try database.execute(sql: """
                CREATE TABLE bundle_versions (
                    id TEXT PRIMARY KEY NOT NULL,
                    bundle_id TEXT NOT NULL REFERENCES bundles(id) ON DELETE CASCADE,
                    semantic_version TEXT NOT NULL,
                    manifest_version INTEGER NOT NULL,
                    okf_version TEXT NOT NULL,
                    content_digest TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_by_actor_id TEXT NOT NULL REFERENCES actors(id),
                    created_at REAL NOT NULL,
                    operation_id TEXT NOT NULL UNIQUE,
                    UNIQUE(bundle_id, semantic_version)
                )
                """)
            try database.execute(sql: """
                CREATE TABLE bundle_members (
                    id TEXT PRIMARY KEY NOT NULL,
                    bundle_version_id TEXT NOT NULL REFERENCES bundle_versions(id) ON DELETE CASCADE,
                    target_kind TEXT NOT NULL,
                    target_id TEXT NOT NULL,
                    target_revision_id TEXT NOT NULL,
                    export_path TEXT NOT NULL,
                    role TEXT NOT NULL,
                    rank INTEGER NOT NULL,
                    UNIQUE(bundle_version_id, target_kind, target_id)
                )
                """)
            try database.execute(sql: """
                CREATE TABLE bundle_artifact_files (
                    bundle_version_id TEXT NOT NULL REFERENCES bundle_versions(id) ON DELETE CASCADE,
                    path TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    content_hash TEXT NOT NULL,
                    PRIMARY KEY(bundle_version_id, path)
                )
                """)
            try database.execute(sql: """
                CREATE TABLE integration_outbox (
                    id TEXT PRIMARY KEY NOT NULL,
                    event_name TEXT NOT NULL,
                    schema_version INTEGER NOT NULL,
                    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                    actor_id TEXT NOT NULL REFERENCES actors(id),
                    aggregate_kind TEXT NOT NULL,
                    aggregate_id TEXT NOT NULL,
                    operation_id TEXT NOT NULL REFERENCES applied_operations(operation_id) ON DELETE CASCADE,
                    occurred_at REAL NOT NULL,
                    payload BLOB NOT NULL,
                    state TEXT NOT NULL DEFAULT 'pending',
                    attempts INTEGER NOT NULL DEFAULT 0,
                    available_at REAL NOT NULL,
                    last_error TEXT,
                    completed_at REAL,
                    UNIQUE(event_name, aggregate_id, operation_id)
                )
                """)
            try database.execute(sql: """
                CREATE INDEX integration_outbox_claim
                ON integration_outbox(state, available_at, occurred_at)
                """)
            try database.execute(
                sql: "UPDATE workspaces SET schema_version = 3"
            )
        }
        migrator.registerMigration("v4-output-mainline") { database in
            try database.execute(sql: """
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
                )
                """)
            try database.execute(sql: """
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
                )
                """)
            try database.execute(sql: """
                CREATE TABLE output_revision_members (
                    id TEXT PRIMARY KEY NOT NULL,
                    output_revision_id TEXT NOT NULL REFERENCES output_revisions(id) ON DELETE CASCADE,
                    target_kind TEXT NOT NULL,
                    target_id TEXT NOT NULL,
                    target_revision_id TEXT NOT NULL,
                    role TEXT NOT NULL,
                    rank INTEGER NOT NULL,
                    UNIQUE(output_revision_id, target_kind, target_id)
                )
                """)
            try database.execute(sql: """
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
                )
                """)
            try database.execute(sql: """
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
                )
                """)
            try database.execute(sql: """
                CREATE TABLE validation_runs (
                    id TEXT PRIMARY KEY NOT NULL,
                    change_set_id TEXT NOT NULL REFERENCES change_sets(id) ON DELETE CASCADE,
                    policy_version INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    started_at REAL NOT NULL,
                    completed_at REAL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
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
                )
                """)
            try database.execute(sql: """
                CREATE TABLE reviews (
                    id TEXT PRIMARY KEY NOT NULL,
                    change_set_id TEXT NOT NULL REFERENCES change_sets(id) ON DELETE CASCADE,
                    reviewer_actor_id TEXT NOT NULL REFERENCES actors(id),
                    reviewer_kind TEXT NOT NULL,
                    decision TEXT NOT NULL,
                    reviewed_snapshot_id TEXT NOT NULL REFERENCES output_revisions(id),
                    created_at REAL NOT NULL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
                CREATE TABLE review_findings (
                    id TEXT PRIMARY KEY NOT NULL,
                    review_id TEXT NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
                    severity TEXT NOT NULL,
                    target_id TEXT,
                    anchor_json TEXT,
                    message TEXT NOT NULL,
                    resolution_status TEXT NOT NULL
                )
                """)
            try database.execute(sql: """
                CREATE TABLE approvals (
                    id TEXT PRIMARY KEY NOT NULL,
                    change_set_id TEXT NOT NULL REFERENCES change_sets(id) ON DELETE CASCADE,
                    snapshot_id TEXT NOT NULL REFERENCES output_revisions(id),
                    approved_by_actor_id TEXT NOT NULL REFERENCES actors(id),
                    created_at REAL NOT NULL,
                    invalidated_at REAL,
                    operation_id TEXT NOT NULL UNIQUE
                )
                """)
            try database.execute(sql: """
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
                )
                """)
            try database.execute(
                sql: "UPDATE workspaces SET schema_version = 4"
            )
        }
        return migrator
    }
}
