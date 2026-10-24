# GameLingoAI Universal OCR 3.7.2 (Build 17) — 真机诊断修复

更新：2026-10-24 · 分支：`feature/universal-ocr-ui-language` · 工作流：`ios-universal-ocr-unsigned`。

> 本次只依据最新导出的 JSONL 数字及源码修改策略。源码提交、静态检查及纯 Foundation Swift 测试不代表已经在 Codemagic/Xcode 或 iPhone 上验证延迟下降。没有修改 `main` 或旧 ML Kit 分支。

## 新诊断数据

文件：`GameLingo-diagnostics-DE727C09-BB4B-4A2A-8B77-AA12C6D4F5CC.jsonl`，共 63 条，时间 2026-10-24 06:14:03–06:19:08 UTC。**OCR 是至少每五秒才写一次的抽样**，不可将本表视为每帧覆盖统计；P95 是小样本线性插值，仅供比较。

| 指标 | 数据 |
| --- | --- |
| Vision OCR 预热 | 112 / 117 ms |
| 离线翻译预热 | 首次状态码 2（未就绪）；第二次状态码 1（已安装），预热 326 ms |
| PiP 创建 | 928 / 638 ms，均成功 |
| 采集启动 / 停止 | 两次启动，一次停止 |
| OCR `ocr_ms` | 16 次采样；P50 349 ms，P95 约 1,147 ms，最大 1,893 ms |
| `translation_complete` | 11 次；翻译耗时 P50 225 ms，最大 1,347 ms |
| 采集→译文 | 11 次；P50 606 ms，最大 1,702 ms |
| 第一次成功翻译 | 第二次采集启动后约 52.18 秒；不等于模型执行耗时 |
| Accurate 重扫累计 | 70 次（最新采样）；旧策略避免重扫累计 32 次 |
| 待处理帧替换 | 123 次（最新采样） |
| `pipeline_skip` 可见抽样 | reason 2：15 次（等待稳定确认）；reason 3：4 次（源语言无法确认）；reason 4：3 次（重复字幕）；reason 6：1 次（短间隔重复提交） |
| Paddle | `ocr_requested_backend=1` 且 `ocr_backend=1`，此会话选的是 Vision；`ocr_paddle_available=1` 仅代表模型可用 |
| 失败事件 | 无 `translation_failure`；不能据此断言所有文字都被识别、翻译 |

`sampled_out` 是正常采样限频计数，不是实际漏翻的对白数量。下方精细 OCR、整屏扫描和实时 Vision 可能竞争设备计算资源，但日志不能单独证明造成最慢单次 OCR 的具体操作。

## 3.7.2 修复范围

1. **动画画面下的 Accurate 预算**：新增 `GameOCRRecoveryPolicy`。不同像素指纹也必须满足全局复检最小间隔（平衡模式 1.4 秒、快速模式 1.0 秒，空文本 0.9 秒）；完全相同指纹至少间隔 2.5 秒。已重复得到的同一 Fast 候选（且置信度达到 0.48）优先由多帧稳定确认，而不是再同步 Accurate 重扫。保留首次及必要时的 Accurate 兜底，不通过提高采集帧率“提速”。
2. **可靠的自动源语言上下文**：只有当前游戏已经明确检测出 `ja`、`zh-Hans` 或 `zh-Hant`，且不超过 120 秒，才允许对至少包含两个汉字、无其他文字脚本的短句继承该来源；不根据纯英文 HUD 或未识别来源猜测日语。切换游戏、画面几何信息或重新采集时清空历史。
3. **冷启动诊断更完整**：再次启动采集时重新记录首次 OCR；新增 `first_stable_ocr`（首次得到稳定文本）与 `first_source_resolved`（首次确认翻译源语言）的启动耗时，进一步区分 OCR 稳定性判断和语言判定造成的等待。在 OCR 采样记录 `context_source_uses`（累计继承源语言次数），不包含截图或任何识别文本。
4. **独立测试**：增加 `tests/ocr_session_policy_smoke.swift`，覆盖首个 Accurate 请求、全局间隔、相同画面间隔、稳定候选抑制、汉字上下文有效期、跨语种切换及重置。Codemagic 预编译阶段运行 `swiftc` Foundation-only 测试，并由 `tools/verify_universal_ocr.py` 检查工程收录和源码关联。
5. **版本和交付**：应用版本更新为 **3.7.2 (Build 17)**，IPA 文件名 `GameLingoAI-UniversalOCR-v3.7.2-b17-unsigned.ipa`。保留原 3.7.1 文档，便于前后比较。

## 真机验收

- 同一游戏、相同区域、相同性能模式，连续玩 10–15 分钟，再导出 JSONL。
- 重点看 `ocr_ms` 的 P50/P95、`accurate_rescans` 增量/分钟、`accurate_suppressed`、`dropped`、`first_ocr_ms` 和 `first_translation_ms`；不要把稀疏日志当作全部帧。
- 开启“自动识别语言”测试日语假名+纯汉字对白、游戏菜单、中文界面、英语 HUD。确认不会误把英语或韩国语字幕当作日语。
- 验收 PiP 是否启动、翻译结果是否整页稳定显示、是否漏掉切换场景时的首句；若质量下降，手动指定源语言或重新校准识别区域。
- 如果耗时高或翻译延迟仍明显，追加真实的逐阶段耗时/设备热状态，再决定是否在底部 OCR、后台菜单扫描或 Vision 模型复杂度上做下一轮调整。

不新增快捷指令、外部上传或收费 API；PiP 实际悬浮位置继续由 iOS 管理。
