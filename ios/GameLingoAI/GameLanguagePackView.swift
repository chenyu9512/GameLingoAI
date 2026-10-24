import SwiftUI
import Translation

/// The system owns the actual download. The Translation framework does not
/// expose transferred bytes or a reliable download percentage to applications.
@available(iOS 27.0, *)
@MainActor
struct GameLanguagePackView: View {
    @State private var source = "ja"
    @State private var manualLanguage = ""
    @State private var isAdvanced = false
    @State private var isChecking = false
    @State private var isRequesting = false
    @State private var availability: LanguageAvailability.Status?
    @State private var lastError = ""
    @State private var taskConfiguration: TranslationSession.Configuration?
    @Environment(\.scenePhase) private var scenePhase

    private let target = Locale.Language(identifier: "zh-Hans")
    private let options: [(String, String)] = [
        ("日语", "ja"), ("英语", "en"), ("韩语", "ko"),
        ("繁体中文", "zh-Hant"), ("法语", "fr"), ("德语", "de"),
        ("西班牙语", "es"), ("葡萄牙语", "pt"), ("意大利语", "it"),
        ("俄语", "ru"), ("泰语", "th"), ("越南语", "vi"),
        ("阿拉伯语", "ar")
    ]
    private var effectiveSource: String {
        (isAdvanced && !manualLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
         ? manualLanguage : source).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var installed: Bool { availability == .installed }
    private var unsupported: Bool { availability == .unsupported }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("离线语言资源", systemImage: "character.book.closed.fill")
                    .font(.headline)
                Spacer()
                stateLabel
            }
            Text("选择原文语言，目标固定为简体中文。语言包由 iOS 安装在本机。")
                .font(.subheadline).foregroundStyle(.secondary)
            Picker("源语言", selection: $source) {
                ForEach(options, id: \.1) { item in
                    Text(item.0).tag(item.1)
                }
            }
            .pickerStyle(.menu)
            .disabled(isRequesting)
            DisclosureGroup("高级：自定义语言代码", isExpanded: $isAdvanced) {
                TextField("BCP-47，例如 nl、id、zh-Hant", text: $manualLanguage)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Text("不是每种 OCR 语言都受系统离线翻译支持。实际状态以系统检测为准。")
                    .font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline)
            HStack(spacing: 10) {
                Image(systemName: installed ? "checkmark.circle.fill" :
                        unsupported ? "xmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(installed ? .green : (unsupported ? .orange : .secondary))
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle).font(.subheadline.bold())
                    Text(statusDescription).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isChecking || isRequesting { ProgressView() }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            if !lastError.isEmpty {
                Text(lastError).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button {
                    requestDownload()
                } label: {
                    Label(installed ? "已经安装" : "请求系统下载 / 安装",
                          systemImage: installed ? "checkmark.circle.fill" : "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(installed || unsupported || isRequesting || isChecking || effectiveSource.isEmpty)
                Button {
                    Task { await refreshStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise").frame(minWidth: 34, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .disabled(isChecking || isRequesting)
                .accessibilityLabel("重新检查语言包")
            }
            Text("下载进度由 iOS 系统弹窗显示。这里使用真实状态和活动指示器，不伪造百分比。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { Task { await refreshStatus() } }
        .onChange(of: source) { _, _ in
            lastError = ""
            availability = nil
            Task { await refreshStatus() }
        }
        .onChange(of: manualLanguage) { _, _ in
            if isAdvanced {
                availability = nil
                Task { await refreshStatus() }
            }
        }
        .onChange(of: isAdvanced) { _, _ in
            availability = nil
            Task { await refreshStatus() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
        }
        .translationTask(taskConfiguration) { session in
            isRequesting = true
            lastError = ""
            defer { isRequesting = false }
            do {
                try await session.prepareTranslation()
                // prepareTranslation may return while iOS is still downloading.
                // Only LanguageAvailability.installed means ready.
                await refreshStatus()
            } catch {
                lastError = "系统语言资源准备失败：" + error.localizedDescription
                await refreshStatus()
            }
        }
    }

    private var stateLabel: some View {
        Text(installed ? "已就绪" :
             unsupported ? "不支持" :
             isRequesting ? "系统处理中" :
             isChecking ? "检查中" : "待准备")
            .font(.caption.bold())
            .foregroundStyle(installed ? .green : .secondary)
    }
    private var statusTitle: String {
        if isRequesting { return "等待 iOS 下载或安装" }
        if isChecking { return "正在检查可用性" }
        if installed { return "已安装，可以本机翻译" }
        if unsupported { return "系统不支持此语言对" }
        if availability == .supported { return "语言包未就绪" }
        return "尚未检查"
    }
    private var statusDescription: String {
        if installed { return "语言资源已安装，识别出的文字可交给本机翻译。" }
        if unsupported { return "可以继续使用 OCR，但需要换用支持的翻译语言或自行配置在线翻译。" }
        if isRequesting { return "请查看系统弹窗；离开应用后也可以重新检查安装状态。" }
        return "如果需要下载安装，请通过下方按钮交给系统处理。"
    }
    private func refreshStatus() async {
        guard !effectiveSource.isEmpty else {
            availability = nil
            return
        }
        let requested = effectiveSource
        isChecking = true
        defer { isChecking = false }
        let result = await LanguageAvailability().status(
            from: Locale.Language(identifier: requested), to: target)
        guard requested == effectiveSource else { return }
        availability = result
    }
    private func requestDownload() {
        guard !isRequesting && !isChecking && !unsupported && !installed else { return }
        let language = Locale.Language(identifier: effectiveSource)
        if taskConfiguration == nil {
            taskConfiguration = TranslationSession.Configuration(source: language, target: target)
        } else {
            taskConfiguration?.source = language
            taskConfiguration?.target = target
            taskConfiguration?.invalidate()
        }
        isRequesting = true
        lastError = ""
    }
}
