INSERT INTO grdb_migrations (identifier) VALUES ('v3-knowledge-assets');

CREATE TABLE actors (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    display_name TEXT NOT NULL,
    created_at REAL NOT NULL,
    modified_at REAL NOT NULL,
    revision INTEGER NOT NULL,
    operation_id TEXT NOT NULL UNIQUE
);

CREATE TABLE creator_profiles (
    id TEXT PRIMARY KEY NOT NULL,
    actor_id TEXT NOT NULL REFERENCES actors(id) ON DELETE CASCADE,
    biography TEXT NOT NULL DEFAULT '',
    website_url TEXT,
    revision INTEGER NOT NULL,
    operation_id TEXT NOT NULL UNIQUE
);

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
);

CREATE TABLE document_revisions (
    id TEXT PRIMARY KEY NOT NULL,
    document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    parent_revision_id TEXT REFERENCES document_revisions(id),
    content_hash TEXT NOT NULL,
    content_relative_path TEXT NOT NULL,
    author_actor_id TEXT NOT NULL REFERENCES actors(id),
    created_at REAL NOT NULL,
    operation_id TEXT NOT NULL UNIQUE
);

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
);

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
);

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
);

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
);

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
);

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
);

CREATE TABLE bundle_drafts (
    id TEXT PRIMARY KEY NOT NULL,
    bundle_id TEXT NOT NULL REFERENCES bundles(id) ON DELETE CASCADE,
    revision INTEGER NOT NULL,
    created_at REAL NOT NULL,
    modified_at REAL NOT NULL,
    operation_id TEXT NOT NULL UNIQUE
);

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
);

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
);

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
);

CREATE TABLE bundle_artifact_files (
    bundle_version_id TEXT NOT NULL REFERENCES bundle_versions(id) ON DELETE CASCADE,
    path TEXT NOT NULL,
    payload BLOB NOT NULL,
    content_hash TEXT NOT NULL,
    PRIMARY KEY(bundle_version_id, path)
);

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
);

CREATE INDEX integration_outbox_claim
ON integration_outbox(state, available_at, occurred_at);

UPDATE workspaces
SET schema_version = 3,
    name = 'Fixture Knowledge';
