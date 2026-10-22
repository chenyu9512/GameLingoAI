import SwiftUI
import PhotosUI
import Vision
import Translation
import UIKit

// iOS 27 single-App user interface. No ReplayKit extension or App Groups.
@available(iOS 27.0, *)
@MainActor
struct DirectHomeView: View {
    @StateObject private var store = GameLingoStore.shared
    @ObservedObject private var capture = DirectGameCapture.shared
    @StateObject private var overlay = FloatingSubtitleController()

    @State private var tab = 0
    @State private var profileDraft = GameProfile(name: "默认游戏")
    @State private var sampleImage: UIImage?
    @State private var regionPhoto: PhotosPickerItem?
    @State private var translationPreparation: TranslationSession.Configuration?
    @State private var preparationState = "首次使用请准备系统离线语言包"
    @State private var screenshot: PhotosPickerItem?
    @State private var screenshotText = ""
    @State private var screenshotResult = ""
    @State private var screenshotStatus = ""
    @State private var screenshotConfiguration: TranslationSession.Configuration?
    @State private var historySearch = ""
    @State private var showingOnboarding = false
    @State private var showingRestore = false
    @State private var restoreJSONString = ""
    @State private var restoreMessage = ""

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
                        else if tab == 1 { gamePage }
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
            profileDraft = store.activeProfile
            updateCaptureConfiguration()
            configureOverlay()
            if !store.onboardingComplete { showingOnboarding = true }
        }
        .onChange(of: store.activeID) { _, _ in
            profileDraft = store.activeProfile
            updateCaptureConfiguration()
        }
        .onChange(of: store.profiles) { _, _ in updateCaptureConfiguration() }
        .onChange(of: store.performance) { _, _ in updateCaptureConfiguration() }
        .onChange(of: store.fontScale) { _, _ in configureOverlay() }
        .onChange(of: store.pipLayout) { _, _ in configureOverlay() }
        .onChange(of: store.subtitleMode) { _, _ in configureOverlay() }
        .onReceive(capture.$latestLine) { item in
            guard let item else { return }
            overlay.setBilingual(original: item.original, translated: item.translated)
        }
        .onChange(of: screenshot) { _, value in
            Task { await processScreenshot(value) }
        }
        .onChange(of: regionPhoto) { _, value in
            Task {
                guard let data = try? await value?.loadTransferable(type: Data.self) else { return }
                sampleImage = UIImage(data: data)
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
                Text("DIRECT 3.0  ·  双语实时翻译")
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
                    Text("离线").font(.caption.bold()).foregroundStyle(mint)
                }
                Text("上方游戏原文，下方中文翻译。所有 OCR 与翻译在本机进行。")
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
                .font(.caption).foregroundStyle(.white.opacity(0.67))
                Button {
                    translationPreparation = TranslationSession.Configuration(
                        source: Locale.Language(identifier: store.activeProfile.language),
                        target: Locale.Language(identifier: "zh-Hans"))
                } label: {
                    Label("准备 / 下载系统语言包", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Text(preparationState).font(.caption2).foregroundStyle(.white.opacity(0.68))
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
                ShareLink(item: capture.diagnostics) {
                    Label("分享无截图诊断报告", systemImage: "square.and.arrow.up")
                }.buttonStyle(.bordered)
            }

            screenshotPanel
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
                Picker("游戏原语言", selection: $profileDraft.language) {
                    Text("日语").tag("ja")
                    Text("英语").tag("en")
                    Text("韩语").tag("ko")
                }.pickerStyle(.segmented)
            }

            panel {
                sectionTitle("专属 OCR 识别区域", icon: "scope")
                Text("选择游戏截图，然后拖动绿色识别框定位对白。可用下方滑块精细调整。")
                    .font(.caption).foregroundStyle(.white.opacity(0.71))
                PhotosPicker(selection: $regionPhoto, matching: .images) {
                    Label("导入游戏截图用于定位", systemImage: "photo")
                }.buttonStyle(.bordered)
                regionPreview
                control("左边界 X", value: $profileDraft.region.x)
                control("底边界 Y", value: $profileDraft.region.y)
                control("宽度", value: $profileDraft.region.width, min: 0.12)
                control("高度", value: $profileDraft.region.height, min: 0.12)
                HStack {
                    Button("对白区域") { profileDraft.region = .dialogue }
                    Button("全屏") { profileDraft.region = .full }
                }.buttonStyle(.bordered)
                Text("坐标以 Vision 的左下角为原点；不要把 PiP 小窗放在识别框里。")
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

    private var regionPreview: some View {
        GeometryReader { geometry in
            let bounds = profileDraft.region.rect
            ZStack {
                Rectangle().fill(.black.opacity(0.4))
                if let sampleImage {
                    Image(uiImage: sampleImage).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Text("在截图上拖动绿框\n或使用滑块定位对白")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Rectangle().stroke(mint, lineWidth: 2.5)
                    .background(mint.opacity(0.12))
                    .frame(width: bounds.width * geometry.size.width,
                           height: bounds.height * geometry.size.height)
                    .position(x: bounds.midX * geometry.size.width,
                              y: (1 - bounds.midY) * geometry.size.height)
                if let ignored = profileDraft.excluded?.rect {
                    Rectangle().stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .frame(width: ignored.width * geometry.size.width,
                               height: ignored.height * geometry.size.height)
                        .position(x: ignored.midX * geometry.size.width,
                                  y: (1 - ignored.midY) * geometry.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .coordinateSpace(name: "ocrPreview")
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("ocrPreview"))
                .onChanged { value in
                    guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                    let w = profileDraft.region.width
                    let h = profileDraft.region.height
                    profileDraft.region.x = min(1 - w, max(0,
                        value.location.x / geometry.size.width - w / 2))
                    profileDraft.region.y = min(1 - h, max(0,
                        1 - value.location.y / geometry.size.height - h / 2))
                })
        }
        .frame(height: 180)
    }

    private var bottomNavigation: some View {
        HStack(spacing: 0) {
            tabButton(0, "实时", icon: "dot.radiowaves.left.and.right")
            tabButton(1, "游戏配置", icon: "slider.horizontal.3")
            tabButton(2, "历史", icon: "clock.arrow.circlepath")
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
        ["ja": "日语", "en": "英语", "ko": "韩语"][language] ?? language
    }

    private func updateCaptureConfiguration() {
        capture.configure(profile: store.activeProfile, performance: store.performance)
    }

    private func configureOverlay() {
        overlay.setMode(store.subtitleMode.rawValue, layout: store.pipLayout.rawValue)
        overlay.setFontScale(CGFloat(store.fontScale))
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
            request.recognitionLanguages = [
                ["ja": "ja-JP", "en": "en-US", "ko": "ko-KR"]
                    [store.activeProfile.language] ?? "ja-JP"
            ]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            screenshotText = (request.results ?? []).compactMap {
                $0.topCandidates(1).first?.string
            }.prefix(15).joined(separator: "\n")
            screenshotResult = ""
            screenshotConfiguration = nil
            screenshotStatus = screenshotText.isEmpty
                ? "没有识别到文字" : "已识别原文，点击本机翻译"
        } catch {
            screenshotStatus = "OCR 失败：" + error.localizedDescription
        }
    }

    private var onboardingSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 19) {
                Label("GameLingo 双语模式", systemImage: "captions.bubble.fill")
                    .font(.title2.bold()).foregroundStyle(mint)
                Text("① 在首页准备日语 / 英语 / 韩语对应的系统离线翻译包。\n\n② 点击“双语测试”，开启 PiP 确认原文在上、中文在下。\n\n③ 点击“授权捕获整个屏幕”，再切换回游戏。\n\n④ 在“游戏配置”中调整对白识别框、排除 UI 区域和术语表。\n\n⑤ 运行状态可以导出，但不会记录原始游戏画面。")
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
