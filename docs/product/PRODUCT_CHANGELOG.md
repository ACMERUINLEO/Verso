# Verso 产品能力更新日志

这份日志用于判断“用户现在实际获得了什么、底层已经走到哪里、下一步产品节奏是否合理”。它不是提交记录，也不把计划中的能力写成已完成能力。

## 更新规则

- 每次版本或功能批次更新后，在本文件顶部追加一条，最新内容在最前。
- 每条必须回答：当前版本具备哪些能力、哪些能力不在表层 UI、需要注意什么。
- 明确区分“用户可操作”“后台已接线”“仅有代码骨架”“尚未实现”。
- 写出本次验证结果、已知限制和当前阶段，不能只罗列代码模块。
- 未通过测试、没有接入 App 运行流程或没有 UI 入口的能力，不得描述为用户已获得。

---

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
