# Verso 产品能力更新日志

这份日志用于判断“用户现在实际获得了什么、底层已经走到哪里、下一步产品节奏是否合理”。它不是提交记录，也不把计划中的能力写成已完成能力。

## 更新规则

- 每次版本或功能批次更新后，在本文件顶部追加一条，最新内容在最前。
- 每条必须回答：当前版本具备哪些能力、哪些能力不在表层 UI、需要注意什么。
- 明确区分“用户可操作”“后台已接线”“仅有代码骨架”“尚未实现”。
- 写出本次验证结果、已知限制和当前阶段，不能只罗列代码模块。
- 未通过测试、没有接入 App 运行流程或没有 UI 入口的能力，不得描述为用户已获得。

---

## 2026-07-23｜Phase 0B/0C 知识资产与 Output Mainline 工程闭环

状态：底层纵向切片已完成并通过本地验证；没有新增表层 UI，等待产品检查后再决定交互节奏。

### 当前版本具备哪些能力？

#### 用户可以直接操作

- 本批次不新增 App 中可见、可点击的能力。现有 Workspace 创建/打开/切换/关闭、文件夹导入、Markdown 编辑和只读恢复界面保持不变。

#### App 核心现在能够执行，但尚未接入界面

- 建立与登录账号、设备和模型名称解耦的 Actor；捕获 SourceRecord，并把来源、Document Revision、KnowledgeConcept Revision 和发布策略连接为可反向追踪的事实。
- 创建 Bundle Draft，冻结引用确切 revision 的不可变 BundleVersion；冻结时校验文件哈希、私密/敏感策略和导出路径。
- 确定性生成最小 Experty/OKF Artifact：外层 manifest、`okf/`、`assets/` 与 validation/benchmark reports；可校验、重新导入、保留 UUID、相对链接和未知 frontmatter。
- 创建 Output Main Revision、基于确切 main revision 的 Contribution、不可变 ChangeSet、确定性 Diff/Validation、Review/Finding 和人工 Approval。
- 原子 Merge：一次事务共同生成新 Main Revision、完整成员快照、MergeRecord、Contribution 状态、applied operation、Sync Outbox 与 Integration Outbox。
- 相同 operation 重放不会产生重复 BundleVersion 或 main revision；不同意图复用 ID 会失败；并发 Contribution 使用过期 main revision 会明确冲突。
- schema 已追加 v3 knowledge assets 与 v4 output mainline，v1/v2/v3/v4 fixture 均可迁移到当前版本并保留迁移前备份。

### 哪些能力不在用户可以感知或控制到的表层 UI？

| 能力 | 当前状态 |
|---|---|
| Actor / Source / Concept 管理 | Command、事务和测试已完成，无列表或编辑界面 |
| Bundle Draft / Freeze | 核心闭环已完成，无 Bundle Studio、导出目录或 ZIP 入口 |
| OKF 导入/导出/校验 | 纯格式模块已完成，无文件选择和结果报告界面 |
| Output / Contribution / Review / Merge | 状态机、命令、校验和原子事务已完成，无工作流界面 |
| Diff | 确定性成员、revision、rank、引用、provenance 与 Markdown 行 Diff 已完成，无预览 |
| Sync Outbox | 新正式事实已分类并写入，但仍无真实 transport 或消费者 |
| Integration Outbox | `BundleBuilt` / `OutputMerged` 只在本地持久化，不发送 Experty 或遥测 |
| 新诊断操作 | Bundle Build、Output Validation、Output Merge 已接入 trace，无诊断 UI |

### 哪些内容需要注意？

1. 这些是后续产品功能的安全底座，不代表用户现在可以在 App 中创建 Concept、Bundle 或 Contribution。
2. Artifact 的确切路径、字节和逐文件哈希会随 BundleVersion 一并冻结；之后源 Markdown 改动或 App 重启都不会改变该版本。当前还没有“导出到 Finder”、ZIP 归档、签名、发布或 Experty 上传入口。
3. `PublicationPolicy` 是本地技术门禁，不是版权认证、法律审核或 DRM。
4. Sync Outbox 仍不等于多设备同步。两台 Mac 继续只通过 Git 同步源码，不要并发打开同一个云盘 Workspace。
5. Integration Outbox 没有网络消费者；不会发送正文、路径、凭据或调用遥测。
6. 当前 Output 只允许引用已登记的 Document/Concept revision；Asset revision 的正式持久化写入链仍属于后续文件模型工作。
7. Contribution 流程目前要求人工 Actor 批准；AI review 可以评论或请求修改，不能批准或自动合并。

### 验证与节奏信号

- Source → Concept → BundleVersion → OKF export/validate/import 端到端测试通过。
- Output Revision 1 → Contribution → ChangeSet → Validation → human Approval → Main Revision 2 端到端测试通过。
- stale mainline、blocking finding、AI approval、operation fingerprint、幂等重放、事务回滚/重试和重启恢复测试通过。
- v1 active、v1 closed、v2 synced、v3 knowledge assets、v4 output mainline 五类 fixture 迁移通过。
- VersoCore 共 44 项测试（11 个测试套件）通过；App 共 6 项测试通过；macOS Debug 与 Release 构建通过。
- 新模块依赖边界没有引入网络、Experty、CloudKit、UI 或新的第三方依赖。
- 双机协作仍以 Git 同步源码：另一台 macOS 26 稳定版 Mac 拉取后需要运行同一组工程格式、依赖、Core、App、Debug 与 Release 检查；Workspace bookmark、签名和 DerivedData 不随 Git 同步。
- 产品节奏建议：下一步先做最小只读/手动操作 UI，让用户能看见 Source、Concept、Output 和 Contribution 流程；在此之前不应进入 Experty、AI 自动合并或真实同步。

## 2026-07-22｜Xcode 26 双机开发兼容修复

状态：工程兼容修复已通过本地 Xcode 26.6 和远端 Xcode 26.5 CI，等待第二台 Mac 验证。

### 当前版本具备哪些能力？

- 本次不新增用户功能；Workspace、导入、编辑和恢复能力保持不变。
- 工程文件格式固定为 Xcode 26.5 可读取的版本，支持在当前 Xcode 26.6 开发机、GitHub Xcode 26.5 runner 和另一台 macOS 26 稳定版开发机之间通过 Git 协作。

### 哪些能力不在用户可以感知或控制到的表层 UI？

- CI 和本地脚本会阻止误将工程升级为稳定 Xcode 26 无法读取的格式，并检查 App 与单元测试 scheme 已共享给其他设备。
- security-scoped bookmark 仍是每台 Mac 独立保存的本地授权，不会随 Git 或未来的 Workspace 内容同步传播。

### 哪些内容需要注意？

1. 源码可以通过 Git 在两台 Mac 间同步；`xcuserdata`、DerivedData、签名设置和安全作用域书签不能同步。
2. Phase 0 尚无真实多设备 Workspace 同步。不要在两台 Mac 上同时打开同一份云盘 Workspace，否则 `.verso` 数据库和 WAL 没有跨设备冲突保护。
3. 在 Xcode 27 打开工程时，不要接受会提升 project format 的自动修改；提交前运行 `bash Scripts/check_project_format.sh`。

### 验证与节奏信号

- Xcode 26.6 本地 Debug、Release 构建通过。
- VersoCore 28 项测试与 App 6 项单元测试通过。
- 工程格式和 shared scheme 守卫检查通过。
- GitHub Xcode 26.5 CI 的 Debug、Release、VersoCore 与 App 单元测试全部通过。
- 第二台 Mac 首次拉取后，应运行同一组检查，确认其具体 Xcode build version。

## 2026-07-22｜Phase 0 同步兼容基线

状态：本地功能完成，等待人工验收；尚未提交或运行远端 CI。

### 当前版本具备哪些能力？

#### 用户可以直接操作

- 创建 Workspace：用户选择的文件夹本身成为 Workspace，不创建同名子文件夹。
- 打开、切换、关闭和重新打开最近的 Workspace。
- 忘记 Workspace：移除访问书签，不删除文件或 `.verso`。
- 将整个 Workspace 文件夹移到废纸篓，并在执行前明确提示影响范围。
- 浏览实际磁盘文件树、展开目录、选择文件并在 Finder 中显示。
- 新建 Markdown 文档。
- 导入多个文件或整个文件夹；同名目标自动添加编号。
- 编辑 UTF-8 Markdown，通过保存按钮或 `Command-S` 原子保存。
- 使用 Quick Look 预览系统支持的 PDF、图片、音视频和其他文件。
- 数据库异常时进入只读恢复界面：浏览原始文件、查看错误和备份、从备份恢复数据库。

#### App 已经自动执行

- App Sandbox 与 security-scoped bookmark；保存最近一个 Workspace 的访问授权。
- 使用隐藏 `.verso/` 目录存放数据库、备份和恢复材料。
- SQLite/GRDB、WAL、外键约束、轻量完整性检查和 schema v1 → v2 迁移。
- 确有待执行迁移时创建迁移前数据库备份。
- Markdown 临时文件、operation journal、同步落盘和原子替换。
- Workspace 创建时生成稳定身份、revision、`OperationID` 与 Sync Outbox。
- 同一 `OperationID` 的幂等重放保护，以及过期 revision 的冲突保护。
- 本机稳定 `DeviceID`、结构化日志、错误分类和性能 signpost。
- 普通备份的容量预检、最多保留 10 份，以及恢复前保护当前数据库。

### 哪些能力不在用户可以感知或控制到的表层 UI？

#### 已实现，但没有 UI 入口

| 能力 | 当前状态 |
|---|---|
| 手动创建数据库备份 | 服务已实现，没有“立即备份”按钮 |
| Workspace 重命名 | Command、revision 和事务已实现，没有重命名入口 |
| 诊断包导出 | 导出器已实现，没有导出界面 |
| Sync Outbox 查看 | 创建和重命名会写入，用户不可查看 |
| 数据分类策略 | synced/local-only/cache 已固化在代码和测试中，没有设置页 |
| revision / tombstone | 模型已建立，没有历史版本、冲突或回收站 UI |
| 备份保留与空间策略 | 后台执行，没有备份管理界面 |

#### 只有骨架，尚未进入 App 运行闭环

- 没有 CloudKit、iCloud Drive、NAS 或其他真实远端同步；`SyncTransport` 目前只是 provider-neutral 接口。
- Sync Outbox 没有消费者，不会上传或拉取数据。
- 后台 Job Runner 已实现，但 App 没有启动持续消费循环。
- 中断写入恢复器已实现并测试，但尚未在 App 启动时自动调用。
- 没有周期性普通备份；新 Workspace 不保证已经存在可恢复备份。
- Markdown 保存和文件导入尚未形成 Document/Revision 业务事实，也没有进入 Sync Outbox。
- Node 数据模型只有根节点基线；当前 Sidebar 直接读取磁盘目录，不是逻辑文件树。
- 没有搜索、标签、引用、任务、AI、日历或真实多设备能力。

### 哪些内容需要注意？

1. **所选文件夹就是 Workspace。** `.verso` 会写入其中；“移到废纸篓”会移动整个文件夹，包括成为 Workspace 前已有的文件。验收时建议使用专门目录。
2. **不要手动删除 `.verso`。** 这会同时删除数据库、内部恢复材料和其中的备份。原始文件仍在，但 Verso 元数据和身份可能无法恢复。
3. **Markdown 目前必须手动保存。** 没有自动保存，也没有切换文件、切换 Workspace 或关闭前的未保存提示，未保存编辑可能丢失。
4. **数据库恢复不等于文件恢复。** 当前备份主要保护 `workspace.sqlite`，不会回滚已经修改、覆盖或删除的 Markdown、图片和其他原始文件。
5. **导入是复制，不是 Linked。** 没有 Managed/Linked 选择、导入进度、取消或完整的中断恢复流程。
6. **文件树仍有原型限制。** 最多读取 10,000 个节点和 32 层目录；隐藏文件不显示；外部变化需要手动重新载入。
7. **当前只保存一个最近 Workspace。** 没有全局 Workspace catalog 或最近项目列表。
8. **同步基线不等于内容已经同步。** 当前验证的是身份、幂等、revision、数据分类和事务边界。

### 验证与节奏信号

- VersoCore：28 个测试通过。
- App：6 个单元测试通过。
- schema v1 active、v1 closed、v2 synced 三份 fixture 通过。
- Debug 与 Release 构建通过。
- 依赖边界、entitlements 和 diff 格式检查通过。
- 当前阶段判断：Phase 0 的底层边界已建立；用户已能完成最小本地文件工作流，但在进入完整 Phase 1 前，应优先处理启动写恢复接线、可用备份入口和未保存内容保护。
