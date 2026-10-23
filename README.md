# GameLingo Direct 3.2 · 竖屏/横屏自动识别

**2026-10-23 源码更新；等待 Codemagic 和真实 iPhone 验证。** 保留 iOS 27 ScreenCaptureKit、Vision、离线 Translation、双语 PiP、全屏菜单清单与 SideStore 单 App 安装方式。

## 横竖屏适配

- **自动判断**：根据 ScreenCaptureKit 提供的每帧 \`CVPixelBuffer\` 宽高判断竖屏/横屏，不依赖 GameLingo 当前的 UI 方向。手机从竖屏切换到横屏时刷新 OCR 稳定性状态、阻止旧翻译覆盖新画面、取消旧菜单任务。
- **两套对白扫描框**：每个游戏分别保存竖屏 \`region\` 和横屏 \`landscapeRegion\`，旧配置自动保留竖屏 ROI；横屏首次使用默认下部对白区。进入“游戏配置”切换“竖屏区域 / 横屏区域”，导入同方向截图即可拖动或通过滑块设置。
- **方向纠正**：默认“自动识别”（假设屏幕流像素已正向排列）；少数游戏把画面横着绘制在固定方向的帧里，可手动尝试 **左转 90° / 右转 90° / 旋转 180°**。Vision 对实时 OCR、全屏菜单 OCR 使用一致的 \`CGImagePropertyOrientation\`，采样去重区域转换回原始像素坐标。
- **照片与截图**：采用 \`UIImage.imageOrientation\` 到 \`CGImagePropertyOrientation\` 的明确映射，避免从 PhotosPicker 获得的竖屏 JPEG 被误认为横屏；手动方向设置也能覆盖截图识别。绿色 ROI 叠层对应实际等比缩放后的图片范围，而不是整个预览容器。
- **全屏菜单**：翻译文本块继续记录标准化 Vision 坐标、原文、中文和画面方向。屏幕方向变化时旧扫描结果不会覆盖新任务。旧版本的游戏配置与菜单页面兼容解码。
- **画中画**：PiP 继续展示原文在上、中文在下的双语字幕；视频小窗按系统行为显示，不强制跟随游戏画面旋转，也不重新申请 App Groups。

## 构建和安装

Codemagic 选择 \`main\` / **\`ios-direct-unsigned\`**，版本为 **3.2.0 Build 6**。Xcode 工程和语法预检都包含新增的 \`GameCaptureGeometry.swift\`；打包成功后使用 SideStore 更新 \`GameLingoAI-Direct-iOS27-unsigned.ipa\`。

建议验收四种场景：（1）竖屏剧情和静态菜单；（2）横屏剧情和静态菜单；（3）游戏过程中旋转手机，验证识别框及时切换；（4）横着显示文字的特殊游戏，尝试手动旋转 90°。如果游戏锁定方向、系统流画面未随手机旋转而旋转，需要手动纠正。没有任何 OCR 能保证识别全部小字或被遮挡内容。

**状态说明**：已提交源码和静态检查；尚未完成本轮的 Swift 全量编译、SideStore 侧载及竖屏/横屏真机测试。

---

# GameLingo Direct 3.1 · 极速双语 + 整屏菜单翻译

**代码提交于 2026-10-23；目前还需要 Codemagic / iPhone 真机验收。**

保留单 App + ScreenCaptureKit + Apple Vision + 本地 Translation + PiP，不引入 ReplayKit BroadcastUpload 或 App Groups。

## 双通道工作方式

1. **快速对白通道（PiP）**：只处理游戏配置的对白识别区域，并优先使用快速 OCR；高置信度对白直接翻译，不再一律等待 2 次 OCR。翻译后的 PiP 仍是“原文在上，中文在下”。采样间隔：快速档约 0.30 秒，平衡档约 0.48 秒；这些是最低采样间隔，不是端到端翻译延迟保证。
2. **静态菜单通道（整屏清单）**：在**游戏处于前台**时，画面基本静止后自动执行完整屏幕精确 OCR；动画菜单有低频兜底扫描。**不按 7 行截断**，保留每一条 Vision 检测到的文字及坐标，按屏幕阅读顺序排列。
3. **逐块离线翻译**：Apple Translation 的 \`translate(batch:)\` 逐步返回结果，按照 \`clientIdentifier\` 匹配源文本与中文。已翻译文字与最近 12 个页面保存在本地，可以完整滚动、导出文本、反复查看；不保存原始游戏图片。
4. **去重和重试**：同一菜单不反复翻译；已译文字从本地缓存载入；断开的菜单翻译可以重新扫描补齐。少于 4 条文字的自动扫描不覆盖已有菜单记录，但手动扫描会保留少量文字页面。
5. **手动整屏扫描**：在 GameLingo 点“返回游戏后扫描”，**约 3 秒内切回游戏**，在收到游戏画面后执行 OCR；不会立即把 GameLingo 自己的设置按钮扫进去。截图导入也会把全部 OCR 文本块发送到整屏双语清单。
6. **阅读方式**：PiP 只承担快速对白；装备、任务、菜单的**完整翻译在“整屏文字”页**滚动查看。iOS 的系统 PiP 不是跨应用任意位置的透明覆盖层，不能在游戏菜单原文字旁直接创建一对一的多条中文浮层。

## Codemagic / SideStore

- 分支：\`main\`；工作流：**\`ios-direct-unsigned\`**；Xcode 27.1；版本 **3.1.0 (Build 5)**。
- 工作流在实际 Xcode 构建前运行源码检查 \`tools/verify_direct_release.py\` 和 Swift 语法解析，并检查不包含 \`.appex\`。
- 成功产出 \`GameLingoAI-Direct-iOS27-unsigned.ipa\`，用 SideStore 签名安装。App 显示名称继续为 GameLingo Direct。
- 手动测试：先准备所选离线语言包，检查 PiP 双语；然后授权整个屏幕，返回游戏打开一张静态菜单，保持 2–4 秒后在“整屏文字”查看结果。对动画菜单或较少文字的菜单用“返回游戏后扫描”。
- 验收：动态对白翻译顺序、全屏菜单块数量与准确率、手动延迟扫描、重复菜单缓存、超过 7 行菜单、菜单翻译中断重试、30 分钟游戏稳定性、游戏声音、电池发热。
- 限制：系统屏幕采集授权、后台执行、游戏防录屏和最小可识别字体均受 iOS 与游戏本身约束。**当前新增实现还未得到 Codemagic 编译通过或 iPhone 真机运行结论**；源码预检查不能代替这两项验证。

---

# GameLingo Direct 3.0 · 双语游戏实时翻译

**2026-10-22 源码升级说明。默认字幕是上方原文、下方中文。** 这是单一 iPhone App 的 iOS 27 版本；不需要 OpenAI API、翻译服务器、App Groups 或 ReplayKit 广播扩展。

## 本轮功能

- **字幕双语输出**：PiP 和主界面同时显示游戏原文（上方青绿色）与简体中文（下方白色），可选择“仅中文 / 仅原文”，以及精简 / 标准双语 / 学习布局、80%～140% 字号。
- **新画面优先流水线**：通过 CVPixelBuffer 轻量像素指纹跳过部分不变画面；OCR 结果稳定检查；新的对白取消旧翻译任务，只有最新版本结果才能刷新字幕。快速、平衡、省电三种节奏；平衡档使用快速+精确双层 OCR。
- **多游戏配置**：每游戏单独保存语言、Vision 识别区域、排除区域和精确匹配术语表。可以导入截图拖动识别框，还能导出 / 粘贴恢复 JSON 配置备份。
- **设备内历史**：保留最多 200 条已翻译的原文与中文，可以搜索、分享文本、清空；不保存游戏画面，不调用外部翻译 API。
- **故障诊断**：采集状态、扫描次数、跳过静态画面、OCR 置信度、识别与翻译耗时、错误说明，可导出不含画面内容的诊断文本。
- **稳定性保护**：翻译失败保留重试机会；过期翻译不覆盖新句；屏幕流异常停止时最多有限重试两次，不绕过系统授权。所有数据保存在 App 自己的本地空间。

## 构建与更新（Windows + SideStore）

1. Codemagic 选择 GitHub \`main\` 的最新提交，工作流 **\`ios-direct-unsigned\`**，使用 Xcode 27.1。
2. 该工作流会执行 \`tools/verify_direct_release.py\` 静态检查、Xcode 真正编译、单 App 包审计。成功才会产出 **\`GameLingoAI-Direct-iOS27-unsigned.ipa\`**。
3. 用 SideStore 导入、签名并安装新 IPA。应用名 **GameLingo Direct**，Bundle ID 与旧 ReplayKit 版不同，并且不请求 App Groups 权限。
4. 打开 App → 准备系统语言包 → 点击“双语测试”→ 开启 PiP → 在系统授权窗口选择**整个屏幕** → 回到游戏。
5. 根据游戏对白的位置，在“游戏配置”用截图调整识别框，并保存；根据游戏画面刷新速率选择快速、平衡或省电模式。

## 必须实测的项目（不能只靠编译通过）

| 验收项目 | 验收方式 |
|---|---|
| 双语小窗 | 最小常用 PiP 下上原文、下中文均居中且不裁切；翻页顺序自然 |
| 真正全屏直采 | 切换到游戏后 OCR 扫描计数继续增长，不只是主 App 预览成功 |
| 翻译更新 | 快速切换 10 条对白，旧翻译不能覆盖新对白 |
| 语言包 | 飞行模式下翻译已安装语言；未安装语言显示可理解错误 |
| 运行可靠性 | 连续使用至少 30 分钟，系统中断时状态与有限重试正常 |
| 性能 | 比较快速、平衡、省电的处理时间、耗电和发热 |
| 游戏预设与历史 | 新增、切换、导出、恢复配置及清空字幕历史 |
| 游戏声音 | 画中画开启后游戏音频不被独占或意外静音 |

**状态：代码已集成到 GitHub，尚未完成本轮 Codemagic Swift 编译 / SideStore 真机验收。** iOS 27 虽可使用 ScreenCaptureKit 全屏采集，但系统在后台可能调度、暂停某些任务；PiP 位置和大小由 iOS 控制。不承诺每款游戏都能持续翻译，须以真机结果为准。

官方参考：
- https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios
- https://developer.apple.com/documentation/translation/translationsession
- https://developer.apple.com/documentation/vision/vnrecognizetextrequest/recognitionlevel

---

# GameLingo AI — iOS 27 单机直采版本（新增）

> **目标：解决 SideStore 对 ReplayKit 扩展 App Groups 共享不稳定的问题。** 新增的 `ios-direct-unsigned` 工作流仅构建主 App，不嵌入 BroadcastUpload 扩展，也不请求 App Groups 权限；用户授权后通过 iOS 27 ScreenCaptureKit 直接获得屏幕帧，Vision OCR 与 Apple Translation 均在 iPhone 本地运行。

## PiP 字幕布局修复（v2.2.0 build 3）

- 图像采用 640×360 像素，**`UIGraphicsImageRendererFormat.scale = 1.0`**，与 BGRA PixelBuffer 大小一致；避免 Retina 绘制输出裁切。
- 小窗只保留字幕：居中、自动字号适配、长对白 3.2 秒换页，使用边缘细线提示翻页。
- 画中画界面增加 **字号 80%–140%**、**显示小窗测试字幕** 和 **字幕帧输出计数**。
- 界面预览和系统 PiP 小窗共用同一视频渲染管线。先测试字号和位置，再返回游戏确认画面采集和实时翻译。
- 此代码已提交 GitHub，**尚未在 Codemagic / 真实 iPhone 完成此次修复的编译与运行验收**。

## iOS 27 直采版本的安装识别（2026-10-22 修订）

- **直采版本安装后名称为 `GameLingo Direct`**，Bundle ID 使用单独的 `com.example.GameLingoAI.direct`（如果使用自定义基础 ID 则追加 `.direct`）。这能避免 SideStore 将它误认为先前需要 App Groups 的 ReplayKit 版。
- 工作流仍为 **`ios-direct-unsigned`**，IPA 为 `GameLingoAI-Direct-iOS27-unsigned.ipa`。不要从 `ios-offline-unsigned` 下载旧包。
- 直采编译只包含独立的 `DirectHomeView.swift`、`DirectGameCapture.swift` 与画中画渲染；**不编译 `SharedSubtitles` / `SubtitleInbox`，不嵌入 `BroadcastUpload.appex`，也不请求 `com.apple.security.application-groups`**。
- 构建产物包含 `direct-package-audit.txt`，其中应出现 `com.example.GameLingoAI.direct`、`GameLingo Direct` 与 `PASS: no broadcast extension`。
- 如果安装过程中弹出 **SideStore.OperationError 1012**，其含义是 *SideStore 自己* 无法访问自己的共享备份目录，而不是 GameLingo AI 申请了 App Groups。请参考 https://docs.sidestore.io/docs/troubleshooting/error-codes 并通过 iLoader 更新/修复 SideStore 的自身签名。
- **新版本尚需 Xcode 27.1 编译与真机运行验证**。在侧载后还要确认系统的屏幕采集授权、Apple 离线语言包、PiP 后台表现。

## 新版本编译与安装

1. 必须使用 **iOS 27 或更新版本**。如果手机仍是 iOS 26，不能安装此直采 IPA；保留原来的 `ios-offline-unsigned` 工作流供旧系统测试。
2. Codemagic 中选择 `main` 分支，工作流选 **`ios-direct-unsigned`**，不要再选择 `ios-offline-unsigned`。
   - 此工作流明确固定 **Xcode 27.1（iOS 27 SDK）**，不要改回 `xcode: latest`，因为 Codemagic 的 `latest` 当前可能指向 Xcode 26.6，导致 `import ScreenCaptureKit` 编译失败。
   - 需要 **iPhone 自身运行 iOS 27 或更新版**才能安装直采 IPA。
3. 构建成功后下载 `GameLingoAI-Direct-iOS27-unsigned.ipa`，使用 SideStore 侧载并签名。这个 IPA 只有单个 App，没有独立的广播扩展，也不需要创建 App Group。
4. 在 GameLingo 中下载所需 Apple 本地语言包，开启画中画字幕，再点击 **授权并捕获整个屏幕**。
5. 系统 picker 里请选择**整个屏幕**，不要只选择 GameLingo 自己，随后切到游戏。采集与翻译状态可在 App 中查看。

**限制与验证：** 这是针对 iOS 27 SDK 新能力的代码实现，已与 Apple 官方 API 文档核对，但尚未在真实 iPhone 上完成云端编译及运行验收。某些游戏或系统状态可能限制捕获；PiP 字幕的后台刷新依赖 iOS 的正常运行机制。请查看构建日志 `xcodebuild-direct.log` 来定位 Swift 编译问题。

**为什么改变？** SideStore issue #1437 已记录扩展通过 SideStore 侧载后无法读取 App Groups `UserDefaults` 的情况。旧架构继续调整 Group ID 并不能保证解决。苹果官方 iOS 27 ScreenCaptureKit 提供经系统授权的主 App 全屏采集，减少这条依赖。

- Apple: https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios
- SideStore: https://github.com/SideStore/SideStore/issues/1437

---

# GameLingo AI Offline v1.3 — 仅使用一台 iPhone 的免费侧载实验项目

> **重要：尚未在 macOS/Xcode 或 iPhone 真机编译测试，也未上传 GitHub。** 这是源代码，不是可立即安装的 IPA。不要以为 PiP 同屏覆盖已完成验证。

## 你的四个要求

1. 代码上传 GitHub：目标仓库 `https://github.com/chenyu9512/GameLingoAI`；如果 ChatGPT 连接权限不足，可使用 Windows 上传脚本。
2. Windows 侧载：Codemagic 使用 macOS 机器执行 `xcodebuild`，产出 **未签名的 IPA**，Windows Sideloadly 持有 Apple ID 进行签名和安装，不使用 TestFlight。
3. **完全不调用 OpenAI 或 ChatGPT API**；不部署翻译服务器，不运行 Ollama，不使用 Python 端口转发。离线翻译计算运行在 iPhone 上，依赖 Apple 的系统翻译语言模型。
4. Codemagic 账户已注册：本仓库根目录配置好 `codemagic.yaml`，只需在 Codemagic 连接此仓库并选择 `ios-offline-unsigned`。

## 为什么系统要求 iOS 26+

Apple `TranslationSession(installedSource:target:)` 这个不依赖前台 SwiftUI View 的直接初始化 API 从 **iOS 26** 开始提供。ReplayKit 广播扩展需在前台 App 已准备好语言包后使用此接口进行设备内翻译。iOS 18 的 `.translationTask()` 主要由 SwiftUI View 驱动，无法在 ReplayKit 扩展中按同样方式处理。当前工程最低系统 iOS 26.0；若 iPhone 系统更低，此版本无法安装。

Apple 官方： https://developer.apple.com/documentation/translation/translationsession

## 真实实现 / 局限

- App 界面：SwiftUI 中文控制页。
- 本地 OCR：Apple Vision `VNRecognizeTextRequest`，检测画面变化、合并行并去重。OCR 可能遗漏竖排、艺术字、菜单文字。
- 本地翻译：Apple Translation + 系统语言包，日→中、英→中、韩→中。实际可用性依系统语言支持与下载安装情况而定；**不是 ChatGPT 大模型，不保证理解长篇游戏剧情**。
- ReplayKit 屏幕广播扩展：请求用户系统授权后，截取画面帧；翻译计算在扩展里完成。
- 同机字幕：广播扩展写入 App Group 的 `UserDefaults`，宿主 App 读取后尝试在 PiP 视频小窗显示。**字幕刷新依赖宿主 PiP 实际处于可运行状态；苹果不保证这种非标准画中画用法或后台连续运行。**
- 备用稳定功能：从照片中选择游戏截图，在 App 内设备端 OCR 与翻译；如果广播/PiP 不工作，仍可使用。
- 完全没有 `server/`，没有 HTTP 网络客户端，也不包含 API Key 或模型远端路径。

## 免费 Apple ID 侧载的重要风险

**App Groups 权限不可随便省掉。** Apple 官方规定跨扩展共享容器必须设置 `com.apple.security.application-groups` 这项 entitlement，并在开发账号里注册对应的 group ID。工程使用 `group.com.gamelingoai.offline`。

使用免费 Apple ID 的 Sideloadly 可能无法注册/保留 App Groups 权限，结果是 **广播翻译无法传给前台 App / PiP**。如果签名工具移除了权限，代码本身无法绕过系统隔离。不建议尝试隐藏系统授权或绕过签名限制。此项目首先确保截图 OCR + 翻译可运行；自动游戏同屏字幕只能在签名、扩展、PiP 兼容全部满足时试验。

苹果 App Groups 官方文档： https://developer.apple.com/documentation/xcode/configuring-app-groups

## Windows 操作步骤

### 1. 解压 ZIP，上传到指定 GitHub 仓库

安装 [Git for Windows](https://git-scm.com/downloads/win)。直接双击根目录 `上传到GitHub.cmd`，已经为你预填仓库 `https://github.com/chenyu9512/GameLingoAI.git`。首次运行会弹出 Git Credential Manager 登录窗口：通过浏览器授权 GitHub。脚本通过临时 clone 并提交源码，不会强制覆盖 Git 历史；如果仓库已有冲突项目文件会安全停止。也可以使用通用的 PowerShell 脚本：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\push_to_github_windows.ps1 -RepositoryUrl "https://github.com/chenyu9512/GameLingoAI.git"
```

**不要把账号密码、访问令牌或者验证验证码发到聊天里。**

如果你把 GitHub App 的权限授予刚创建的仓库，ChatGPT 也可以在授权可见后尝试直接上传。

### 2. Codemagic 编译未签名 IPA

1. 打开 https://codemagic.io/ ，在 Codemagic 中连接 GitHub 仓库。
2. `Add application` → 选择上面仓库 → iOS Native/Other（界面版本不同选项可能变动）。
3. 读取仓库根目录 `codemagic.yaml` → 选择 **ios-offline-unsigned**。
4. 点击 **Start new build**。不需要 `WINDOWS_SERVER_URL`、OpenAI Key、App Store Connect API Key。
5. 如果构建成功，Build → **Artifacts** 下载 `GameLingoAI-Offline-unsigned.ipa`。
6. 如果构建失败，复制第一条 `error:` 前后日志，用于修正 Xcode 构建错误。

### 3. Windows 侧载

1. 到 https://sideloadly.io/ 下载 Windows 版本，并安装该网站要求的 Apple 设备驱动/网页版 iTunes 与 iCloud。
2. USB 连接 iPhone，点「信任此电脑」。
3. 在 Sideloadly 将 unsigned IPA 拖入窗口，选中手机，输入你的 Apple ID，然后执行 sideload，工具会尝试重签 App 和 Broadcast Extension。
4. 在 iPhone 启用「设置 → 隐私与安全性 → 开发者模式」（如果系统提示），按系统提示信任开发者。
5. 免费 Apple ID 签名通常 7 天到期，届时需要重新刷新。

**不要在聊天中发送 Apple ID 密码、2FA 验证码或 GitHub token。**

### 4. iPhone 使用

1. 确保系统 iOS 26 或更新。首次打开 App 后选择日语，点击「准备 / 下载本地翻译语言」，允许系统安装日语与中文模型，其他语言按需准备。
2. 先用「备用：单张截图翻译」测试 Vision OCR 和翻译，确认设备内语言模型能用。
3. 点击「开启同屏字幕小窗」，看 PiP 是否启动；再点击 ReplayKit 广播按钮并选择 GameLingo Broadcast。
4. 返回游戏，查看 PiP 是否持续显示字幕。若没有，先验证广播扩展有没有正确签名及 App Group entitlement，再检查画中画后台运行。

## 研发验收顺序

A. Codemagic `xcodebuild` 首次编译；B. Sideloadly 侧载；C. 单张截图识字 / 翻译；D. 广播扩展工作；E. App Group 共享结果；F. PiP 后台字幕。A~F 必须分开验收，此项目没有夸称全部通过。

## 隐私

本工程不联网发送游戏画面和文字。不保证系统不会为首次语言模型下载等苹果系统服务联网。App Group 中字幕只保留最新条目，无自动云端上传。图片从用户选择的照片中读取。
