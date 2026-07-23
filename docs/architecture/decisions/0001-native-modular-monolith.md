# ADR-0001：原生 macOS 与模块化单体

状态：Accepted
日期：2026-07-22

## 背景

产品依赖文件权限、拖拽、Quick Look、媒体框架、系统日历、菜单和多窗口。团队初期较小，但项目预计长期维护。

## 决策

使用 Swift 6、SwiftUI 和必要的 AppKit，暂定最低 macOS 15。部署为单个 macOS App，通过 Domain、Application、Infrastructure 和 Feature 边界形成模块化单体。

## 后果

- 获得原生系统能力、性能、辅助功能和安全模型。
- Swift 6 严格并发降低数据竞争风险。
- 需要掌握 Swift/AppKit，部分编辑器能力可能通过隔离的 WKWebView 实现。
- 不引入进程间网络协议、微服务部署或跨平台抽象成本。

## 未选择

- Electron：前期编辑器生态更直接，但系统集成、资源占用和双运行时边界不符合当前优先级。
- 多服务架构：本地 App 没有独立部署需求，反而增加故障面。

## 复审触发条件

正式决定支持 Windows/Web，或某个安全敏感能力必须隔离到 XPC helper 时复审；不因普通 Feature 数量增加而复审。
