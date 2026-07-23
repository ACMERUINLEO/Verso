# ADR-0005：知识血缘、OKF Adapter 与不可变 BundleVersion

状态：Accepted
日期：2026-07-23

## 背景

Workspace 中可编辑的 Markdown、知识语义和可交换的 OKF 文件承担不同职责。若把文件路径当身份、让 OKF frontmatter 直接成为数据库事实，或在导出时动态读取“最新内容”，移动文件和后续编辑都会悄悄改变已冻结产物，也无法证明来源、作者和发布策略。

## 决策

- `Actor`、`SourceRecord`、`KnowledgeConcept`、Concept Revision、Reference 与 `PublicationPolicy` 使用稳定 UUID 和确切 revision 形成知识血缘。
- `Document` 继续表示可编辑内容；`KnowledgeConcept` 表示可复用语义，二者不能合并。
- `BundleDraft` 是可变工作聚合；`BundleVersion` 与 `BundleMember` 是冻结后的完整快照，只引用确切 revision。
- 内部 UUID 与 `exportPath` 分离。改变 OKF 路径不改变 Concept 身份。
- 新增纯 `VersoBundleFormat` 模块。它只依赖 Domain，负责确定性导入、导出、校验、相对链接改写、未知 frontmatter 保留和 SHA-256 内容摘要；它不访问数据库、文件权限、网络或 UI。
- Artifact 外层使用版本化 `expert-manifest.json`，OKF 位于 `okf/`，assets 与 validation/benchmark report 使用独立目录。相同输入必须生成相同文件和摘要。
- Freeze 将 Artifact 的确切路径、字节和逐文件哈希作为 BundleVersion 的不可变快照同事务保存；后续编辑或移动当前 Workspace 文件不会改变已冻结产物。
- `FreezeBundleVersion` 在一个事务中固化版本、成员、applied operation、Sync Outbox 与 `BundleBuilt` Integration Event；冻结前重新校验文件内容哈希和发布策略。

## 后果

- Workspace 后续编辑不会改变既有 BundleVersion 的成员身份和内容摘要。
- 导出文件可重新导入并保留 Concept/Revision UUID 与未知 frontmatter。
- 文件正文仍由文件系统拥有；数据库保存不可变 revision、哈希、血缘和构建事实。
- Phase 0 不实现 ZIP、数字签名、Experty 上传、许可证执行或远端 Registry。

## 未选择

- 将 OKF Markdown 或 YAML 作为 Workspace 唯一事实来源。
- 使用文件路径、标题或内容哈希代替稳定业务身份。
- 每次读取 Bundle 时动态解析 Concept 的当前 revision。
- 为 YAML 引入新的第三方依赖；当前受控子集足以覆盖 Phase 0 合规字段。

## 复审触发条件

OKF 规范升级要求完整 YAML 语义、正式签名或跨 Bundle 依赖解析时，新增 ADR 评估格式兼容、依赖许可证和迁移策略，不修改本 ADR。
