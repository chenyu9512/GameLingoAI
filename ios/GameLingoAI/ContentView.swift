import SwiftUI
import ReplayKit
import PhotosUI
import Vision
import Translation
import UIKit

private enum GLStyle {
    static let mint = Color(red: 0.21, green: 0.93, blue: 0.78)
    static let blue = Color(red: 0.27, green: 0.57, blue: 1.0)
    static let text = Color(red: 0.91, green: 0.96, blue: 1)
    static let muted = Color(red: 0.58, green: 0.68, blue: 0.76)
    static let panel = Color(red: 0.075, green: 0.115, blue: 0.19)
}

struct ContentView: View {
    @StateObject private var inbox = SubtitleInbox()
    @StateObject private var overlay = FloatingSubtitleController()
    @State private var selectedTab = 0
    @State private var language = UserDefaults.standard.string(forKey: "direct.sourceLanguage") ?? SharedSubtitles.sourceLanguage
    @State private var scanArea = UserDefaults.standard.string(forKey: "direct.scanArea") ?? SharedSubtitles.scanArea
    @State private var preparation: TranslationSession.Configuration?
    @State private var preparationStatus = "未准备语言包"
    @State private var screenshot: PhotosPickerItem?
    @State private var screenshotOriginal = ""
    @State private var screenshotResult = ""
    @State private var screenshotStatus = ""
    @State private var screenshotTranslation: TranslationSession.Configuration?
    @State private var glossary = SharedSubtitles.glossaryText()
    @State private var showUsage = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.035, green: 0.058, blue: 0.11),
                                    Color(red: 0.055, green: 0.10, blue: 0.16),
                                    Color(red: 0.025, green: 0.045, blue: 0.09)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            Circle().fill(GLStyle.blue.opacity(0.16)).blur(radius: 90)
                .frame(width: 260, height: 260).offset(x: 160, y: -320)
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if selectedTab == 0 { dashboard }
                        else if selectedTab == 1 { archive }
                        else { preferences }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                tabBar
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(inbox.$current) { line in
            if line.updatedAt > 0 { overlay.setText(line.translated) }
        }
        .onChange(of: language) { _, newValue in
            SharedSubtitles.setSourceLanguage(newValue)
            UserDefaults.standard.set(newValue, forKey: "direct.sourceLanguage")
            preparation = nil
            preparationStatus = "语言已切换，请准备对应语言包"
        }
        .onChange(of: scanArea) { _, newValue in
            SharedSubtitles.setScanArea(newValue)
            UserDefaults.standard.set(newValue, forKey: "direct.scanArea")
        }
        .onChange(of: screenshot) { _, newValue in
            Task { await readScreenshot(newValue) }
        }
        .translationTask(preparation) { session in
            do {
                try await session.prepareTranslation()
                preparationStatus = "语言包已经准备完毕，可以开始翻译"
            } catch {
                preparationStatus = "语言包准备失败：\(error.localizedDescription)"
            }
        }
        .translationTask(screenshotTranslation) { session in
            guard !screenshotOriginal.isEmpty else { return }
            do {
                screenshotResult = try await session.translate(screenshotOriginal).targetText
                screenshotStatus = "截图翻译完成 · 本机处理"
            } catch {
                screenshotStatus = "翻译失败：\(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showUsage) { usageSheet }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 17).fill(GLStyle.mint.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 23, weight: .semibold)).foregroundStyle(GLStyle.mint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("GameLingo").font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("OFFLINE  ·  游戏语言助手").font(.system(size: 10, weight: .bold))
                    .tracking(2).foregroundStyle(GLStyle.muted)
            }
            Spacer()
            Button { showUsage = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title2).foregroundStyle(GLStyle.muted)
                    .frame(width: 42, height: 42)
            }
            .accessibilityLabel("使用说明")
        }
    }

    private var dashboard: some View {
        VStack(spacing: 17) {
            HStack {
                Label("单机本地翻译", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(GLStyle.mint)
                Spacer()
                Text("V2.1 · ReplayKit")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(GLStyle.muted)
            }
            .padding(.horizontal, 4)

            capsulePanel {
                HStack(spacing: 12) {
                    Image(systemName: connectionOkay ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title2).foregroundStyle(connectionOkay ? GLStyle.mint : .orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(connectionOkay ? "字幕共享通道正常" : "字幕共享通道不可用")
                            .font(.system(size: 15, weight: .semibold))
                        Text(connectionOkay ? "App 与录屏扩展可共享字幕与设置" : "侧载签名缺少 App Groups 权限，同屏自动字幕无法传递")
                            .font(.system(size: 11)).foregroundStyle(GLStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            capsulePanel {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("翻译语言", icon: "character.book.closed.fill")
                    Picker("原文语言", selection: $language) {
                        Text("日语 → 中文").tag("ja")
                        Text("英语 → 中文").tag("en")
                        Text("韩语 → 中文").tag("ko")
                    }.pickerStyle(.segmented)
                    Button {
                        preparation = TranslationSession.Configuration(
                            source: Locale.Language(identifier: language),
                            target: Locale.Language(identifier: "zh-Hans"))
                    } label: {
                        Label("准备 / 下载系统语言包", systemImage: "arrow.down.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    Text(preparationStatus)
                        .font(.system(size: 11)).foregroundStyle(GLStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            capsulePanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        sectionHeading("同屏字幕", icon: "captions.bubble.fill")
                        Spacer()
                        Text(overlay.isActive ? "ACTIVE" : "STANDBY")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(overlay.isActive ? GLStyle.mint : GLStyle.muted)
                    }
                    FloatingSubtitlePreview(controller: overlay)
                        .frame(height: 154)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13)
                            .stroke(GLStyle.mint.opacity(0.22), lineWidth: 1))
                    Text("预览方向：↑ ABC 123 应当正向显示。小窗方向与此预览一致。")
                        .font(.system(size: 11)).foregroundStyle(GLStyle.muted)
                    Button {
                        if overlay.isActive { overlay.stop() }
                        else { overlay.start() }
                    } label: {
                        Label(overlay.isActive ? "关闭画中画字幕" : "开启画中画字幕",
                              systemImage: overlay.isActive ? "xmark.circle.fill" : "rectangle.on.rectangle")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(GLStyle.mint, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.black)
                    Text(overlay.status).font(.system(size: 11)).foregroundStyle(GLStyle.muted)
                    Divider().overlay(.white.opacity(0.08))
                    HStack(spacing: 14) {
                        BroadcastPicker().frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("开始系统屏幕共享")
                                .font(.system(size: 14, weight: .semibold))
                            Text("点击左侧圆形按钮 → 选择 GameLingo Broadcast → 开始广播 → 切回游戏")
                                .font(.system(size: 11)).foregroundStyle(GLStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            capsulePanel {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("翻译运行状态", icon: "waveform.path.ecg")
                    HStack(spacing: 8) {
                        metric(inbox.telemetry.frames, "采集帧")
                        metric(inbox.telemetry.scans, "文字扫描")
                        metric(inbox.telemetry.translated, "翻译成功")
                    }
                    HStack(spacing: 7) {
                        Circle().fill(isBroadcastRecent ? GLStyle.mint : .orange)
                            .frame(width: 7, height: 7)
                        Text(inbox.telemetry.phase)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(isBroadcastRecent ? "刚刚更新" : "暂无实时状态")
                            .font(.system(size: 10)).foregroundStyle(GLStyle.muted)
                    }
                    Text(inbox.telemetry.detail.isEmpty ? "启动录屏后，这里会显示是否收到了游戏画面。" : inbox.telemetry.detail)
                        .font(.system(size: 11)).foregroundStyle(GLStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if inbox.telemetry.failures > 0 {
                        Label("累计错误：\(inbox.telemetry.failures) 次", systemImage: "exclamationmark.circle")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }
            }

            capsulePanel {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeading("最新中文字幕", icon: "text.bubble")
                    Text(inbox.current.translated)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                    if !inbox.current.original.isEmpty {
                        Text(inbox.current.original)
                            .font(.system(size: 12)).foregroundStyle(GLStyle.muted)
                            .textSelection(.enabled)
                    }
                    Text(inbox.current.status)
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(GLStyle.mint)
                }
            }
        }
    }

    private var archive: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("最近的游戏字幕").font(.title2.bold())
            Text("仅保存在当前 App 内存中，不上传任何翻译内容。")
                .font(.caption).foregroundStyle(GLStyle.muted)
            if inbox.history.isEmpty {
                capsulePanel {
                    ContentUnavailableView("暂无翻译记录", systemImage: "text.bubble",
                                           description: Text("开始识别游戏后，将显示最近的字幕。"))
                }
            }
            ForEach(inbox.history, id: \.updatedAt) { line in
                capsulePanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(line.translated).font(.headline)
                        Text(line.original).font(.subheadline).foregroundStyle(GLStyle.muted)
                        Text(Date(timeIntervalSince1970: line.updatedAt), style: .time)
                            .font(.caption2).foregroundStyle(GLStyle.mint)
                    }
                }
            }
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("个性化设置").font(.title2.bold())
            capsulePanel {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("文字识别范围", icon: "viewfinder")
                    Picker("识别区域", selection: $scanArea) {
                        Text("对白优先").tag("bottom")
                        Text("全屏").tag("full")
                    }.pickerStyle(.segmented)
                    Text("对白优先扫描画面下部，减少识别游戏地图与画中画字幕的干扰。部分游戏对白在顶部时选全屏。")
                        .font(.caption).foregroundStyle(GLStyle.muted)
                }
            }
            capsulePanel {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("游戏专有名词", icon: "text.book.closed")
                    Text("原文=中文，每行一条。仅完全匹配时替换，避免误改剧情句子。")
                        .font(.caption).foregroundStyle(GLStyle.muted)
                    TextEditor(text: $glossary)
                        .scrollContentBackground(.hidden)
                        .frame(height: 120)
                        .padding(6)
                        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 9))
                    Button("保存术语表") { SharedSubtitles.setGlossary(glossary) }
                        .buttonStyle(.borderedProminent).tint(GLStyle.blue)
                }
            }
            capsulePanel {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("截图翻译", icon: "photo.on.rectangle")
                    PhotosPicker(selection: $screenshot, matching: .images) {
                        Label("选择一张游戏截图", systemImage: "photo.badge.plus")
                    }.buttonStyle(.borderedProminent).tint(GLStyle.blue)
                    if !screenshotOriginal.isEmpty {
                        Text(screenshotOriginal).font(.caption).foregroundStyle(GLStyle.muted)
                            .textSelection(.enabled)
                        Button("在 iPhone 上翻译") {
                            screenshotTranslation = TranslationSession.Configuration(
                                source: Locale.Language(identifier: language),
                                target: Locale.Language(identifier: "zh-Hans"))
                        }.buttonStyle(.bordered)
                    }
                    if !screenshotResult.isEmpty {
                        Text(screenshotResult).font(.headline).textSelection(.enabled)
                    }
                    if !screenshotStatus.isEmpty {
                        Text(screenshotStatus).font(.caption).foregroundStyle(GLStyle.muted)
                    }
                }
            }
            capsulePanel {
                VStack(alignment: .leading, spacing: 7) {
                    sectionHeading("隐私与兼容性", icon: "lock.shield")
                    Text("无 ChatGPT API、无转发端口。系统语言包首次需要联网下载。")
                    Text("屏幕广播扩展与主 App 的实时共享需要双方有效的 App Groups 授权。画中画为系统播放功能，无法保证每个游戏或免费侧载签名下持续刷新。")
                }.font(.caption).foregroundStyle(GLStyle.muted)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tab(0, "实时翻译", "dot.radiowaves.left.and.right")
            tab(1, "字幕记录", "clock.arrow.circlepath")
            tab(2, "设置", "slider.horizontal.3")
        }
        .padding(.top, 12).padding(.bottom, 6)
        .background(GLStyle.panel.opacity(0.94))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }
    private func tab(_ index: Int, _ title: String, _ symbol: String) -> some View {
        Button { selectedTab = index } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 21, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selectedTab == index ? GLStyle.mint : GLStyle.muted)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func sectionHeading(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 15, weight: .bold))
            .foregroundStyle(GLStyle.text)
    }
    private func capsulePanel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GLStyle.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.075), lineWidth: 1))
    }
    private func metric(_ count: Int, _ label: String) -> some View {
        VStack(spacing: 6) {
            Text("\(count)").font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label).font(.system(size: 10)).foregroundStyle(GLStyle.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }
    private var connectionOkay: Bool { SharedSubtitles.isGroupAvailable }
    private var isBroadcastRecent: Bool {
        inbox.telemetry.updatedAt > 0 &&
        Date().timeIntervalSince1970 - inbox.telemetry.updatedAt < 12
    }
    private var usageSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("1 · 下载所选语言的本地翻译包。\n\n2 · 在首页开启画中画字幕，确认 ABC ↑ 方向正确。\n\n3 · 点击系统录屏按钮，选择 GameLingo Broadcast，开始共享。\n\n4 · 返回游戏，查看翻译。没有更新时返回 App 查看采集帧与错误信息。\n\n5 · 如果显示字幕共享通道不可用，需修复侧载签名中的 App Groups 权限。")
                    .font(.body).lineSpacing(5)
                Spacer()
            }
            .padding(22)
            .navigationTitle("使用说明")
            .toolbar { Button("完成") { showUsage = false } }
        }.presentationDetents([.medium, .large])
    }

    private func readScreenshot(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        screenshotStatus = "正在本机识别截图…"
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data), let cgImage = image.cgImage else {
                screenshotStatus = "无法读取图片"; return
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [["ja": "ja-JP", "en": "en-US", "ko": "ko-KR"][language] ?? "ja-JP"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            screenshotOriginal = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .prefix(18).joined(separator: "\n")
            screenshotResult = ""
            screenshotTranslation = nil
            screenshotStatus = screenshotOriginal.isEmpty ? "未识别到文字" : "识别完成，点击本机翻译"
        } catch { screenshotStatus = "识别失败：\(error.localizedDescription)" }
    }
}

private struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 54, height: 54))
        picker.preferredExtension = (Bundle.main.bundleIdentifier ?? "com.example.GameLingoAI") + ".BroadcastUpload"
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
