# 从架构到首个可用版本

路线图按风险消除排序，而不是按界面可见度排序。每个阶段都必须留下可运行、可迁移、可恢复的版本。

Verso 的长期产品主线：

```text
Source
    → KnowledgeConcept
    → Contribution / ChangeSet
    → Review / Validation
    → Output Mainline
    → immutable BundleVersion
    → OKF Artifact
    → Experty 发布、交易、安装与效果反馈
```

没有 Experty 时，Verso 必须独立完成“搜集信息 → 理解与 AI 共创 → 沉淀知识 → 形成产出 → 持续复用”；连接 Experty 只增加公开身份、分发、交易、许可交付和效果网络，不能成为打开、编辑、导出或恢复用户私人 Workspace 的前置条件。

## Phase 0：工程与可靠性骨架（2–3 周）

目标：建立以后所有功能共用的安全底座。

- 创建 Xcode Workspace、App target、本地 Packages 和测试 targets
- 开启 Swift 6 严格并发、App Sandbox、基础签名与 CI
- 建立 Domain / Application / Infrastructure 依赖规则
- 集成 SQLite/GRDB、迁移器、fixture、备份与恢复测试
- 建立 Command Bus、事务 Outbox、后台 Job Runner
- 建立结构化日志、错误分类和诊断导出骨架
- 为关键路径设置性能 signpost
- 固化同步兼容数据基线：稳定 UUID、`deviceID`、revision、tombstone、幂等 `OperationID`
- 将数据明确分类为 synced fact、local-only fact 或 rebuildable cache
- 定义与 CloudKit、云盘和 NAS 无关的 `SyncTransport` 抽象；本阶段不连接真实远端

退出标准：

- 空工作空间可创建、关闭、重新打开。
- schema v1 可迁移，损坏数据库会进入只读恢复流程而不是继续写入。
- 测试可模拟在事务、文件写入和应用终止点失败。
- CI 对 Debug/Release、单元测试、迁移测试均通过。
- 正式 Command 可在同一事务中提交业务事实与 Sync Outbox；重复应用同一 `OperationID` 不产生重复结果。
- 本地路径、security-scoped bookmark、API Key 和其他设备凭据不会进入同步协议。

### Phase 0B：知识资产与 Bundle 发布契约补强（1–2 周）

状态：2026-07-23 工程纵向切片完成；表层 Bundle Studio 与用户导出入口仍按后续阶段推进。

目标：在不提前实现 Experty 商店、支付和远端 Registry 的前提下，让 Verso 中的知识从创建第一天起就能保留作者、来源、权利、版本和调用归因，并可确定性地构建为未来能够分享、发布和交易的 OKF Bundle。

产品边界：

- Verso 负责“搜集信息 → 沉淀知识 → 转化产出 → 构建与验证 Bundle”，是专家上下文资产的生产源头。
- Experty 负责 Bundle 的发布、发现、交易、许可交付、安装、调用计量和效果网络。
- Workspace 内部模型不直接等同于 OKF v0.1；OKF 是版本化的导入、导出和交换协议，不能反向限制 Verso 的稳定身份、事务和同步模型。

身份与知识血缘基线：

- 定义与登录账号、邮箱、Apple ID 和设备 ID 解耦的 `ActorID` / `CreatorProfileID`；初期允许本地创建，未来可绑定 Experty 身份。
- 增加 `SourceRecord` 契约，记录来源类型、canonical URL、原作者、捕获时间、内容哈希、快照 revision 和可选原始 Asset。
- 扩展 `Reference.relation`，至少预留 `cites`、`quotes`、`supports`、`contradicts`、`derivedFrom`、`summarizes` 和 `includedIn`。
- 来源、知识文档、AI 生成内容、最终产出和 Bundle Member 之间必须能够通过稳定 ID 与具体 revision 反向追踪。
- AI、导入器和恢复流程仍使用 Actor 身份与 author kind 区分，不把模型名称或设备当成作者身份。

可发布知识与 Bundle 领域基线：

- 在可编辑的 `Document` 之上定义 `KnowledgeConcept` 契约，包含稳定 ID、`type`、标题、描述、资源 URI、标签、创作者和生命周期状态。
- `KnowledgeConcept` 的发布快照必须绑定确切的内容 revision 与元数据 revision；移动文件、重命名和改变导出路径不得改变内部 Concept 身份。
- 定义稳定的 `Bundle`、可变的 `BundleDraft`、不可变的 `BundleVersion` 和固定成员快照 `BundleMember`。
- `BundleVersion` 至少记录 `bundleID`、版本号、manifest 版本、OKF 目标版本、成员 revision、导出路径、内容摘要和生命周期状态。
- 已冻结或已发布的 BundleVersion 不得随 Workspace 后续编辑发生隐式变化；更新只能创建新的 BundleVersion。

OKF 与构建契约：

- 定义版本化 `OKFAdapter`：`import`、`export`、`validate`、内部链接重写和未知 frontmatter 保留。
- 内部 UUID 与 OKF 路径身份分离；`BundleMember.exportPath` 只在某个 BundleVersion 中固定映射。
- 生成的 `index.md`、`log.md` 和 YAML frontmatter 是构建产物，不形成第二个可写业务事实来源。
- 定义 Experty Artifact 外层 manifest；纯 OKF 内容位于独立目录，交易、作者、许可、依赖和内容摘要等平台字段不污染 OKF 的标准兼容层。
- 构建过程必须确定性：相同成员 revision、构建器版本和规范版本产生相同的知识内容与 `contentDigest`。
- 为未来签名预留 `ArtifactSigner` / `SignatureVerifier` 接口，本阶段只生成内容哈希，不建设证书或远端签名服务。

权利、隐私与发布策略基线：

- Workspace 内容默认 `private`；只有被明确加入 BundleVersion 的 revision 才允许进入构建产物。
- 定义最小 `PublicationPolicy`：发布可见性、ownership basis、商业使用状态、署名要求、验证状态和敏感等级。
- 构建前验证器至少检查私密内容、AI 对话、设备本地路径、凭据、Linked 文件可分发性、缺失来源、未知商业使用权和不可解析内部链接。
- AI 对话、API Key、OAuth Token、security-scoped bookmark、本地绝对路径和诊断内容永远不能因引用关系被自动打包。
- Phase 0 只建立字段、策略接口、失败类型和 fixture；身份认证、版权审核、投诉和下架流程属于 Experty 后续阶段。

发布集成与效果归因基线：

- Sync Outbox 只负责设备数据一致性；另定义版本化 Integration Event Envelope 和 Integration Outbox，避免同步协议与 Experty 业务事件耦合。
- 事件信封预留 `BundleBuilt`、`BundlePublished`、`BundleInstalled`、`BundleInvoked`、`OutcomeRecorded` 和 `BundleDeprecated`，并包含稳定 `eventID`、schema version、actor、发生时间与幂等键。
- `AgentRun.contextManifest` 必须能够记录实际加载的 `BundleID`、`BundleVersionID`、`ConceptID` 和 `ConceptRevisionID`，为未来调用归因和效果评估提供事实。
- 本阶段不发送真实 Experty 事件、不采集效果遥测，只验证序列化、版本演进、隐私过滤和重复消费的幂等性。

最小架构切片：

```text
导入一份来源
    → 创建 SourceRecord
    → 创建 KnowledgeConcept 与 derivedFrom / citation
    → 加入 BundleDraft
    → 冻结 BundleVersion
    → 确定性导出 OKF Artifact
    → 校验、重新导入并验证身份、引用与内容摘要
```

新增退出标准：

- Concept 的内部 UUID 在重命名、移动和改变 OKF 导出路径后保持不变。
- 一条 Bundle 内容可以反向追踪到确切 ConceptRevision、来源和 Actor。
- BundleVersion 固定引用确切 revision，冻结后的内容不受后续编辑影响。
- 两次使用相同输入和构建器版本构建，产生相同的知识文件内容和 `contentDigest`。
- 能导出并重新导入一个符合目标 OKF 版本的最小 Bundle，未知 frontmatter 不丢失。
- 发布验证器能够阻止私密内容、设备凭据、未授权 Linked 文件和未明确加入的 revision 泄漏。
- Integration Event 可版本化序列化；重复消费相同 `eventID` 不会重复发布或重复计量。
- AgentRun fixture 能准确指出调用了哪个 Bundle、BundleVersion 和 ConceptRevision。
- schema 和迁移 fixture 覆盖 Actor、Source、Concept、Bundle 及其不可变版本关系。

本阶段明确延后：

- Experty Store、在线 Registry、支付、结算、退款与定价
- 创作者实名认证、版权人工审核、投诉与下架
- 正式数字签名服务、许可证执行与 Bundle DRM
- 推荐、评价、Outcome Dashboard 和真实调用遥测
- Bundle 自动依赖解析、组合运行时与跨组织协作发布

### Phase 0C：Output Mainline 与 Contribution / Review / Merge 契约（1–2 周）

状态：2026-07-23 工程纵向切片完成；Output、Contribution、Review 与 Merge 的产品 UI 尚未接入。

目标：把“工作草稿 → 提交贡献 → 自动检查 → 用户与 AI 复核 → 合并到主产出”固化为与 AI、Experty 和 UI 无关的通用领域能力。AI 以后只是 Contribution 作者或 Reviewer 的一种 Actor，不能拥有绕过该流程直接修改主产出的专用写入路径。

产品不变量：

- `Document` 是可编辑内容；`Output` 是有目的、受众、结构和当前主版本的正式产出，两者不能合并为同一个概念。
- Source 和 KnowledgeConcept 不会因为被 AI 读取或总结就自动进入主产出。
- Contribution 只能基于一个确定的 OutputRevision 工作，不能直接修改 `Output.currentRevisionID`。
- 提交复核生成不可变 ChangeSet；继续修改后必须产生新的提交序号，不能覆盖已审查的 ChangeSet。
- Approval、Validation 和 Merge 都绑定确切的 ChangeSet 与 snapshot；内容变化后旧 Approval 自动失效。
- 合并到 Output Mainline 仍然是私人 Workspace 操作，不等于冻结 BundleVersion，更不等于发布到 Experty。

领域契约：

- 定义稳定的 `Output`、不可变 `OutputRevision` 与 `OutputRevisionMember`；一次 OutputRevision 是 Document、KnowledgeConcept 和 Asset 的确定 revision 组成的结构快照。
- 定义 `Contribution`，至少记录 `outputID`、`baseOutputRevisionID`、意图、Actor、状态和时间。
- 固化 Contribution 状态机：`draft → submitted → reviewing → changesRequested | approved → merged | closed`；不允许从 draft 直接进入 merged。
- 定义不可变 `ChangeSet`，记录提交序号、base revision、proposed snapshot、提交 Actor 和提交时间。
- 定义 `Review` / `ReviewFinding`；Reviewer 可以是 human、AI 或 deterministic validator，但 Phase 0 只有 human Actor 可以产生最终 Approval。
- 定义 `ValidationRun` / `ValidationResult`，每条规则拥有稳定 `ruleID`、`ruleVersion` 和 `severity: info | warning | blocking`。
- 定义 `MergeRecord`，完整记录 `mainBeforeRevisionID`、`contributionHeadRevisionID`、`mainAfterRevisionID`、Approval、Actor 与 `operationID`。

Diff 与 Validation：

- 业务事实是 base snapshot 与 proposed snapshot；内容 Diff、结构 Diff 和语义摘要属于可重建结果，不能成为恢复主产出的唯一来源。
- Phase 0 只实现确定性 Diff：成员新增、删除、移动、revision 变化、引用变化和最小 Markdown 内容变化；AI 语义 Diff 延后到 Phase 3。
- Phase 0 首批确定性检查：结构可解析、成员 revision 存在、内部引用有效、来源存在、无设备绝对路径或凭据、无隐式私人内容、Linked 文件满足分发策略、无未解决主版本冲突。
- Validator 结果只有在绑定 `ruleVersion`、ChangeSet 和目标 snapshot 后才能作为 Approval 或发布审计依据。

命令与事务边界：

- 至少定义 `CreateOutput`、`CreateContribution`、`SubmitChangeSet`、`RecordReview`、`RequestChanges`、`ApproveChangeSet`、`MergeContribution` 和 `CloseContribution` Typed Commands。
- `MergeContribution` 必须携带 `expectedMainRevisionID`、Approval 和 `operationID`，并在一个事务中创建新 OutputRevision、更新 Mainline、写入 MergeRecord、更新 Contribution 状态以及提交 Sync / Integration Outbox。
- 重放同一 `operationID` 返回已持久化结果；不同意图复用同一 ID 必须失败关闭。
- 当当前 Mainline 已不同于 Contribution 的 base / expected revision 时，必须返回显式冲突，重新计算 Diff 并再次提交复核，禁止静默覆盖。
- 文件内容与数据库事实跨边界写入继续使用 operation journal；中断恢复不能留下“主版本已变化但 MergeRecord 不存在”的半完成状态。

数据分类：

- synced fact：Output、OutputRevision、OutputRevisionMember、Contribution、已保存草稿、ChangeSet、用于决策的 ValidationRun / Result、Review、Approval、MergeRecord。
- local-only fact：编辑器未保存输入、选区、窗口状态、设备权限、临时 AI 流式内容。
- rebuildable cache：内容 Diff、结构 Diff 预览、未作为 Review 事实保存的 AI 语义建议和渲染缓存。

最小架构切片：

```text
创建 Output Main Revision 1
    → 创建基于 Revision 1 的 Contribution
    → 修改一个 KnowledgeConcept revision
    → 提交不可变 ChangeSet
    → 运行确定性 Validation
    → 记录用户 Approval
    → 执行 MergeContribution
    → 原子生成 Main Revision 2、MergeRecord 与 Outbox
```

并发切片：

```text
Contribution A 与 B 都基于 Main Revision 1
    → A 先合并为 Revision 2
    → B 尝试按 Revision 1 合并
    → 返回显式 revision conflict
    → Revision 2 保持不变，B 不产生部分 MergeRecord
```

新增退出标准：

- Contribution 和 AI 不能直接修改 Mainline。
- ChangeSet 提交后不可覆盖，重新提交产生新的 sequence。
- Approval 只对确切 snapshot 有效，内容变化后不能继续用于合并。
- blocking Validation 未解决时 `MergeContribution` 必须失败关闭。
- 合并事务中断时，OutputRevision、Mainline、MergeRecord、状态和 Outbox 一起回滚或可恢复。
- 重放同一 Merge `operationID` 只产生一个 mainAfterRevision。
- stale `expectedMainRevisionID` 不能覆盖新主版本。
- MergeRecord 能反向追踪合并前、贡献和合并后三个确定 revision。
- BundleVersion 只能引用确定的 OutputRevision / ConceptRevision，不能引用“当前最新内容”。
- 整个 Contribution / Review / Merge 切片在无 AI、无 Experty、无网络时通过测试。

本阶段明确延后：

- Git 仓库、Git 命令和完整分支 DAG
- 多人 Reviewer 分配、评论线程、@mention 和 Web PR 页面
- AI 自动批准、AI 自动语义合并和无人值守发布
- CRDT、实时协作和复杂 rebase UI
- Experty 在线审核、自动上架和远端合并

## Phase 1：工作空间、逻辑文件树与 Markdown（4–6 周）

目标：不依赖 AI 就已是可靠的本地工作工具。

- Managed / Linked 两种导入
- Security-scoped Bookmark 生命周期
- Node 逻辑树、拖拽排序、重命名、软删除与恢复
- Markdown 编辑、原子保存、immutable revision、内容哈希、撤销/恢复
- 引用与反向链接的最小语法
- 外部文件移动、离线、权限失效的 UI 状态

退出标准：

- 导入中强制退出不会产生半文件或幽灵节点。
- 外部重命名、移动、磁盘离线后能正确显示并重新绑定。
- AI 尚未接入时，所有数据仍可完整导出和恢复。
- 10 万个测试节点可以惰性浏览，不一次加载整棵树。

## Phase 2：预览、媒体与搜索（3–5 周）

目标：让工作空间真正可找、可看。

- Quick Look 缩略图和通用预览
- PDFKit / AVFoundation 的必要增强
- 异步元数据提取与缓存预算
- FTS5 索引、重建、增量更新
- 文件名、正文、标签、时间筛选统一搜索
- 中文搜索质量基准与 tokenizer 技术验证

退出标准：

- 删除全部缓存后能够后台重建，业务内容不受影响。
- 索引失败不阻塞编辑，重试不会产生重复记录。
- 大文件和 iCloud 占位文件不会在滚动时触发主线程阻塞。

## Phase 3：AI 共创与受控 Agent（4–6 周）

目标：AI 建立在稳定数据层和 Contribution / Review / Merge 流程之上，并且所有输入、建议、修改与调用可审计。

- 可替换的 Model Provider 与模型能力声明
- Context Builder：当前项、显式引用、检索结果、预算
- 流式对话、取消、重试、错误恢复
- 结构化 Conversation / Message / MessagePart；AI 对话从第一天就是可同步的 Workspace 业务事实
- Typed Tools 与 Policy Engine
- AI 创建或修改 Contribution，通过 ChangeSet 提交提案；复用 Phase 0C 的 Diff、Validation、Review、Approval 与 Merge，不建立 Agent 专用写入通道
- AI 语义 Review：重复、矛盾、证据缺失、适用边界、目标偏离和未经确认推断
- AgentRun、ToolCall、operation journal
- Prompt Injection 与权限回归测试集

首批工具只包含：

- 读取选中内容
- 搜索当前 Workspace
- 创建 Markdown 或 KnowledgeConcept 草稿
- 创建 Contribution 草稿
- 向 ChangeSet 提议结构化修改
- 提交 ReviewFinding；不能产生 human Approval
- 创建任务草稿

退出标准：

- 模型无法通过文本内容绕过工具权限。
- 所有写操作都能定位到一次用户授权和一次应用 Command。
- AI 不能批准自己的 ChangeSet、不能直接更新 Output Mainline、不能冻结 BundleVersion 或发布到 Experty。
- 网络中断、限流和模型不可用不影响本地编辑。
- 用户可以同时检查内容 Diff、结构 Diff、来源变化和 AI ReviewFinding，并恢复修改前 revision。

## Phase 4：本地 Bundle Studio（4–6 周）

目标：用户在不注册、不连接 Experty 的情况下，也能把已有 Source、KnowledgeConcept 和 OutputRevision 转化为可验证、可携带的 OKF Bundle。

- 从文件夹、标签、项目、时间范围、OutputRevision 或手动选择范围创建 BundleDraft
- 资料清单、主题聚类、重复与矛盾发现、来源覆盖和隐私预检查
- Bundle 目标定义：目标用户、目标任务、使用场景、禁止场景和成功 Rubric
- 最小 Concept 模板：Principle、Framework、Decision Rule、Playbook、Case Study、Anti-pattern、Boundary、Rubric、Reference
- AI 访谈补全隐性判断、冲突取舍、反例、适用边界和完成标准
- Bundle Composer：把已确认 Concept 组织成明确结构，而不是直接把文件夹打包
- OKF Adapter：导入、导出、链接重写、未知 frontmatter 保留和版本兼容
- Publishability Validator：来源、权利、隐私、凭据、Linked 文件、边界、案例和 Rubric
- Bundle Test Lab：在本地安装候选版本，用固定任务和 Rubric 对照验证
- 确定性构建 Experty Artifact：外层 manifest、纯 OKF 目录、可选 assets、validation / benchmark report
- 冻结 immutable BundleVersion；后续编辑只能创建新版本

退出标准：

- 用户可以把一组非结构化资料转化为来源可追踪的 BundleDraft。
- 同一组成员 revision、Adapter 版本和构建器版本产生相同知识内容与 `contentDigest`。
- 发布候选不包含未明确加入的私人内容、设备路径、凭据或无分发权限的 Linked 文件。
- OKF 导入后再导出不会丢失未知 frontmatter，内部 UUID 不因导出路径变化而改变。
- BundleVersion 固定引用确切 OutputRevision / ConceptRevision，Workspace 后续编辑不会改变冻结产物。
- 没有 Experty 账号和网络时，用户仍能导出 OKF、ZIP 或本地 Artifact 并完成 Test Lab。

## Phase 5：Experty Creator Bridge（3–5 周）

目标：在保持 Verso 本地优先和用户数据所有权的前提下，把已验证 BundleVersion 明确地交付给 Experty 发布、交易和分发。

- 本地 CreatorProfile 与 Experty Account 显式绑定；账号不是内部内容身份
- 选择一个已冻结且通过发布门槛的 BundleVersion
- 上传确定 Artifact，不上传整个 Workspace、活动 SQLite、私人 Source 或未入包对话
- 商品元数据：标题、描述、适用任务、作者、许可、价格、版本说明和验证报告
- Experty 返回上传、审核、发布、拒绝、下架和版本采用状态
- 更新发布必须展示 BundleVersion Diff、重新运行 Validator / Test Lab，并创建新版本
- Integration Outbox 负责可重试交付，Sync Outbox 仍只负责设备一致性
- 本地保留上传 Artifact、内容摘要、Experty listing reference 和发布审计

退出标准：

- Experty 不可用、拒绝发布或上传中断时，Verso 本地 Workspace 和 BundleVersion 不受影响。
- 重试同一 publish `eventID` 不会产生重复 listing 或重复版本。
- Experty 只能访问用户明确选择的 Artifact，不能读取 Workspace 数据库或任意文件。
- 已发布版本与本地内容摘要一致；上传后本地继续编辑不会静默改变线上版本。
- 用户可以导出并带走纯 OKF Bundle，不被 Experty 账号或交易状态锁定。

## Phase 6：时间管理（3–5 周）

目标：先建立清晰的任务与时间语义，再连接系统日历。

- Task、TimeBlock、时区、全天与重复规则
- 日/周 Timeline 与拖拽排期
- EventKit 权限与只读聚合
- 显式导出到日历
- Agent 仅可创建日程 proposal

退出标准：

- 夏令时切换、跨时区、全天事件和重复事件测试通过。
- 拒绝日历权限时，应用内任务和排期仍完整可用。
- 外部事件丢失或 ID 改变不会删除内部 Task。

## Phase 7：上线准备

- 威胁建模、隐私清单、数据保留设置
- Accessibility、键盘操作、VoiceOver、Reduce Motion
- 真实大型工作空间性能测试与内存预算
- 更新失败、回滚、备份恢复演练
- 崩溃与诊断流程、用户支持工具
- 公证、签名、自动更新或 Mac App Store 分发决策

## Experty 后续：Bundle Runtime 与 Outcome 网络

这些能力属于 Experty 与 Verso 连接后的后续阶段，不作为 Verso 首个可用版本的阻塞项：

- 在 Verso 或其他 Agent 中安装、更新、停用和组合 Bundle
- Context Builder 记录实际加载的 BundleVersion 与 ConceptRevision
- 用户授权下记录任务、成本、质量、速度和结果变化
- Bundle 调用归因、版本采用率、回滚和兼容性
- Creator Outcome Dashboard、推荐、定价反馈和收益
- Runtime / SDK、Private Registry、团队许可和企业治理

## 同步兼容基线与实施顺序

同步协议现在进入底层设计，但真实远端同步仍在核心离线版本达到上述门槛后实施。这样可以避免 Phase 1 的文件模型和 Phase 3 的 AI 对话模型在加入多设备能力时返工，同时不提前扩大运行时故障面。

架构决策：

- 每台设备维护独立的本地 SQLite Workspace 副本；禁止把正在使用的 SQLite、WAL 或 journal 文件直接放入 iCloud Drive、第三方云盘或 NAS 供多设备共同打开。
- 本地 Command 在事务中同时提交业务事实与 Sync Outbox；远端变更必须通过幂等的 `ApplyRemoteChangeCommand` 进入本地数据层。
- 默认托管同步采用 CloudKit / CKSyncEngine：同一 Apple ID 使用 private database，不同用户共享使用 CKShare / shared database。
- macOS 与未来 iOS / iPadOS 客户端共享同一 CloudKit container、WorkspaceID、record zone、同步协议版本和冲突规则，但每台设备仍拥有独立的本地 SQLite 副本。
- `VersoDomain`、`VersoApplication` 与未来 `VersoSyncProtocol` 保持 Apple 平台通用，不导入 AppKit 或 UIKit；文件选择、权限、后台调度和界面由各平台 adapter 实现。
- iCloud Drive、第三方云盘和 NAS 采用统一的便携 Folder Transport，只传输版本化 change batch、tombstone、manifest 和不可变 Blob。
- iOS / iPadOS 通过 `UIDocumentPickerViewController` 选择 iCloud Drive、第三方 File Provider 或 Files 中已挂载的 NAS 目录，并在本机保存 security-scoped bookmark；该 bookmark 仍是设备本地权限，不参与同步。
- iOS 后台通知只作为“存在远端变更”的提示，不能作为可靠事件流。客户端必须在启动、回到前台、打开 Workspace 和用户主动刷新时按 change token 补拉，并把后台同步设计为可中断、可重入和幂等。
- iOS 上的大型 `CKAsset`、Folder Transport Blob 和媒体文件按需下载；文件尚未本地化时，文件树只显示可用性与下载状态，预览和 AI Context Builder 不得阻塞主线程等待下载。
- Managed 文件使用内容哈希与 immutable revision；Markdown 并发修改先采用 revision 分支和显式冲突，不提前引入 CRDT。
- Conversation、Message、AgentRun、ToolCall、Approval 和影响后续行为的 AI 记忆属于 synced fact。
- FTS、Embedding、缩略图、媒体缓存和模型缓存属于 rebuildable cache，不同步并可在各设备重建。
- security-scoped bookmark、设备本地绝对路径、API Key、OAuth Token、临时流式 buffer、Job lease 和本机执行状态属于 local-only fact，永远不进入同步协议。
- 正在运行的 Agent 不在设备间直接迁移；首版只同步已确认消息、运行状态、审计记录和最终领域变更。未来如需接管，必须增加执行租约、幂等工具调用和重新授权规则。
- iOS Agent 运行不能假设 App 可持续驻留后台。进入后台前应提交已确认消息和 checkpoint；系统终止后从最后一次 durable checkpoint 恢复，外部副作用工具不得自动重放。

推荐实施顺序：

1. 本地 Workspace、revision、备份和恢复达到退出标准。
2. 完成同步协议版本、数据分类、冲突矩阵、设备身份和双副本故障测试。
3. 在 macOS 实现 CloudKit 同 Apple ID 多设备同步。
4. 建立 iOS / iPadOS 本地副本、前后台恢复和按需资源下载，并接入同一 CloudKit Workspace。
5. 实现 CKShare 跨 Apple 设备和不同用户共享。
6. 在 macOS 实现 iCloud Drive / 通用云盘 Folder Transport，再用同一协议接入 iOS Document Picker。
7. 实现 NAS、离线队列、压缩与高级恢复工具；iOS 仅在 Files 可见且用户已授权目录时启用 NAS transport。
8. 只有真实需求证明必要时，再评估实时协作与 CRDT。

File Provider、插件、多 Agent 自主协作和实时协作仍明确延后。它们分别需要新的 Finder 暴露、代码执行、权限、冲突和恢复模型，不能作为普通 Feature 插入现有代码。

## 第一个工程里程碑的任务顺序

1. 确认产品假设：macOS 15+、本地优先、默认 Managed 导入、Markdown proposal-first；未来 iOS / iPadOS 客户端共享同步协议而不共享数据库文件，最低系统版本在建立移动端 target 时按 CKSyncEngine 与产品覆盖范围单独锁定。
2. 保持已经发布的 schema v1 与 v2 migration 不可修改；所有新增领域结构使用新 migration，并为每个新版本追加迁移 fixture。
3. 创建工程骨架和依赖检查。
4. 实现空 Workspace 的创建、打开、备份和恢复。
5. 实现一个端到端切片：创建文件夹 → 新建 Markdown → 原子保存 → 搜索 → 重启恢复。
6. 固化新的 ADR 与数据模型：Verso / Experty 边界、OKF Adapter、知识血缘、Bundle 不可变版本、Output Mainline、Contribution / Review / Merge 和 Integration Event。
7. 实现 Phase 0B 最小架构切片：来源 → Concept → BundleDraft → BundleVersion → OKF 导出、校验与重新导入。
8. 实现 Phase 0C 最小架构切片：Output Revision 1 → Contribution → ChangeSet → Validation → Approval → 原子 Merge → Output Revision 2。
9. 增加并发与故障切片：两个 Contribution 基于同一 revision；先合并者成功，后合并者显式冲突，事务终止和重复 `operationID` 均不产生部分结果。
10. 再开始制作完整 Sidebar、Editor 和 Preview 视觉体验。

这些端到端切片比先完成全部页面更重要：它们会尽早验证本地数据边界、并发与恢复能力，知识血缘、主产出治理、不可变发布版本和 Verso / Experty 交换契约是否真的成立。
