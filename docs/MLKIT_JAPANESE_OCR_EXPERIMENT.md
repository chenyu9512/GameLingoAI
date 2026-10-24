# GameLingo Direct — ML Kit 日语 OCR 实验分支

分支：`experiment/mlkit-japanese-ocr`

此支线从 `main` 创建，不影响主线代码。实验版构建号 **3.6.0 (13)**；原版仍为 3.5.2 (12)。

## 新增能力

- 独立可选 OCR：Google ML Kit Text Recognition v2 Japanese（CocoaPods `GoogleMLKit/TextRecognitionJapanese`, 固定 **9.0.0**）。官方 iOS SDK 的模型会随安装包一起分发；运行中不上传游戏画面。
- 游戏配置增加 OCR 切换；**默认 Apple Vision**。手动选择 ML Kit 日语后仅在**固定日语 `ja`**时生效。`auto`、英语、韩语及其他语言仍使用 Vision，因此现有自动语言识别、离线翻译、词库和 PiP 路径不变。
- **只替换实时对白主 OCR**，菜单整屏 OCR、底部补扫、截图 OCR 仍按原来的 Vision 流程运行；采用既有 latest-frame-wins、复检稳定性和过期文本丢弃。
- ML Kit 识别前按方向纠正并 **ROI 裁剪**，排除用户设定的 HUD/PiP 区域，识别只在后台 OCR 工作队列同步运行；仅保留行文本和框位用于处理，不保存原始画面。
- ML Kit v2 没有和 Vision 相同的置信度：本支线用 **0.65 作为两帧确认的内部策略值**，UI 不显示成真实 ML Kit 置信度。诊断日志添加 `ocr_backend`（1=Vision,2=MLKit）和 `confidence_available`（Vision=1,MLKit=0）。
- 当 ML Kit 初始化、裁剪或推理抛异常，会退回 Apple Vision，避免致命失效。测试版的选择保存在当前游戏配置；普通构建即使读到实验选择也安全回退 Vision。

## Codemagic 构建（仅实验分支）

1. Codemagic 仓库分支切换到 `experiment/mlkit-japanese-ocr`。
2. 选择 **`ios-direct-mlkit-unsigned`** 工作流，使用 Xcode 27.1。
3. 生成单 Target Xcode 项目：`GAMELINGO_DIRECT_CAPTURE=1 GAMELINGO_EXPERIMENTAL_MLKIT=1 python3 tools/build_xcodeproj.py`。
4. `pod install --repo-update` 安装官方 Google ML Kit 日语 OCR，生成 `GameLingoAI.xcworkspace`。
5. 构建 `-workspace GameLingoAI.xcworkspace`，输出 `GameLingoAI-MLKit-Japanese-Experimental-unsigned.ipa`，供现有 SideStore 签名及侧载流程使用。

**注意**：实验版版本号为 3.6.0 (13)，App ID 沿用原来的 direct ID。可在设备上升级并保留游戏配置，但建议首次试验前先导出游戏配置备份。安装包比不包含 ML Kit 的版本明显变大。若同时保留两版，需改用独立 Bundle ID 才能并存。

正常 `ios-direct-unsigned` 工作流仍不需要 CocoaPods、不编译 `MLKIT_OCR` 代码，保留正常版的构建方式。

## 性能对照

建议在同一款日语游戏里做 A/B 测试。每组关闭其他 App 干扰，使用相同对白框、相同文本内容和相同性能设置：

| 指标 | Vision（A） | ML Kit Japanese（B） |
|---|---|---|
| OCR P50/P95 | 待真机 | 待真机 |
| 画面到双语字幕 P50/P95 | 待真机 | 待真机 |
| 日语逐字错误率 CER | 待人工标注 | 待人工标注 |
| 内存峰值 / 温度 / 15 分钟耗电 | 待真机 | 待真机 |
| 连续运行 30 分钟是否卡顿 | 待真机 | 待真机 |

只有真实 iPhone 对照数据能判断哪套 OCR 更好。Google 官方指出，日语等非拉丁文字识别可能比 Latin 模型慢，且每种脚本 SDK 约增加 38MB；**本支线不保证速度一定优于 Vision**。

## 目前验证状态

代码和独立 Codemagic 工作流已提交，基础兼容性检查已加入 `tools/verify_mlkit_experiment.py`；**尚未获得这条分支的 Codemagic 构建通过证明，也尚未完成 iPhone 真机基准测试。**

官方文档：https://developers.google.com/ml-kit/vision/text-recognition/v2/ios
