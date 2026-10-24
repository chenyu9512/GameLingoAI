# GameLingo AI 3.8.0 Beta 1 · 工程改造与验收

日期：2026-10-24。代码分支：`feature/universal-translation-3.8-beta`。从 `feature/universal-ocr-ui-language` 3.7.2 (Build 17) 派生，保留后者作为可回退版本。**没有更改 main 或 ML Kit 实验分支。**

## 本轮问题与解决

| 问题 | 原因（源代码/日志） | 本次修改 |
| --- | --- | --- |
| 选了混合引擎首页却显示 Vision | `activeOCRName` 曾仅根据该帧实际后端更新；下拉菜单绑定的是未保存的 `profileDraft` | 增加当前选择名称和运行结果双状态；配置页引擎选择立即持久化、下一帧应用 |
| 快速模式下 Paddle 不触发 | `GameOCRRouting.shouldEnhance` 在 `performanceFast` 为 true 时直接返回 false | 给快速模式单独设置 3s 冷却及 <0.45 置信度阈值；混合模式不再被完全禁用 |
| 第一次 PiP 失败，需要重按 | 系统 PiP 可用状态依赖首帧和内联预览；失败后首页一直保留 `awaitingPiPForCapture` 状态 | 内联预览预生成；PiP 状态增加 preparing/launchFailed；首轮不可用自动重试一次，渲染失败或系统拒绝后结束等待、提供人工重试 |
| 点击按钮无反馈 | 操作散落在按钮回调、Picker 与异步系统回调，缺少统一可见状态 | 首页操作提示、震动反馈、保存/引擎/语言/菜单/截图/PiP 的可见提示、系统失败原因 |
| 语言逻辑看起来是日语应用 | 自动启动预热隐含 `ja`、OCR 优先列表 `ja-JP` 第一、翻译目标固定 `zh-Hans`、多个入口固定中文 | 按设备语言偏好确定默认目标；源语言不再强制日语预热；支持用户选择目标，并贯通实时、菜单、截图、离线资源、语音和主动启用的在线服务 |
| 不同目标语言会串用旧菜单缓存 | 以前菜单页和缓存键没有目标语言 | 对旧页面兼容可选 `targetLanguage`，新缓存键区分目标语言；非中文目标不再使用中文专用术语 |

## 主要文件

- `ios/GameLingoAI/GameTranslationLanguages.swift`：支持的常见目标语言、系统语言默认值以及 API 语言代码转换
- `ios/GameLingoAI/GameLingoStore.swift`：持久化目标语言、立即保存源语言和 OCR 引擎、泛化 PiP 显示模式名称
- `ios/GameLingoAI/DirectGameCapture.swift`：将选择/实际 OCR 拆分，实时翻译支持目标语言，并区分缓存
- `ios/GameLingoAI/GameOnlineTranslation.swift`：所有翻译服务接受显式目标语言；服务可用性仍需真实在线检验
- `ios/GameLingoAI/GameMenuCatalog.swift`：目标语言贯通整屏菜单与缓存、保护老版本保存的数据
- `ios/GameLingoAI/GameLanguagePackView.swift` / `GameStartupWarmup.swift`：资源按所选语言对准备，自动模式不强制日语
- `ios/GameLingoAI/GameLanguageSupport.swift`：Vision 自动检测优先设备语言，仍受设备识别模型支持范围限制
- `ios/GameLingoAI/FloatingSubtitleController.swift`：PiP 预热、自动重试和失败状态；朗读选定目标语言
- `ios/GameLingoAI/DirectHomeView.swift`：实时源语言和目标语言选择、操作反馈与启动恢复流程
- `tests/translation_languages_smoke.swift`：新增语言偏好/代码转换冒烟测试
- `tests/universal_ocr_routing_smoke.swift`：验证快速模式下混合增强有条件运行

## 预期输出与验证边界

- 版本：**3.8.0 (Build 18) Beta 1**
- Codemagic 工作流：`ios-universal-ocr-unsigned`
- 未签名 IPA（须先构建成功）：`GameLingoAI-Universal-v3.8.0-b18-beta-unsigned.ipa`
- 改动已按仓库源码进行审计；Xcode iPhoneOS 完整构建与真机 PiP 行为需要 Codemagic/设备确认
- 快速模式 PaddleOCR 仍只是按需增强；**并不是“纯 Paddle 直接识别整屏”**
- Apple Translation、在线 API 的实际可用语言对必须逐个验证；不同提供商可能返回不支持或要求下载
- 在 iOS 不允许 PiP 的状态下，只能清楚报错和提供回退，不能绕过系统权限

## 真机验收建议

1. 全新安装：仅点击首页一次开始，观察 PiP 是否成功，失败后是否释放主按钮并可重试；随后完成屏幕授权
2. 运行中 Vision ↔ 混合模式切换：无需再次点击保存，核对「已选择引擎」「本帧实际结果」「Paddle 可用性」三处信息；快速/平衡模式分别测试
3. 从日、英、韩、法或混合菜单截图测试自动识别与手动源语言；验证未强制当作日语
4. 将目标切换为中文、英语、日语；分别验证实时字幕、截图、菜单、语音、语言包、缓存独立
5. 先让在线 Provider 做固定短句测试再选择启用；对不支持的语言对显示错误，不静默回退和不擅自调用在线服务
6. 连续 15 分钟导出 JSONL，对照 OCR P50/P95、翻译错误、第一条可稳定识别文字、PiP 启动次数和延迟
7. 检查应用在退出重进、切换目标语言/识别引擎、首次系统授权拒绝、App 前后台切换后能否恢复

**明确不在本轮范围：** 苹果快捷指令、静默绕过系统采集权限、任意屏幕覆盖或直接替换第三方游戏文字。
