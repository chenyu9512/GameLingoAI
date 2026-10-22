import SwiftUI
import PhotosUI
import Vision
import Translation
import UIKit

// Single-target iOS 27 UI. This target does not compile the old
// ReplayKit inbox, shared UserDefaults, or broadcast extension.
@available(iOS 27.0, *)
struct DirectHomeView: View {
    @StateObject private var overlay = FloatingSubtitleController()
    @ObservedObject private var capture = DirectGameCapture.shared

    @State private var sourceLanguage = UserDefaults.standard.string(forKey: "direct.sourceLanguage") ?? "ja"
    @State private var scanArea = UserDefaults.standard.string(forKey: "direct.scanArea") ?? "bottom"
    @State private var prepareConfiguration: TranslationSession.Configuration?
    @State private var preparationStatus = "请先准备所选语言包"
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var screenshotText = ""
    @State private var screenshotResult = ""
    @State private var screenshotStatus = ""
    @State private var screenshotTranslation: TranslationSession.Configuration?
    @State private var subtitleScale = (UserDefaults.standard.object(forKey: "pip.subtitle.scale") as? Double) ?? 1.0

    private let mint = Color(red: 0.24, green: 0.92, blue: 0.78)
    private let navy = Color(red: 0.035, green: 0.064, blue: 0.12)
    private let panel = Color(red: 0.085, green: 0.135, blue: 0.22)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [navy, Color(red: 0.035, green: 0.105, blue: 0.18), navy],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleSection
                    statusPanel
                    languagePanel
                    pipPanel
                    capturePanel
                    subtitlePanel
                    screenshotPanel
                    guidancePanel
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 18)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear {
            capture.configure(language: sourceLanguage, scanArea: scanArea)
            overlay.setFontScale(CGFloat(subtitleScale))
        }
        .onChange(of: subtitleScale) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "pip.subtitle.scale")
            overlay.setFontScale(CGFloat(newValue))
        }
        .onChange(of: sourceLanguage) { _, next in
            UserDefaults.standard.set(next, forKey: "direct.sourceLanguage")
            capture.configure(language: next, scanArea: scanArea)
            prepareConfiguration = nil
            preparationStatus = "语言已切换，请重新准备语言包"
        }
        .onChange(of: scanArea) { _, next in
            UserDefaults.standard.set(next, forKey: "direct.scanArea")
            capture.configure(language: sourceLanguage, scanArea: next)
        }
        .onReceive(capture.$latest) { text in
            if !text.isEmpty { overlay.setText(text) }
        }
        .onChange(of: selectedPhoto) { _, newPhoto in
            Task { await readScreenshot(newPhoto) }
        }
        .translationTask(prepareConfiguration) { session in
            do {
                try await session.prepareTranslation()
                preparationStatus = "系统离线语言包已准备"
            } catch {
                preparationStatus = "语言包准备失败：" + error.localizedDescription
            }
        }
        .translationTask(screenshotTranslation) { session in
            guard !screenshotText.isEmpty else { return }
            do {
                screenshotResult = try await session.translate(screenshotText).targetText
                screenshotStatus = "已在本机完成翻译"
            } catch {
                screenshotStatus = "翻译失败：" + error.localizedDescription
            }
        }
    }

    private var titleSection: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(mint.opacity(0.15))
                    .frame(width: 53, height: 53)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(mint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("GameLingo")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("DIRECT  •  iOS 27  •  ON DEVICE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.1).foregroundStyle(mint)
            }
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(mint)
                .font(.title2)
        }
    }

    private var statusPanel: some View {
        section {
            Label("独立直采版本", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(mint)
            Text("屏幕采集、文字识别和翻译都在同一 App 内执行。不需要广播扩展或跨进程共享权限。")
                .font(.caption).foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var languagePanel: some View {
        section {
            heading("翻译设置", systemName: "globe")
            Picker("识别语言", selection: $sourceLanguage) {
                Text("日语").tag("ja")
                Text("英语").tag("en")
                Text("韩语").tag("ko")
            }
            .pickerStyle(.segmented)
            Picker("识别区域", selection: $scanArea) {
                Text("对白优先").tag("bottom")
                Text("整个屏幕").tag("full")
            }.pickerStyle(.segmented)
            Button {
                prepareConfiguration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: sourceLanguage),
                    target: Locale.Language(identifier: "zh-Hans"))
            } label: {
                Label("准备系统翻译语言包", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .buttonStyle(.bordered)
            Text(preparationStatus).font(.caption).foregroundStyle(.white.opacity(0.7))
        }
    }

    private var pipPanel: some View {
        section {
            HStack {
                heading("悬浮中文字幕", systemName: "rectangle.on.rectangle")
                Spacer()
                Text(overlay.isActive ? "ON" : "OFF")
                    .font(.caption.monospaced()).foregroundStyle(overlay.isActive ? mint : .secondary)
            }
            FloatingSubtitlePreview(controller: overlay)
                .frame(height: 155)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("预览应正向显示。先开启画中画，再切换到游戏。")
                .font(.caption2).foregroundStyle(.white.opacity(0.72))
            HStack(spacing: 10) {
                Text("字号").font(.caption).foregroundStyle(.white.opacity(0.82))
                Slider(value: $subtitleScale, in: 0.8...1.4, step: 0.1)
                    .tint(mint)
                Text("\(Int(subtitleScale * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
                    .foregroundStyle(mint)
            }
            Button {
                overlay.setText("小窗测试：中文字幕居中显示，字号可调")
            } label: {
                Label("显示小窗测试字幕", systemImage: "textformat.size")
            }
            .buttonStyle(.bordered)
            Button {
                if overlay.isActive { overlay.stop() }
                else { overlay.start() }
            } label: {
                Label(overlay.isActive ? "关闭画中画" : "开启画中画",
                      systemImage: "rectangle.on.rectangle")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .background(mint, in: RoundedRectangle(cornerRadius: 11))
            Text(overlay.status).font(.caption).foregroundStyle(.white.opacity(0.76))
            HStack {
                Text("字幕帧输出：\(overlay.outputFrameCount)")
                    .font(.caption2.monospacedDigit())
                Spacer()
                Text(overlay.isActive ? "PiP 已启动" : "PiP 未启动")
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.63))
        }
    }

    private var capturePanel: some View {
        section {
            heading("全屏实时翻译", systemName: "viewfinder")
            DirectCapturePanel(language: sourceLanguage, scanArea: scanArea) { translated in
                overlay.setText(translated)
            }
            Text("点击授权时请选择整个屏幕。系统禁止录制的游戏画面可能无法识别。")
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
    }

    private var subtitlePanel: some View {
        section {
            heading("最新翻译", systemName: "character.bubble")
            Text(capture.latest.isEmpty ? "等待游戏字幕…" : capture.latest)
                .font(.system(size: 18, weight: .semibold))
                .textSelection(.enabled)
            if !capture.original.isEmpty {
                Text(capture.original)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.63))
                    .textSelection(.enabled)
            }
        }
    }

    private var screenshotPanel: some View {
        section {
            heading("截图翻译备用模式", systemName: "photo")
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("选取游戏截图", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.bordered)
            if !screenshotText.isEmpty {
                Text(screenshotText).font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .textSelection(.enabled)
                Button("翻译识别出的文字") {
                    screenshotTranslation = TranslationSession.Configuration(
                        source: Locale.Language(identifier: sourceLanguage),
                        target: Locale.Language(identifier: "zh-Hans"))
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            if !screenshotResult.isEmpty {
                Text(screenshotResult).font(.headline).textSelection(.enabled)
            }
            if !screenshotStatus.isEmpty {
                Text(screenshotStatus).font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var guidancePanel: some View {
        section {
            heading("使用提示", systemName: "info.circle")
            Text("1. 准备日语或英语离线语言包。\n2. 先打开画中画小窗。\n3. 授权捕获整个屏幕，再切回游戏。\n4. 查看 OCR、翻译次数和状态信息。\n5. 部分游戏会屏蔽系统屏幕捕获，无法保证所有场景可用。")
                .font(.caption).lineSpacing(5).foregroundStyle(.white.opacity(0.72))
        }
    }

    private func heading(_ title: String, systemName: String) -> some View {
        Label(title, systemImage: systemName)
            .font(.system(size: 15, weight: .bold))
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panel.opacity(0.91), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17)
                .stroke(.white.opacity(0.09), lineWidth: 1))
    }

    private func readScreenshot(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        screenshotStatus = "正在识别截图…"
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data), let cgImage = image.cgImage
            else {
                screenshotStatus = "图片读取失败"
                return
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [["ja": "ja-JP", "en": "en-US", "ko": "ko-KR"][sourceLanguage] ?? "ja-JP"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            screenshotText = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .prefix(16).joined(separator: "\n")
            screenshotResult = ""
            screenshotTranslation = nil
            screenshotStatus = screenshotText.isEmpty ? "没有识别到文字" : "已识别，请点击翻译"
        } catch {
            screenshotStatus = "OCR 失败：" + error.localizedDescription
        }
    }
}
