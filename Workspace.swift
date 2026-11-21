import SwiftUI

enum WorkspaceBlockKind: String, Codable, CaseIterable, Identifiable {
    case heading, text, checklist, table, board, task

    var id: Self { self }

    var title: String {
        switch self {
        case .heading: L("Başlık")
        case .text: L("Metin")
        case .checklist: L("Kontrol listesi")
        case .table: L("Tablo")
        case .board: L("Proje panosu")
        case .task: L("Görev bağlantısı")
        }
    }

    var icon: String {
        switch self {
        case .heading: "textformat.size.larger"
        case .text: "text.alignleft"
        case .checklist: "checklist"
        case .table: "tablecells"
        case .board: "rectangle.split.3x1"
        case .task: "link"
        }
    }

    var accent: Color {
        switch self {
        case .heading: SadePalette.accent
        case .text: SadePalette.rose
        case .checklist: SadePalette.mint
        case .table: SadePalette.blue
        case .board: SadePalette.honey
        case .task: SadePalette.peach
        }
    }
}

struct WorkspacePage: Codable, Identifiable {
    var id = UUID()
    var title = ""
    var blocks: [WorkspaceBlock] = []
    var connections: [CanvasConnection]?
    var canvasMinimumSize: CGSize?

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("Başlıksız sayfa") : title
    }
}

struct CanvasConnection: Codable, Hashable, Identifiable {
    let source: UUID
    let target: UUID

    var id: Self { self }
}

enum CardStage: String, Codable, CaseIterable, Identifiable {
    case planned, active, done
    var id: Self { self }
    var title: String {
        switch self {
        case .planned: L("Yapılacak")
        case .active: L("Sürüyor")
        case .done: L("Bitti")
        }
    }
    var color: Color {
        switch self {
        case .planned: SadePalette.accent
        case .active: SadePalette.peach
        case .done: SadePalette.mint
        }
    }
}

struct ProjectCard: Codable, Identifiable {
    var id = UUID()
    var title = ""
    var stage: CardStage
}

struct WorkspaceTable: Codable {
    var headers = [L("Ad"), L("Not")]
    var rows = [["", ""]]

    mutating func addColumn() {
        headers.append("")
        for index in rows.indices {
            rows[index].append("")
        }
    }

    mutating func addRow() {
        rows.append(Array(repeating: "", count: headers.count))
    }
}

struct WorkspaceBlock: Codable, Identifiable {
    var id = UUID()
    var kind: WorkspaceBlockKind
    var text = ""
    var checklist: [Subtask] = []
    var table = WorkspaceTable()
    var cards: [ProjectCard] = []
    var taskID: UUID?
    var placement: CanvasPlacement?
    var size: CGSize?
}

struct CanvasPlacement: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat

    var point: CGPoint { CGPoint(x: x, y: y) }
}

final class WorkspaceStore: ObservableObject {
    @Published var pages: [WorkspacePage] = [] {
        didSet { save() }
    }
    @Published private(set) var error: String?
    private(set) var canEdit = true
    private let file: URL

    init(root: URL) {
        file = root.appendingPathComponent("workspace.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                pages = try JSONDecoder().decode([WorkspacePage].self, from: Data(contentsOf: file))
            }
        } catch {
            canEdit = false
            self.error = L("Çalışma alanı açılamadı. Kayıt dosyası korunuyor. %@", String(error.localizedDescription))
        }
    }

    private func save() {
        guard canEdit else { return }
        do {
            try JSONEncoder().encode(pages).write(to: file, options: .atomic)
            error = nil
        } catch {
            self.error = L("Çalışma alanı kaydedilemedi. %@", String(error.localizedDescription))
        }
    }
}

struct WorkspaceBlockEditor: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @EnvironmentObject private var taskLibrary: CanvasTaskLibrary
    @Binding var block: WorkspaceBlock
    var openTask: (TaskItem) -> Void
    var focusedBlock: FocusState<UUID?>.Binding

    var body: some View {
        Group {
            switch block.kind {
            case .heading:
                TextField(L("Başlık"), text: $block.text, axis: .vertical)
                    .textFieldStyle(.plain).font(.title2.weight(.semibold))
                    .focused(focusedBlock, equals: block.id)
            case .text:
                TextField(L("Yazmaya başla veya / yaz"), text: $block.text, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...12)
                    .focused(focusedBlock, equals: block.id)
            case .checklist:
                checklist
            case .table:
                WorkspaceTableEditor(table: $block.table)
            case .board:
                ProjectBoardEditor(cards: $block.cards)
            case .task:
                taskLink
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($block.checklist) { $item in
                HStack {
                    Toggle(L("Tamamlandı"), isOn: $item.done).labelsHidden().toggleStyle(.checkbox)
                    TextField(L("Liste öğesi"), text: $item.title)
                        .textFieldStyle(.plain).strikethrough(item.done)
                    let id = item.id
                    Button { block.checklist.removeAll { $0.id == id } } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Liste öğesini sil"))
                }
            }
            Button {
                block.checklist.append(Subtask(title: ""))
            } label: {
                Label(L("Liste öğesi ekle"), systemImage: "plus")
            }
        }
    }

    private var taskLink: some View {
        HStack {
            if let task = taskLibrary.tasks.first(where: { $0.id == block.taskID }) {
                Button {
                    openTask(task)
                } label: {
                    Label(task.title, systemImage: task.done ? "checkmark.circle" : "arrow.up.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(SadePalette.accent)
            } else if block.taskID != nil {
                Text(L("Bağlı görev bulunamadı")).foregroundStyle(.secondary)
            }
            Menu(block.taskID == nil ? L("Görev seç") : L("Bağlantıyı değiştir")) {
                ForEach(taskLibrary.tasks) { task in
                    Button(task.title) { block.taskID = task.id }
                }
                if taskLibrary.tasks.isEmpty {
                    Text(L("Sade’de görev bulunamadı"))
                }
                if block.taskID != nil {
                    Divider()
                    Button(L("Bağlantıyı kaldır")) { block.taskID = nil }
                }
            }
            .fixedSize()
        }
    }
}

struct WorkspaceTableEditor: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @Binding var table: WorkspaceTable

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(table.headers.indices, id: \.self) { column in
                            cell(L("Sütun adı"), text: $table.headers[column], heading: true)
                        }
                    }
                    ForEach(table.rows.indices, id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(table.headers.indices, id: \.self) { column in
                                cell("—", text: $table.rows[row][column], heading: false)
                            }
                            Button { table.rows.remove(at: row) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("Satırı sil"))
                        }
                    }
                }
            }
            HStack {
                Button(L("Satır ekle")) { table.addRow() }
                Button(L("Sütun ekle")) { table.addColumn() }
            }
        }
    }

    private func cell(_ placeholder: String, text: Binding<String>, heading: Bool) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(heading ? .callout.weight(.semibold) : .callout)
            .padding(8)
            .frame(width: 145)
            .background(heading ? SadePalette.selection : SadePalette.canvas)
    }
}

struct ProjectBoardEditor: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @Binding var cards: [ProjectCard]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(CardStage.allCases) { stage in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        Circle().fill(stage.color).frame(width: 7, height: 7)
                        Text(stage.title).font(.callout.weight(.semibold))
                        Spacer()
                    }
                    ForEach($cards) { $card in
                        if card.stage == stage {
                            cardView($card)
                        }
                    }
                    Button {
                        cards.append(ProjectCard(stage: stage))
                    } label: {
                        Label(L("Kart ekle"), systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(stage.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func cardView(_ card: Binding<ProjectCard>) -> some View {
        HStack(alignment: .top, spacing: 3) {
            TextField(L("Kart başlığı"), text: card.title, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...4)
            Menu {
                ForEach(CardStage.allCases) { stage in
                    Button(stage.title) { card.wrappedValue.stage = stage }
                }
                Divider()
                Button(L("Kartı sil"), role: .destructive) {
                    let id = card.wrappedValue.id
                    cards.removeAll { $0.id == id }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(L("Kart durumu"))
        }
        .padding(7)
        .background(SadePalette.paper, in: RoundedRectangle(cornerRadius: 8))
    }
}
