import AppKit
import SwiftUI

enum ThemeChoice: String, CaseIterable, Identifiable {
    case automatic, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .automatic: L("Otomatik")
        case .light: L("Sıcak açık")
        case .dark: L("Koyu")
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }

    @MainActor func apply() {
        switch self {
        case .automatic: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct SadeSettingsView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @ObservedObject var updater: UpdateChecker
    @AppStorage("appearanceChoice") private var theme = ThemeChoice.automatic.rawValue
    @AppStorage("updateRepository") private var repository = UpdateChecker.defaultRepository
    @AppStorage("plannerLayout") private var layout = PlannerLayout.classic.rawValue
    @AppStorage("automaticUpdateChecks") private var automaticUpdates = true
    @AppStorage("didChoosePlannerLayout") private var didChooseLayout = false

    private var isTaskApp: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "Sade"
    }

    private var validRepository: Bool { GitHubRepository(repository) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(L("Ayarlar"), systemImage: "slider.horizontal.3")
                .font(.system(size: 23, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 9) {
                Text(L("Görünüm")).font(.headline)
                Picker(L("Tema"), selection: $theme) {
                    ForEach(ThemeChoice.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text(L("Otomatik görünüm, Mac’in açık ve koyu modunu izler."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Text(L("Dil")).font(.headline)
                Picker(L("Dil"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text(L("Dil seçimi iki uygulamada ayrı saklanır. Görev ve kategori adların değişmez."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if isTaskApp {
                VStack(alignment: .leading, spacing: 9) {
                    Text(L("Görev düzeni")).font(.headline)
                    Picker(L("Düzen"), selection: $layout) {
                        ForEach(PlannerLayout.allCases) { choice in Text(choice.title).tag(choice.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                Divider()
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(L("Güncellemeler")).font(.headline)
                    Spacer()
                    Text(L("Sürüm %@", String(updater.version))).font(.caption).foregroundStyle(.secondary)
                }
                Toggle(L("Güncellemeleri otomatik denetle"), isOn: $automaticUpdates)
                    .toggleStyle(.checkbox)
                Text(L("Açılışta ve uygulamaya döndüğünde günde en fazla bir kez kontrol edilir. İndirme ve kurulum sana aittir."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField(L("https://github.com/kullanıcı/depo"), text: $repository)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L("Güncelleme için GitHub deposu"))
                if repository.isEmpty {
                    Text(L("GitHub deposu eklendiğinde yayımlanan sürümleri buradan denetleyebilirsin."))
                        .font(.caption).foregroundStyle(.secondary)
                } else if !validRepository {
                    Text(L("GitHub depo adresini veya kullanıcı/depo biçimini kullan."))
                        .font(.caption).foregroundStyle(SadePalette.peach)
                }
                Button {
                    updater.check(repository: repository)
                } label: {
                    Label(L("Güncellemeleri denetle"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent))
                .disabled(!validRepository || updater.state == .checking)
                updateStatus
            }
            Spacer(minLength: 0)
        }
        .padding(25)
        .frame(width: 445, height: isTaskApp ? 650 : 565)
        .modifier(SadeTheme())
        .onAppear {
            if repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                repository = UpdateChecker.defaultRepository
            }
        }
        .onChange(of: repository) { _, _ in updater.reset(); updater.invalidateAutomaticHistory() }
        .onChange(of: automaticUpdates) { _, enabled in
            if enabled { updater.checkAutomatically() }
        }
        .onChange(of: appLanguage) { _, _ in updater.reset() }
        .onChange(of: layout) { _, _ in didChooseLayout = true }
    }

    @ViewBuilder private var updateStatus: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView(L("Denetleniyor…")).controlSize(.small)
        case .current:
            Label(L("Güncel sürümü kullanıyorsun."), systemImage: "checkmark.circle")
                .foregroundStyle(SadePalette.mint).font(.callout)
        case .available(let version, let url):
            HStack {
                Text(L("%@ sürümü hazır.", String(version))).font(.callout)
                Link(L("Sürümü aç"), destination: url).font(.callout.weight(.semibold))
            }
        case .message(let message):
            Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct UpdateCommands: Commands {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @ObservedObject var updater: UpdateChecker
    @Environment(\.openSettings) private var openSettings
    @AppStorage("updateRepository") private var repository = UpdateChecker.defaultRepository

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(L("Güncellemeleri denetle…")) {
                openSettings()
                updater.check(repository: repository)
            }
            .disabled(updater.state == .checking)
        }
    }
}

struct UpdateBanner: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        if case .available(let version, let url) = updater.state {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                Text(L("%@ sürümü hazır.", version)).font(.callout)
                Spacer()
                Link(L("Sürümü aç"), destination: url)
                    .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent))
            }
            .padding(12)
            .foregroundStyle(SadePalette.ink)
            .background(SadePalette.paper)
        }
    }
}
