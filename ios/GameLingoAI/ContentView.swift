import SwiftUI
import ReplayKit
import PhotosUI
import Vision
import Translation
import UIKit

struct ContentView: View {
    @StateObject private var inbox = SubtitleInbox()
    @StateObject private var subtitleWindow = FloatingSubtitleController()
    @State private var preparation: TranslationSession.Configuration?
    @State private var source: String = SharedSubtitles.sourceLanguage
    @State private var scanArea: String = SharedSubtitles.scanArea
    @State private var preparationMessage = "未安装语言包时，点击准备按钮让系统请求下载。"
    @State private var capturedImage: PhotosPickerItem?
    @State private var scannedText = ""
    @State private var photoStatus = ""
    @State private var photoTranslationConfiguration: TranslationSession.Configuration?
    @State private var photoTranslation = ""
    @State private var glossaryText = ""
    @State private var showGlossary = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    title
                    GroupBox {
                        HStack(spacing: 10) {
                            Image(systemName: SharedSubtitles.isGroupAvailable ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(SharedSubtitles.isGroupAvailable ? .mint : .orange)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(SharedSubtitles.isGroupAvailable ? "设备端私密翻译" : "字幕共享权限不可用")
                                    .font(.headline)
                                Text(SharedSubtitles.isGroupAvailable
                                     ? "不使用 API、账号或翻译服务器"
                                     : "当前签名没有 App Groups 权限，实时画中画字幕无法传递。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    GroupBox("一、准备手机本地语言包") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("游戏语言", selection: $source) {
                                Text("日语 → 简体中文").tag("ja")
                                Text("英语 → 简体中文").tag("en")
                                Text("韩语 → 简体中文").tag("ko")
                            }.pickerStyle(.menu)
                            Button("准备 / 下载本地翻译语言") {
                                preparation = TranslationSession.Configuration(
                                    source: Locale.Language(identifier: source),
                                    target: Locale.Language(identifier: "zh-Hans"))
                            }.buttonStyle(.borderedProminent)
                            Text(preparationMessage).font(.caption).foregroundStyle(.secondary)
                            Text("首次准备需要网络下载系统语言模型；之后翻译计算在 iPhone 上完成。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("二、系统广播识别游戏") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("先启动画中画小窗（实验功能），再点击系统广播按钮；选择 GameLingo Broadcast，切回游戏。")
                                .font(.subheadline)
                            FloatingSubtitlePreview(controller: subtitleWindow)
                                .frame(height: 158)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Button(subtitleWindow.isActive ? "关闭翻译小窗" : "开启同屏字幕小窗") {
                                if subtitleWindow.isActive { subtitleWindow.stop() }
                                else { subtitleWindow.start() }
                            }.buttonStyle(.borderedProminent)
                            Text(subtitleWindow.status).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                BroadcastPicker().frame(width: 60, height: 60)
                                VStack(alignment: .leading) {
                                    Text("点击左侧系统录屏按钮")
                                    Text("授权游戏画面采集，不需要其他设备")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("三、实时识别状态") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                metric(inbox.telemetry.frames, "采集帧")
                                metric(inbox.telemetry.scans, "OCR 扫描")
                                metric(inbox.telemetry.translated, "翻译成功")
                            }
                            Label(inbox.telemetry.phase, systemImage: "waveform.path.ecg")
                                .foregroundStyle(.mint).font(.subheadline.bold())
                            Text(inbox.telemetry.detail.isEmpty
                                 ? "开启录屏后，将显示真实识别和翻译状态。"
                                 : inbox.telemetry.detail)
                                .font(.caption).foregroundStyle(.secondary)
                            if inbox.telemetry.failures > 0 {
                                Text("翻译错误次数：\(inbox.telemetry.failures)")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("四、最新中文字幕") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(inbox.current.translated).font(.title3).fontWeight(.medium)
                            if !inbox.current.original.isEmpty {
                                Text(inbox.current.original).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(inbox.current.status).font(.caption).foregroundStyle(.secondary)
                            ForEach(inbox.history.prefix(4), id: \.updatedAt) { line in
                                Divider()
                                Text(line.translated)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("五、扫描范围") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("识别区域", selection: $scanArea) {
                                Text("对白优先").tag("bottom")
                                Text("全屏").tag("full")
                            }.pickerStyle(.segmented)
                            Text("对白在屏幕上方时切换全屏；通常使用对白优先以减少界面干扰。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("六、本地游戏专有名词") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("人名、技能名或菜单短语，整条文字完全匹配时优先按术语表显示。")
                                .font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("编辑术语表", isExpanded: $showGlossary) {
                                Text("格式：原文=中文；每行一条")
                                    .font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: $glossaryText)
                                    .frame(height: 125)
                                    .scrollContentBackground(.hidden)
                                Button("保存到本机") { SharedSubtitles.setGlossary(glossaryText) }
                                    .buttonStyle(.bordered)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("七、截图翻译（稳定备用方案）") {
                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $capturedImage, matching: .images) {
                                Label("从照片中选择游戏截图", systemImage: "photo")
                            }.buttonStyle(.bordered)
                            if !scannedText.isEmpty {
                                Text("识别文字：\n" + scannedText).font(.caption)
                                Button("在本机翻译截图文字") {
                                    photoTranslationConfiguration = TranslationSession.Configuration(
                                        source: Locale.Language(identifier: source),
                                        target: Locale.Language(identifier: "zh-Hans"))
                                }.buttonStyle(.borderedProminent)
                            }
                            if !photoTranslation.isEmpty { Text(photoTranslation).font(.headline) }
                            Text(photoStatus).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("无 API Key、无服务器、无本地 HTTP 端口。字幕广播、后台 PiP 和免费侧载的扩展兼容性尚未真机验证，不能保证所有游戏可用。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("GameLingo AI")
            .groupBoxStyle(GameLingoGroupStyle())
            .background(
                LinearGradient(
                    colors: [Color(red: 0.035, green: 0.055, blue: 0.12),
                             Color(red: 0.055, green: 0.12, blue: 0.18),
                             Color(red: 0.025, green: 0.045, blue: 0.09)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ).ignoresSafeArea()
            )
            .onChange(of: source) { _, newValue in SharedSubtitles.setSourceLanguage(newValue) }
            .onChange(of: scanArea) { _, newValue in SharedSubtitles.setScanArea(newValue) }
            .onAppear {
                glossaryText = UserDefaults(suiteName: SharedSubtitles.groupID)?
                    .string(forKey: "glossaryText") ?? ""
            }
            .onReceive(inbox.$current) { message in
                subtitleWindow.setText(message.translated)
            }
            .onChange(of: capturedImage) { _, image in
                Task { await recognizeScreenshot(image) }
            }
            .translationTask(preparation) { session in
                do {
                    try await session.prepareTranslation()
                    preparationMessage = "语言准备完成。如系统未下载请检查语言支持和网络。"
                } catch {
                    preparationMessage = "准备失败：\(error.localizedDescription)"
                }
            }
            .translationTask(photoTranslationConfiguration) { session in
                guard !scannedText.isEmpty else { return }
                do {
                    let reply = try await session.translate(scannedText)
                    photoTranslation = reply.targetText
                } catch {
                    photoStatus = "本地翻译失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private var title: some View {
        HStack(spacing: 14) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 26)).foregroundStyle(.mint)
                .frame(width: 56, height: 56)
                .background(.mint.opacity(0.16), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text("GameLingo AI").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("OFFLINE · 随身游戏翻译官")
                    .font(.caption.bold()).tracking(0.8).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func metric(_ count: Int, _ title: String) -> some View {
        VStack(spacing: 5) {
            Text("\(count)").font(.system(size: 21, weight: .bold, design: .rounded))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func recognizeScreenshot(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        photoStatus = "正在本机识别…"
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data), let cgImage = image.cgImage else {
                photoStatus = "读取截图失败"; return
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["ja-JP", "en-US", "ko-KR"]
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            scannedText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .prefix(12).joined(separator: "\n")
            photoTranslation = ""
            photoTranslationConfiguration = nil
            photoStatus = scannedText.isEmpty ? "没有识别到文字" : "识别完成，点击本机翻译"
        } catch { photoStatus = "识别失败：\(error.localizedDescription)" }
    }
}

private struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = (Bundle.main.bundleIdentifier ?? "com.example.GameLingoAI") + ".BroadcastUpload"
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

private struct GameLingoGroupStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label.font(.headline).foregroundStyle(.white)
            configuration.content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(red: 0.075, green: 0.115, blue: 0.19).opacity(0.94),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(.white.opacity(0.09), lineWidth: 1))
    }
}
