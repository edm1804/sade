import SwiftUI
import AppKit
import AVFoundation
import UserNotifications

enum DayStatus: Equatable {
    case overdue, soon, today, finished, empty
    var icon: String {
        switch self {
        case .overdue: return "exclamationmark.circle.fill"
        case .soon: return "bell.badge.fill"
        case .today: return "checklist"
        case .finished: return "checkmark.seal.fill"
        case .empty: return "leaf"
        }
    }
    var title: String {
        switch self {
        case .overdue: return L("Zamanı gelen görev var")
        case .soon: return L("Bir görev yaklaşıyor")
        case .today: return L("Bugün yapılacaklar var")
        case .finished: return L("Bugünün işleri tamam")
        case .empty: return L("Bugün için görev yok")
        }
    }
    static func includes(_ task: TaskItem, now: Date, calendar: Calendar = .current) -> Bool {
        if task.done {
            return calendar.isDate(task.completedAt ?? task.created, inSameDayAs: now)
        }
        let dates = [task.scheduledDay, task.reminder, task.timerEnd].compactMap { $0 }
        if !dates.isEmpty {
            return dates.contains { calendar.isDate($0, inSameDayAs: now) }
        }
        return calendar.isDate(task.created, inSameDayAs: now)
    }
    static func resolve(_ tasks: [TaskItem], now: Date) -> DayStatus {
        let open = tasks.filter { !$0.done && includes($0, now: now) }
        let dates = open.flatMap { [$0.reminder, $0.timerEnd].compactMap { $0 } }
        if dates.contains(where: { Calendar.current.isDate($0, inSameDayAs: now) && $0 <= now }) { return .overdue }
        if dates.contains(where: { $0 > now && $0.timeIntervalSince(now) <= 15 * 60 }) { return .soon }
        if !open.isEmpty { return .today }
        if tasks.contains(where: { $0.done && includes($0, now: now) }) { return .finished }
        return .empty
    }
}
final class Store: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var tasks: [TaskItem] = [] { didSet { save() } }
    @Published var categories = ["Genel", "Günlük", "İçerik", "Oyun geliştirme"] { didSet { save() } }
    @Published var message: String?
    @Published var now = Date()
    private var clock: Timer?
    private var canSave = false
    let root: URL
    override init() {
        root = SadeData.root
        super.init()
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("tasks.json")
            if FileManager.default.fileExists(atPath: url.path) {
                let saved = try JSONDecoder().decode(SavedData.self, from: Data(contentsOf: url))
                tasks = saved.tasks; categories = saved.categories
            }
            canSave = true
        } catch { message = L("Kayıtlar okunamadı: %@", String(error.localizedDescription)) }
        UNUserNotificationCenter.current().delegate = self
        clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.now = Date() }
        RunLoop.main.add(clock!, forMode: .common)
    }
    func save() {
        guard canSave else { return }
        do { try JSONEncoder().encode(SavedData(tasks: tasks, categories: categories)).write(to: root.appendingPathComponent("tasks.json"), options: .atomic) }
        catch { DispatchQueue.main.async { self.message = L("Değişiklikler kaydedilemedi: %@", String(error.localizedDescription)) } }
    }
    func cancel(_ id: UUID, kind: String) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString + kind]) }
    func schedule(_ task: TaskItem, at date: Date, kind: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { allowed, error in
            guard allowed else { DispatchQueue.main.async { self.message = L("Bildirim izni kapalı. Sistem Ayarları → Bildirimler → Sade bölümünden açabilirsin.") }; return }
            DispatchQueue.main.async {
                guard let current = self.tasks.first(where: { $0.id == task.id }), !current.done,
                      (kind == "timer" ? current.timerEnd : current.reminder) == date else { return }
                let content = UNMutableNotificationContent()
                content.title = kind == "timer" ? L("Süre doldu") : L("Görev zamanı")
                content.body = current.title; content.sound = .default
                let request = UNNotificationRequest(identifier: task.id.uuidString + kind, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false))
                center.add(request) { error in
                    if let error { DispatchQueue.main.async { self.message = L("Bildirim kurulamadı: %@", String(error.localizedDescription)) } }
                }
            }
        }
    }
    func refreshNotificationLanguage() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                for request in requests {
                    guard let task = self.tasks.first(where: {
                        request.identifier == $0.id.uuidString + "timer" || request.identifier == $0.id.uuidString + "reminder"
                    }), !task.done else { continue }
                    let timer = request.identifier.hasSuffix("timer")
                    guard let date = timer ? task.timerEnd : task.reminder,
                          date > Date(),
                          let content = request.content.mutableCopy() as? UNMutableNotificationContent else { continue }
                    content.title = timer ? L("Süre doldu") : L("Görev zamanı")
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
                    center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
                }
            }
        }
    }
    func complete(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].done.toggle()
        tasks[i].completedAt = tasks[i].done ? Date() : nil
        if tasks[i].done { cancel(id, kind: "timer"); cancel(id, kind: "reminder"); tasks[i].timerEnd = nil; tasks[i].reminder = nil }
    }
    func delete(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        cancel(id, kind: "timer"); cancel(id, kind: "reminder")
        for voice in task.voices { try? FileManager.default.removeItem(at: root.appendingPathComponent(voice.file)) }
        tasks.removeAll { $0.id == id }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound, .list]) }
}
final class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var recordingTask: UUID?
    @Published var playing: UUID?
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var file: URL?
    func record(task: UUID, root: URL) {
        AVAudioApplication.requestRecordPermission { allowed in
            DispatchQueue.main.async {
                guard allowed else { self.error = L("Mikrofon izni gerekli. Sistem Ayarları → Gizlilik ve Güvenlik → Mikrofon bölümünden açabilirsin."); return }
                self.stopPlayback()
                let url = root.appendingPathComponent(UUID().uuidString + ".m4a")
                do {
                    self.recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
                    guard self.recorder!.record() else { self.error = L("Ses kaydı başlatılamadı."); return }
                    self.file = url; self.recordingTask = task
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    func finish() -> (UUID, VoiceNote)? {
        guard let task = recordingTask, let file else { return nil }
        recorder?.stop(); recorder = nil; recordingTask = nil; self.file = nil
        return (task, VoiceNote(file: file.lastPathComponent))
    }
    func play(_ voice: VoiceNote, root: URL) {
        if playing == voice.id { stopPlayback(); return }
        do { player = try AVAudioPlayer(contentsOf: root.appendingPathComponent(voice.file)); player?.delegate = self; player?.play(); playing = voice.id }
        catch { self.error = error.localizedDescription }
    }
    func stopPlayback() { player?.stop(); player = nil; playing = nil }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { playing = nil }
}

struct TaskOpenRequest: Equatable {
    let taskID: UUID
    private let eventID = UUID()
}

final class AppDelegate: StartupSplashDelegate, ObservableObject {
    @Published private(set) var taskRequest: TaskOpenRequest?
    @Published private(set) var reopenRequest: UUID?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let id = urls.compactMap(SadeTaskLink.taskID(from:)).last else { return }
        taskRequest = TaskOpenRequest(taskID: id)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopenRequest = UUID()
        return false
    }

    func revealMainWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "Sade" }) else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
@main struct SadeApp: App {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var store = Store()
    @StateObject private var audio = AudioManager()
    @StateObject private var updater = UpdateChecker()
    var body: some Scene {
        Window("Sade", id: "main") {
            ContentView()
                .environment(\.locale, AppLanguage.current.locale)
                .environmentObject(store)
                .environmentObject(audio)
                .environmentObject(delegate)
                .frame(minWidth: 890, minHeight: 570)
                .modifier(SadeTheme())
                .modifier(WindowEntrance())
                .safeAreaInset(edge: .bottom, spacing: 0) { UpdateBanner(updater: updater) }
                .onAppear { updater.checkAutomatically() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    updater.checkAutomatically()
                }
                .onChange(of: appLanguage) { _, _ in store.refreshNotificationLanguage() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    if let (id, voice) = audio.finish(), let i = store.tasks.firstIndex(where: { $0.id == id }) {
                        store.tasks[i].voices.append(voice)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .onChange(of: delegate.taskRequest, initial: true) { _, request in
            if request != nil {
                openWindow(id: "main")
            }
        }
        .onChange(of: delegate.reopenRequest) { _, request in
            guard request != nil else { return }
            openWindow(id: "main")
            DispatchQueue.main.async {
                delegate.revealMainWindow()
            }
        }
        .commands {
            UpdateCommands(updater: updater)
            CommandGroup(replacing: .newItem) {
                Button(L("Yeni görev")) { NotificationCenter.default.post(name: Notification.Name("newTask"), object: nil) }
                    .keyboardShortcut("n")
            }
        }
        MenuBarExtra {
            MenuPanel().environmentObject(store).environment(\.locale, AppLanguage.current.locale).modifier(SadeTheme())
        } label: {
            DayStatusLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SadeSettingsView(updater: updater)
        }
    }
}
private struct DayStatusLabel: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @EnvironmentObject private var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = DayStatus.resolve(store.tasks, now: store.now)
        Image(systemName: status.icon)
            .contentTransition(.symbolEffect(.replace))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: status)
            .help(status.title)
            .accessibilityLabel("Sade: " + status.title)
    }
}
struct MenuPanel: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headerVisible = false
    @State private var opening = 0
    var todaysTasks: [TaskItem] {
        store.tasks.filter { !$0.done && DayStatus.includes($0, now: store.now) }.sorted {
            min($0.reminder ?? .distantFuture, $0.timerEnd ?? .distantFuture) < min($1.reminder ?? .distantFuture, $1.timerEnd ?? .distantFuture)
        }
    }
    var body: some View {
        let status = DayStatus.resolve(store.tasks, now: store.now)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: status.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(SadePalette.accent)
                        .frame(width: 42, height: 42)
                        .background(SadePalette.selection, in: RoundedRectangle(cornerRadius: 14))
                        .symbolEffect(.bounce, options: .nonRepeating, value: opening)
                        .accessibilityHidden(true)
                    Text("sade").font(.system(.title3, design: .rounded).weight(.semibold))
                    Spacer()
                    Text(store.now, format: .dateTime.day().month(.wide))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(status.title)
                    .font(.system(.headline, design: .rounded))
            }
            .opacity(headerVisible || reduceMotion ? 1 : 0)
            .offset(y: headerVisible || reduceMotion ? 0 : -5)
            if status == .soon { Text(L("Önümüzdeki 15 dakika içinde bir hatırlatma veya zamanlayıcı var.")).font(.caption).foregroundStyle(.secondary) }
            if todaysTasks.isEmpty {
                Text(status == .finished ? L("Hepsi bitti. Kendine biraz vakit ayır.") : L("Yeni bir görev ekleyerek başlayabilirsin.")).foregroundStyle(.secondary)
            } else {
                Text(L("Bugün %@ görev kaldı", String(todaysTasks.count))).font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(todaysTasks) { task in
                            HStack(alignment: .top, spacing: 10) {
                                Button { store.complete(task.id) } label: { Image(systemName: "circle").font(.title3) }.buttonStyle(.plain).help(L("Görevi tamamla"))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title).lineLimit(2)
                                    if let end = task.timerEnd {
                                        Text(end <= store.now ? L("Zamanlayıcı: süre doldu") : L("Zamanlayıcı: %@ dk kaldı", String(max(1, Int(ceil(end.timeIntervalSince(store.now) / 60)))))).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let date = task.reminder { HStack(spacing: 4) { Image(systemName: "bell"); Text(date, format: .dateTime.day().month().hour().minute()); if date <= store.now { Text(L("• Zamanı geldi")) } }.font(.caption).foregroundStyle(date <= store.now ? .orange : .secondary) }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }.frame(maxHeight: 250)
            }
            Divider()
            HStack {
                Button(L("Sade’yi aç")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }.buttonStyle(.borderedProminent)
                Spacer()
                Button(L("Çıkış")) { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
        }.padding(20).frame(width: 330).background(SadePalette.paper).tint(SadePalette.accent)
        .background {
            MenuPresentationObserver(onShow: animateHeader)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private func animateHeader() {
        guard !reduceMotion else {
            headerVisible = true
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { headerVisible = false }
        DispatchQueue.main.async {
            opening += 1
            withAnimation(.easeOut(duration: 0.24)) { headerVisible = true }
        }
    }
}

private struct MenuPresentationObserver: NSViewRepresentable {
    var onShow: () -> Void

    func makeNSView(context: Context) -> PresentationView { PresentationView() }

    func updateNSView(_ view: PresentationView, context: Context) {
        view.onShow = onShow
    }

    final class PresentationView: NSView {
        var onShow: (() -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var presented = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            presented = false
            guard let window else { return }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.checkPresentation()
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                     object: window, queue: .main) { [weak self] _ in
                self?.presented = false
            })
            DispatchQueue.main.async { [weak self] in self?.checkPresentation() }
        }

        private func checkPresentation() {
            let visible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
            if visible && !presented { onShow?() }
            presented = visible
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
struct ContentView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @EnvironmentObject var store: Store
    @EnvironmentObject var audio: AudioManager
    @EnvironmentObject private var appDelegate: AppDelegate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @AppStorage("taskSidebarCompact") private var compactSidebar = false
    @AppStorage("plannerLayout") private var plannerLayout = PlannerLayout.classic.rawValue
    @AppStorage("didChoosePlannerLayout") private var didChooseLayout = false
    @State private var filter = "Bugün"
    @State private var canvasAvailable = false
    @State private var selected: UUID?
    @State private var activeSheet: PlannerSheet?
    @State private var newTaskDay = Date()
    @State private var showCompletedToday = false
    @State private var search = ""
    @State private var deleting: UUID?
    private enum PlannerSheet: String, Identifiable {
        case setup, task, categories
        var id: String { rawValue }
    }
    private var weeklyLayout: Bool { plannerLayout == PlannerLayout.weekly.rawValue }
    var visible: [TaskItem] {
        store.tasks.filter { task in
            let matches: Bool
            switch filter {
            case "Bugün": matches = !task.done && DayStatus.includes(task, now: store.now)
            case "Tüm görevler": matches = !task.done
            case "Tamamlananlar": matches = task.done
            default: matches = !task.done && task.category == filter
            }
            return matches && (search.isEmpty || task.title.localizedCaseInsensitiveContains(search) || task.notes.localizedCaseInsensitiveContains(search))
        }.sorted { $0.created > $1.created }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            if weeklyLayout || store.categories.contains(filter) {
                WeekPlanner(
                    tasks: store.tasks, filter: filter, now: store.now, focusDay: newTaskDay,
                    onAdd: { day in newTaskDay = day; activeSheet = .task },
                    onOpen: { selected = $0.id },
                    onComplete: { store.complete($0) }
                )
            } else {
                agenda
            }
            if let selected, let index = store.tasks.firstIndex(where: { $0.id == selected }) {
                Divider()
                DetailView(task: $store.tasks[index], delete: { deleting = selected }, close: { self.selected = nil })
                    .id(selected)
                    .frame(width: 320)
            }
        }.tint(SadePalette.accent)
        .onAppear {
            refreshCompanion()
            if !didChooseLayout { activeSheet = .setup }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshCompanion()
        }
        .onChange(of: appDelegate.taskRequest, initial: true) { _, request in
            guard let id = request?.taskID else { return }
            guard let task = store.tasks.first(where: { $0.id == id }) else {
                store.message = L("Bağlantıdaki görev bulunamadı.")
                return
            }
            filter = task.done ? "Tamamlananlar" : "Tüm görevler"
            search = ""
            selected = id
            newTaskDay = task.plannerDay
            activeSheet = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("newTask"))) { _ in
            newTaskDay = store.now
            activeSheet = .task
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .setup:
                PlannerSetup(initial: PlannerLayout(rawValue: plannerLayout) ?? .classic) { layout in
                    plannerLayout = layout.rawValue
                    didChooseLayout = true
                    activeSheet = nil
                }
                .interactiveDismissDisabled()
            case .task:
                TaskComposer(categories: store.categories, initialCategory: store.categories.contains(filter) ? filter : "Genel",
                             initialDay: newTaskDay) { task in
                    store.tasks.append(task)
                    search = ""
                    newTaskDay = task.plannerDay
                    if filter == "Tamamlananlar" { filter = "Bugün" }
                    else if filter != "Bugün" && filter != "Tüm görevler" && filter != task.category { filter = "Tüm görevler" }
                    if !weeklyLayout && filter == "Bugün" && !DayStatus.includes(task, now: store.now) {
                        filter = "Tüm görevler"
                    }
                    selected = task.id
                    activeSheet = nil
                }
            case .categories:
                CategoryBooks(categories: store.categories, tasks: store.tasks, onSelect: { name in
                    filter = name
                    search = ""
                    selected = nil
                    newTaskDay = store.now
                    activeSheet = nil
                }, onCreate: { name in
                    store.categories.append(name)
                })
            }
        }
        .alert(L("Bir sorun oluştu"), isPresented: Binding(get: { store.message != nil || audio.error != nil }, set: { if !$0 { store.message = nil; audio.error = nil } })) { Button(L("Tamam")) { store.message = nil; audio.error = nil } } message: { Text(store.message ?? audio.error ?? "") }
        .alert(L("Görev silinsin mi?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button(L("Vazgeç"), role: .cancel) { deleting = nil }; Button(L("Sil"), role: .destructive) { if let deleting { if audio.recordingTask == deleting { finishRecording() }; audio.stopPlayback(); store.delete(deleting); if selected == deleting { selected = nil } }; deleting = nil } } message: { Text(L("Görev ve ona bağlı sesli notlar silinecek.")) }
    }
    private var dayTasks: [TaskItem] {
        store.tasks.filter { DayStatus.includes($0, now: store.now) }
    }

    private var completedToday: [TaskItem] {
        dayTasks.filter(\.done)
    }

    private var agenda: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(store.now, format: .dateTime.month(.wide).year())
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(SadePalette.secondaryInk)
                Spacer()
                Button { newTaskDay = store.now; activeSheet = .task } label: {
                    Label(L("Yeni görev"), systemImage: "plus")
                }
                .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, featured: true))
                .help(L("Yeni görev (⌘N)"))
            }
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 15)
            Rectangle().fill(SadePalette.line.opacity(0.65)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 0) {
                            Text(store.now, format: .dateTime.day())
                                .font(.system(size: 45, weight: .light, design: .serif))
                            Text(store.now, format: .dateTime.weekday(.abbreviated))
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(SadePalette.accent)
                        .padding(.vertical, 9)
                        .frame(width: 70)
                        .background(SadePalette.selection.opacity(0.6), in: RoundedRectangle(cornerRadius: 19))
                        VStack(alignment: .leading, spacing: 7) {
                            Text(filter == "Bugün" ? L("Günün planı") : filterTitle(filter))
                                .font(.system(size: 32, weight: .medium, design: .serif))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(filter == "Bugün" ? L("%@ iş seni bekliyor", String(dayTasks.filter { !$0.done }.count)) : L("%@ görev", String(visible.count)))
                                .font(.callout)
                                .foregroundStyle(SadePalette.secondaryInk)
                        }
                        .padding(.top, 8)
                        Spacer(minLength: 0)
                    }
                    if filter == "Bugün", !dayTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(L("Bugünün ilerlemesi"))
                                Spacer()
                                Text("\(completedToday.count) / \(dayTasks.count)").monospacedDigit()
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SadePalette.secondaryInk)
                            ProgressView(value: Double(completedToday.count), total: Double(dayTasks.count))
                                .progressViewStyle(AgendaProgressStyle())
                                .accessibilityLabel(L("Bugünün tamamlanan görevleri"))
                        }
                        .padding(14)
                        .background(SadePalette.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                    }
                    searchField
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(filter == "Tamamlananlar" ? L("Tamamladıkların") : L("Yapılacaklar"))
                                .font(.system(.headline, design: .rounded))
                            Spacer()
                            Text(visible.count.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 15)
                        Rectangle().fill(SadePalette.line).frame(height: 1)
                        if visible.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(search.isEmpty ? L("Listen rahat.") : L("Eşleşen görev yok."))
                                    .font(.system(.title3, design: .serif))
                                Text(search.isEmpty ? L("Yeni bir iş için yukarıdaki Yeni görev’e bas.") : L("Başka bir kelimeyle aramayı dene."))
                                    .font(.callout).foregroundStyle(SadePalette.secondaryInk)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(visible) { task in taskRow(task) }
                            }
                        }
                    }
                    .background(SadePalette.paper, in: RoundedRectangle(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(SadePalette.line.opacity(0.75)).allowsHitTesting(false) }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    if filter == "Bugün", search.isEmpty, !completedToday.isEmpty {
                        DisclosureGroup(isExpanded: $showCompletedToday) {
                            VStack(spacing: 0) {
                                ForEach(completedToday) { task in taskRow(task) }
                            }
                            .padding(.top, 9)
                        } label: {
                            Label(L("Bugün tamamlananlar · %@", String(completedToday.count)), systemImage: "checkmark.circle")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(SadePalette.mint)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            if let id = audio.recordingTask {
                HStack {
                    Image(systemName: "record.circle").foregroundStyle(.red)
                    Text(L("Ses kaydediliyor"))
                    Spacer()
                    Button(L("Kaydı bitir"), action: finishRecording)
                }
                .font(.callout)
                .padding(12)
                .background(SadePalette.paper)
                .onTapGesture { selected = id }
            }
        }
        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        .background(SadePalette.canvas)
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
                HStack(spacing: 8) {
                    brand
                    Text("sade").font(.system(size: 25, weight: .semibold, design: .rounded))
                        .fixedSize()
                        .opacity(compactSidebar ? 0 : 1)
                        .frame(width: compactSidebar ? 0 : 110, alignment: .leading)
                        .clipped()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            sidebarToggle
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                sidebarItem(weeklyLayout ? "Bu hafta" : "Bugün", weeklyLayout ? "calendar" : "sun.max", isSelected: filter == "Bugün") {
                    filter = "Bugün"
                    selected = nil
                }
                nav("Tüm görevler", "tray")
                nav("Tamamlananlar", "checkmark.circle")
                if canvasAvailable {
                    sidebarItem("Sade Tuval", "square.grid.2x2") {
                        Task {
                            do { try await SadeCompanion.open(.canvas) }
                            catch { store.message = error.localizedDescription }
                        }
                    }
                }
            }
            Divider()
            sidebarItem(L("Kategoriler"), "books.vertical", isSelected: store.categories.contains(filter)) {
                activeSheet = .categories
            }
            Spacer()
            Divider()
            sidebarItem(L("Ayarlar"), "slider.horizontal.3") { openSettings() }
        }
        .padding(.top, 34)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(width: compactSidebar ? 62 : 204)
        .background(SadePalette.sidebar)
        .clipped()
    }
    private func refreshCompanion() {
        canvasAvailable = SadeCompanion.applicationURL(.canvas) != nil
    }

    private var brand: some View {
        Image(systemName: "circle.hexagongrid.fill")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(SadePalette.accent)
            .frame(width: 34, height: 34)
            .background(SadePalette.selection, in: RoundedRectangle(cornerRadius: 11))
            .accessibilityHidden(true)
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                compactSidebar.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
        }
        .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, selected: compactSidebar))
        .help(compactSidebar ? L("Kenar çubuğunu genişlet") : L("Kenar çubuğunu daralt"))
        .accessibilityLabel(compactSidebar ? L("Kenar çubuğunu genişlet") : L("Kenar çubuğunu daralt"))
    }

    private func nav(_ name: String, _ icon: String) -> some View {
        sidebarItem(name, icon, isSelected: filter == name) {
            filter = name
            selected = nil
        }
    }

    private func sidebarItem(_ name: String, _ icon: String, isSelected: Bool = false,
                             alwaysShowText: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: icon).frame(width: 18)
                Text(L(name)).lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 8)
                    .opacity(compactSidebar && !alwaysShowText ? 0 : 1)
                    .frame(width: compactSidebar && !alwaysShowText ? 0 : 139, alignment: .leading)
                    .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .padding(.horizontal, 6)
            .foregroundStyle(isSelected ? SadePalette.accent : .primary)
            .background(isSelected ? SadePalette.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L(name))
        .accessibilityLabel(L(name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(L("Görevlerde ara"), text: $search).textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L("Aramayı temizle"))
            }
        }
        .padding(9)
        .background(SadePalette.paper, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(SadePalette.line).allowsHitTesting(false) }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(spacing: 9) {
            Button { store.complete(task.id) } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(task.done ? SadePalette.mint : SadePalette.accent)
                    .frame(width: 29, height: 31)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? L("Görevi yeniden aç") : L("Görevi tamamla"))
            Button { selected = task.id } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title).font(.system(size: 14, weight: .medium)).strikethrough(task.done)
                        HStack(spacing: 7) {
                            Text(task.category)
                                .lineLimit(1)
                                .foregroundStyle(SadePalette.secondaryInk)
                            if task.priority == "Yüksek" {
                                Label(L("Yüksek öncelik"), systemImage: "flag.fill").foregroundStyle(SadePalette.peach)
                            }
                            if !task.voices.isEmpty { Image(systemName: "waveform").accessibilityLabel(L("Sesli not")) }
                            if task.reminder != nil { Image(systemName: "bell").accessibilityLabel(L("Hatırlatma")) }
                            if task.timerEnd != nil { Image(systemName: "timer").accessibilityLabel(L("Zamanlayıcı")) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(selected == task.id ? SadePalette.selection.opacity(0.7) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(SadePalette.line.opacity(0.6)).frame(height: 1).padding(.leading, 50).allowsHitTesting(false) }
        .contextMenu { Button(L("Sil"), role: .destructive) { deleting = task.id } }
    }
    func finishRecording() { if let (id, voice) = audio.finish(), let i = store.tasks.firstIndex(where: { $0.id == id }) { store.tasks[i].voices.append(voice) } }
}
struct DetailView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @Binding var task: TaskItem
    var delete: () -> Void
    var close: () -> Void
    @EnvironmentObject var store: Store
    @EnvironmentObject var audio: AudioManager
    @State private var date = Date().addingTimeInterval(3600)
    @State private var minutes = 25
    @State private var subtask = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 4) {
                    Text(L("Görev detayı")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                        .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.rose))
                        .accessibilityLabel(L("Görevi sil"))
                    Button(action: close) { Image(systemName: "xmark") }
                        .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent))
                        .accessibilityLabel(L("Görev detayını kapat"))
                }
                TextField(L("Görev adı"), text: $task.title, axis: .vertical).font(.title2.weight(.semibold))
                Picker(L("Ajanda"), selection: $task.category) { ForEach(store.categories, id: \.self) { Text($0) } }
                DatePicker(L("Planlanan gün"), selection: Binding(
                    get: { task.plannerDay },
                    set: { task.scheduledDay = Calendar.current.startOfDay(for: $0) }
                ), displayedComponents: .date)
                Picker(L("Öncelik"), selection: $task.priority) { Text(L("Normal")).tag("Normal"); Text(L("Yüksek")).tag("Yüksek"); Text(L("Düşük")).tag("Düşük") }
                VStack(alignment: .leading, spacing: 8) { Text(L("Notlar")).font(.headline); TextEditor(text: $task.notes).frame(height: 90).padding(5).background(.quaternary, in: RoundedRectangle(cornerRadius: 8)) }
                VStack(alignment: .leading, spacing: 10) {
                    Label(L("Alt görevler"), systemImage: "checklist").font(.headline)
                    ForEach($task.subtasks) { $sub in HStack { Toggle("", isOn: $sub.done).labelsHidden().toggleStyle(.checkbox); TextField(L("Alt görev"), text: $sub.title); Button { task.subtasks.removeAll { $0.id == sub.id } } label: { Image(systemName: "xmark") }.buttonStyle(.plain) } }
                    TextField(L("Alt görev ekle ↵"), text: $subtask).onSubmit { let value = subtask.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { task.subtasks.append(Subtask(title: value)); subtask = "" } }
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label(L("Hatırlatma"), systemImage: "bell").font(.headline)
                    DatePicker(L("Zaman"), selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                    if let reminder = task.reminder { Text(reminder, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(reminder < Date() ? .orange : .secondary) }
                    HStack { Button(task.reminder == nil ? L("Hatırlatıcı kur") : L("Güncelle")) { task.reminder = date; store.schedule(task, at: date, kind: "reminder") }.disabled(task.done || date <= Date()); if task.reminder != nil { Button(L("Kaldır")) { store.cancel(task.id, kind: "reminder"); task.reminder = nil } } }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label(L("Odak zamanlayıcısı"), systemImage: "timer").font(.headline)
                    if let end = task.timerEnd {
                        TimelineView(.periodic(from: .now, by: 1)) { context in Text(remaining(end, now: context.date)).font(.system(size: 32, weight: .light, design: .rounded)).monospacedDigit() }
                        Button(L("Zamanlayıcıyı kaldır")) { store.cancel(task.id, kind: "timer"); task.timerEnd = nil }
                    } else {
                        Stepper(L("%@ dakika", String(minutes)), value: $minutes, in: 1...240)
                        Button(L("Başlat")) { let end = Date().addingTimeInterval(Double(minutes * 60)); task.timerEnd = end; store.schedule(task, at: end, kind: "timer") }.disabled(task.done)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label(L("Sesli notlar"), systemImage: "waveform").font(.headline)
                    if audio.recordingTask == task.id { HStack { Circle().fill(.red).frame(width: 8, height: 8); Text(L("Kaydediliyor…")); Button(L("Bitir")) { if let (_, note) = audio.finish() { task.voices.append(note) } } } }
                    else { Button { audio.record(task: task.id, root: store.root) } label: { Label(L("Sesli not kaydet"), systemImage: "mic") }.disabled(audio.recordingTask != nil) }
                    ForEach(task.voices) { voice in HStack { Button { audio.play(voice, root: store.root) } label: { Image(systemName: audio.playing == voice.id ? "stop.fill" : "play.fill") }.disabled(audio.recordingTask != nil); Text(voice.created, format: .dateTime.day().month().hour().minute()).font(.caption); Spacer(); Button { audio.stopPlayback(); task.voices.removeAll { $0.id == voice.id }; try? FileManager.default.removeItem(at: store.root.appendingPathComponent(voice.file)) } label: { Image(systemName: "trash") }.buttonStyle(.plain) } }
                    Text(L("Sesli notlar bu Mac’te saklanır.")).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(22)
        }.background(SadePalette.pages).onAppear { date = task.reminder ?? Date().addingTimeInterval(3600) }
    }
    func remaining(_ end: Date, now: Date) -> String { let seconds = max(0, Int(ceil(end.timeIntervalSince(now)))); return seconds == 0 ? L("Süre doldu") : String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}

private struct AgendaProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(SadePalette.mint.opacity(0.13))
                Capsule()
                    .fill(SadePalette.mint)
                    .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: 5)
    }
}

private struct TaskComposer: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    var categories: [String]
    var onSave: (TaskItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var category: String
    @State private var priority = "Normal"
    @State private var day: Date
    @FocusState private var titleFocused: Bool

    init(categories: [String], initialCategory: String, initialDay: Date, onSave: @escaping (TaskItem) -> Void) {
        self.categories = categories
        self.onSave = onSave
        _category = State(initialValue: categories.contains(initialCategory) ? initialCategory : categories.first ?? "Genel")
        _day = State(initialValue: initialDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L("Yeni bir iş")).font(.system(size: 28, weight: .medium, design: .serif))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent))
                    .accessibilityLabel(L("Vazgeç"))
                    .keyboardShortcut(.cancelAction)
            }
            TextField(L("Ne yapmak istiyorsun?"), text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($titleFocused)
                .padding(13)
                .background(SadePalette.paper, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(L("Görev adı"))
            HStack(spacing: 16) {
                Picker(L("Ajanda"), selection: $category) {
                    if categories.isEmpty { Text("Genel").tag("Genel") }
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                Picker(L("Öncelik"), selection: $priority) {
                    ForEach(["Normal", "Yüksek", "Düşük"], id: \.self) { Text(L($0)).tag($0) }
                }
            }
            DatePicker(L("Gün"), selection: $day, displayedComponents: .date)
            TextField(L("Bir not ekle (isteğe bağlı)"), text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
                .padding(12)
                .background(SadePalette.paper, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(L("Görev notu"))
            HStack {
                Spacer()
                Button(L("Görevi ekle"), action: save)
                    .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, featured: true))
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(25)
        .frame(width: 450)
        .modifier(SadeTheme())
        .task {
            await Task.yield()
            titleFocused = true
        }
    }

    private func save() {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var task = TaskItem(title: value)
        task.category = category
        task.priority = priority
        task.notes = notes
        task.scheduledDay = Calendar.current.startOfDay(for: day)
        onSave(task)
    }
}
