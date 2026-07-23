# ADR-0004：Agent 只能通过受控命令执行写操作

状态：Accepted
日期：2026-07-22

## 背景

Agent 会读取不可信文件和模型输出，并可能修改用户内容、文件和日历。让模型直接访问数据库、Shell 或任意文件路径会绕过产品权限和数据一致性规则。

## 决策

Agent 只能调用有版本、强类型的工具。所有工具写操作转换为 Application Command，经 Policy Engine、必要的用户确认、事务和 operation journal 执行。模型永远不能获得数据库句柄、任意 Shell 或不受限文件 API。

## 后果

- UI 与 Agent 共用业务规则、权限、测试和撤销机制。
- 工具设计需要更谨慎，新增能力速度略慢。
- 每次写入可关联到 AgentRun、ToolCall、Approval 和 Operation。
- Prompt 中的指令不能自行提升权限。

## 未选择

- 让 Agent 直接生成并运行 SQL。
- 让 Agent 使用通用 Shell 完成应用内操作。
- 用系统 Prompt 代替权限校验。

## 复审触发条件

只有在独立沙箱、能力令牌和可验证策略成熟后，才讨论第三方插件或代码执行；不得直接放宽本 ADR。
