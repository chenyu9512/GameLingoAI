import Foundation
import SwiftUI

/// Optional online provider settings. This View never sends game text until
/// the user actively tests and then enables a network provider.
@available(iOS 27.0, *)
@MainActor
struct GameTranslationSettingsView: View {
    @ObservedObject private var store = GameLingoStore.shared
    @ObservedObject private var tester = GameOnlineTranslator.shared
    @State private var choice: GameTranslationProvider = .offline
    @State private var draft = GameTranslationEndpoint()
    @State private var apiSecret = ""
    @State private var saveMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("翻译引擎与自定义 API", systemImage: "network")
                .font(.headline)
            HStack {
                Image(systemName: store.provider == .offline
                      ? "iphone.gen3" : "wifi")
                Text("当前启用：\(store.provider.title)")
                    .font(.subheadline.bold())
            }
            .foregroundStyle(store.provider == .offline ? Color.mint : Color.orange)
            Text("默认且推荐本机离线。选择在线模式后，只有你主动点“测试并启用”，游戏中 OCR 识别出的文字才会发送给该提供商；绝不上传原始截图。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("候选服务", selection: $choice) {
                ForEach(GameTranslationProvider.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.menu)

            if choice == .myMemory {
                Text("MyMemory：匿名免费额度约 5,000 字符/日、单次不超过 500 字节。服务可能限流，在线翻译可能比本机更慢。")
                    .font(.caption).foregroundStyle(.orange)
                Text("接口由 App 内置；不需要输入 API Key。")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if choice == .libreTranslate || choice == .customJSON {
                TextField("HTTPS 完整 API 地址", text: $draft.url)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key / Bearer Token（无密钥可留空）", text: $apiSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                if choice == .libreTranslate {
                    Text("兼容 POST /translate 的 LibreTranslate 实例；官方托管站一般要求付费密钥，自建或第三方服务依其规则。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("适用于 POST JSON，字段对应文字、源语言、目标语言。返回字段支持嵌套路径（如 data.0.translation）。")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("发送文字字段", text: $draft.textField)
                        .textFieldStyle(.roundedBorder)
                    TextField("源语言字段", text: $draft.sourceField)
                        .textFieldStyle(.roundedBorder)
                    TextField("目标语言字段", text: $draft.targetField)
                        .textFieldStyle(.roundedBorder)
                    TextField("返回译文字段路径", text: $draft.resultPath)
                        .textFieldStyle(.roundedBorder)
                    TextField("鉴权请求头", text: $draft.apiKeyHeader)
                        .textFieldStyle(.roundedBorder)
                    TextField("鉴权前缀（如 Bearer 后带空格）", text: $draft.apiKeyPrefix)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 10) {
                Button {
                    store.provider = .offline
                    choice = .offline
                    saveMessage = "已切回完全本机翻译"
                } label: {
                    Label("使用本机翻译", systemImage: "iphone.gen3")
                }
                .buttonStyle(.bordered)

                if choice != .offline {
                    Button {
                        Task { await testAndEnable() }
                    } label: {
                        Label(tester.isTesting ? "测试中…" : "测试并启用",
                              systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tester.isTesting)
                }
            }
            if tester.isTesting { ProgressView() }
            if !saveMessage.isEmpty {
                Text(saveMessage).font(.caption)
                    .foregroundStyle(store.provider == .offline ? .mint : .orange)
            }
            Text(tester.lastTestResult)
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .onAppear {
            choice = store.provider
            draft = store.endpoint
            apiSecret = GameAPIKeychain.read(for: choice)
        }
        .onChange(of: choice) { _, newChoice in
            apiSecret = GameAPIKeychain.read(for: newChoice)
            if newChoice == .libreTranslate && draft.url.isEmpty {
                draft.url = "https://libretranslate.com/translate"
            }
        }
    }

    private func testAndEnable() async {
        guard choice != .offline else { return }
        if choice == .libreTranslate || choice == .customJSON {
            guard GameAPIKeychain.save(apiSecret, for: choice) else {
                saveMessage = "无法保存 Keychain 凭据；在线模式未启用"
                return
            }
        }
        saveMessage = "仅发送原创测试句进行接口验证…"
        let ok = await tester.test(provider: choice, endpoint: draft)
        if ok {
            store.endpoint = draft
            store.provider = choice
            saveMessage = "联网测试成功；已由你主动启用 \(choice.title)"
        } else {
            saveMessage = "测试未通过；保留之前的翻译模式"
        }
    }
}
