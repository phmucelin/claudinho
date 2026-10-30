import Foundation

enum CodexError: Error {
    case noCredentials
    case unauthorized
    case http(Int)
    case decoding

    var message: String {
        switch self {
        case .noCredentials: "Login do Codex não encontrado."
        case .unauthorized: "Token do Codex expirou. Abra o `codex` em qualquer terminal que ele renova."
        case .http(let code): "A API do Codex respondeu HTTP \(code)."
        case .decoding: "Resposta do Codex em formato inesperado."
        }
    }
}

/// Same endpoint the Codex CLI hits for `/status`, authenticated with the ChatGPT login in ~/.codex/auth.json.
enum CodexAPI {
    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let authFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")

    static var isLoggedIn: Bool { (try? tokens()) != nil }

    static func fetch() async throws -> UsageSnapshot {
        let (token, account) = try tokens()
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let account { request.setValue(account, forHTTPHeaderField: "chatgpt-account-id") }
        request.setValue("Claudinho/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 401, 403: throw CodexError.unauthorized
        default: throw CodexError.http(status)
        }

        guard let raw = try? JSONDecoder().decode(RawCodexUsage.self, from: data) else { throw CodexError.decoding }
        return raw.snapshot
    }

    private static func tokens() throws -> (token: String, account: String?) {
        guard let data = try? Data(contentsOf: authFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String
        else { throw CodexError.noCredentials }
        return (token, tokens["account_id"] as? String)
    }
}

// MARK: - Wire format

private struct RawCodexUsage: Decodable {
    struct Window: Decodable {
        let used_percent: Double
        let limit_window_seconds: Double?
        let reset_at: Double?
    }

    struct RateLimit: Decodable {
        let primary_window: Window?
        let secondary_window: Window?
    }

    struct Additional: Decodable {
        let limit_name: String?
        let rate_limit: RateLimit?
    }

    let plan_type: String?
    let rate_limit: RateLimit?
    let additional_rate_limits: Lenient<[Additional]>?

    var snapshot: UsageSnapshot {
        var limits = windows(of: rate_limit, scope: nil)
        for extra in additional_rate_limits?.value ?? [] {
            limits += windows(of: extra.rate_limit, scope: extra.limit_name)
        }
        return UsageSnapshot(limits: limits, extra: nil, plan: plan_type?.capitalized)
    }

    private func windows(of rateLimit: RateLimit?, scope: String?) -> [UsageLimit] {
        [rateLimit?.primary_window, rateLimit?.secondary_window].compactMap { $0 }.map { window in
            let seconds = window.limit_window_seconds
            let isWeekly = (seconds ?? 0) >= 86400
            let base = switch seconds {
            case 18000?: "Sessão (5h)"
            case 604800?: "Semanal"
            case let s?: s >= 86400 ? "\(Int(s / 86400))d" : "\(Int(s / 3600))h"
            case nil: "Limite"
            }
            let title = scope.map { "\(base) · \($0)" } ?? (isWeekly && seconds == 604800 ? "Semanal · todos os modelos" : base)
            return UsageLimit(
                id: "codex-\(scope ?? "")-\(Int(seconds ?? 0))",
                kind: scope == nil ? (isWeekly ? "weekly_all" : "session") : "scoped",
                title: title,
                percent: window.used_percent,
                resetsAt: window.reset_at.map { Date(timeIntervalSince1970: $0) },
                window: seconds
            )
        }
    }
}

/// Decodes to nil instead of failing the whole response when a field has a shape we don't know.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
