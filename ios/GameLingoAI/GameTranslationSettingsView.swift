import Foundation
import SwiftUI

@available(iOS 27.0, *)
@MainActor
struct GameTranslationSettingsView: View {
    @ObservedObject private var store = GameLingoStore.shared
    @ObservedObject private var tester = GameOnlineTranslator.shared
    @State private var choice: GameTranslationProvider = .offline
    @State private var draft = GameTranslationEndpoint()
    @State private var apiSecret = ""
    @State private var dailyLimit = "50000"
    @State private var saveMessage = ""
    @State private var advanced = false

    private var usesKey: Bool {
        ![GameTranslationProvider.offline, .myMemory].contains(choice)
    }
    private var usesURL: Bool { choice == .libreTranslate || choice == .customJSON }

    private var providerNote: String {
        switch choice {
        case .offline: return "本机默认引擎，不上传游戏 OCR 文字；语言资源由 iOS 按需下载。"
        case .myMemory: return "匿名免费约 5,000 字符/日，适合偶尔翻译；无需密钥，不适合长时间游戏。"
        case .azure: return "Microsoft Translator：支持全球资源只填 Key；区域或多服务资源还需要 Region。创建 F0 资源并遵守其官方额度。"
        case .deepL: return "DeepL Developer：新账户试用总计约 100 万字符（不是每月重置）；旧 API Free 计划条件不同。"
        case .google: return "Google Cloud Translation：使用 Cloud 项目 API Key，必须先启用相关 API 和计费。可能产生超额费用。"
        case .libreTranslate: return "LibreTranslate 兼容服务：自建实例或第三方 HTTPS 地址，部分实例需要 Key。"
        case .customJSON: return "高级 REST 适配：可自行设置 HTTPS 地址、请求字段、返回字段和鉴权格式。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: store.provider == .offline ? "iphone.gen3" : "network.badge.shield.half.filled")
                    .font(.title2).foregroundStyle(store.provider == .offline ? .mint : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("翻译引擎").font(.headline)
                    Text("正在使用：\(store.provider.title)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.provider == .offline ? "本机保护" : "已联网")
                    .font(.caption.bold())
                    .foregroundStyle(store.provider == .offline ? .mint : .orange)
            }
            Picker("翻译服务", selection: $choice) {
                ForEach(GameTranslationProvider.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.menu)
            Text(providerNote).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if choice != .offline {
                if usesKey {
                    SecureField("粘贴 API Key（保存在 iPhone Keychain）", text: $apiSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }
                if choice == .azure {
                    TextField("Region（全球 Translator 资源可留空）",
                              text: Binding(
                                get: { draft.region ?? "" },
                                set: { draft.region = $0 }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }
                if usesURL {
                    TextField("HTTPS API 地址", text: $draft.url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("每日字符保护限额").font(.caption)
                    Spacer()
                    TextField("50000", text: $dailyLimit)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 105)
                        .textFieldStyle(.roundedBorder)
                }
                Text("本机今日估算已请求 \(tester.usedCharacters(for: choice)) 字符。额度保护按本机统计，不等于服务商官方账单。设置 0 可关闭本地限制。")
                    .font(.caption2).foregroundStyle(.secondary)
                if choice == .customJSON {
                    DisclosureGroup(isExpanded: $advanced) {
                        VStack(spacing: 8) {
                            field("发送文字参数", text: $draft.textField)
                            field("源语言参数", text: $draft.sourceField)
                            field("目标语言参数", text: $draft.targetField)
                            field("响应译文字段路径", text: $draft.resultPath)
                            field("鉴权请求头", text: $draft.apiKeyHeader)
                            field("鉴权前缀（Bearer 后需空格）", text: $draft.apiKeyPrefix)
                        }
                    } label: {
                        Label("展开高级 API 映射", systemImage: "slider.horizontal.3")
                    }
                }
                Button {
                    Task { await verifyAndActivate() }
                } label: {
                    Label(tester.isTesting ? "正在验证…" : "测试连接并启用",
                          systemImage: "checkmark.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.mint)
                .disabled(tester.isTesting || (usesKey && apiSecret.isEmpty))
            }
            Button {
                store.provider = .offline
                choice = .offline
                saveMessage = "已切换本机离线；无需网络"
            } label: {
                Label("立即切回本机离线", systemImage: "iphone.gen3")
            }
            .buttonStyle(.bordered)

            if tester.isTesting { ProgressView("连接测试：仅发送一条固定测试句") }
            if !saveMessage.isEmpty {
                Text(saveMessage).font(.caption).foregroundStyle(.mint)
            }
            Text(tester.lastTestResult)
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("仅在你主动启用时向第三方发送 OCR 文字；从不发送原始游戏截图。在线服务可限流、下线或收费，默认不会自动切换到另一家。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear {
            choice = store.provider
            draft = store.endpoint
            apiSecret = GameAPIKeychain.read(for: choice)
            dailyLimit = String(store.endpoint.dailyCharacterLimit ?? 50000)
        }
        .onChange(of: choice) { _, newValue in
            apiSecret = GameAPIKeychain.read(for: newValue)
            saveMessage = ""
            if newValue == .libreTranslate && draft.url.isEmpty {
                draft.url = "https://libretranslate.com/translate"
            }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
    }

    private func verifyAndActivate() async {
        guard choice != .offline else { return }
        if usesKey && !GameAPIKeychain.save(apiSecret, for: choice) {
            saveMessage = "Keychain 保存失败，未启用在线模式"
            return
        }
        draft.dailyCharacterLimit = max(0, Int(dailyLimit) ?? 50000)
        saveMessage = "正在验证翻译接口…"
        let passed = await tester.test(provider: choice, endpoint: draft,
                                      target: store.targetLanguage)
        guard passed else {
            saveMessage = "连接测试未通过，原有翻译引擎保持不变"
            return
        }
        store.endpoint = draft
        store.provider = choice
        saveMessage = "接口测试成功；已启用 \(choice.title)"
    }
}
