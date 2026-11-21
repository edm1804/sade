import SwiftUI

struct AgendaCover: Codable, Equatable {
    var color = "lavender"
    var symbol = "sparkles"
    var pattern = "plain"
    var caption: String?
    var lettering: String?
    var bookmark: Bool?

    static let colors: [(id: String, title: String, hex: UInt32)] = [
        ("lavender", "Lavanta", 0x73549A), ("rose", "Gül", 0xA45F77),
        ("sage", "Adaçayı", 0x537C70), ("blue", "Mavi", 0x4D6F94),
        ("ochre", "Bal", 0x987343), ("clay", "Kiremit", 0xA4634F)
    ]
    static let symbols: [(id: String, title: String)] = [
        ("sparkles", "Fikir"), ("sun.max", "Günlük"), ("book", "Ders"),
        ("camera", "İçerik"), ("leaf", "Kişisel"), ("star", "Hedef"),
        ("pencil", "Not"), ("gamecontroller", "Oyun")
    ]
    static let patterns: [(id: String, title: String)] = [
        ("plain", "Düz"), ("lines", "Çizgili"), ("dots", "Noktalı")
    ]

    var tint: Color {
        let value = Self.colors.first { $0.id == color }?.hex ?? Self.colors[0].hex
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }

    var safeSymbol: String {
        Self.symbols.contains { $0.id == symbol } ? symbol : "sparkles"
    }

    static func load(_ name: String, from data: Data) -> Self {
        let saved = (try? JSONDecoder().decode([String: Self].self, from: data)) ?? [:]
        if let cover = saved[name] { return cover }
        let index = name.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % colors.count }
        var cover = Self()
        cover.color = colors[index].id
        return cover
    }

    static func saving(_ cover: Self, for name: String, in data: Data) throws -> Data {
        var saved = data.isEmpty ? [:] : try JSONDecoder().decode([String: Self].self, from: data)
        saved[name] = cover
        return try JSONEncoder().encode(saved)
    }
}

struct AgendaBook: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    let title: String
    let cover: AgendaCover

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [cover.tint, cover.tint.opacity(0.88)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if cover.pattern == "lines" {
                Canvas { context, size in
                    for y in stride(from: CGFloat(12), through: size.height, by: 13) {
                        var path = Path()
                        path.move(to: CGPoint(x: 15, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 1)
                    }
                }
            } else if cover.pattern == "dots" {
                Canvas { context, size in
                    var dots = Path()
                    for x in stride(from: CGFloat(18), to: size.width, by: 13) {
                        for y in stride(from: CGFloat(12), to: size.height, by: 13) {
                            dots.addEllipse(in: CGRect(x: x, y: y, width: 1.8, height: 1.8))
                        }
                    }
                    context.fill(dots, with: .color(.white.opacity(0.17)))
                }
            }
            Rectangle().fill(.black.opacity(0.14)).frame(width: 11)
            Rectangle().fill(.white.opacity(0.16)).frame(width: 1).padding(.leading, 12)
            if cover.bookmark == true {
                UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
                    .fill(.white.opacity(0.65))
                    .frame(width: 13, height: 36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 19)
            }
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: cover.safeSymbol)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 6)
                Text(title)
                    .font(.system(size: 21, weight: .medium, design: cover.lettering == "rounded" ? .rounded : .serif))
                    .lineLimit(3)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let caption = cover.caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(caption).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.83)).lineLimit(2)
                } else {
                    Capsule().fill(.white.opacity(0.45)).frame(width: 22, height: 2)
                }
            }
            .padding(.leading, 24)
            .padding(.trailing, 13)
            .padding(.vertical, 22)
        }
        .frame(height: 190)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5,
                                         bottomTrailingRadius: 13, topTrailingRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.16))
        }
        .shadow(color: cover.tint.opacity(0.18), radius: 5, x: 2, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

struct CategoryBooks: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    let categories: [String]
    let tasks: [TaskItem]
    let onSelect: (String) -> Void
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("agendaCoverStyles") private var styles = Data()
    @State private var newName = ""
    @State private var editing: EditableBook?
    @State private var error: String?

    private struct EditableBook: Identifiable {
        let name: String
        var id: String { name }
    }

    private var proposedName: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool {
        !proposedName.isEmpty
            && !["Bugün", "Tüm görevler", "Tamamlananlar", "Bu hafta"].contains(proposedName)
            && !categories.contains { $0.localizedCaseInsensitiveCompare(proposedName) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Kategoriler")).font(.system(size: 29, weight: .medium, design: .serif))
                    Text(L("Ajandanı seç ve haftanı planla.")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent))
                    .accessibilityLabel(L("Kategorileri kapat"))
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 185), spacing: 20)], spacing: 24) {
                    ForEach(categories, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { onSelect(name) } label: {
                                AgendaBook(title: name, cover: AgendaCover.load(name, from: styles))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("Ajanda aç: %@", name))
                            HStack {
                                Text(L("%@ açık görev", String(tasks.filter { $0.category == name && !$0.done }.count)))
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { editing = EditableBook(name: name) } label: {
                                    Image(systemName: "paintbrush.pointed")
                                }
                                .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, compact: true))
                                .help(L("Kapağı kişiselleştir"))
                                .accessibilityLabel(L("Kapağı kişiselleştir: %@", name))
                            }
                        }
                        .padding(.bottom, 5)
                    }
                }
                .padding(5)
            }
            if let error { Text(error).font(.caption).foregroundStyle(SadePalette.peach) }
            HStack(spacing: 9) {
                TextField(L("Yeni kategori adı"), text: $newName).textFieldStyle(.roundedBorder).onSubmit(create)
                Button(L("Kategori ekle"), action: create)
                    .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, featured: true))
                    .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 590, height: 470)
        .modifier(SadeTheme())
        .sheet(item: $editing) { book in
            AgendaCoverEditor(name: book.name, initial: AgendaCover.load(book.name, from: styles)) { cover in
                do {
                    styles = try AgendaCover.saving(cover, for: book.name, in: styles)
                    editing = nil
                    error = nil
                } catch {
                    self.error = L("Kapak kaydedilemedi. Tekrar dene.")
                }
            }
        }
    }

    private func create() {
        guard canCreate else { return }
        onCreate(proposedName)
        newName = ""
    }
}

private struct AgendaCoverEditor: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    let name: String
    let onSave: (AgendaCover) -> Void
    @State private var cover: AgendaCover
    @Environment(\.dismiss) private var dismiss

    init(name: String, initial: AgendaCover, onSave: @escaping (AgendaCover) -> Void) {
        self.name = name
        self.onSave = onSave
        _cover = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L("Ajandanın kapağı")).font(.system(size: 26, weight: .medium, design: .serif))
            HStack(alignment: .top, spacing: 24) {
                AgendaBook(title: name, cover: cover).frame(width: 155)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Renk")).font(.callout.weight(.semibold))
                        HStack(spacing: 8) {
                            ForEach(AgendaCover.colors, id: \.id) { item in
                                Button { cover.color = item.id } label: {
                                    Circle()
                                        .fill(AgendaCover(color: item.id).tint)
                                        .frame(width: 24, height: 24)
                                        .overlay {
                                            if cover.color == item.id {
                                                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                            }
                                        }
                                        .padding(3)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L(item.title))
                                .accessibilityAddTraits(cover.color == item.id ? .isSelected : [])
                            }
                        }
                    }
                    Picker(L("Simge"), selection: $cover.symbol) {
                        ForEach(AgendaCover.symbols, id: \.id) { item in
                            Label(L(item.title), systemImage: item.id).tag(item.id)
                        }
                    }
                    Picker(L("Desen"), selection: $cover.pattern) {
                        ForEach(AgendaCover.patterns, id: \.id) { Text(L($0.title)).tag($0.id) }
                    }
                    Picker(L("Yazı"), selection: Binding(
                        get: { cover.lettering ?? "serif" }, set: { cover.lettering = $0 }
                    )) {
                        Text(L("Klasik")).tag("serif")
                        Text(L("Yuvarlak")).tag("rounded")
                    }
                    TextField(L("Kısa kapak yazısı"), text: Binding(
                        get: { cover.caption ?? "" },
                        set: { cover.caption = String($0.prefix(32)) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Toggle(L("Ayraç"), isOn: Binding(
                        get: { cover.bookmark ?? false }, set: { cover.bookmark = $0 }
                    ))
                    .toggleStyle(.checkbox)
                }
                .frame(width: 245)
                .padding(.top, 8)
            }
            HStack {
                Button(L("Vazgeç")) { dismiss() }
                    .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent))
                Spacer()
                Button(L("Kapağı kaydet")) { onSave(cover) }
                    .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, featured: true))
            }
        }
        .padding(24)
        .modifier(SadeTheme())
    }
}
