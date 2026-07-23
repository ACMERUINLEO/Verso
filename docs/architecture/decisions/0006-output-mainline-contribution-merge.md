# ADR-0006：Output Mainline 通过 Contribution、Review 与原子 Merge 演进

状态：Accepted
日期：2026-07-23

## 背景

Document 的可编辑“当前内容”不能同时承担正式产出的主版本。若 UI、用户或未来 AI 可直接更新 Output 当前指针，Review、Approval、冲突和来源追踪都会被绕过，故障时还可能产生主版本已变化但审计事实缺失的半完成状态。

## 决策

- `OutputRevision` 是完整、不可变的成员快照；每个成员固定 target ID、target revision、role 与 rank。
- `Contribution` 必须绑定创建时的 `baseOutputRevisionID`，状态按 `draft → submitted → reviewing → changesRequested → draft` 或 `reviewing → approved → merged` 演进，终态可关闭。
- 每次提交创建新的不可变 `ChangeSet` 和 proposed snapshot，sequence 单调递增，不覆盖已审查快照。
- Diff 是由 base/proposed snapshot 派生的可重建结果；Phase 0 支持成员、revision、rank、Reference、provenance 和最小 Markdown 行变化。
- Validation 使用稳定 rule ID/version，绑定 ChangeSet；人工 Review/Finding 和 Approval 绑定确切 proposed snapshot。AI 不能批准。
- `MergeContribution` 必须携带 expected main revision、ChangeSet、Approval 与 `OperationID`。
- Merge 在一个 SQLite 事务中检查状态、最新 ChangeSet、人工 Approval、blocking Validation 和 expected main revision，然后创建新 main snapshot、更新 Output、写 MergeRecord、更新 Contribution、写 applied operation、Sync Outbox 与 Integration Outbox。
- 相同 operation 重放返回原 main-after revision；不同意图复用同一 operation 失败。stale mainline 明确冲突，不自动 rebase。

## 后果

- UI 与未来 Agent 都只能通过同一 Typed Command 边界修改正式产出。
- 两个基于同一 main revision 的 Contribution 可以独立审查，但只有先合并者成功；后者保持原状态并且不产生部分事实。
- 事务故障会同时回滚 OutputRevision、当前指针、MergeRecord 和两个 Outbox。
- Phase 0 不实现 Git、CRDT、完整分支 DAG、复杂 rebase、多人评论线程或 AI 自动合并。

## 未选择

- 直接把 Document current revision 当作 Output Mainline。
- 让 Contribution 修改 `Output.currentRevisionID`。
- 把 Diff 保存为恢复 Output 的唯一事实。
- 使用最后写入者胜出处理并发 Merge。

## 复审触发条件

需要多人实时协作、多主分支、复杂 rebase 或跨 Workspace 合并时，通过新 ADR 扩展，不放宽 expected revision 与原子事务不变量。
