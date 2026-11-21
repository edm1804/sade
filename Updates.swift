import Foundation
import Combine

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
    static let defaultRepository = "https://github.com/edm1804/sade"
    private let session: URLSession
    private let preferences: UserDefaults
    private let versionOverride: String?

    init(session: URLSession = .shared, preferences: UserDefaults = .standard, version: String? = nil) {
        self.session = session
        self.preferences = preferences
        self.versionOverride = version
        if let tag = preferences.string(forKey: "cachedReleaseTag"),
           preferences.string(forKey: "cachedReleaseRepository") == repositoryInput,
           let published = ReleaseVersion(tag), let current = ReleaseVersion(self.version), published > current,
           let repository = GitHubRepository(repositoryInput) {
            state = .available(tag, repository.releasesURL)
        }
    }

    private var repositoryInput: String {
        let value = preferences.string(forKey: "updateRepository")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? Self.defaultRepository : value
    }

    func invalidateAutomaticHistory() {
        for key in ["lastAutomaticUpdateCheck", "cachedReleaseTag", "cachedReleaseRepository"] {
            preferences.removeObject(forKey: key)
        }
    }

    func checkAutomatically(now: Date = Date()) {
        guard preferences.object(forKey: "automaticUpdateChecks") as? Bool ?? true,
              state != .checking, GitHubRepository(repositoryInput) != nil else { return }
        if let last = preferences.object(forKey: "lastAutomaticUpdateCheck") as? Date {
            let elapsed = now.timeIntervalSince(last)
            if elapsed >= 0 && elapsed < 24 * 60 * 60 { return }
        }
        preferences.set(now, forKey: "lastAutomaticUpdateCheck")
        check(repository: repositoryInput)
    }

    @Published private(set) var state: State = .idle
    private var request: Task<Void, Never>?

    var version: String {
        versionOverride ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
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
                let (data, response) = try await session.data(for: urlRequest)
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
                preferences.set(release.tag_name, forKey: "cachedReleaseTag")
                preferences.set(input.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "cachedReleaseRepository")
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

