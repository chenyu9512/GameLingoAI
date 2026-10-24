# 版本与分支说明

这份表是仓库的版本索引。**实际编译出来的版本以所选分支中 `tools/build_xcodeproj.py` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 为准**。GitHub 分支名、README 和 Codemagic 显示名称是辅助标识，不会自动修改 App 版本。

更新：2026-10-24。版本状态按目前仓库源码、分支与工作流盘点，不等于真机验收结果。

## 一眼看懂

| 标识 | 版本 | GitHub 分支 | Codemagic 工作流 | 用途 |
| --- | --- | --- | --- | --- |
| **MAIN · 维护线** | **v3.5.3 (Build 14)** | `main` | `ios-direct-unsigned` | Apple Vision + iOS 27 单 App 直采。当前推荐先测试这条维护线 |
| **LEGACY · 历史方案** | **v2.0.0 (Build 1)** | `main` 的旧模式 | `ios-offline-unsigned` | iOS 26 ReplayKit 扩展方案；保留作参考，不是当前推荐安装路径 |
| **EXPERIMENT · 旧 OCR** | **v3.6.0 (Build 14)** | `experiment/mlkit-japanese-ocr` | `ios-direct-mlkit-unsigned` | Google ML Kit 日语实验版，已由新 OCR 路线取代；保留原始历史 |
| **WILD / UNIVERSAL OCR · 开发版** | **v3.7.0 (Build 15)** | `feature/universal-ocr-ui-language` | `ios-universal-ocr-unsigned` | 多语言 Vision + PaddleOCR、语言资源 UI 和界面改版；**单独开发，不在本次整理中修改** |

> **维护线**表示目前维护与对照的分支，不是“App Store 已上架”或“全部功能已实测通过”。
> **Build 14** 在 3.5.3 和 3.6.0 中都有使用，所以**不要只看 Build 数字**；至少同时看版本号、分支和构建工作流。

## 从哪里开始

**只想使用、先确认基础翻译**：选 `main` → `ios-direct-unsigned`，产物为：

`GameLingoAI-Direct-v3.5.3-b14-unsigned.ipa`

**排查旧日语 ML Kit 实验问题**：保留原分支 `experiment/mlkit-japanese-ocr`；不要把它当成最新稳定版。

**测试多语言通用 OCR**：进入 `feature/universal-ocr-ui-language` → `ios-universal-ocr-unsigned`。它的独立说明位于[该分支的 Universal OCR 文档](https://github.com/chenyu9512/GameLingoAI/blob/feature/universal-ocr-ui-language/docs/UNIVERSAL_OCR.md)。这一路线仍需以实际 Codemagic Xcode 构建和 iPhone 测试为准。

**旧 ReplayKit 方案**：`main` → `ios-offline-unsigned`，产物为：

`GameLingoAI-ReplayKit-v2.0.0-b1-legacy-unsigned.ipa`

旧方案的使用背景见[历史 ReplayKit 文档](legacy/REPLAYKIT_OFFLINE.md)。

## 命名怎么读

- **仓库名**：固定为 `GameLingoAI`。一个仓库维护一套项目，不再为每个试验重新建同名仓库。
- **Git 分支**：`main` 是当前维护线；`feature/` 是新功能开发；`experiment/` 是隔离实验。旧分支保留，不用强行重命名破坏 Codemagic 关联。
- **App 版本**：`v主版本.次版本.修订版 (Build 构建号)`，例如 `v3.5.3 (14)`。**分支不同，版本号与 Build 数字也要一起看**。
- **Codemagic**：前缀 `01 | MAIN` 表示首选维护线；`99 | LEGACY` 表示历史方案。实际工作流机器标识保持不变，避免破坏 Codemagic 配置。
- **IPA 文件**：`GameLingoAI-方案-v版本-b构建号-unsigned.ipa`。文件名包含版本是为了在 Windows 下载文件夹里也能直接辨认；文件仍**未签名**，需 SideStore 等工具签名侧载。
- **历史报告**：`docs/RELEASE_AUDIT_3_5_*.md` 是旧版本审计记录，不应因最新版本推进而删除或改写为“已验收”。

## 防止版本再次混乱

1. 改版本必须先改对应分支的 `tools/build_xcodeproj.py`，再更新该分支的 `README.md` 版本表、`codemagic.yaml` 显示名称和 IPA 文件名。
2. 新增实验功能只在自己的 `feature/` 或 `experiment/` 分支进行。**不要直接把实验内容合并到 `main`**。
3. 在 Codemagic 中同时核对 **Branch + Workflow + IPA 文件名 + App 内版本**；不能只核对工作流名称。
4. 每次宣称“构建成功”前检查 Codemagic 的 Xcode 编译结果；每次宣称“功能完成”前检查真实 iPhone 运行情况。静态检查通过不等于真机成功。
5. 历史日志里的旧文件名（例如 `GameLingoAI-Direct-iOS27-unsigned.ipa`）仍指先前的产物；本次命名整理没有修改旧文件或重写历史构建。

## 常用入口

- [项目首页](../README.md)
- [v3.5.3（Build 14）变更记录](RELEASE_AUDIT_3_5_3.md)
- [v3.5.2（Build 12）变更记录](RELEASE_AUDIT_3_5_2.md)
- [旧 ReplayKit 项目文档](legacy/REPLAYKIT_OFFLINE.md)
- [Universal OCR 独立分支](https://github.com/chenyu9512/GameLingoAI/tree/feature/universal-ocr-ui-language)
