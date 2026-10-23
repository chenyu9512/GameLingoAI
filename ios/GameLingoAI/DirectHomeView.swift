import SwiftUI
import PhotosUI
import Vision
import Translation
import UIKit

// iOS 27 single-App user interface. No ReplayKit extension or App Groups.
@available(iOS 27.0, *)
@MainActor
struct DirectHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = GameLingoStore.shared
    @ObservedObject private var capture = DirectGameCapture.shared
    @StateObject private var menuCatalog = GameMenuCatalog.shared
    @StateObject private var overlay = FloatingSubtitleController()

    @State private var tab = 0
    @State private var profileDraft = GameProfile(name: "默认游戏")
    @State private var sampleImage: UIImage?
    @State private var regionPhoto: PhotosPickerItem?
    @State private var editingLayout: GameFrameLayout = .portrait
    @State private var translationPreparation: TranslationSession.Configuration?
    @State private var preparationState = "首次使用请准备系统离线语言包"
    @State private var downloadSourceLanguage = "ja"
    @State private var screenshot: PhotosPickerItem?
    @State private var screenshotText = ""
    @State private var screenshotResult = ""
    @State private var screenshotStatus = ""
    @State private var screenshotConfiguration: TranslationSession.Configuration?
    @State private var historySearch = ""
    @State private var showOCRDebug = false
    @State private var showingOnboarding = false
    @State private var showingRestore = false
    @State private var restoreJSONString = ""
    @State private var restoreMessage = ""
    @State private var dragonQuestNotice = ""

    private let mint = Color(red: 0.25, green: 0.94, blue: 0.78)
    private let navy = Color(red: 0.035, green: 0.065, blue: 0.12)
    private let card = Color(red: 0.08, green: 0.13, blue: 0.21)

    var body: some View {
        ZStack {
            LinearGradient(colors: [
                navy, Color(red: 0.04, green: 0.11, blue: 0.17), navy
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 17) {
                        header
                        if tab == 0 { realtimePage }
                        else if tab == 1 { fullScreenPage }
                        else if tab == 2 { gamePage }
                        else { historyPage }
                    }
                    .padding(.horizontal, 17).padding(.vertical, 16)
                }
                bottomNavigation
            }
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(.white)
        .onAppear {
            capture.setHostAppForeground(true)
            profileDraft = store.activeProfile
            downloadSourceLanguage = store.activeProfile.language
            updateCaptureConfiguration()
            configureOverlay()
            if !store.onboardingComplete { showingOnboarding = true }
        }
        .onChange(of: scenePhase) { _, state in
            capture.setHostAppForeground(state == .active)
        }
        .onChange(of: store.activeID) { _, _ in
            dragonQuestNotice = ""
            profileDraft = store.activeProfile
            updateCaptureConfiguration()
        }
        .onChange(of: store.profiles) { _, _ in updateCaptureConfiguration() }
        .onChange(of: store.provider) { _, _ in
            updateCaptureConfiguration()
            menuCatalog.cancelForProfileChange()
        }
        .onChange(of: store.endpoint) { _, _ in updateCaptureConfiguration() }
        .onChange(of: store.performance) { _, _ in updateCaptureConfiguration() }
        .onChange(of: store.fontScale) { _, _ in configureOverlay() }
        .onChange(of: store.pipLayout) { _, _ in configureOverlay() }
        .onChange(of: store.subtitleMode) { _, _ in configureOverlay() }
        .onReceive(capture.$latestLine) { item in
            guard let item else { return }
            overlay.setBilingual(original: item.original, translated: item.translated)
        }
        .onReceive(menuCatalog.$currentPage) { _ in
            syncMenuOverlay()
        }
        .onChange(of: screenshot) { _, value in
            Task { await processScreenshot(value) }
        }
        .onChange(of: regionPhoto) { _, value in
            Task {
                guard let data = try? await value?.loadTransferable(type: Data.self) else { return }
                if let image = UIImage(data: data) {
                    sampleImage = image
                    editingLayout = image.size.width >= image.size.height
                        ? .landscape : .portrait
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            capture.heartbeat()
        }
        .translationTask(translationPreparation) { session in
            do {
                try await session.prepareTranslation()
                preparationState = "语言包准备完成；可离线翻译"
            } catch {
                preparationState = "准备失败：" + error.localizedDescription
            }
        }
        .translationTask(screenshotConfiguration) { session in
            guard !screenshotText.isEmpty else { return }
            do {
                let output = try await session.translate(screenshotText).targetText
                let mapping = GameLingoStore.glossaryMap(store.activeProfile.glossary)
                screenshotResult = mapping[screenshotText] ?? output
                screenshotStatus = "截图离线翻译完成"
            } catch {
                screenshotStatus = "截图翻译失败：" + error.localizedDescription
            }
        }
        .sheet(isPresented: $showingOnboarding) { onboardingSheet }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(mint.opacity(0.17))
                    .frame(width: 51, height: 51)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(mint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("GameLingo").font(.system(size: 27, weight: .bold, design: .rounded))
                Text("DIRECT 3.4  ·  极速 OCR / 多行双语")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(mint)
            }
            Spacer()
            Button { showingOnboarding = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title2).foregroundStyle(.white.opacity(0.72))
            }
            .accessibilityLabel("使用说明")
        }
    }

    private var realtimePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            panel {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(mint)
                    Text("单 App 直采 · 双语模式").font(.subheadline.bold())
                    Spacer()
                    Text(store.provider == .offline ? "本机" : "在线已开启")
                        .font(.caption.bold())
                        .foregroundStyle(store.provider == .offline ? mint : .orange)
                }
                Text(store.provider == .offline
                    ? "原文在上、中文在下。横竖屏自动适配；默认完全本机翻译。"
                    : "原文在上、中文在下。你已主动开启在线模式：识别出的文字会发送到选定的翻译服务器，截图不会上传。")
                    .font(.caption).foregroundStyle(.white.opacity(0.73))
            }

            panel {
                HStack {
                    sectionTitle("当前游戏", icon: "gamecontroller")
                    Spacer()
                    Picker("游戏", selection: $store.activeID) {
                        ForEach(store.profiles) { p in Text(p.name).tag(p.id) }
                    }.pickerStyle(.menu).tint(mint)
                }
                HStack {
                    Text("原文语言：\(languageLabel(store.activeProfile.language))")
                    Spacer()
                    Text("性能：\(store.performance.title)")
                }
                HStack {
                    Label("当前画面：\(capture.detectedLayout.title)",
                          systemImage: "iphone.gen3")
                    Spacer()
                    Text(capture.screenDimensions)
                        .font(.caption.monospacedDigit())
                }
                .font(.caption).foregroundStyle(.white.opacity(0.67))
                Text("按需下载语言包（不随 IPA 内置）")
                    .font(.caption.bold()).foregroundStyle(mint)
                TextField("源语言代码，如 ja、en、ko、fr、de", text: $downloadSourceLanguage)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Picker("快速选择语言包", selection: $downloadSourceLanguage) {
                    Text("日语 ja").tag("ja")
                    Text("英语 en").tag("en")
                    Text("韩语 ko").tag("ko")
                    Text("法语 fr").tag("fr")
                    Text("德语 de").tag("de")
                    Text("西班牙语 es").tag("es")
                    Text("意大利语 it").tag("it")
                    Text("葡萄牙语 pt").tag("pt")
                    Text("俄语 ru").tag("ru")
                }.pickerStyle(.menu).tint(mint)
                Button {
                    let code = downloadSourceLanguage
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !code.isEmpty else {
                        preparationState = "请先填写 BCP-47 语言代码"
                        return
                    }
                    guard code != "zh-Hans" else {
                        preparationState = "源语言与目标中文相同，无需下载翻译包"
                        return
                    }
                    translationPreparation = TranslationSession.Configuration(
                        source: Locale.Language(identifier: code),
                        target: Locale.Language(identifier: "zh-Hans"))
                    preparationState = "正在请求系统安装对应语言资源…"
                } label: {
                    Label("按需准备 / 下载所选系统语言", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Text(preparationState).font(.caption2).foregroundStyle(.white.opacity(0.68))
                Text("语言由 iOS Translation 管理；需要用户确认和网络下载。非所有语言对都受设备支持。下载后在游戏配置中选择同一源语言。")
                    .font(.caption2).foregroundStyle(.white.opacity(0.65))
            }

            panel {
                HStack {
                    sectionTitle("悬浮双语字幕", icon: "captions.bubble")
                    Spacer()
                    Text(overlay.isActive ? "PiP ON" : "PiP OFF")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(overlay.isActive ? mint : .orange)
                }
                FloatingSubtitlePreview(controller: overlay)
                    .frame(height: 157)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack {
                    Text("字号").font(.caption)
                    Slider(value: $store.fontScale, in: 0.8...1.4, step: 0.1).tint(mint)
                    Text("\(Int(store.fontScale * 100))%")
                        .font(.caption.monospacedDigit())
                }
                HStack(spacing: 10) {
                    Button {
                        overlay.setBilingual(
                            original: "おかえりなさい。今日はいい天気ですね。",
                            translated: "欢迎回来。今天天气真不错。")
                    } label: {
                        Label("双语测试", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                    Button {
                        if overlay.isActive { overlay.stop() }
                        else { overlay.start() }
                    } label: {
                        Label(overlay.isActive ? "关闭小窗" : "开启小窗",
                              systemImage: "rectangle.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(mint)
                }
                Text(overlay.status)
                    .font(.caption2).foregroundStyle(.white.opacity(0.67))
                Text("PiP 视频帧：\(overlay.outputFrameCount)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                Text("多行双语显示最近 2～3 组；中文高密度最多 5 条；菜单分页显示已保存的整屏项目。")
                    .font(.caption2).foregroundStyle(.white.opacity(0.66))
            }

            panel {
                sectionTitle("实时屏幕翻译", icon: "viewfinder")
                DirectCapturePanel(profile: store.activeProfile, performance: store.performance)
                Text("请在系统选择器中选择整个屏幕，再返回游戏。")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }

            panel {
                sectionTitle("最新对白 · 原文 / 中文", icon: "character.bubble")
                Text(capture.original.isEmpty ? "等待识别游戏原文…" : capture.original)
                    .font(.subheadline).foregroundStyle(mint)
                    .textSelection(.enabled)
                Divider().overlay(.white.opacity(0.1))
                Text(capture.latest.isEmpty ? "等待中文字幕…" : capture.latest)
                    .font(.system(size: 19, weight: .semibold))
                    .textSelection(.enabled)
            }

            panel {
                sectionTitle("运行诊断", icon: "waveform.path.ecg")
                HStack(spacing: 6) {
                    metric("\(capture.scans)", "扫描")
                    metric("\(capture.translatedCount)", "翻译")
                    metric("\(capture.ignoredFrames)", "跳过静态帧")
                }
                HStack(spacing: 6) {
                    metric("\(capture.ocrElapsedMs)ms", "OCR")
                    metric("\(capture.translationElapsedMs)ms", "翻译耗时")
                    metric("\(Int(capture.ocrConfidence * 100))%", "OCR 置信度")
                }
                if !capture.lastError.isEmpty {
                    Text("最近错误：" + capture.lastError)
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("OCR 检测到 \(capture.lastOCRCandidates) 行 · 过滤 \(capture.rejectedOCRLines) 行")
                    .font(.caption2).foregroundStyle(.white.opacity(0.72))
                DisclosureGroup(isExpanded: $showOCRDebug) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("原始 OCR 候选（过滤前）").font(.caption.bold())
                        Text(String(capture.lastOCRRaw.prefix(1600)))
                            .font(.caption).foregroundStyle(.orange)
                            .textSelection(.enabled)
                        Text("有效 OCR 原文（过滤后）").font(.caption.bold())
                        Text(String(capture.lastOCRAccepted.prefix(1600)))
                            .font(.caption).foregroundStyle(mint)
                            .textSelection(.enabled)
                        Text("最新中文译文").font(.caption.bold())
                        Text(String(capture.latest.prefix(1600)))
                            .font(.caption).textSelection(.enabled)
                    }.padding(.top, 8)
                } label: {
                    Label("查看 OCR 乱码诊断与原文／中文对照", systemImage: "text.magnifyingglass")
                        .font(.caption.bold())
                }
                ShareLink(item: capture.diagnostics) {
                    Label("分享诊断文本（包含最近 OCR 文字）", systemImage: "square.and.arrow.up")
                }.buttonStyle(.bordered)
            }

            panel {
                HStack {
                    sectionTitle("整屏菜单扫描", icon: "text.viewfinder")
                    Spacer()
                    if menuCatalog.isTranslating {
                        ProgressView().tint(mint)
                    }
                }
                Text(menuCatalog.status)
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
                HStack {
                    Button {
                        capture.requestFullScreenScan()
                    } label: {
                        Label("返回游戏后扫描", systemImage: "viewfinder")
                    }.buttonStyle(.bordered)
                    Button {
                        tab = 1
                    } label: {
                        Label("查看完整译文", systemImage: "list.bullet.rectangle")
                    }.buttonStyle(.borderedProminent).tint(mint)
                }
                Text("完整菜单译文保存在 App 的清单中；PiP 仍只显示快速双语对白。")
                    .font(.caption2).foregroundStyle(.white.opacity(0.67))
            }

            screenshotPanel
        }
    }

    private var fullScreenPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            panel {
                HStack(spacing: 8) {
                    sectionTitle("整屏菜单翻译", icon: "text.viewfinder")
                    Spacer()
                    Text("全屏 OCR").font(.caption.bold()).foregroundStyle(mint)
                }
                Text("画面静止后自动补充扫描；包含菜单、装备、任务与说明等识别到的文字。")
                    .font(.caption).foregroundStyle(.white.opacity(0.72))
                HStack {
                    Button {
                        capture.requestFullScreenScan()
                    } label: {
                        Label("返回游戏后重新扫描", systemImage: "arrow.clockwise")
                    }.buttonStyle(.borderedProminent).tint(mint)
                    if menuCatalog.isTranslating {
                        ProgressView().tint(mint)
                    }
                }
                Text(menuCatalog.status).font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                if menuCatalog.lastScanMilliseconds > 0 {
                    Text("全屏 OCR 耗时 \(menuCatalog.lastScanMilliseconds)ms · 复用已有译文 \(menuCatalog.lastCacheHits) 条 · 待新增翻译 \(menuCatalog.changedBlocks) 条")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            panel {
                HStack {
                    sectionTitle("本次识别结果", icon: "list.bullet.rectangle")
                    Spacer()
                    if let page = menuCatalog.currentPage {
                        Text("\(menuCatalog.translatedCount)/\(page.blocks.count)")
                            .font(.caption.monospacedDigit()).foregroundStyle(mint)
                    }
                }
                if !menuCatalog.savedPages.isEmpty {
                    Menu {
                        ForEach(menuCatalog.savedPages) { page in
                            Button {
                                menuCatalog.open(page)
                            } label: {
                                Text("\(page.gameName) · \(page.scannedAt.formatted(date: .abbreviated, time: .shortened)) · \(page.blocks.count)条")
                            }
                        }
                    } label: {
                        Label("切换保存的菜单页面", systemImage: "square.stack")
                    }.buttonStyle(.bordered)
                }
                HStack {
                    ShareLink(item: menuCatalog.exportText) {
                        Label("导出当前整屏双语", systemImage: "square.and.arrow.up")
                    }.buttonStyle(.bordered)
                    .disabled(menuCatalog.currentPage == nil)
                    Button(role: .destructive) {
                        menuCatalog.clear()
                    } label: {
                        Label("清空菜单记录", systemImage: "trash")
                    }.buttonStyle(.bordered)
                    .disabled(menuCatalog.savedPages.isEmpty)
                }
                if !menuCatalog.lastError.isEmpty {
                    Text("菜单翻译错误：" + menuCatalog.lastError)
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            if let page = menuCatalog.currentPage {
                panel {
                    HStack {
                        Text(page.gameName).font(.headline)
                        Text(page.layout?.title ?? "未记录方向")
                            .font(.caption2).foregroundStyle(mint)
                        Spacer()
                        Text("\(page.blocks.count) 个文本块")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    Text("原文和对应中文逐块排列。长菜单可向下滚动，未译出的项目会明确标记。")
                        .font(.caption2).foregroundStyle(.white.opacity(0.66))
                }
                ForEach(page.blocks) { block in
                    panel {
                        HStack {
                            Text(block.original)
                                .font(.subheadline).foregroundStyle(mint)
                                .textSelection(.enabled)
                            Spacer(minLength: 6)
                            Text("\(Int(block.confidence * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.38))
                        }
                        Divider().overlay(.white.opacity(0.09))
                        if let translated = block.chinese, !translated.isEmpty {
                            Text(translated).font(.headline).textSelection(.enabled)
                        } else {
                            Text(menuCatalog.isTranslating ? "正在翻译…" : "尚未翻译")
                                .font(.subheadline).foregroundStyle(.orange)
                        }
                    }
                }
            } else {
                panel {
                    ContentUnavailableView("暂无整屏识别结果",
                        systemImage: "text.viewfinder",
                        description: Text("请先开启屏幕捕获，再打开游戏菜单并保持片刻"))
                }
            }
        }
    }

    private var gamePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            panel {
                HStack {
                    sectionTitle("游戏配置", icon: "gamecontroller.fill")
                    Spacer()
                    Picker("选择", selection: $store.activeID) {
                        ForEach(store.profiles) { item in Text(item.name).tag(item.id) }
                    }.pickerStyle(.menu).tint(mint)
                }
                HStack {
                    Button {
                        store.createProfile()
                        profileDraft = store.activeProfile
                    } label: {
                        Label("新建游戏", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) {
                        store.deleteActiveProfile()
                        profileDraft = store.activeProfile
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .disabled(store.profiles.count <= 1)
                    .buttonStyle(.bordered)
                }
                TextField("游戏名称", text: $profileDraft.name)
                    .textFieldStyle(.roundedBorder)
                Picker("常用游戏语言", selection: $profileDraft.language) {
                    Text("日语").tag("ja")
                    Text("英语").tag("en")
                    Text("韩语").tag("ko")
                    Text("法语").tag("fr")
                    Text("德语").tag("de")
                    Text("西班牙语").tag("es")
                    Text("意大利语").tag("it")
                    Text("俄语").tag("ru")
                    Text("葡萄牙语").tag("pt")
                }.pickerStyle(.menu)
                TextField("自定义 BCP-47 语言代码", text: $profileDraft.language)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            panel {
                sectionTitle("游戏画面方向", icon: "rotate-cw")
                Picker("方向识别", selection: Binding(
                    get: { profileDraft.screenRotation },
                    set: { profileDraft.rotation = $0 })) {
                    ForEach(GameScreenRotation.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu).tint(mint)
                Text("默认自动：根据屏幕采集帧的宽高判断竖屏或横屏，无须转动手机操作。如果游戏画面横着显示、文字识别方向不对，可尝试左转或右转 90°，保存后立即生效。")
                    .font(.caption).foregroundStyle(.white.opacity(0.72))
                Text("当前捕获：\(capture.detectedLayout.title) · \(capture.screenDimensions)")
                    .font(.caption2).foregroundStyle(mint)
            }

            panel {
                sectionTitle("专属 OCR 识别区域", icon: "scope")
                Text("竖屏和横屏分别保存识别框。导入对应方向的游戏截图，再拖动绿色框或使用滑块调整。")
                    .font(.caption).foregroundStyle(.white.opacity(0.71))
                Picker("编辑方向", selection: $editingLayout) {
                    Text("竖屏区域").tag(GameFrameLayout.portrait)
                    Text("横屏区域").tag(GameFrameLayout.landscape)
                }.pickerStyle(.segmented)
                PhotosPicker(selection: $regionPhoto, matching: .images) {
                    Label("导入游戏截图用于定位", systemImage: "photo")
                }.buttonStyle(.bordered)
                regionPreview
                control("左边界 X", value: regionBinding(\.x))
                control("底边界 Y", value: regionBinding(\.y))
                control("宽度", value: regionBinding(\.width), min: 0.12)
                control("高度", value: regionBinding(\.height), min: 0.12)
                HStack {
                    Button("对白区域") {
                        saveEditingRegion(editingLayout == .portrait
                            ? .dialogue : .landscapeDialogue)
                    }
                    Button("全屏") { saveEditingRegion(.full) }
                }.buttonStyle(.bordered)
                Text("当前编辑：\(editingLayout.title)。坐标基于正确方向的画面；系统旋转后自动切换对应识别框。")
                    .font(.caption2).foregroundStyle(.white.opacity(0.65))
            }

            panel {
                Toggle(isOn: Binding(
                    get: { profileDraft.excluded != nil },
                    set: { value in
                        profileDraft.excluded = value
                            ? GameOCRBox(x: 0.72, y: 0.68, width: 0.26, height: 0.30)
                            : nil
                    })) {
                    sectionTitle("排除 HUD / 小窗区域", icon: "eye.slash")
                }.tint(mint)
                if profileDraft.excluded != nil {
                    control("排除区 X", value: Binding(
                        get: { profileDraft.excluded?.x ?? 0.72 },
                        set: { profileDraft.excluded?.x = $0 }))
                    control("排除区 Y", value: Binding(
                        get: { profileDraft.excluded?.y ?? 0.68 },
                        set: { profileDraft.excluded?.y = $0 }))
                    control("排除区宽度", value: Binding(
                        get: { profileDraft.excluded?.width ?? 0.26 },
                        set: { profileDraft.excluded?.width = $0 }), min: 0.05)
                    control("排除区高度", value: Binding(
                        get: { profileDraft.excluded?.height ?? 0.3 },
                        set: { profileDraft.excluded?.height = $0 }), min: 0.05)
                }
            }

            panel {
                sectionTitle("游戏专用术语表", icon: "text.book.closed")
                Text("原文=中文；每行一条。完全匹配时优先使用术语译文。")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                TextEditor(text: $profileDraft.glossary)
                    .frame(height: 140)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
            }

            panel {
                sectionTitle("勇者斗恶龙 · 一键术语包", icon: "book.closed.fill")
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("专用术语 \(GameRPGDictionary.dragonQuestTermCount) 条")
                            .font(.subheadline.bold())
                        Text("另有通用 RPG 词条一直可用")
                            .font(.caption2).foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Text(profileDraft.dragonQuestEnabled ? "已启用" : "未启用")
                        .font(.caption.bold())
                        .foregroundStyle(profileDraft.dragonQuestEnabled ? mint : .orange)
                }
                Button {
                    let newValue = !profileDraft.dragonQuestEnabled
                    if store.setDragonQuestPackEnabled(newValue, for: profileDraft.id) {
                        profileDraft.useDragonQuestLexicon = newValue
                        dragonQuestNotice = newValue
                            ? "整套专用术语已启用并保存，当前游戏立即生效。"
                            : "整套专用术语已停用并保存；自定义术语仍保留。"
                    } else {
                        dragonQuestNotice = "未找到当前游戏配置，请重新选择游戏。"
                    }
                } label: {
                    Label(
                        profileDraft.dragonQuestEnabled
                            ? "一键停用整套勇者斗恶龙术语"
                            : "一键启用整套勇者斗恶龙术语",
                        systemImage: profileDraft.dragonQuestEnabled
                            ? "checkmark.circle.fill" : "bolt.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(mint)
                if !dragonQuestNotice.isEmpty {
                    Text(dragonQuestNotice).font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                }
                Text("点击一次即保存到当前游戏，PiP 对白、整屏菜单与截图翻译全部使用；不用逐条添加，也不会改动你的自定义术语。")
                    .font(.caption).foregroundStyle(.white.opacity(0.69))
                GameRPGDictionaryView()
            }

            panel {
                GameTranslationSettingsView()
            }

            panel {
                sectionTitle("性能与双语字幕", icon: "slider.horizontal.3")
                Picker("性能模式", selection: $store.performance) {
                    ForEach(GamePerformance.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }.pickerStyle(.segmented)
                Picker("字幕显示", selection: $store.subtitleMode) {
                    ForEach(GameSubtitleMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }.pickerStyle(.segmented)
                Picker("小窗排版", selection: $store.pipLayout) {
                    ForEach(GamePiPLayout.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }.pickerStyle(.segmented)
                Text("多行双语显示最近几组对话；中文高密度提高容量；菜单分页从整屏清单读取内容。所有内容仍保存在 App 中。")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
                Text("默认双语：上方显示游戏原文，下方显示中文；字号可在实时页调整。")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }

            panel {
                sectionTitle("游戏配置备份", icon: "square.and.arrow.up")
                Text("导出与恢复游戏名称、语言、识别区域和术语表。内容仅在本机处理。")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                ShareLink(item: store.profileBackupJSON) {
                    Label("导出配置 JSON", systemImage: "square.and.arrow.up")
                }.buttonStyle(.bordered)
                Button(showingRestore ? "收起导入" : "粘贴备份内容恢复") {
                    showingRestore.toggle()
                }.buttonStyle(.bordered)
                if showingRestore {
                    TextEditor(text: $restoreJSONString)
                        .frame(height: 118)
                        .scrollContentBackground(.hidden)
                        .padding(5)
                        .background(.black.opacity(0.2),
                                    in: RoundedRectangle(cornerRadius: 10))
                    Button("导入配置") {
                        if store.restoreProfiles(from: restoreJSONString) {
                            profileDraft = store.activeProfile
                            restoreMessage = "已恢复游戏配置"
                            showingRestore = false
                            restoreJSONString = ""
                        } else {
                            restoreMessage = "无效的配置 JSON，原有数据未改变"
                        }
                    }.buttonStyle(.borderedProminent).tint(mint)
                }
                if !restoreMessage.isEmpty {
                    Text(restoreMessage).font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Button {
                if profileDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    profileDraft.name = "未命名游戏"
                }
                store.saveProfile(profileDraft)
                updateCaptureConfiguration()
            } label: {
                Label("保存游戏配置", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .background(mint, in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            panel {
                sectionTitle("本地字幕历史", icon: "clock.arrow.circlepath")
                Text("最多保存 200 条双语字幕，仅在本机，不保存截图。")
                    .font(.caption).foregroundStyle(.white.opacity(0.67))
                TextField("搜索原文、中文或游戏名", text: $historySearch)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    ShareLink(item: store.history.map {
                        "[\($0.game)] \($0.original)\n\($0.translated)"
                    }.joined(separator: "\n\n")) {
                        Label("导出文本", systemImage: "square.and.arrow.up")
                    }.buttonStyle(.bordered)
                    Button(role: .destructive) { store.clearHistory() } label: {
                        Label("清空历史", systemImage: "trash")
                    }.buttonStyle(.bordered)
                }
            }
            if filteredHistory.isEmpty {
                panel {
                    ContentUnavailableView("暂无记录", systemImage: "text.bubble",
                        description: Text("翻译成功后会自动保留最新双语对白"))
                }
            } else {
                ForEach(filteredHistory) { line in
                    panel {
                        HStack {
                            Text(line.game).font(.caption.bold()).foregroundStyle(mint)
                            Spacer()
                            Text(line.timestamp, style: .time)
                                .font(.caption2).foregroundStyle(.white.opacity(0.61))
                        }
                        Text(line.original).font(.subheadline).foregroundStyle(mint)
                            .textSelection(.enabled)
                        Text(line.translated).font(.headline).textSelection(.enabled)
                        Text("端到端 \(line.elapsedMs)ms")
                            .font(.caption2).foregroundStyle(.white.opacity(0.61))
                    }
                }
            }
        }
    }

    private var filteredHistory: [GameSubtitleLine] {
        let q = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.history }
        return store.history.filter {
            $0.original.localizedCaseInsensitiveContains(q)
                || $0.translated.localizedCaseInsensitiveContains(q)
                || $0.game.localizedCaseInsensitiveContains(q)
        }
    }

    private var screenshotPanel: some View {
        panel {
            sectionTitle("截图翻译备用模式", icon: "photo.on.rectangle")
            PhotosPicker(selection: $screenshot, matching: .images) {
                Label("选择一张游戏截图", systemImage: "photo.badge.plus")
            }.buttonStyle(.bordered)
            if !screenshotText.isEmpty {
                Button {
                    tab = 1
                } label: {
                    Label("查看截图完整双语清单", systemImage: "list.bullet.rectangle")
                }.buttonStyle(.borderedProminent).tint(mint)
                Text(screenshotText).font(.subheadline).foregroundStyle(mint)
                    .textSelection(.enabled)
                Button("在本机翻译截图") {
                    screenshotConfiguration = TranslationSession.Configuration(
                        source: Locale.Language(identifier: store.activeProfile.language),
                        target: Locale.Language(identifier: "zh-Hans"))
                }.buttonStyle(.borderedProminent).tint(mint)
            }
            if !screenshotResult.isEmpty {
                Text(screenshotResult).font(.headline).textSelection(.enabled)
            }
            if !screenshotStatus.isEmpty {
                Text(screenshotStatus).font(.caption)
                    .foregroundStyle(.white.opacity(0.73))
            }
        }
    }

    private var editingRegion: GameOCRBox {
        profileDraft.region(for: editingLayout)
    }

    private func saveEditingRegion(_ newValue: GameOCRBox) {
        if editingLayout == .portrait {
            profileDraft.region = newValue
        } else {
            profileDraft.landscapeRegion = newValue
        }
    }

    private func regionBinding(_ keyPath: WritableKeyPath<GameOCRBox, Double>) -> Binding<Double> {
        Binding(
            get: { editingRegion[keyPath: keyPath] },
            set: { value in
                var region = editingRegion
                region[keyPath: keyPath] = value
                saveEditingRegion(region)
            })
    }

    private var regionPreview: some View {
        GeometryReader { geometry in
            let region = editingRegion
            let bounds = region.rect
            let source = sampleImage?.size ?? (editingLayout == .portrait
                ? CGSize(width: 9, height: 16) : CGSize(width: 16, height: 9))
            let scale = min(geometry.size.width / max(1, source.width),
                            geometry.size.height / max(1, source.height))
            let scaledSize = CGSize(width: source.width * scale,
                                    height: source.height * scale)
            let pictureRect = CGRect(
                x: (geometry.size.width - scaledSize.width) / 2,
                y: (geometry.size.height - scaledSize.height) / 2,
                width: scaledSize.width, height: scaledSize.height)

            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.35))
                if let sampleImage {
                    Image(uiImage: sampleImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: scaledSize.width, height: scaledSize.height)
                        .position(x: pictureRect.midX, y: pictureRect.midY)
                } else {
                    Rectangle().fill(.white.opacity(0.035))
                        .frame(width: scaledSize.width, height: scaledSize.height)
                        .position(x: pictureRect.midX, y: pictureRect.midY)
                    Text("导入\(editingLayout.title)游戏截图\n或拖动绿框设置范围")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.65))
                        .position(x: pictureRect.midX, y: pictureRect.midY)
                }

                Rectangle()
                    .stroke(mint, lineWidth: 2.5)
                    .background(mint.opacity(0.12))
                    .frame(width: bounds.width * pictureRect.width,
                           height: bounds.height * pictureRect.height)
                    .position(x: pictureRect.minX + bounds.midX * pictureRect.width,
                              y: pictureRect.minY + (1 - bounds.midY) * pictureRect.height)

                if let excluded = profileDraft.excluded?.rect {
                    Rectangle()
                        .stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .frame(width: excluded.width * pictureRect.width,
                               height: excluded.height * pictureRect.height)
                        .position(x: pictureRect.minX + excluded.midX * pictureRect.width,
                                  y: pictureRect.minY + (1 - excluded.midY) * pictureRect.height)
                }
            }
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .coordinateSpace(name: "ocrPreview")
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("ocrPreview"))
                .onChanged { touch in
                    guard pictureRect.width > 0, pictureRect.height > 0 else { return }
                    var changed = region
                    let centerX = (touch.location.x - pictureRect.minX) / pictureRect.width
                    let centerY = 1 - (touch.location.y - pictureRect.minY) / pictureRect.height
                    changed.x = max(0, min(1 - changed.width, centerX - changed.width / 2))
                    changed.y = max(0, min(1 - changed.height, centerY - changed.height / 2))
                    saveEditingRegion(changed)
                })
        }
        .frame(height: editingLayout == .portrait ? 235 : 178)
    }

    private var bottomNavigation: some View {
        HStack(spacing: 0) {
            tabButton(0, "实时", icon: "dot.radiowaves.left.and.right")
            tabButton(1, "整屏文字", icon: "text.viewfinder")
            tabButton(2, "游戏配置", icon: "slider.horizontal.3")
            tabButton(3, "历史", icon: "clock.arrow.circlepath")
        }
        .padding(.top, 11).padding(.bottom, 6)
        .background(card)
    }

    private func tabButton(_ i: Int, _ text: String, icon: String) -> some View {
        Button { tab = i } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(text).font(.system(size: 11))
            }
            .foregroundStyle(tab == i ? mint : .white.opacity(0.62))
            .frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }

    private func control(_ name: String, value: Binding<Double>,
                         min: Double = 0) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.caption).frame(width: 83, alignment: .leading)
            Slider(value: value, in: min...1, step: 0.01).tint(mint)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(card.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.07), lineWidth: 1))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 16, weight: .bold))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.66))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }

    private func languageLabel(_ language: String) -> String {
        ["ja": "日语", "en": "英语", "ko": "韩语",
         "fr": "法语", "de": "德语", "es": "西班牙语",
         "pt": "葡萄牙语", "it": "意大利语", "ru": "俄语"][language] ?? language
    }

    private func updateCaptureConfiguration() {
        capture.configure(profile: store.activeProfile, performance: store.performance)
    }

    private func configureOverlay() {
        overlay.setMode(store.subtitleMode.rawValue, layout: store.pipLayout.rawValue)
        overlay.setFontScale(CGFloat(store.fontScale))
        syncMenuOverlay()
    }

    private func syncMenuOverlay() {
        let contents = menuCatalog.currentPage?.blocks ?? []
        overlay.setMenuEntries(contents.map { ($0.original, $0.chinese ?? "翻译中…") })
    }

    private func processScreenshot(_ photo: PhotosPickerItem?) async {
        guard let photo else { return }
        screenshotStatus = "正在执行本机 OCR…"
        do {
            guard let data = try await photo.loadTransferable(type: Data.self),
                  let bitmap = UIImage(data: data), let image = bitmap.cgImage else {
                screenshotStatus = "图片读取失败"
                return
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try GameLanguageSupport.setup(request, language: store.activeProfile.language)
            let orientation = store.activeProfile.screenRotation == .automatic
                ? bitmap.imageOrientation.gameVisionOrientation
                : store.activeProfile.screenRotation.imageOrientation
            try VNImageRequestHandler(cgImage: image, orientation: orientation)
                .perform([request])
            let results = (request.results ?? []).compactMap {
                item -> (String, CGRect, Double)? in
                guard let best = item.topCandidates(1).first,
                      !best.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }
                return (best.string, item.boundingBox, Double(best.confidence))
            }.sorted { lhs, rhs in
                abs(lhs.1.midY - rhs.1.midY) < 0.025
                    ? lhs.1.minX < rhs.1.minX : lhs.1.midY > rhs.1.midY
            }
            screenshotText = results.map { $0.0 }.joined(separator: "\n")
            screenshotResult = ""
            screenshotConfiguration = nil
            if results.isEmpty {
                screenshotStatus = "没有识别到文字"
            } else {
                let blocks: [GameMenuBlock] = results.enumerated().map { index, item in
                    GameMenuBlock(id: "photo-\(index)", original: item.0,
                                  chinese: nil, x: Double(item.1.minX),
                                  y: Double(item.1.minY), width: Double(item.1.width),
                                  height: Double(item.1.height), confidence: item.2)
                }
                menuCatalog.receive(
                    blocks, profileID: store.activeID,
                    gameName: store.activeProfile.name,
                    language: store.activeProfile.language,
                    glossary: GameRPGDictionary.glossary(for: store.activeProfile),
                    fingerprint: UInt64(Date().timeIntervalSince1970 * 1000),
                    ocrMilliseconds: 0, explicitlyRequested: true,
                    layout: (orientation == .left || orientation == .right)
                        ? (image.width >= image.height ? .portrait : .landscape)
                        : (image.width >= image.height ? .landscape : .portrait),
                    overrideProvider: .offline)
                screenshotStatus = "识别了 \(blocks.count) 条；请在“整屏文字”查看逐条中文"
            }
        } catch {
            screenshotStatus = "OCR 失败：" + error.localizedDescription
        }
    }

    private var onboardingSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 19) {
                Label("GameLingo 双语模式", systemImage: "captions.bubble.fill")
                    .font(.title2.bold()).foregroundStyle(mint)
                Text("① 按需准备系统语言包（IPA 不内置模型），用“双语测试”检查 PiP。\n\n② 授权整个屏幕，回到游戏；程序自动识别横竖屏并优先处理最新画面。\n\n③ 游戏配置 → 小窗排版，可选多行双语、中文高密度或菜单分页。\n\n④ 游戏配置可编辑横竖屏 OCR 区域，并一键启用勇者斗恶龙术语包。默认仍为本机翻译。\n\n⑤ “运行诊断”可对照原始 OCR、过滤后的原文和译文；“整屏文字”可查看完整菜单结果。")
                    .lineSpacing(4)
                Text("限制：系统可能暂停后台翻译，部分游戏可能限制屏幕录制；PiP 大小和位置由 iOS 管理。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("开始使用") {
                    store.onboardingComplete = true
                    showingOnboarding = false
                }.buttonStyle(.borderedProminent).tint(mint)
                    .frame(maxWidth: .infinity)
            }
            .padding(22)
            .navigationTitle("首次使用")
        }
    }
}
