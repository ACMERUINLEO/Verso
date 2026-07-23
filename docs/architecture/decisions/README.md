# Architecture Decision Records

ADR 记录难以逆转的技术决策及其原因。状态只使用 `Proposed`、`Accepted`、`Superseded`、`Rejected`。

规则：

- Accepted ADR 不覆盖修改；新决策通过新 ADR supersede 旧决策。
- 每条 ADR 必须说明背景、选择、后果、替代方案和复审触发条件。
- 外部依赖、最低系统版本、数据格式、隐私边界和同步协议必须有 ADR。

当前决策：

- [0001：原生 macOS 与模块化单体](0001-native-modular-monolith.md)
- [0002：SQLite/GRDB 作为业务事实来源](0002-sqlite-grdb.md)
- [0003：逻辑树与真实文件分离](0003-logical-tree-file-ownership.md)
- [0004：Agent 只能通过受控命令执行写操作](0004-agent-command-boundary.md)
- [0005：知识血缘、OKF Adapter 与不可变 BundleVersion](0005-knowledge-lineage-okf-bundle-version.md)
- [0006：Output Mainline 通过 Contribution、Review 与原子 Merge 演进](0006-output-mainline-contribution-merge.md)
- [0007：Sync Outbox 与 Integration Outbox 分离](0007-separate-sync-and-integration-outboxes.md)
