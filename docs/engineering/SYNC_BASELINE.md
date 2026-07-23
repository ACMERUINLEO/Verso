# Phase 0 同步兼容基线

状态：schema v4 本地实现完成，未连接真实远端

## 边界

`VersoSyncProtocol` 只描述可携带的变更，不选择传输实现。CloudKit、便携云盘目录和 NAS adapter 未来都必须实现同一个 `SyncTransport`，但不得把 provider 类型反向暴露给 Domain 或 Application。

每台设备继续使用独立的 Workspace SQLite。SQLite、WAL、operation journal 和本机安全作用域书签不作为同步文件共享。

## 身份与幂等

- `WorkspaceID`、实体 ID、`DeviceID` 和 `OperationID` 都是稳定 UUID 值对象。
- App 在本机 `UserDefaults` 中创建并复用 `DeviceID`；它不是密钥，也不包含用户路径。
- 每次可同步写命令携带 `OperationID`。
- `applied_operations.operation_id` 是主键，并保存 command fingerprint。
- 完全相同的操作重放返回已持久化结果；不同 command、device 或参数复用同一 ID 会拒绝。
- 业务事实、`applied_operations` 与 `sync_outbox` 在同一个 SQLite 事务提交。

## revision 与删除

- 可同步实体从 revision 1 开始，每次事实修改单调递增。
- mutation 记录 `baseRevision` 与新 `revision`，为未来冲突判断保留因果信息。
- 删除使用带 revision、`deletedAt` 和 `OperationID` 的 tombstone，不以“记录消失”表达同步删除。
- Workspace 的打开/关闭状态属于本机会话状态，不增加同步 revision，也不进入 Sync Outbox。

## 隐私与数据分类

| 分类 | 内容 |
|---|---|
| synced fact | Workspace/Node、Actor/CreatorProfile、Source、Concept/Reference/Policy、Bundle、Output/Revision、Contribution/ChangeSet、用于审批的 Validation、Review/Approval、MergeRecord、Integration Event、immutable revision、tombstone、Operation identity |
| local-only fact | bookmark、绝对路径、API/OAuth 密钥、设备凭据、Job lease、本机执行状态、未保存输入、选区、窗口状态、临时 AI stream |
| rebuildable cache | FTS、Embedding、缩略图、预览产物、Diff preview、render cache、未保存为 Finding 的 AI 建议 |

Sync Outbox payload 使用显式 DTO 编码。禁止直接编码 App 状态、文件 URL、bookmark data、Keychain 内容或数据库 row。

Document Revision 的同步 payload 只包含稳定 ID、内容哈希、父 revision 与 Actor；Workspace 内相对读取路径仍不进入 payload。Concept 同步事实不自动携带 Markdown 正文，Bundle/Output 只同步确定身份、revision、策略与摘要。

## Integration Outbox

Integration Outbox 与 Sync Outbox 是两张独立表和两类协议：

- Sync Outbox 为未来设备一致性传输服务。
- Integration Outbox 保存版本化业务事件信封，当前只产生 `BundleBuilt` 与必要的 `OutputMerged`。
- Integration payload 只含 ID、版本、摘要和数量，不含正文、绝对路径、bookmark、API Key、OAuth Token 或 credential。
- 两个 Outbox 与相关事实使用同一个 SQLite 事务；故障时一起回滚。
- Phase 0 没有 Integration consumer，不连接 Experty，也不发送遥测。

## Phase 0 不做

- 不连接 CloudKit、iCloud Drive、第三方云盘或 NAS。
- 不上传或拉取数据。
- 不定义 provider 认证。
- 不实现多设备冲突 UI。
- 不共享正在使用的 SQLite 文件。
