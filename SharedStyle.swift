import SwiftUI

enum SadePalette {
    static let canvas = adaptive(0xF6F1E9, 0x191B23)
    static let sidebar = adaptive(0xEDE6DC, 0x20232D)
    static let pages = adaptive(0xF1EAE0, 0x222631)
    static let paper = adaptive(0xFFFCF7, 0x282D39)
    static let line = adaptive(0xD8CFC2, 0x434B5D)
    static let selection = adaptive(0xE8DDF1, 0x3E3756)
    static let accent = adaptive(0x70478E, 0xD4B7F4)
    static let mint = adaptive(0x326A53, 0xA1D8BC)
    static let peach = adaptive(0x995130, 0xEFBA97)
    static let rose = adaptive(0x984C68, 0xE9B2C8)
    static let blue = adaptive(0x40668A, 0xA7C8EF)
    static let honey = adaptive(0x795824, 0xE4CC98)
    static let boardSurface = adaptive(0xF9F3E8, 0x1D2029)
    static let ink = adaptive(0x322D28, 0xEEEFF5)
    static let secondaryInk = adaptive(0x70655B, 0xB2BACD)
    static let buttonInk = adaptive(0xFFFDF9, 0x232032)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255,
                alpha: 1
            )
        })
    }
}

struct CanvasToolButtonStyle: ButtonStyle {
    var accent: Color
    var featured = false
    var selected = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Control(configuration: configuration, accent: accent, featured: featured, selected: selected, compact: compact)
    }

    private struct Control: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
        var configuration: Configuration
        var accent: Color
        var featured: Bool
        var selected: Bool
        var compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(featured ? SadePalette.buttonInk : accent)
                .padding(.horizontal, compact ? 1 : 10)
                .padding(.vertical, compact ? 1 : 6)
                .background {
                    Capsule().fill(featured ? accent.opacity(hovered ? 0.86 : 1) : accent.opacity(backgroundOpacity))
                }
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.42)
                .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.94 : hovered && isEnabled ? 1.035 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.75), value: configuration.isPressed)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: hovered)
                .onHover { hovered = $0 }
        }

        private var backgroundOpacity: Double {
            if configuration.isPressed { return 0.25 }
            if selected { return 0.19 }
            if hovered && isEnabled { return 0.14 }
            return 0.04
        }
    }
}

struct SadeTheme: ViewModifier {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("appearanceChoice") private var choice = ThemeChoice.automatic.rawValue

    func body(content: Content) -> some View {
        content
            .environment(\.locale, AppLanguage.current.locale)
            .foregroundStyle(SadePalette.ink)
            .tint(SadePalette.accent)
            .background(SadePalette.canvas)
            .preferredColorScheme((ThemeChoice(rawValue: choice) ?? .automatic).scheme)
            .onChange(of: choice, initial: true) { _, value in
                (ThemeChoice(rawValue: value) ?? .automatic).apply()
            }
    }
}


struct WindowEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = true
    @State private var entranceTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .opacity(entered || reduceMotion ? 1 : 0.72)
            .scaleEffect(entered || reduceMotion ? 1 : 0.992)
            .offset(y: entered || reduceMotion ? 0 : 5)
            .background {
                MainWindowPresentation(onShow: animateEntrance)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .onDisappear {
                entranceTask?.cancel()
                entered = true
            }
    }

    private func animateEntrance() {
        entranceTask?.cancel()
        guard !reduceMotion else { entered = true; return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { entered = false }
        entranceTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.23)) { entered = true }
        }
    }
}

private struct MainWindowPresentation: NSViewRepresentable {
    var onShow: () -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onShow = onShow
    }

    final class ObserverView: NSView {
        var onShow: (() -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var presented = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            presented = false
            guard let window else { return }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.didDeminiaturizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.checkVisibility()
                })
            }
            for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.presented = false
                })
            }
            DispatchQueue.main.async { [weak self] in self?.checkVisibility() }
        }

        private func checkVisibility() {
            let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
            if visible && !presented { onShow?() }
            presented = visible
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
