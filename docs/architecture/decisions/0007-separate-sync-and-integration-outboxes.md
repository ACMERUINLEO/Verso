# ADR-0007：Sync Outbox 与 Integration Outbox 分离

状态：Accepted
日期：2026-07-23

## 背景

设备同步和未来 Experty 业务集成都需要可靠重试，但语义不同：同步复制 Workspace 事实，Integration Event 表达 Bundle 构建、发布、调用或 Output 合并等业务事件。混用同一队列会把 provider、隐私和消费幂等规则耦合。

## 决策

- `sync_outbox` 只保存 provider-neutral 的设备一致性变更，使用 record kind、base revision、revision 和 mutation。
- `integration_outbox` 保存版本化事件信封：event ID/name/schema、Workspace、Actor、aggregate、operation、发生时间和最小 payload。
- 两个 Outbox 可在同一业务事务中写入，但拥有独立表、状态、重试次数、索引和未来消费者。
- Integration payload 只包含业务身份、版本和摘要；不包含正文、绝对路径、bookmark、API/OAuth token、credential 或数据库连接信息。
- Phase 0 只持久化并验证事件，不启动网络消费者、不连接 Experty、不发送遥测。

## 后果

- 更换同步 provider 不会改变 Experty 事件契约，反之亦然。
- 同一 command 的事务失败不会留下只有一个 Outbox 的半完成状态。
- 队列消费、退避和远端幂等将在真正接入 provider 时分别设计。

## 未选择

- 把 `BundleBuilt` 或 `OutputMerged` 编码成 SyncRecord。
- 复用后台 `outbox_jobs` 承担外部业务事件。
- Phase 0 直接发送网络请求。

## 复审触发条件

首次接入真实同步 provider 或 Experty API 前，分别新增传输、认证、保留和消费幂等 ADR。
