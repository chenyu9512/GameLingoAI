import Foundation
import Translation
import Security

enum GameTranslationProvider: String, CaseIterable, Codable, Identifiable {
    case offline, myMemory, libreTranslate, customJSON, azure, deepL, google
    var id: String { rawValue }
    var title: String {
        switch self {
        case .offline: return "本机翻译（默认）"
        case .myMemory: return "MyMemory 免费 API"
        case .libreTranslate: return "LibreTranslate 兼容服务"
        case .customJSON: return "自定义 JSON REST API"
        case .azure: return "Microsoft Translator (Azure)"
        case .deepL: return "DeepL API"
        case .google: return "Google Cloud Translation"
        }
    }
    var sendsDataOnline: Bool { self != .offline }
}

/// Configuration contains no secrets. API credentials are kept in Keychain.
struct GameTranslationEndpoint: Codable, Equatable {
    var url: String = ""
    var textField: String = "q"
    var sourceField: String = "source"
    var targetField: String = "target"
    var resultPath: String = "translatedText"
    var apiKeyHeader: String = "Authorization"
    var apiKeyPrefix: String = "Bearer "
    var region: String? = nil
    var dailyCharacterLimit: Int? = nil

    func validatedURL() throws -> URL {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = URLComponents(string: address),
              value.scheme?.lowercased() == "https",
              let host = value.host, !host.isEmpty,
              value.user == nil, value.password == nil,
              value.fragment == nil,
              let result = value.url
        else { throw GameOnlineTranslationError.invalidEndpoint }
        return result
    }
}

/// Secret data is never put into UserDefaults, screenshots, logs or URL query.
enum GameAPIKeychain {
    private static let service = "GameLingoDirect.OnlineTranslator.v1"
    static func read(for provider: GameTranslationProvider) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var output: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &output) == errSecSuccess,
              let data = output as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    static func save(_ secret: String, for provider: GameTranslationProvider) -> Bool {
        let value = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return true
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return true }
        if update != errSecItemNotFound { return false }
        var combined = query
        combined.merge(attributes) { _, new in new }
        return SecItemAdd(combined as CFDictionary, nil) == errSecSuccess
    }
}

enum GameOnlineTranslationError: LocalizedError {
    case invalidEndpoint, oversizedText, quotaExceeded, invalidResponse
    case http(Int), missingKey, emptyResult, unsafeFields

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "API 地址必须是合法的 HTTPS 地址，不允许嵌入账号和密码"
        case .oversizedText: return "请求包含太多字符，已阻止向免费接口发送"
        case .quotaExceeded: return "已达到该服务的本机字符保护上限，或免费接口返回了额度限制"
        case .invalidResponse: return "API 返回格式不符合配置；请检查译文字段路径"
        case .http(let code): return "在线接口响应 HTTP \(code)"
        case .missingKey: return "此 API 需要先设置密钥"
        case .emptyResult: return "接口未返回有效译文（可能限流或语言对不支持）"
        case .unsafeFields: return "API 字段名只能使用字母、数字、下划线或连接符"
        }
    }
}

@available(iOS 27.0, *)
@MainActor
final class GameOnlineTranslator: ObservableObject {
    static let shared = GameOnlineTranslator()

    @Published private(set) var lastTestResult = "尚未进行在线连接测试"
    @Published private(set) var isTesting = false
    @Published private(set) var lastTested: GameTranslationProvider?

    private var requestCache: [String: String] = [:]
    private let timeout: TimeInterval = 14
    private let anonymousDailyLimit = 4900

    func usedCharacters(for provider: GameTranslationProvider) -> Int {
        let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return UserDefaults.standard.integer(forKey: "GameLingo.API.Used.\(provider.rawValue).\(day)")
    }

    private func reserve(_ length: Int, provider: GameTranslationProvider,
                         limit: Int?) throws {
        guard let limit, limit > 0 else { return }
        let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let key = "GameLingo.API.Used.\(provider.rawValue).\(day)"
        let used = UserDefaults.standard.integer(forKey: key)
        guard used + length <= limit else {
            throw GameOnlineTranslationError.quotaExceeded
        }
        UserDefaults.standard.set(used + length, forKey: key)
    }

    private init() {}

    func test(provider: GameTranslationProvider,
              endpoint: GameTranslationEndpoint) async -> Bool {
        isTesting = true
        lastTestResult = "连接测试中：仅发送一条测试短句"
        defer { isTesting = false }
        do {
            let result = try await translate("勇者は旅に出た。",
                                             source: "ja", provider: provider,
                                             endpoint: endpoint, allowCache: false)
            guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  result != "勇者は旅に出た。" else {
                throw GameOnlineTranslationError.emptyResult
            }
            lastTested = provider
            lastTestResult = "测试成功：\(result)"
            return true
        } catch {
            lastTested = nil
            lastTestResult = "测试失败：\(error.localizedDescription)"
            return false
        }
    }

    func translate(_ text: String, source: String,
                   provider: GameTranslationProvider,
                   endpoint: GameTranslationEndpoint,
                   allowCache: Bool = true) async throws -> String {
        try Task.checkCancellation()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw GameOnlineTranslationError.emptyResult }
        if provider == .offline {
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: source),
                target: Locale.Language(identifier: "zh-Hans"))
            return try await session.translate(value).targetText
        }

        // Provider choice is explicit. Never silently send text over the network.
        let cacheKey = provider.rawValue + "|" + endpoint.url + "|" + source + "|" + value
        if allowCache, let cached = requestCache[cacheKey] { return cached }
        let pieces = try provider == .myMemory
            ? splitUTF8(value, maxBytes: 440)
            : splitUTF8(value, maxBytes: 1200)
        var results: [String] = []
        for piece in pieces {
            try Task.checkCancellation()
            let response = try await onlinePiece(piece, source: source,
                                                 provider: provider, endpoint: endpoint)
            results.append(response)
        }
        let combined = results.joined(separator: pieces.count > 1 ? "\n" : "")
        guard !combined.isEmpty else { throw GameOnlineTranslationError.emptyResult }
        if allowCache {
            requestCache[cacheKey] = combined
            if requestCache.count > 220 { requestCache.removeAll(keepingCapacity: true) }
        }
        return combined
    }

    private func onlinePiece(_ text: String, source: String,
                             provider: GameTranslationProvider,
                             endpoint: GameTranslationEndpoint) async throws -> String {
        try reserve(text.count, provider: provider, limit: endpoint.dailyCharacterLimit)
        switch provider {
        case .offline:
            throw GameOnlineTranslationError.invalidEndpoint
        case .myMemory:
            let count = text.count
            try reserveFreeCharacters(count)
            var url = URLComponents(string: "https://api.mymemory.translated.net/get")!
            url.queryItems = [
                URLQueryItem(name: "q", value: text),
                URLQueryItem(name: "langpair", value: source + "|zh-CN"),
                URLQueryItem(name: "mt", value: "1")
            ]
            guard let address = url.url else { throw GameOnlineTranslationError.invalidEndpoint }
            var request = URLRequest(url: address)
            request.timeoutInterval = timeout
            request.setValue("GameLingoDirect/3.3 (translation client)", forHTTPHeaderField: "User-Agent")
            let response = try await requestJSON(request)
            guard let status = response["responseStatus"] as? Int, status == 200,
                  let details = response["responseData"] as? [String: Any],
                  let translated = details["translatedText"] as? String
            else { throw GameOnlineTranslationError.invalidResponse }
            guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !translated.uppercased().contains("MYMEMORY WARNING"),
                  !translated.uppercased().contains("QUOTA EXCEEDED")
            else { throw GameOnlineTranslationError.quotaExceeded }
            return translated
        case .azure:
            let secret = GameAPIKeychain.read(for: provider)
            guard !secret.isEmpty else { throw GameOnlineTranslationError.missingKey }
            var components = URLComponents(string:
                "https://api.cognitive.microsofttranslator.com/translate")!
            components.queryItems = [
                URLQueryItem(name: "api-version", value: "3.0"),
                URLQueryItem(name: "from", value: source),
                URLQueryItem(name: "to", value: "zh-Hans")
            ]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(secret, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            if let region = endpoint.region?.trimmingCharacters(in: .whitespacesAndNewlines),
               !region.isEmpty {
                request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: [["Text": text]])
            let data = try await requestData(request)
            guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = array.first,
                  let translations = first["translations"] as? [[String: Any]],
                  let translated = translations.first?["text"] as? String,
                  !translated.isEmpty else { throw GameOnlineTranslationError.invalidResponse }
            return translated
        case .deepL:
            let secret = GameAPIKeychain.read(for: provider)
            guard !secret.isEmpty else { throw GameOnlineTranslationError.missingKey }
            // Legacy :fx API Free keys use the api-free host. Current
            // Developer plan keys use the production api.deepl.com endpoint.
            let host = secret.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
            var request = URLRequest(url: URL(string: "https://\(host)/v2/translate")!)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("DeepL-Auth-Key " + secret, forHTTPHeaderField: "Authorization")
            let body: [String: Any] = ["text": [text],
                                       "source_lang": source.uppercased(),
                                       "target_lang": "ZH-HANS"]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let json = try await requestJSON(request)
            guard let translations = json["translations"] as? [[String: Any]],
                  let translated = translations.first?["text"] as? String,
                  !translated.isEmpty else { throw GameOnlineTranslationError.invalidResponse }
            return translated
        case .google:
            let secret = GameAPIKeychain.read(for: provider)
            guard !secret.isEmpty else { throw GameOnlineTranslationError.missingKey }
            var url = URLComponents(string:
                "https://translation.googleapis.com/language/translate/v2")!
            url.queryItems = [URLQueryItem(name: "key", value: secret)]
            var request = URLRequest(url: url.url!)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["q": text, "source": source,
                                       "target": "zh-CN", "format": "text"]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let json = try await requestJSON(request)
            guard let outer = json["data"] as? [String: Any],
                  let list = outer["translations"] as? [[String: Any]],
                  let translated = list.first?["translatedText"] as? String,
                  !translated.isEmpty else { throw GameOnlineTranslationError.invalidResponse }
            return translated
        case .libreTranslate, .customJSON:
            let address = try endpoint.validatedURL()
            let key = GameAPIKeychain.read(for: provider)
            var request = URLRequest(url: address)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let language = source == "zh-Hans" ? "zh" : source
            var body: [String: String]
            if provider == .libreTranslate {
                body = ["q": text, "source": language, "target": "zh", "format": "text"]
                if !key.isEmpty { body["api_key"] = key }
            } else {
                for field in [endpoint.textField, endpoint.sourceField,
                              endpoint.targetField, endpoint.apiKeyHeader] {
                    guard field.range(of: "^[A-Za-z][A-Za-z0-9_-]{0,63}$",
                                      options: .regularExpression) != nil else {
                        throw GameOnlineTranslationError.unsafeFields
                    }
                }
                body = [endpoint.textField: text, endpoint.sourceField: language,
                        endpoint.targetField: "zh"]
                if !key.isEmpty {
                    request.setValue(endpoint.apiKeyPrefix + key,
                                     forHTTPHeaderField: endpoint.apiKeyHeader)
                }
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let json = try await requestJSON(request)
            let path = provider == .libreTranslate ? "translatedText" : endpoint.resultPath
            guard let text = resultAtPath(json, path: path),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw GameOnlineTranslationError.invalidResponse }
            return text
        }
    }

    private func requestData(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GameOnlineTranslationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GameOnlineTranslationError.http(http.statusCode)
        }
        guard data.count < 1_000_000 else {
            throw GameOnlineTranslationError.invalidResponse
        }
        return data
    }

    private func requestJSON(_ req: URLRequest) async throws -> [String: Any] {
        let data = try await requestData(req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw GameOnlineTranslationError.invalidResponse }
        return json
    }

    private func resultAtPath(_ json: [String: Any], path: String) -> String? {
        let parts = path.split(separator: ".").map(String.init)
        guard !parts.isEmpty && parts.count <= 8 else { return nil }
        var result: Any = json
        for part in parts {
            if let dictionary = result as? [String: Any], let next = dictionary[part] {
                result = next
            } else if let array = result as? [Any],
                      let index = Int(part), array.indices.contains(index) {
                result = array[index]
            } else { return nil }
        }
        return result as? String
    }

    private func splitUTF8(_ source: String, maxBytes: Int) throws -> [String] {
        guard source.utf8.count <= 30_000 else { throw GameOnlineTranslationError.oversizedText }
        var result: [String] = []
        var part = ""
        for char in source {
            let next = String(char)
            if part.utf8.count + next.utf8.count > maxBytes {
                if !part.isEmpty { result.append(part); part = "" }
                guard next.utf8.count <= maxBytes else {
                    throw GameOnlineTranslationError.oversizedText
                }
            }
            part += next
        }
        if !part.isEmpty { result.append(part) }
        return result
    }

    private func reserveFreeCharacters(_ characters: Int) throws {
        let day = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let key = "GameLingo.MyMemory.Used." + day
        let used = UserDefaults.standard.integer(forKey: key)
        guard used + characters <= anonymousDailyLimit else {
            throw GameOnlineTranslationError.quotaExceeded
        }
        UserDefaults.standard.set(used + characters, forKey: key)
    }
}
