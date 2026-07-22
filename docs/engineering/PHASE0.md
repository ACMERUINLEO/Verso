# Phase 0：工程与可靠性骨架

状态：功能完成，待人工验收与远端 CI
产品：Verso
项目代号：Prologue

面向产品功能与节奏判断的版本摘要统一记录在 `docs/product/PRODUCT_CHANGELOG.md`。工程文档说明实现边界，产品更新日志只描述用户实际获得和已经验证的能力。

## 本批交付

- `Verso.xcworkspace`：正式开发入口。
- `Packages/VersoCore`：本地 Swift Package，承载稳定边界。
- `VersoDomain`：身份、Workspace 模型与领域规则。
- `VersoApplication`：Command Bus、Workspace 命令、故障注入、Outbox 与 Job Runner 端口。
- `VersoPersistence`：GRDB 7、schema v1→v2、WAL、迁移、事务 Outbox、备份、损坏检测与恢复入口。
- `VersoSyncProtocol`：与 CloudKit、云盘和 NAS 无关的 change batch、cursor、tombstone、数据分类与 `SyncTransport` 端口；Phase 0 不连接真实远端。
- `VersoFileSystem`：带 operation journal 的原子文件写入和启动恢复。
- `VersoObservability`：Unified Logging、错误分类、诊断 JSON 与关键路径 signpost。
- 正式 App Shell：创建、打开、关闭、重开、遗忘、移到废纸篓与只读恢复。
- 隐藏 `.verso/` 元数据布局，以及最小 Markdown 新建、导入、编辑与原子保存能力。
- 三份可审查的 SQL 快照：schema v1 active/closed 与 schema v2 synced，覆盖历史迁移和当前同步基线。
- 备份安全策略：默认保留 10 份普通备份、预留 64 MB 可用空间，并在恢复前复制当前数据库。
- 统一诊断上下文：App 启动、数据库迁移、Workspace 创建/打开/备份/恢复、原子文件写入和 Job Runner 共用关联 trace。
- 同步兼容基线：稳定 `DeviceID`/`OperationID`、单调 revision、tombstone、`applied_operations` 和 `sync_outbox`。
- `CreateWorkspace` 与 `RenameWorkspace` 在一个 SQLite 事务中同时提交业务事实、已应用操作和 Sync Outbox；同一操作重放不重复写入，不同意图复用同一 ID 会失败关闭。
- `Scripts/check_dependencies.sh`：可执行的依赖方向检查。
- GitHub Actions：Package 测试以及 App 的 Debug/Release 构建。
- `VersoUnitTests` shared scheme：只运行 App 单元测试，不隐式构建 UI Test Runner。

## 依赖规则

```text
Verso App / Features
        |
        v
VersoApplication ---> VersoDomain
        |                 ^
        v                 |
VersoSyncProtocol --------+
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

## schema v1 与 v2

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

## 数据分类

- synced fact：Workspace/Node 元数据、immutable revision、tombstone、Operation identity。
- local-only fact：security-scoped bookmark、绝对路径、API Key、OAuth token、设备凭据、Job lease、本机执行状态。
- rebuildable cache：FTS、Embedding、缩略图与预览产物。

完整的可执行分类定义见 `VersoSyncProtocol/SyncProtocol.swift`；测试要求每个分类项只能属于其中一类。

## 已覆盖的失败场景

- 数据库事务提交前失败：业务事实和 Outbox 一起回滚，可安全重试。
- 同一 `OperationID` 重放：返回已持久化事实，不新增业务记录或 Sync Outbox；不同意图复用会拒绝。
- 文件替换前失败：旧文件保持不变，启动恢复会清理临时文件。
- 文件提交后终止：新文件保持完整，启动恢复会完成 journal 收尾。
- 数据库头或 `quick_check` 异常：返回 `recoveryRequired`，不再提供写会话。
- 一致性备份恢复：恢复后重新执行完整性检查并打开原 Workspace 身份。

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

## Phase 0 仍需完成

- 在 GitHub 的 macOS runner 实际跑通 CI 后锁定 runner 与 Xcode 版本。

当前固定三份 fixture：两个已发布 schema v1 状态与一个 schema v2 同步状态。新增 schema 版本时必须保留这些快照，并追加跨版本迁移 fixture。
