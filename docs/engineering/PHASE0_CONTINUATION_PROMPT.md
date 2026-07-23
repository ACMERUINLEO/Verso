# Verso Phase 0B / 0C 继续开发提示词

请直接复制本文件中从“任务开始”到“任务结束”的全部内容，发送给专门负责【Phase0 开发】的 Codex 任务。

---

## 任务开始

你正在继续开发一个已经存在的 macOS 工程。不要重新创建项目，不要从空白架构开始，也不要推翻已经验证的 Phase 0A。

### 一、产品与项目身份

- 产品正式名称：**Verso**
- `Prologue` 只是早期项目代号，不是产品名称；代码、模块、UI 和新文档统一使用 Verso。
- 本地仓库：`/Users/leochen/Developer/Prologue Project/Verso`
- 正式工程入口：`Verso.xcworkspace`
- 最低系统基线：macOS 15+
- 语言与并发：Swift 6 严格并发
- 主体技术：SwiftUI，必要处使用 AppKit

Verso 是本地优先的个人知识工作空间与 AI 共创产品。即使没有 Experty，用户也必须能独立完成：

```text
搜集信息
    → 理解与 AI 共创
    → 沉淀知识
    → 形成正式产出
    → 持续复用与导出
```

Experty 是后续平台，负责：

```text
Bundle 发布
    → 身份与许可
    → 发现与交易
    → 安装到 Agent
    → 调用计量
    → 效果反馈
```

Verso 不能依赖 Experty 才能打开、编辑、恢复、构建或导出用户的私人 Workspace。连接 Experty 只是用户明确选择后的发布与交易通道。

### 二、必须先阅读的仓库资料

开始修改代码前，完整阅读并以当前仓库内容为准：

- `README.md`
- `DEVELOPMENT.md`
- `docs/product/ROADMAP.md`
- `docs/architecture/ARCHITECTURE.md`
- `docs/architecture/DATA_MODEL.md`
- `docs/architecture/decisions/README.md`
- `docs/architecture/decisions/0001-native-modular-monolith.md`
- `docs/architecture/decisions/0002-sqlite-grdb.md`
- `docs/architecture/decisions/0003-logical-tree-file-ownership.md`
- `docs/architecture/decisions/0004-agent-command-boundary.md`
- `docs/engineering/PHASE0.md`
- `docs/engineering/SYNC_BASELINE.md`
- `docs/product/PRODUCT_CHANGELOG.md`
- `Packages/VersoCore/Package.swift`
- `Packages/VersoCore/Sources/**`
- `Packages/VersoCore/Tests/**`

检查工作树和现有改动。用户或其他 Codex 任务的修改必须保留；不要 reset、checkout、stash、删除或覆盖不属于本任务的改动。不要提交或推送 Git，除非用户另行明确要求。

### 三、当前已完成的 Phase 0A 基线

当前代码已经包含：

- `VersoDomain`
- `VersoApplication`
- `VersoPersistence`
- `VersoFileSystem`
- `VersoSyncProtocol`
- `VersoObservability`
- Swift 6 严格并发和模块依赖检查
- GRDB / SQLite
- schema v1 与 `v2-sync-baseline`
- Workspace 创建、打开、关闭、重开、备份与恢复
- 数据库损坏时进入只读恢复流程
- Command Bus
- `OperationID` 幂等处理和 command fingerprint 冲突关闭
- `applied_operations`
- 事务 `sync_outbox`
- Job Runner 与 operation journal
- 文件原子写入和中断恢复
- DeviceID、revision、tombstone 与 provider-neutral `SyncTransport`
- 结构化诊断、错误分类和性能 trace
- 历史 migration fixtures 与故障注入测试

现有 schema v1 和 `v2-sync-baseline` 已经发布，**绝对不能修改名称或内容**。所有新结构必须追加新 migration，并保留从所有旧 fixture 迁移到当前版本的测试。

不要重写已经工作的 Workspace 生命周期和同步幂等逻辑。复用它们的事务、fingerprint、失败注入、Outbox 和测试模式。

### 四、本任务总目标

继续完成：

1. **Phase 0B：知识资产、来源血缘、Bundle 与 OKF 发布契约**
2. **Phase 0C：Output Mainline、Contribution、ChangeSet、Validation、Review、Approval 与 Merge 契约**

不要只创建空类型或接口。优先完成少量但真实可运行、可迁移、可重试、可恢复的端到端切片。

本任务不是 UI 任务。除非最小接线或编译需要，不制作完整 Sidebar、编辑器、Bundle Studio 或 Experty 页面。

### 五、不可改变的架构原则

1. 原生 Swift 6 + SwiftUI / AppKit，模块化单体。
2. SQLite / GRDB 是唯一业务事实来源；原始文件和大型不可变内容保留在文件系统。
3. 虚拟 Node 树与真实文件路径分离。
4. 所有业务实体使用稳定 UUID 类型；路径、名称、hash、rowid、账号和设备 ID 都不是实体身份。
5. 所有正式写入经 Typed Command 和 Application 层执行。
6. UI、AI、导入器和未来 Experty adapter 不能直接操作数据库或任意文件。
7. 正式 Command 在同一事务中提交业务事实、`applied_operations` 和对应 Outbox。
8. 重放同一 `OperationID` 返回已持久化结果；不同意图复用同一 ID 失败关闭。
9. optimistic revision conflict 不能静默覆盖。
10. FTS、Embedding、缩略图、Diff 预览等派生数据可删除、可重建。
11. 本地路径、bookmark、API Key、OAuth Token 和设备凭据不进入同步与发布协议。
12. AI 只能成为 Actor、Contribution 作者或 Reviewer；不能拥有直接修改 Mainline、冻结 BundleVersion 或发布到 Experty 的后门。
13. OKF 是版本化导入导出协议，不是 Verso 内部数据库模型。
14. Sync Outbox 只负责设备一致性；Integration Outbox 负责未来 Experty 事件，两者不能混用。

### 六、Phase 0B：身份与知识血缘

在 `VersoDomain` 中增加必要的强类型 ID。根据最终持久化设计至少考虑：

- `ActorID`
- `CreatorProfileID`
- `SourceRecordID`
- `KnowledgeConceptID`
- `KnowledgeConceptRevisionID`
- `ReferenceID`
- `PublicationPolicyID`
- `BundleID`
- `BundleDraftID`
- `BundleVersionID`
- `BundleMemberID`
- `IntegrationEventID`

所有领域值必须遵循现有风格，尽量满足：

- `Codable`
- `Equatable` / `Hashable`
- `Sendable`
- 明确初始化器
- 不把数据库或平台类型泄漏到 Domain

定义最小 Actor 契约：

```text
Actor
- id
- kind: person | agent | organization | importer | recovery
- displayName
- createdAt / modifiedAt
```

要求：

- Actor 与 Apple ID、邮箱、设备和 Experty Account 解耦。
- 初期允许本地 CreatorProfile；未来通过 external reference 绑定 Experty。
- 模型名称不是 Actor 身份。

定义最小 SourceRecord 契约：

```text
SourceRecord
- id
- workspaceID
- kind: web | book | video | file | interview | original
- canonicalURL?
- title
- originalCreator?
- capturedAt
- contentHash?
- sourceAssetID?
- snapshotRevisionID?
- licenseHint?
- createdByActorID
- revision / deletedAt?
```

定义 Reference 关系，至少支持：

- `cites`
- `quotes`
- `supports`
- `contradicts`
- `derivedFrom`
- `summarizes`
- `includedIn`

来源、知识、AI 生成内容、正式产出和 Bundle Member 必须能够通过稳定 ID 与具体 revision 反向追踪。

### 七、Phase 0B：KnowledgeConcept 与 Bundle

`Document` 表示可编辑内容；`KnowledgeConcept` 表示可复用、可发布的知识语义。不要把两者合并。

最小 KnowledgeConcept：

```text
KnowledgeConcept
- id
- workspaceID
- documentID
- type
- title
- description
- resourceURI?
- creatorActorID
- lifecycleState
- currentRevisionID
- createdAt / modifiedAt / deletedAt?

KnowledgeConceptRevision
- id
- conceptID
- documentRevisionID
- metadata snapshot
- parentRevisionID?
- authorActorID
- contentHash
- createdAt
```

首批 type 不需要固定封闭 taxonomy，但 fixture 至少覆盖：

- Principle
- Framework
- DecisionRule
- Playbook
- CaseStudy
- AntiPattern
- Boundary
- Rubric
- Reference

定义：

```text
Bundle
- stable id
- workspaceID
- creatorActorID
- title
- lifecycleState

BundleDraft
- mutable working aggregate
- revision

BundleVersion
- immutable release candidate
- semantic version
- manifestVersion
- okfVersion
- contentDigest
- status: frozen | exported | published | deprecated | revoked

BundleMember
- bundleVersionID
- target kind / target ID
- exact target revision ID
- exportPath
- role / rank
```

不变量：

- 冻结后的 BundleVersion 不随 Workspace 编辑变化。
- BundleVersion 不引用“当前最新内容”，只引用确定 revision。
- 移动文件、重命名和改变 `exportPath` 不改变内部 Concept UUID。

### 八、PublicationPolicy 与隐私边界

定义最小 PublicationPolicy：

```text
- visibility: private | candidate | included
- ownershipBasis: original | licensed | quoted | unknown
- commercialUse: allowed | prohibited | unknown
- attributionRequired
- attributionText?
- verificationStatus: selfDeclared | reviewed | verified
- sensitivity: normal | personal | confidential
```

要求：

- Workspace 默认 private。
- 只有明确加入 BundleVersion 的 revision 可以进入 Artifact。
- AI 对话、API Key、OAuth Token、bookmark、本地绝对路径、诊断内容不能因引用关系自动进入 Bundle。
- Linked 文件必须显式满足分发策略。
- Phase 0 只实现数据契约、确定性检查和失败类型；不做实名认证、人工版权审核、投诉和下架。

### 九、OKF Adapter 与确定性构建

OKF v0.1 是带 YAML frontmatter 的 Markdown 目录：

- 每个普通 Concept `.md` 至少有非空 `type`
- 推荐 `title`、`description`、`resource`、`tags`、`timestamp`
- `index.md` 与 `log.md` 是保留文件
- Concept 通过普通 Markdown link 建立关系
- 消费端应容忍未知 type、未知 frontmatter、缺失可选字段和 broken link

实现或建立一个纯、可测试的版本化 OKF Adapter 边界：

```text
- import
- export
- validate
- internal link rewrite
- preserve unknown frontmatter
```

内部 UUID 与 OKF path identity 必须分离：

```text
KnowledgeConceptID
    → BundleMember.exportPath
    → principles/value-first.md
```

确定性构建要求：

- 路径使用稳定 `/`
- 文件列表按确定顺序
- UTF-8 与 LF 规范化
- YAML key 输出顺序固定
- 不把 ZIP 时间戳或随机 metadata 计入内容摘要
- 相同输入 revision、Adapter 版本和构建器版本产生相同知识内容与 `contentDigest`
- `index.md`、`log.md` 和 frontmatter 是构建产物，不是第二个可写事实来源

推荐 Artifact 边界：

```text
ExpertyArtifact/
├── expert-manifest.json
├── okf/
│   ├── index.md
│   ├── log.md
│   └── concepts/*.md
├── assets/
└── reports/
    ├── validation.json
    └── benchmark.json
```

Phase 0 不做正式签名服务。可以定义 `ArtifactSigner` / `SignatureVerifier` 端口，但当前只生成内容 hash。

如果需要增加 YAML 或归档依赖，不要静默引入。先检查是否可以用小型受控实现；如果必须增加依赖，记录 ADR、版本、许可证、维护风险和替代方案。

### 十、Integration Event / Outbox

不要把 Experty 事件塞入 `sync_outbox`。

定义版本化 Integration Event Envelope，至少包含：

```text
- eventID
- eventName
- schemaVersion
- workspaceID
- actorID
- aggregate kind / aggregate ID
- operationID
- occurredAt
- payload
```

预留事件：

- `BundleBuilt`
- `BundlePublished`
- `BundleInstalled`
- `BundleInvoked`
- `OutcomeRecorded`
- `BundleDeprecated`

Phase 0 只持久化和验证事件，不连接 Experty，不发送遥测。

增加独立 Integration Outbox，并保证：

- 与相关业务事实同事务提交
- 同一 eventID 重试不重复
- 不包含本地路径、凭据或未明确发布的私人正文
- provider-neutral，不导入网络或 Experty SDK

### 十一、Phase 0C：Output Mainline

新增强类型 ID：

- `OutputID`
- `OutputRevisionID`
- `OutputRevisionMemberID`
- `ContributionID`
- `ChangeSetID`
- `ValidationRunID`
- `ValidationResultID`
- `ReviewID`
- `ReviewFindingID`
- `ApprovalID`
- `MergeRecordID`

`Document` 是可编辑内容，`Output` 是具有目的、受众、结构和主版本的正式产出。

```text
Output
- id
- workspaceID
- title
- purpose
- audience
- outputType
- currentRevisionID
- structureSchemaVersion
- createdAt / modifiedAt / deletedAt?
- revision

OutputRevision
- id
- outputID
- parentRevisionID?
- manifestHash
- createdByActorID
- createdAt

OutputRevisionMember
- outputRevisionID
- targetKind: document | concept | asset
- targetID
- targetRevisionID
- role
- rank
```

一次 OutputRevision 必须是确定的完整结构快照，不能在读取时动态解析“当前最新 Concept”。

### 十二、Contribution 与 ChangeSet

```text
Contribution
- id
- outputID
- baseOutputRevisionID
- title
- intent
- createdByActorID
- status
- revision
- createdAt / modifiedAt / closedAt?

ChangeSet
- id
- contributionID
- sequence
- baseOutputRevisionID
- proposedSnapshotID
- submittedByActorID
- submittedAt
- status
```

固化状态机：

```text
draft
  → submitted
  → reviewing
  → changesRequested → draft
  → approved → merged
  → closed
```

要求：

- 不能从 draft 直接 merged。
- Contribution 只能基于确定的 OutputRevision。
- Contribution 不能直接修改 `Output.currentRevisionID`。
- 每次提交产生不可变 ChangeSet。
- 请求修改后再次提交必须创建新的 sequence。
- 不能覆盖已经被 Review 的 snapshot。

### 十三、Diff、Validation、Review 与 Approval

事实是 base snapshot 与 proposed snapshot。Diff 是派生结果。

最小 Diff：

- member added / removed / moved
- member revision changed
- reference added / removed
- provenance changed
- 最小 Markdown content diff

Diff preview 属于 rebuildable cache。

定义 Validation：

```text
ValidationRule
- stable ruleID
- ruleVersion
- category
- defaultSeverity

ValidationRun
- id
- changeSetID
- policyVersion
- status
- startedAt / completedAt

ValidationResult
- runID
- ruleID / ruleVersion
- severity: info | warning | blocking
- status: passed | failed | skipped
- targetID?
- anchorJSON?
- message
```

首批确定性规则：

- Output structure 可解析
- 所有成员 revision 存在
- 内部引用有效
- 来源可追溯
- 无本地绝对路径、bookmark、API Key、Token 或 credential
- 无未明确加入的私人内容
- Linked 文件满足分发策略
- 当前 Mainline 与 expected revision 一致

定义 Review / Approval：

```text
Review
- id
- changeSetID
- reviewerActorID
- reviewerKind: human | ai | validator
- decision: comment | requestChanges | approve
- reviewedSnapshotID
- createdAt

ReviewFinding
- id
- reviewID
- severity
- targetID?
- anchorJSON?
- message
- resolutionStatus
```

Phase 0 权限：

- human Actor 可以 approve
- AI 可以 comment / request changes / produce finding
- validator 只能产生结果
- AI 不能批准自己的 ChangeSet
- 内容 snapshot 变化后旧 Approval 失效
- Approval 必须绑定确切 ChangeSet 与 snapshot

### 十四、Typed Commands

所有写操作必须通过 `ApplicationCommand`。至少实现端到端切片需要的命令：

Phase 0B：

- `CreateActor`
- `CaptureSource`
- `CreateKnowledgeConcept`
- `CreateBundleDraft`
- `FreezeBundleVersion`

Phase 0C：

- `CreateOutput`
- `CreateContribution`
- `SubmitChangeSet`
- `RecordValidationRun` 或等价的确定性验证命令
- `RecordReview`
- `RequestChanges`
- `ApproveChangeSet`
- `MergeContribution`
- `CloseContribution`

命令使用稳定版本化 identifier，例如：

```text
output.create.v1
contribution.create.v1
changeset.submit.v1
changeset.approve.v1
contribution.merge.v1
```

不要让 UI 或 Agent 绕过这些命令。

### 十五、MergeContribution 原子事务

`MergeContribution` 至少携带：

```text
- contributionID
- changeSetID
- expectedMainRevisionID
- approvalID
- operationID
```

一个事务中必须完成：

1. 检查 Contribution / ChangeSet 状态。
2. 检查 ChangeSet 与 proposed snapshot 没有变化。
3. 检查 human Approval 绑定同一 snapshot。
4. 检查没有未解决 blocking Validation。
5. 比较当前 Mainline 与 expected revision。
6. 创建新的 OutputRevision。
7. 创建完整 OutputRevisionMember snapshot。
8. 更新 `Output.currentRevisionID` 与 revision。
9. 创建 MergeRecord。
10. 将 Contribution 标记为 merged。
11. 写 `applied_operations`。
12. 写 Sync Outbox。
13. 写必要的 Integration Outbox。

```text
MergeRecord
- id
- contributionID
- changeSetID
- mainBeforeRevisionID
- contributionHeadRevisionID
- mainAfterRevisionID
- approvalID
- approvedByActorID
- operationID
- mergedAt
```

失败时以上事实必须一起回滚，或通过既有 operation journal 完成可证明的恢复。不能出现 Mainline 已变化但 MergeRecord / Outbox 缺失。

### 十六、并发、幂等与冲突

必须测试：

```text
Contribution A 与 B 都基于 Main Revision 1
A 先合并为 Revision 2
B 使用 expected Revision 1 合并
→ 返回显式 revision conflict
→ Main Revision 2 不变
→ B 不产生部分 MergeRecord / Outbox
```

还必须测试：

- 同一 Merge `operationID` 重放，只返回同一个 mainAfterRevision。
- 不同 merge intent 复用同一 operationID，失败关闭。
- 事务提交前注入失败，所有业务事实和 Outbox 一起回滚。
- retry 使用相同 operationID 后成功且不重复。
- blocking Validation 阻止 Merge。
- Approval 对错误 snapshot 无效。
- ChangeSet 重新提交后旧 Approval 失效。
- closed / merged Contribution 不能再次合并。

不需要 CRDT、完整 Git DAG 或自动 rebase。使用 `expectedMainRevisionID`、不可变 snapshot 和 MergeRecord 即可。

### 十七、schema 与 migration

当前 `DatabaseSchema.currentVersion == 2`。

推荐按两个可审查 migration 推进：

- `v3-knowledge-assets`
- `v4-output-mainline`

如果实际依赖要求不同，可以调整拆分，但必须：

- 不修改 v1 / v2。
- 每个 migration 名称一旦提交就不可修改。
- 添加 schema v3 / v4 fixture。
- 保留 v1 active、v1 closed、v2 synced fixtures。
- 测试每个历史 fixture 逐级迁移到 current schema。
- 创建必要 foreign key、unique、check 和 partial index 保证领域不变量。
- 所有时间和 UUID 序列化延续现有数据库约定。
- 迁移前备份和损坏恢复继续有效。

Domain 模型不要求与数据库一表一对象，但数据库必须能够表达不可变 revision、状态机、唯一 sequence、idempotency 和完整 lineage。

### 十八、同步分类

更新 `SyncRecordKind`、数据分类和测试，使以下正式事实可以未来同步：

- Actor / CreatorProfile
- SourceRecord
- KnowledgeConcept / revision
- Reference
- Bundle / BundleVersion / BundleMember
- PublicationPolicy
- Output / OutputRevision / members
- Contribution / saved draft
- ChangeSet
- 用于审批决策的 ValidationRun / Result
- Review / Approval
- MergeRecord
- Integration Event 的业务事实

local-only：

- 未保存输入
- selection / window state
- security-scoped bookmark
- 绝对路径
- API Key / OAuth Token
- Job lease
- 临时 AI stream

rebuildable：

- Diff preview
- FTS
- Embedding
- thumbnail
- render cache
- 未保存为 ReviewFinding 的 AI 语义建议

同步协议仍保持 provider-neutral。不要接 CloudKit、iCloud Drive、NAS 或 Experty SDK。

### 十九、推荐模块边界

优先复用现有模块：

- `VersoDomain`：ID、实体、状态机、不变量和领域错误
- `VersoApplication`：Commands、ports、policies、validation orchestration
- `VersoPersistence`：GRDB migration、repository / service、事务、Outbox
- `VersoSyncProtocol`：record kinds、payload contract、分类
- `VersoFileSystem`：Artifact 与不可变内容的原子写入
- `VersoObservability`：新操作 trace 和错误分类

如确实需要纯格式模块，可以创建类似 `VersoBundleFormat`，但必须保持依赖单向、无 UI、无数据库、无 provider SDK，并更新：

- `Package.swift`
- `Scripts/check_dependencies.sh`
- 对应 test target
- 架构文档

不要为了“看起来模块化”创建一组没有端到端调用的空 package。

### 二十、ADR 与文档交付

实现前或与实现同步补充：

1. `docs/architecture/DATA_MODEL.md`
2. 新 ADR：知识血缘、OKF Adapter 与不可变 BundleVersion
3. 新 ADR：Output Mainline、Contribution / Review / Merge
4. 新 ADR：Sync Outbox 与 Integration Outbox 分离（如果不能在前两份中清晰表达）
5. `docs/architecture/decisions/README.md`
6. `docs/engineering/PHASE0.md`
7. `docs/engineering/SYNC_BASELINE.md`

只把真正完成并验证的用户能力写入 `docs/product/PRODUCT_CHANGELOG.md`。不要把设计完成但尚未实现的能力写成已交付。

### 二十一、最小端到端切片

先完成纵向切片，不要同时铺开所有 CRUD。

Phase 0B：

```text
创建 Actor
    → 捕获 SourceRecord
    → 创建 KnowledgeConcept 与 derivedFrom / citation
    → 创建 BundleDraft
    → 冻结 BundleVersion
    → 确定性导出 OKF
    → Validate
    → 重新 Import
    → 验证 UUID、来源、引用、未知 frontmatter 与 contentDigest
```

Phase 0C：

```text
创建 Output Main Revision 1
    → 创建基于 Revision 1 的 Contribution
    → 提交 ChangeSet
    → 运行确定性 Validation
    → 记录 human Approval
    → MergeContribution
    → 原子生成 Main Revision 2、MergeRecord、Sync Outbox 与 Integration Outbox
```

完成后再补并发、失败注入和旧 schema migration 测试。

### 二十二、测试要求

使用当前仓库采用的 Swift Testing 风格。

至少覆盖：

Domain：

- ID Codable / Hashable / Sendable 使用
- 状态机合法与非法迁移
- BundleVersion 与 OutputRevision 不可变
- ChangeSet sequence 与 snapshot 绑定
- Approval 失效规则

Persistence：

- v1 / v2 / v3 / v4 migration
- foreign key 和唯一约束
- immutable snapshot 重启恢复
- 事务内业务事实 + applied operation + Sync Outbox + Integration Outbox
- idempotent replay
- operation fingerprint 冲突
- stale revision conflict
- transaction rollback / retry
- backup / recovery 兼容

Format：

- 最小 OKF 合规
- required type
- unknown frontmatter round-trip
- internal / relative links
- exportPath 与 UUID 分离
- 两次构建 digest 相同
- 私密字段和本地路径不进入 Artifact

Contribution / Merge：

- Contribution 不能直接更新 Mainline
- blocking validation 阻止 merge
- human approval 必需
- AI reviewer 不能 approve
- snapshot 变化后 approval 失效
- 重复 merge 不重复产生 revision
- 两个并发 Contribution 的 stale merge 失败
- 失败注入不会留下半 Merge

Sync / privacy：

- 每个新增 record kind 只有一个数据分类
- sync / integration payload 不含 bookmark、绝对路径、API Key、OAuth Token、credential 或未授权正文

### 二十三、本地验证命令

在仓库根目录执行：

```sh
bash Scripts/check_dependencies.sh

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --package-path Packages/VersoCore

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild \
  -workspace Verso.xcworkspace \
  -scheme Verso \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild \
  -workspace Verso.xcworkspace \
  -scheme VersoUnitTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

如果当前 Xcode 路径不同，先用 `xcode-select`、`xcrun` 和实际已安装版本确认，不要猜测。

### 二十四、完成标准

只有以下条件全部满足，才能报告 Phase 0B / 0C 对应切片完成：

- 历史 migration 未被修改。
- 新 migration 与 fixture 可从所有受支持版本升级。
- 依赖方向检查通过。
- Swift Package 测试通过。
- App Debug build 通过。
- App 单元测试通过。
- Source → Concept → BundleVersion → OKF 的最小切片可运行。
- Output → Contribution → ChangeSet → Validation → Approval → Merge 的最小切片可运行。
- 同一 operation 重放不重复。
- stale revision 不覆盖。
- 事务失败不产生部分事实。
- BundleVersion 与 OutputRevision 不受后续编辑影响。
- 本地路径、凭据和私人内容不泄漏到 sync、integration 或 Artifact。
- 无 AI、无 Experty、无网络时核心切片仍可工作。
- 文档准确描述已经实现的代码，不把规划当成交付。

### 二十五、明确禁止提前实现

本任务不要实现：

- Experty Store、Registry、支付、价格、退款、结算
- Experty 登录或真实网络 API
- 创作者实名认证、人工版权审核、投诉和下架
- 正式数字签名服务或 DRM
- Outcome Dashboard、推荐和真实调用遥测
- CloudKit、CKSyncEngine、iCloud Drive 或 NAS transport
- 完整 Bundle Studio UI
- 完整 Markdown / TipTap 编辑器
- Git 仓库或 Git 命令
- 完整分支 DAG、复杂 rebase
- 多人 Reviewer、评论线程、@mention
- CRDT、实时协作
- AI 自动批准、AI 自动合并、AI 自动发布
- 插件系统、多 Agent 自主协作

### 二十六、工作方式

- 先检查现状，再制定短计划。
- 每完成一个可验证的垂直切片就运行相关测试。
- 不要用大量空协议和 TODO 代替实现。
- 不要为了减少代码而削弱事务、幂等、revision、隐私或审计约束。
- 不要为了“长期架构”提前引入微服务、网络层或云端依赖。
- 遇到不影响用户意图的实现细节，做稳健假设并记录。
- 只有涉及范围扩大、不可逆数据格式决定或无法从现有文档判断的产品语义时才请求用户选择。

### 二十七、最终交付报告

最终报告必须说明：

1. 实际实现了哪些 Phase 0B / 0C 能力。
2. 新增或修改了哪些 Domain / Application / Persistence / Format 模块。
3. 新 schema 版本、migration 名称和 fixture。
4. 实现了哪些 Commands 和状态机。
5. Merge 的事务、幂等和冲突行为。
6. OKF 确定性构建与 round-trip 行为。
7. Sync Outbox 与 Integration Outbox 如何分离。
8. 运行了哪些测试和命令，结果如何。
9. 哪些内容仍按路线图延后。
10. 任何尚未完成或需要人工验收的真实事项。

不要把尚未实现的规划描述成完成。

## 任务结束
