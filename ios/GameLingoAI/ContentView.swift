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
    @State private var source: String = "ja"
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
                    GroupBox("三、实时翻译") {
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
                    GroupBox("四、本地游戏专有名词") {
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
                    GroupBox("五、备用：单张截图翻译（无需屏幕广播）") {
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
            .navigationTitle("GameLingo 本机翻译")
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
        VStack(alignment: .leading, spacing: 6) {
            Text("GameLingo AI · Offline").font(.largeTitle).bold()
            Text("一台 iPhone｜本地 OCR｜Apple 离线翻译").font(.subheadline).foregroundStyle(.secondary)
        }
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
