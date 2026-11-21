import AppKit
import SwiftUI

enum SplashProduct {
    case tasks, canvas

    var name: String { self == .tasks ? "Sade" : "Sade Tuval" }
    var accent: Color { self == .tasks ? SadePalette.accent : SadePalette.mint }
}

@MainActor
class StartupSplashDelegate: NSObject, NSApplicationDelegate {
    var splashProduct: SplashProduct { .tasks }
    private var splash: NSPanel?
    private var shownAt = Date()

    func applicationWillFinishLaunching(_ notification: Notification) {
        (ThemeChoice(rawValue: UserDefaults.standard.string(forKey: "appearanceChoice") ?? "") ?? .automatic).apply()
        let preference = "didShowStartupSplash"
        guard !UserDefaults.standard.bool(forKey: preference) else { return }
        let size = NSSize(width: 380, height: 204)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = L("%@ açılıyor", splashProduct.name)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: StartupSplash(product: splashProduct))
        panel.setContentSize(size)
        panel.center()
        splash = panel
        shownAt = Date()
        panel.orderFront(nil)
        UserDefaults.standard.set(true, forKey: preference)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard splash != nil else { return }
        let remaining = max(0, 0.72 - Date().timeIntervalSince(shownAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            self?.splash?.orderOut(nil)
            self?.splash = nil
        }
    }
}

private struct StartupSplash: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    let product: SplashProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 15) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)
                Text(product.name)
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            ProgressView()
                .progressViewStyle(.linear)
                .tint(product.accent)
                .accessibilityLabel(L("Uygulama açılıyor"))
            Text(L("Açılıyor…"))
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 380, height: 204)
        .background {
            RoundedRectangle(cornerRadius: 25)
                .fill(SadePalette.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 25)
                        .fill(LinearGradient(colors: [product.accent.opacity(0.16), .clear],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 25)
                        .strokeBorder(product.accent.opacity(0.24))
                }
        }
    }
}
