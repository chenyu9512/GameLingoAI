# GameLingoAI · Universal OCR 3.7.2

**当前分支：`feature/universal-ocr-ui-language` · v3.7.2 (Build 17) · 开发测试版**

> Vision + PaddleOCR 混合识别、多语言、离线翻译、满窗 PiP、首次启动预热。本版尚待 Codemagic Xcode 编译和 iPhone 真机验收。**不要把本分支当成 `main` 稳定发布。**

| 项目 | 当前设置 |
| --- | --- |
| GitHub 分支 | `feature/universal-ocr-ui-language` |
| App 版本 | **3.7.2（Build 17）** |
| OCR 引擎 | Apple Vision（默认） / Vision + PaddleOCR（按需增强） |
| 翻译 | Apple 本机离线；在线服务仅在用户明确配置启用后使用 |
| Codemagic 工作流 | `ios-universal-ocr-unsigned` |
| 构建产物（若成功） | `GameLingoAI-UniversalOCR-v3.7.2-b17-unsigned.ipa` |
| 当前验收状态 | 源码开发完成，待 Codemagic 与真机验证 |

## 3.7.2 重点修复（真机日志驱动）

- **解决 Accurate 复检过密：** 对动画画面加入全局 OCR 精确复检间隔；相同候选文本优先交给多帧确认，而不是重复加载 Accurate。
- **减少自动语言遗漏：** 只有当前游戏近期明确识别出日语或中文后，才允许纯汉字短对白继承该语言；混合字母、跨游戏或过期上下文不做推断。
- **增强会话诊断：** 重新开始采集时重新记录首次 OCR；追加基于上下文解决语言的计数，后续可对照等待时间和 OCR 复检次数。
- **真机证据：** 参考新日志 2026-10-24 的 16 条 OCR 采样、70 次累计 Accurate 复检和多次自动语言不确定事件。源码修复不等于已验证设备延迟下降。

[3.7.2 诊断和修复说明](docs/RELEASE_AUDIT_3_7_2.md)

## 新版重点

- **冷启动预热：** 首页打开后用固定测试画面预热 Vision，检查当前语言对是否安装，已安装时尝试固定短句离线翻译预热。不会自动下载语言包或发送游戏文字到在线服务。
- **更少的重复识别：** 相同画面低置信度情况下，对 Vision Accurate 复检加 2 秒的限频；保留 OCR 多帧确认和 PaddleOCR 按需增强。
- **满窗 PiP：** 满窗双语、满窗中文、原位菜单阅读模式。原文和中文成对分页；窗口变小时调整内容密度，而非不断滚动长文本。历史排版模式仍可使用。
- **一键启动：** 首页一次操作准备 PiP，收到成功回调后再走系统屏幕采集授权；PiP 无法使用时可手动跳过小窗继续采集。
- **诊断：** 新增 Vision / 翻译预热、首次识别、首次字幕、PiP 启动时延和被限频的 Accurate 次数，不存储截图或译文内容。

**本版没有新增任何快捷指令、桌面长按快捷操作或轻点背面触发功能。** App 内原有的游戏截图翻译依旧保留。

## 如何构建和安装

1. 在 Codemagic 连接仓库 `chenyu9512/GameLingoAI`，选择分支 **`feature/universal-ocr-ui-language`**。
2. 运行工作流 **`ios-universal-ocr-unsigned`**，Xcode 27.1 环境。
3. 工作流会生成 Xcode 工程、执行静态审计与 Swift 冒烟测试、下载官方 PP-OCRv6 Small Recognition ONNX 模型、安装 CocoaPods，再尝试构建。
4. 构建成功后从 Artifacts 下载 **`GameLingoAI-UniversalOCR-v3.7.2-b17-unsigned.ipa`**。
5. 使用 SideStore 等工具重签名并侧载到 iPhone。产物是**未签名 IPA**，不能直接点击安装。

## 使用步骤

1. 打开 App，查看首页的预热状态；若显示离线语言包未安装，在“离线语言资源”中交给 iOS 安装。
2. 在游戏配置中设置源语言；遇到自动识别不准，可指定日语、英语、韩语或其他 Vision 可识别语言。
3. 在首页点击 **「一键开始游戏翻译」**。默认尝试开启 PiP，成功后出现系统屏幕采集授权；请按系统提示完成授权。
4. 根据阅读习惯选择 **「满窗双语阅读」** 或 **「满窗中文阅读」**。默认静态显示完整当前页，可手动翻页；需要时才启用自动播放。
5. 翻译大型菜单时使用「整屏菜单扫描」；也可以选「原位菜单阅读」把游戏菜单的识别坐标近似应用到 PiP 排版。
6. 延迟、卡顿或文字异常时，导出「运行诊断」JSONL，并附上 Codemagic 构建日志或截图。

## 限制

- 首次 Vision/Translation 模型加载、系统 PiP 创建和屏幕采集权限均由 iOS 管理。预热有助于减少等待，但不能承诺固定毫秒延迟。
- OCR 可识别语言与 Apple 离线翻译的语言对支持范围不完全相同。未安装的系统翻译包需要用户单独安装。
- PaddleOCR 仅对 Vision 识别到的困难文本框提供第二次识别，**不是完整独立 OCR 检测替代**。
- PiP 的悬浮位置、外部窗口大小和跨 App 生命周期归系统控制；本应用优化的是**小窗内部**的文字布局，不会任意覆盖整个游戏或修改游戏文件。
- 本仓库没有因这次源码提交而自动获得 App Store 审核通过或真机性能达标认证。

[3.7.2 完整改动、验收清单](docs/RELEASE_AUDIT_3_7_1.md) · [Universal OCR 基础说明](docs/UNIVERSAL_OCR.md) · [返回 main 维护线](https://github.com/chenyu9512/GameLingoAI/tree/main)
