import Foundation
import ServiceManagement

enum MenuBarMode: String, CaseIterable, Identifiable {
    case sessionAndWeekly = "5h + semanal"
    case all = "Todos os limites"
    case highest = "Só o mais alto"
    case iconOnly = "Só o ícone"

    var id: String { rawValue }
}

/// Latest known state for one service (Claude or Codex).
struct ProviderUsage {
    var limits: [UsageLimit] = []
    var extra: ExtraUsage?
    var plan: String?
    var error: String?

    func menuBarText(_ mode: MenuBarMode) -> String {
        guard !limits.isEmpty else { return "" }
        let pct = { (limit: UsageLimit) in "\(Int(limit.percent.rounded()))%" }
        switch mode {
        case .iconOnly:
            return ""
        case .highest:
            return limits.max { $0.percent < $1.percent }.map(pct) ?? ""
        case .all:
            return limits.map(pct).joined(separator: " · ")
        case .sessionAndWeekly:
            let picked = limits.filter { $0.kind == "session" || $0.kind == "weekly_all" }
            return (picked.isEmpty ? limits : picked).map(pct).joined(separator: " · ")
        }
    }

    var highestPercent: Double { limits.map(\.percent).max() ?? 0 }
}

@MainActor
final class UsageStore: ObservableObject {
    static let pollInterval: TimeInterval = 60

    @Published private(set) var claude = ProviderUsage()
    @Published private(set) var codex = ProviderUsage()
    @Published private(set) var codexAvailable = CodexAPI.isLoggedIn
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false
    @Published var mode: MenuBarMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "menuBarMode") }
    }
    @Published var showCodexInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showCodexInMenuBar, forKey: "showCodexInMenuBar") }
    }

    private var timer: Timer?
    private var backoffUntil: Date?

    init() {
        mode = UserDefaults.standard.string(forKey: "menuBarMode").flatMap(MenuBarMode.init) ?? .sessionAndWeekly
        showCodexInMenuBar = UserDefaults.standard.bool(forKey: "showCodexInMenuBar")
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Refreshes unless the last successful fetch is younger than `ifOlderThan` seconds.
    func refresh(ifOlderThan age: TimeInterval = 0) {
        if isLoading { return }
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < age { return }
        if let backoffUntil, backoffUntil > Date() { return }

        isLoading = true
        codexAvailable = CodexAPI.isLoggedIn
        let fetchCodex = codexAvailable
        Task {
            defer { isLoading = false }
            async let claudeResult = capture { try await UsageAPI.fetch() }
            async let codexResult = fetchCodex ? capture { try await CodexAPI.fetch() } : nil

            switch await claudeResult {
            case .success(let snapshot):
                claude = ProviderUsage(limits: snapshot.limits, extra: snapshot.extra, plan: snapshot.plan)
                backoffUntil = nil
            case .failure(let error):
                claude.error = message(for: error)
                if case UsageError.rateLimited(let retryAfter) = error {
                    backoffUntil = Date().addingTimeInterval(retryAfter)
                }
            }

            switch await codexResult {
            case .success(let snapshot)?:
                codex = ProviderUsage(limits: snapshot.limits, extra: snapshot.extra, plan: snapshot.plan)
            case .failure(let error)?:
                codex.error = message(for: error)
            case nil:
                codex = ProviderUsage()
            }

            lastUpdated = Date()
        }
    }

    /// Text shown next to the icon in the menu bar (the Codex part is drawn separately with its own glyph).
    var menuBarText: String { claude.menuBarText(mode) }
    var codexMenuBarText: String? {
        guard showCodexInMenuBar, codexAvailable, mode != .iconOnly else { return nil }
        let text = codex.menuBarText(mode)
        return text.isEmpty ? nil : text
    }

    var highestPercent: Double {
        max(claude.highestPercent, codexMenuBarText == nil ? 0 : codex.highestPercent)
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                claude.error = "Não deu pra mudar o login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case let error as UsageError: error.message
        case let error as CodexError: error.message
        default: "Sem conexão: \(error.localizedDescription)"
        }
    }
}

private func capture(_ operation: () async throws -> UsageSnapshot) async -> Result<UsageSnapshot, Error> {
    do { return .success(try await operation()) } catch { return .failure(error) }
}
