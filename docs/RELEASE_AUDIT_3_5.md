# GameLingo Direct 3.5 — 全量源码审核与验收边界

日期：2026-10-23。以下记录是 GitHub 源码检查，不是完成了 Xcode 或 iPhone 实机验收。

## 目标与功能范围
1. 竖屏/横屏沿用 3.4 的最新帧优先 OCR；屏幕最底部增加独立 21% 区域 Vision .accurate 补扫，最低文字高度 0.003；小字抽取与主区域按相似度去重，支持逐游戏开关。额外 OCR 可能增加电量和 CPU 负担，非固定无条件每帧扫描。
2. PiP 自动播放、手动前后翻页、暂停/继续、每页停留 2～10 秒；中文语音 AVSpeechSynthesizer 可选，默认不朗读，以免干扰游戏。
3. 文本词库独立于 GameLingoStore 的 UserDefaults。TXT UTF-8/UTF-16、日语=中文或 Tab、# 名称备注；单文件 4MB/2.5 万条硬上限；编码、无效行、重复行报告。
4. 同一游戏支持多词库同时启用及全部开关；词库数据库本地 Application Support / GameLingoDirect；可跨所有 TXT 统一搜索。手动游戏译法优先于后导入的词库，其次内置日语 RPG / DQ。
5. 新增 Microsoft Translator、DeepL、Google Cloud Translation 的专用 HTTPS REST 适配器，使用 Keychain 保存 API 密钥，测试成功才改变 provider；保留既有 MyMemory、LibreTranslate、通用 JSON REST。Azure 非 global 资源可填写 Region。
6. 在线 API 有本机每日日字符限额（可设置），没有第三方服务器真实剩余额度查询；对新 Developer DeepL 试用总额应单独管理，不能把本机每天限额说成服务商总额度。
7. UI 已调整：实时首页状态仪表盘、深色渐变卡片、阅读按钮，游戏设置拆为 识别/词库/翻译/偏好 四类；词库包括格式说明和导入错误反馈。
8. Xcode 工程生成包含新增 GameGlossaryTXTParser、GameGlossaryLibrary、GameGlossaryLibraryView；Codemagic 新增 TXT 解析类型检查/示例测试，保留 GameOCRQuality 测试和 Swift 语法预检。

## 兼容与隐私
- 之前安装的游戏配置以 optional 字段迁移 `bottomBoost`, `autoplay`, `playbackSeconds`, `readAloud`, `GameTranslationEndpoint.region`, `dailyCharacterLimit`；初始 provider 依然 `.offline`。
- ScreenCaptureKit 全屏捕获及系统 PiP 的限制仍存在；不使用 App Groups、不含 BroadcastUpload 扩展，SideStore 单 App unsigned IPA。
- 任何在线模式都需要用户主动测试成功；只发送被 OCR 识别的文字，不发送截图；第三方服务可能记录或计费。
- 截图导入沿用强制离线翻译，现已包含已启用 TXT/内置词库的精确匹配。
- Google Cloud API 使用用户自备的 Google Cloud 项目密钥，需要在云端开启 API/计费；免费月度信用额外用完可产生费用，用户应在云控制台设预算和配额。

## 尚未验证（不得宣称已通过）
| 项目 | 本轮状态 | 真机/构建验证 |
|---|---|---|
| Xcode 27.1 编译 | 新增 CI 语法及纯 Foundation 词库用例，尚未执行 Codemagic | 运行 `ios-direct-unsigned`，检查编译日志和 IPA |
| TXT 导入 iOS 文件权限 | 有 `fileImporter` + security scoped read 代码 | iPhone 在“文件”中选取 UTF-8/UTF-16 TXT |
| PiP 自动播放及中文朗读 | 有 AVSpeechSynthesizer 和时间调度代码 | 实机测试后台 PiP 与游戏声音共存 |
| 底部 OCR 准确度 | 有细字精确扫描和缓存 | 游戏底边小字截图逐字比对，并测 30 分钟耗电 |
| Azure/DeepL/Google API | 已按官方协议编码，暂无用户 API Key | 每个提供商点击测试并启用，校验中文与 HTTP 错误 |
| SideStore 兼容及迁移 | 源码配置保留旧工程逻辑 | 更新安装，确保既有游戏配置和历史不丢失 |

## 建议 3.5 验收优先级
1. Codemagic 的 host Swift glossary_txt_smoke 和 ocr_quality_smoke 通过，全部 iOS Swift 源码编译完成。
2. 安装后默认离线模式、已有游戏配置与勇者斗恶龙一键词库功能不回归。
3. 开启底部 OCR，观察 OCR 原文/译文诊断、准确率、增加的 OCR 毫秒数。
4. 导入两份 TXT 同名不同译法，验证后导入优先、关闭时恢复，以及当前游戏自定义最终覆盖。
5. 手动暂停/续播、2～10 秒翻页、中文语音默认关闭，游戏过程中横竖屏切换。
6. 通过真实自备 API Key 分别检测 Azure、DeepL、Google，模拟 HTTP 401、403、429、断网。

**结论：3.5 目标功能已经编码并提交，尚不等于已编译成功或达到消费级最终稳定性。** 后者取决于 CI 和真实 iPhone 的验证结果。