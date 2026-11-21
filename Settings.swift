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

struct GitHubRepository: Equatable {
    let owner: String
    let name: String

    init?(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if value.contains("://") {
            guard let url = URLComponents(string: value), url.scheme == "https",
                  url.host?.lowercased() == "github.com", url.user == nil, url.password == nil,
                  url.port == nil, url.query == nil, url.fragment == nil else { return nil }
            path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            path = value
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              parts[0] != ".", parts[0] != "..", parts[1] != ".", parts[1] != ".." else { return nil }
        owner = String(parts[0])
        var repositoryName = String(parts[1])
        if repositoryName.hasSuffix(".git") { repositoryName.removeLast(4) }
        guard !repositoryName.isEmpty, repositoryName != ".", repositoryName != ".." else { return nil }
        name = repositoryName
    }

    var endpoint: URL { URL(string: "https://api.github.com/repos/\(owner)/\(name)/releases/latest")! }
    var releasesURL: URL { URL(string: "https://github.com/\(owner)/\(name)/releases/latest")! }
}

struct ReleaseVersion: Comparable {
    private let parts: [Int]

    init?(_ tag: String) {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.count <= 4,
              pieces.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }) else { return nil }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == pieces.count else { return nil }
        parts = numbers + Array(repeating: 0, count: 4 - numbers.count)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}

@MainActor final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle, checking, current, available(String, URL), message(String)
    }
    @Published private(set) var state: State = .idle
    private var request: Task<Void, Never>?

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func reset() {
        request?.cancel()
        request = nil
        state = .idle
    }

    func check(repository input: String) {
        reset()
        guard let repository = GitHubRepository(input) else {
            state = .message(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? L("Güncellemeler için GitHub depo adresini ekle.")
                             : L("Geçerli bir GitHub depo adresi gir."))
            return
        }
        let currentVersion = version
        state = .checking
        request = Task {
            do {
                var urlRequest = URLRequest(url: repository.endpoint)
                urlRequest.timeoutInterval = 15
                urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                urlRequest.setValue("Sade-Update-Check", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                guard !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                guard http.statusCode == 200 else {
                    state = .message(http.statusCode == 404
                                     ? L("Depo veya yayımlanmış bir sürüm bulunamadı. Adresi ve GitHub Releases bölümünü kontrol et.")
                                     : L("GitHub şu anda yanıt veremiyor (%@). Daha sonra tekrar dene.", String(http.statusCode)))
                    return
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                guard !release.draft, !release.prerelease,
                      let published = ReleaseVersion(release.tag_name),
                      let current = ReleaseVersion(currentVersion) else {
                    state = .message(L("Sürüm numarası karşılaştırılamadı. Sürüm etiketini 3.0 veya v3.0 biçiminde yayımla."))
                    return
                }
                state = published > current ? .available(release.tag_name, repository.releasesURL) : .current
            } catch {
                guard !Task.isCancelled else { return }
                state = .message(L("Güncellemeler denetlenemedi. İnternet bağlantısını kontrol edip tekrar dene."))
            }
        }
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }
}

struct SadeSettingsView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @ObservedObject var updater: UpdateChecker
    @AppStorage("appearanceChoice") private var theme = ThemeChoice.automatic.rawValue
    @AppStorage("updateRepository") private var repository = ""
    @AppStorage("plannerLayout") private var layout = PlannerLayout.classic.rawValue
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
        .frame(width: 445, height: isTaskApp ? 565 : 480)
        .modifier(SadeTheme())
        .onChange(of: repository) { _, _ in updater.reset() }
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
    @AppStorage("updateRepository") private var repository = ""

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
