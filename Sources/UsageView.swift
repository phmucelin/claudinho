import SwiftUI

func usageColor(_ percent: Double) -> Color {
    switch percent {
    case ..<50: Color(red: 0.36, green: 0.72, blue: 0.45)
    case ..<80: Color(red: 0.93, green: 0.65, blue: 0.25)
    default: Color(red: 0.89, green: 0.33, blue: 0.29)
    }
}

struct UsageView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 14) {
                header(Image(nsImage: Clawd.image(pixel: 1.4)), "Claude", plan: store.claude.plan, showsSpinner: true)
                section(store.claude, now: context.date)
                if store.codexAvailable {
                    Divider()
                    header(Image(systemName: "terminal.fill"), "Codex", plan: store.codex.plan, showsSpinner: false)
                    section(store.codex, now: context.date)
                }
                Divider()
                footer(now: context.date)
            }
            .padding(16)
            .frame(width: 300)
        }
    }

    private func header(_ icon: Image, _ title: String, plan: String?, showsSpinner: Bool) -> some View {
        HStack(spacing: 8) {
            icon.font(.system(size: 13)).frame(width: 25)
            Text(title).font(.system(size: 13, weight: .semibold))
            if let plan {
                Text(plan).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if showsSpinner && store.isLoading { ProgressView().controlSize(.small) }
        }
    }

    @ViewBuilder
    private func section(_ usage: ProviderUsage, now: Date) -> some View {
        if let error = usage.error {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        if usage.limits.isEmpty && usage.error == nil {
            Text("Carregando…").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        ForEach(usage.limits) { limit in
            LimitRow(limit: limit, now: now)
        }
        if let extra = usage.extra {
            extraRow(extra)
        }
    }

    private func extraRow(_ extra: ExtraUsage) -> some View {
        HStack {
            Text("Créditos extras usados").font(.system(size: 12))
            Spacer()
            Text(money(extra.used, extra.currency) + (extra.limit.map { " / " + money($0, extra.currency) } ?? ""))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func footer(now: Date) -> some View {
        HStack(spacing: 12) {
            Text(updatedText(now: now)).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Atualizar agora")
            Menu {
                Picker("Na barra de menu", selection: $store.mode) {
                    ForEach(MenuBarMode.allCases) { Text($0.rawValue).tag($0) }
                }
                if store.codexAvailable {
                    Toggle("Mostrar Codex na barra", isOn: $store.showCodexInMenuBar)
                }
                Toggle("Abrir ao iniciar o Mac", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.launchAtLogin = $0 }
                ))
                Divider()
                Button("Abrir uso no claude.ai") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                }
                Button("Sair do Claudinho") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.borderless)
    }

    private func updatedText(now: Date) -> String {
        guard let updated = store.lastUpdated else { return "Ainda não atualizado" }
        let seconds = Int(now.timeIntervalSince(updated))
        return seconds < 60 ? "Atualizado há \(seconds)s" : "Atualizado há \(seconds / 60)min"
    }

    private func money(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency).locale(Locale(identifier: "pt_BR")))
    }
}

struct LimitRow: View {
    let limit: UsageLimit
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(limit.percent.rounded()))%")
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(usageColor(limit.percent))
            }
            UsageBar(fraction: limit.percent / 100, pace: limit.pace(now: now), color: usageColor(limit.percent))
            Text(resetText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var resetText: String {
        guard let resetsAt = limit.resetsAt else { return "" }
        let remaining = Int(resetsAt.timeIntervalSince(now))
        guard remaining > 0 else { return "Resetando…" }
        let days = remaining / 86400, hours = remaining % 86400 / 3600, minutes = remaining % 3600 / 60
        let countdown = days > 0 ? "\(days)d \(hours)h" : hours > 0 ? "\(hours)h \(minutes)min" : "\(minutes)min"
        guard days > 0 else { return "Reseta em \(countdown)" }
        let weekday = resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Locale(identifier: "pt_BR")))
        return "Reseta em \(countdown) · \(weekday)"
    }
}

/// Progress bar with a tick marking where an even pace through the window would be.
struct UsageBar: View {
    let fraction: Double
    let pace: Double?
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
                if let pace {
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 1.5, height: geo.size.height + 4)
                        .offset(x: geo.size.width * pace - 0.75)
                        .help("Ritmo: onde você estaria usando de forma uniforme até o reset")
                }
            }
        }
        .frame(height: 6)
    }
}
