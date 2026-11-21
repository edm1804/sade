import AppKit

enum SadeCompanion {
    enum Product {
        case tasks, canvas

        var name: String {
            self == .tasks ? "Sade" : "Sade Tuval"
        }

        var bundleID: String {
            self == .tasks ? "com.erdem.sade" : "com.erdem.sade.canvas"
        }
    }

    static func applicationURL(_ product: Product) -> URL? {
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent(product.name + ".app", isDirectory: true)
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: product.bundleID)
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: product.bundleID)
            .filter { !$0.isTerminated }
            .compactMap(\.bundleURL)
        return (running + [sibling, installed].compactMap { $0 }).first { url in
            guard let bundle = Bundle(url: url), bundle.bundleIdentifier == product.bundleID else { return false }
            if product == .canvas { return true }
            let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
            return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(SadeTaskLink.scheme) == true }
        }
    }

    @MainActor
    static func open(_ product: Product, taskID: UUID? = nil) async throws {
        guard let application = applicationURL(product) else {
            throw LaunchError.missing(product.name)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        if let taskID {
            _ = try await NSWorkspace.shared.open([SadeTaskLink.url(for: taskID)],
                                                  withApplicationAt: application,
                                                  configuration: configuration)
        } else {
            _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration)
        }
    }

    private enum LaunchError: LocalizedError {
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .missing(let name):
                return L("%@ bulunamadı. Paketteki güncel %@.app dosyasını açabilirsin.", String(name), String(name))
            }
        }
    }
}
