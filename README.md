# GameLingo AI — iOS 27 单机直采版本（新增）

> **目标：解决 SideStore 对 ReplayKit 扩展 App Groups 共享不稳定的问题。** 新增的 `ios-direct-unsigned` 工作流仅构建主 App，不嵌入 BroadcastUpload 扩展，也不请求 App Groups 权限；用户授权后通过 iOS 27 ScreenCaptureKit 直接获得屏幕帧，Vision OCR 与 Apple Translation 均在 iPhone 本地运行。

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
