import AppKit
import SwiftUI

final class CanvasTaskLibrary: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    private let file: URL

    init(root: URL) {
        file = root.appendingPathComponent("tasks.json")
    }

    func refresh() {
        guard FileManager.default.fileExists(atPath: file.path) else {
            tasks = []
            return
        }
        // Sade replaces the file atomically; Tuval only reads the latest snapshot.
        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(SavedData.self, from: data),
              snapshot.tasks != tasks else { return }
        tasks = snapshot.tasks
    }
}

final class CanvasAppDelegate: StartupSplashDelegate {
    override var splashProduct: SplashProduct { .canvas }
}

@main struct SadeCanvasApp: App {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @NSApplicationDelegateAdaptor(CanvasAppDelegate.self) private var delegate
    @StateObject private var workspace = WorkspaceStore(root: SadeData.root)
    @StateObject private var taskLibrary = CanvasTaskLibrary(root: SadeData.root)
    @State private var launchError: String?
    @StateObject private var updater = UpdateChecker()

    var body: some Scene {
        Window("Sade Tuval", id: "canvas") {
            WorkspaceView(openTask: openTask)
                .environment(\.locale, AppLanguage.current.locale)
                .environmentObject(workspace)
                .environmentObject(taskLibrary)
                .tint(SadePalette.accent)
                .frame(minWidth: 730, minHeight: 520)
                .modifier(SadeTheme())
                .modifier(WindowEntrance())
                .onAppear(perform: taskLibrary.refresh)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    taskLibrary.refresh()
                }
                .alert(L("Görev açılamadı"), isPresented: Binding(
                    get: { launchError != nil },
                    set: { if !$0 { launchError = nil } }
                )) {
                    Button(L("Tamam")) { launchError = nil }
                } message: {
                    Text(launchError ?? "")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
        .commands { UpdateCommands(updater: updater) }
        Settings {
            SadeSettingsView(updater: updater)
        }
    }

    private func openTask(_ task: TaskItem) {
        Task {
            do { try await SadeCompanion.open(.tasks, taskID: task.id) }
            catch { launchError = error.localizedDescription }
        }
    }
}
