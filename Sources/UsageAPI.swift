import Foundation

struct UsageLimit: Identifiable {
    let id: String
    let kind: String
    let title: String
    let percent: Double
    let resetsAt: Date?
    let window: TimeInterval?

    /// How far through the current window we are, i.e. the usage you'd be at with a perfectly even pace.
    func pace(now: Date) -> Double? {
        guard let resetsAt, let window else { return nil }
        let elapsed = 1 - resetsAt.timeIntervalSince(now) / window
        return min(max(elapsed, 0), 1)
    }
}

struct ExtraUsage {
    let used: Double
    let limit: Double?
    let currency: String
}

struct UsageSnapshot {
    let limits: [UsageLimit]
    let extra: ExtraUsage?
    var plan: String? = nil
}

enum UsageError: Error {
    case noCredentials
    case expired
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case http(Int)
    case decoding

    var message: String {
        switch self {
        case .noCredentials: "Login do Claude Code não encontrado. Rode `claude` e faça login."
        case .expired, .unauthorized: "Token expirou. Use o Claude Code em qualquer terminal que ele renova sozinho."
        case .rateLimited: "Muitas consultas, tentando de novo já já."
        case .http(let code): "A API respondeu HTTP \(code)."
        case .decoding: "Resposta da API em formato inesperado."
        }
    }
}

enum UsageAPI {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async throws -> UsageSnapshot {
        let token = try Credentials.accessToken()
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Claudinho/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 401, 403: throw UsageError.unauthorized
        case 429:
            let retry = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 120
            throw UsageError.rateLimited(retryAfter: retry)
        default: throw UsageError.http(status)
        }

        guard let raw = try? JSONDecoder().decode(RawUsage.self, from: data) else { throw UsageError.decoding }
        return raw.snapshot
    }
}

// MARK: - Credentials

enum Credentials {
    /// Reads the OAuth token Claude Code keeps in the login keychain. Going through `/usr/bin/security`
    /// (the same tool Claude Code uses to write it) avoids a keychain permission prompt.
    static func accessToken() throws -> String {
        let json = keychainJSON() ?? fileJSON()
        guard let json,
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw UsageError.noCredentials }

        if let expiresAt = oauth["expiresAt"] as? Double, expiresAt / 1000 < Date().timeIntervalSince1970 {
            throw UsageError.expired
        }
        return token
    }

    private static func keychainJSON() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private static func fileJSON() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: url)
    }
}

// MARK: - Wire format

private struct RawUsage: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
    }

    struct Limit: Decodable {
        struct Scope: Decodable {
            struct Model: Decodable { let display_name: String? }
            let model: Model?
        }

        let kind: String
        let group: String?
        let percent: Double
        let resets_at: String?
        let scope: Scope?
    }

    struct Extra: Decodable {
        let is_enabled: Bool?
        let monthly_limit: Double?
        let used_credits: Double?
        let currency: String?
        let decimal_places: Int?
    }

    let five_hour: Window?
    let seven_day: Window?
    let limits: [Limit]?
    let extra_usage: Extra?

    var snapshot: UsageSnapshot {
        UsageSnapshot(limits: parsedLimits, extra: parsedExtra)
    }

    private var parsedLimits: [UsageLimit] {
        if let limits, !limits.isEmpty {
            return limits.enumerated().map { index, limit in
                let model = limit.scope?.model?.display_name
                let title = switch limit.kind {
                case "session": "Sessão (5h)"
                case "weekly_all": "Semanal · todos os modelos"
                case "weekly_scoped": "Semanal · \(model ?? "escopo")"
                default: model.map { "\(limit.kind) · \($0)" } ?? limit.kind
                }
                return UsageLimit(
                    id: "\(index)-\(limit.kind)-\(model ?? "")",
                    kind: limit.kind,
                    title: title,
                    percent: limit.percent,
                    resetsAt: limit.resets_at.flatMap(parseDate),
                    window: limit.kind == "session" ? 5 * 3600 : (limit.group == "weekly" ? 7 * 86400 : nil)
                )
            }
        }

        // Older response shape without the `limits` array.
        var result: [UsageLimit] = []
        if let w = five_hour, let u = w.utilization {
            result.append(UsageLimit(id: "session", kind: "session", title: "Sessão (5h)", percent: u,
                                     resetsAt: w.resets_at.flatMap(parseDate), window: 5 * 3600))
        }
        if let w = seven_day, let u = w.utilization {
            result.append(UsageLimit(id: "weekly_all", kind: "weekly_all", title: "Semanal · todos os modelos", percent: u,
                                     resetsAt: w.resets_at.flatMap(parseDate), window: 7 * 86400))
        }
        return result
    }

    private var parsedExtra: ExtraUsage? {
        guard let extra = extra_usage, extra.is_enabled == true, let used = extra.used_credits else { return nil }
        let scale = pow(10, Double(extra.decimal_places ?? 2))
        return ExtraUsage(used: used / scale, limit: extra.monthly_limit.map { $0 / scale }, currency: extra.currency ?? "USD")
    }
}

/// The API sends microsecond timestamps ("…59.956497+00:00"), which ISO8601DateFormatter can't parse, so drop the fraction.
private func parseDate(_ string: String) -> Date? {
    let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    return ISO8601DateFormatter().date(from: trimmed)
}
