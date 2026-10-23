# GameLingo Direct 3.5.1 — 性能重构记录

日期：2026-10-23。该记录仅描述已提交源码和可检查的结构，**没有宣称运行过 iOS 构建或 iPhone 性能测试**。

## 修改内容

- **PiP 主线程负载**：新建 `GamePiPFrameRenderer.swift`，用 CoreText + CoreGraphics 在串行后台队列排版文字、绘制像素，并通过 `CVPixelBufferPool` 重用 640×360 BGRA 帧内存。原 `FloatingSubtitleController` 主要维护字幕状态、PiP 系统接口和最终提交；不再在主线程用 `UIGraphicsImageRenderer` 绘制整帧。
- **最新帧优先**：待渲染帧只有一份，新内容会替换等待中的旧内容。完成后按 generation 检查，丢弃旧画面。视频接收端暂不可用时保留最新一帧，监听 `requestMediaDataWhenReady`，不无限入队。
- **首帧时序**：PiP 开启前先异步生成并成功提交首帧，再在短时间内尝试启动画中画，避免原同步绘制逻辑改为异步后空画面就开始 PiP。字幕页码与中文朗读仍保留。
- **减少无意义重绘**：SwiftUI 预览刷新不再强制生成新视频帧；CoreText 文本折行结果有 96 项上限缓存；普通页面按内容变更和翻页更新，未变化时仅约 3 秒发送一次保活画面。
- **实时对白优先**：多行字幕新文本直接显示最新分组，旧文字保留在历史供回看；不必等待上一组翻页完毕。
- **OCR 资源竞争**：底部 21% 精确补扫不再同步堵住实时 OCR。底部补扫与整屏菜单共享单条 utility 队列，避免两个昂贵 Vision 任务同时计算。全屏菜单在最近 1.6 秒有对白活动时让路，用户手动触发的扫描不受此规则限制。
- **按行缓存**：当新增或更正底部文字时，已经翻译的其他原文行先复用本机缓存，避免重新翻译整个多行文本。
- **主线程持久化**：历史记录的 UserDefaults JSON 写入合并为约 800ms 的延后保存；App 进入后台时主动刷新，降低每条字幕都编码 200 条历史记录的开销。
- **延迟统计**：采集回调到 OCR 开始的等待毫秒数、过期帧丢弃次数、OCR 处理耗时、翻译耗时、PiP 排版视频生成耗时、视频渲染器背压，以及采集回调到 PiP 成功入队的最近 60 秒 P50/P95。此指标**不是物理屏幕的最终呈现时间**。

## 构建配置

- 版本 **3.5.1 (Build 11)**，Codemagic 工作流 **`ios-direct-unsigned`**。
- `tools/build_xcodeproj.py` 在 iOS 单 App 目标增加 `GamePiPFrameRenderer.swift`。
- `codemagic.yaml` 在完整 Xcode 编译前独立运行 `xcrun swiftc -typecheck ios/GameLingoAI/GamePiPFrameRenderer.swift`，并把该文件纳入 Swift 语法预检查。
- `tools/verify_direct_release.py` 对新增渲染器、最新帧管理、OCR 调度和遥测指标设立静态断言。
- 仍然默认离线翻译、保留 TXT 词库与勇者斗恶龙一键词库，不增加 App Groups 或 ReplayKit 广播扩展。

## 风险与必须验收的项目

| 项目 | 当前状态 | 需要的实测 |
|---|---|---|
| CoreText 渲染器 iOS SDK 类型兼容 | 源码和 Codemagic 类型检查已加入，**尚未执行** | Codemagic Xcode 27.1 构建通过 |
| CoreText 中文与假名排版 | 按行居中绘制，有字体 fallback，但**未做真机截图对比** | 小 PiP / 大 PiP 字体、方向与标点检查 |
| PiP 启动首帧、背压与恢复 | 已添加等待首帧与可接收时提交逻辑，**未实测** | 连续多次启动/关闭、后台和游戏切换 |
| Vision 补扫与菜单性能 | 已隔离低优先级 OCR 队列，**耗时收益未量化** | 底部模式开/关分别玩 15–30 分钟 |
| 端到端延迟 | 仪表盘已提供采集到视频提交的统计 | 同一个游戏比较 3.5 与 3.5.1 的 P50/P95 |
| SideStore 更新安装 | 单 App 架构保留，未签名 IPA 仍由 Codemagic 生成 | 下载 IPA、SideStore 安装与迁移 |

**注意**：采集间隔不是端到端延迟。PiP 视频帧“已入队”也不等于系统保证用户已看到该帧，游戏保护、iOS 后台调度和画中画生命周期仍可能造成不连续。若构建失败，请保留 `compiler-errors-direct.txt` 或完整 `xcodebuild-direct.log`。
