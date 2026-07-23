# Verso

Verso 是一款本地优先的 macOS 工作空间与 AI 共创应用。它把文件、Markdown、时间安排和 AI 操作组织在同一个可追溯的工作空间中。Prologue 仅作为项目早期代号，不是产品名称。

当前仓库处于架构基线阶段。先确定数据所有权、安全边界和模块依赖，再开始搭建界面与功能。

## 从这里开始

- [系统架构](docs/architecture/ARCHITECTURE.md)：技术边界、模块、数据流、可靠性与安全策略
- [核心数据模型](docs/architecture/DATA_MODEL.md)：Workspace、Node、Asset、Document、Task 等对象的关系
- [交付路线图](docs/product/ROADMAP.md)：从工程骨架到 Agent 的分阶段计划和验收标准
- [架构决策记录](docs/architecture/decisions/README.md)：长期保留“为什么这样做”

## 已锁定的基线

- 原生 macOS：Swift、SwiftUI，必要处使用 AppKit
- Swift 6 严格并发检查，最低系统暂定 macOS 15
- 模块化单体，而非微服务
- SQLite 是业务事实来源，通过 GRDB 访问；文件内容保留在文件系统
- 本地优先；同步、索引和向量数据均不得成为打开工作空间的前置条件
- 虚拟文件树是逻辑树，不等于 Finder 目录，也不在首版实现 File Provider
- 所有 AI 写操作必须经过应用命令层、权限策略和审计记录
- Markdown 原文是可携带的内容事实；编辑器只是可替换的呈现引擎

## 当前不做

首个可用版本不做云同步、多人协作、插件市场、真正的 File Provider、多 Agent 自主协作或独立向量数据库。这些能力的扩展点会被保留，但不会提前承担其运行复杂度。
