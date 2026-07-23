# Phase 0：工程、知识资产与 Output Mainline 基线

状态：Phase 0A、0B、0C 工程切片本地完成；表层产品入口仍待后续阶段
产品：Verso
项目代号：Prologue

面向产品功能与节奏判断的版本摘要统一记录在 `docs/product/PRODUCT_CHANGELOG.md`。工程文档说明实现边界，产品更新日志只描述用户实际获得和已经验证的能力。

## 本批交付

- `Verso.xcworkspace`：正式开发入口。
- `Packages/VersoCore`：本地 Swift Package，承载稳定边界。
- `VersoDomain`：身份、Workspace 模型与领域规则。
- `VersoApplication`：Command Bus、Workspace 命令、故障注入、Outbox 与 Job Runner 端口。
- `VersoBundleFormat`：无 UI、数据库或网络依赖的 OKF/Artifact 确定性导入、导出、校验、链接改写与摘要。
- `VersoPersistence`：GRDB 7、schema v1→v2、WAL、迁移、事务 Outbox、备份、损坏检测与恢复入口。
- `VersoSyncProtocol`：与 CloudKit、云盘和 NAS 无关的 change batch、cursor、tombstone、数据分类与 `SyncTransport` 端口；Phase 0 不连接真实远端。
- `VersoFileSystem`：带 operation journal 的原子文件写入和启动恢复。
- `VersoObservability`：Unified Logging、错误分类、诊断 JSON 与关键路径 signpost。
- 正式 App Shell：创建、打开、关闭、重开、遗忘、移到废纸篓与只读恢复。
- 隐藏 `.verso/` 元数据布局，以及最小 Markdown 新建、导入、编辑与原子保存能力。
- 五份可审查的 SQL 快照：schema v1 active/closed、schema v2 synced、schema v3 knowledge assets 与 schema v4 output mainline。
- 备份安全策略：默认保留 10 份普通备份、预留 64 MB 可用空间，并在恢复前复制当前数据库。
- 统一诊断上下文：App 启动、数据库迁移、Workspace 创建/打开/备份/恢复、原子文件写入和 Job Runner 共用关联 trace。
- 同步兼容基线：稳定 `DeviceID`/`OperationID`、单调 revision、tombstone、`applied_operations` 和 `sync_outbox`。
- `CreateWorkspace` 与 `RenameWorkspace` 在一个 SQLite 事务中同时提交业务事实、已应用操作和 Sync Outbox；同一操作重放不重复写入，不同意图复用同一 ID 会失败关闭。
- `Scripts/check_dependencies.sh`：可执行的依赖方向检查。
- GitHub Actions：Package 测试以及 App 的 Debug/Release 构建。
- `VersoUnitTests` shared scheme：只运行 App 单元测试，不隐式构建 UI Test Runner。
- Phase 0B：Actor、SourceRecord、Document Revision、KnowledgeConcept/Revision、Reference、PublicationPolicy、Bundle Draft、不可变 BundleVersion 与独立 Integration Outbox。
- Phase 0B 纵向切片：Source → Concept → Bundle Draft → Freeze → 确定性 OKF Artifact → Validate → Import；保留 UUID、未知 frontmatter、相对链接与 content digest。
- Phase 0C：Output/Main Revision、Contribution 状态机、不可变 ChangeSet、确定性 Diff/Validation、Review/Finding、人工 Approval 与 MergeRecord。
- Phase 0C 纵向切片：Output Revision 1 → Contribution → ChangeSet → Validation → human Approval → 原子 Main Revision 2、MergeRecord、Sync Outbox 与 Integration Outbox。
- stale mainline、blocking finding、AI approval、operation fingerprint 冲突、事务失败回滚/重试与重启恢复均有测试。

## 依赖规则

```text
Verso App / Features
        |
        v
VersoApplication ---> VersoDomain
        |                 ^
        v                 |
VersoSyncProtocol --------+
VersoBundleFormat --------+
        ^
        |
Infrastructure implementations
(Persistence / FileSystem / future Search and AI)
```

- Domain 不得导入 SwiftUI、AppKit、GRDB、EventKit、WebKit 或 OSLog。
- Application 不得导入具体基础设施框架。
- UI 和未来的 Agent 只发送 Command；不能持有数据库或任意文件句柄。
- 派生任务通过事务 Outbox 提交，事务成功后才允许 Job Runner 消费。
- Sync 协议模块不导入平台 UI、数据库或任何远端 provider SDK。
- BundleFormat 只依赖 Domain，不导入 Application、Persistence、文件权限、UI 或 provider SDK。

## schema v1 到 v4

schema v1 保持不可变：

- `workspaces`
- `nodes`（仅创建逻辑根节点）
- `outbox_jobs`
- `operation_journal`

schema v2 只增加同步兼容字段与表：

- `workspaces.revision` / `workspaces.deleted_at`
- `nodes.revision` / `nodes.operation_id`
- `applied_operations`
- `sync_outbox`

GRDB 自己维护迁移记录。已发布的 `v1` 与 `v2-sync-baseline` 名称和内容不得修改；下一次结构变化必须新增迁移。

schema v3 `v3-knowledge-assets` 追加 Actor、CreatorProfile、Document Revision、SourceRecord、PublicationPolicy、KnowledgeConcept/Revision、Reference、Bundle/Draft/Version/Member、冻结 Artifact 文件快照和 Integration Outbox。

schema v4 `v4-output-mainline` 追加 Output/Revision/Member、Contribution、ChangeSet、Validation Run/Result、Review/Finding、Approval 和 MergeRecord。

五份 fixture 会逐级迁移到 current schema；打开旧版本前仍创建 `pre-migration-v4.sqlite` 保护备份。已发布 migration 名称和 SQL 不得覆盖修改。

## 数据分类

- synced fact：Workspace/Node、Actor/CreatorProfile、Source、Concept/Reference/Policy、Bundle、Output、Contribution/ChangeSet、用于决策的 Validation、Review/Approval、MergeRecord、Integration Event 与 immutable revision。
- local-only fact：security-scoped bookmark、绝对路径、API Key、OAuth token、设备凭据、Job lease、本机执行状态、未保存输入/选区/窗口状态与临时 AI stream。
- rebuildable cache：FTS、Embedding、缩略图、预览产物、Diff、render cache 与未保存的 AI 语义建议。

完整的可执行分类定义见 `VersoSyncProtocol/SyncProtocol.swift`；测试要求每个分类项只能属于其中一类。

## 已覆盖的失败场景

- 数据库事务提交前失败：业务事实和 Outbox 一起回滚，可安全重试。
- 同一 `OperationID` 重放：返回已持久化事实，不新增业务记录或 Sync Outbox；不同意图复用会拒绝。
- 文件替换前失败：旧文件保持不变，启动恢复会清理临时文件。
- 文件提交后终止：新文件保持完整，启动恢复会完成 journal 收尾。
- 数据库头或 `quick_check` 异常：返回 `recoveryRequired`，不再提供写会话。
- 一致性备份恢复：恢复后重新执行完整性检查并打开原 Workspace 身份。
- Bundle 构建前失败：不会留下 BundleVersion、Sync 或 Integration Event；相同 operation 可安全重试。
- Merge 提交前失败：Output Mainline、MergeRecord、Contribution 状态和两个 Outbox 全部回滚。
- 两个 Contribution 基于同一 main revision：先合并者成功，后者返回显式 stale-mainline 冲突且不产生部分事实。

## 本地验证

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

## 尚未进入表层产品的内容

- Phase 0B/0C 目前是 Domain、Command、Persistence、Format 与测试闭环，没有 Bundle Studio、Output、Contribution、Review 或 Merge 的 App UI。
- 没有 Experty、真实同步 transport、网络消费者、支付、Registry、数字签名、CloudKit、NAS、CRDT 或 AI 自动审批/合并。
- Integration Outbox 只持久化并验证最小事件，不发送遥测或外部请求。
- 当前 Artifact 由服务按冻结事实重建；尚无用户选择导出目录、ZIP 或 Finder 导出入口。

完整范围、退出标准与后续产品阶段见 `docs/product/ROADMAP.md`。交给独立 Codex 任务继续生产代码时，使用 `docs/engineering/PHASE0_CONTINUATION_PROMPT.md` 作为自包含提示词。
