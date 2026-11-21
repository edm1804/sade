import SwiftUI

enum PlannerLayout: String, CaseIterable, Identifiable {
    case classic, weekly
    var id: Self { self }
    var title: String { self == .classic ? L("Klasik") : L("Ajandalar") }
    var icon: String { self == .classic ? "list.bullet.rectangle" : "calendar" }
    var description: String {
        self == .classic
            ? L("Bugün ve tüm görevlerini bir listede gör. Ajandalarını Kategoriler’den aç.")
            : L("Haftanın günlerini yan yana gör. Görevlerini doğrudan bir güne ekle.")
    }
}

struct PlannerSetup: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @State private var selection: PlannerLayout
    var onChoose: (PlannerLayout) -> Void

    init(initial: PlannerLayout, onChoose: @escaping (PlannerLayout) -> Void) {
        _selection = State(initialValue: initial)
        self.onChoose = onChoose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(L("Sade’yi nasıl kullanacaksın?"))
                .font(.system(size: 27, weight: .medium, design: .serif))
            Text(L("Görünümü daha sonra Ayarlar’dan değiştirebilirsin."))
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                ForEach(PlannerLayout.allCases) { layout in
                    Button {
                        selection = layout
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            preview(layout)
                            HStack {
                                Label(layout.title, systemImage: layout.icon)
                                    .font(.headline)
                                Spacer()
                                Image(systemName: selection == layout ? "checkmark.circle.fill" : "circle")
                            }
                            .foregroundStyle(SadePalette.accent)
                            Text(layout.description)
                                .font(.callout)
                                .foregroundStyle(SadePalette.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selection == layout ? SadePalette.selection.opacity(0.5) : SadePalette.paper,
                                    in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(selection == layout ? SadePalette.accent : SadePalette.line)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(layout.title + ". " + layout.description)
                    .accessibilityAddTraits(selection == layout ? .isSelected : [])
                }
            }
            HStack {
                Spacer()
                Button(L("Bu düzenle başla")) { onChoose(selection) }
                    .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, featured: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 570)
        .modifier(SadeTheme())
    }

    private func preview(_ layout: PlannerLayout) -> some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 5).fill(SadePalette.accent.opacity(0.16)).frame(width: 24)
            if layout == .classic {
                VStack(spacing: 8) {
                    ForEach(0..<3) { _ in
                        HStack(spacing: 6) {
                            Circle().strokeBorder(SadePalette.accent, lineWidth: 1).frame(width: 7, height: 7)
                            Capsule().fill(SadePalette.accent.opacity(0.23)).frame(height: 4)
                        }
                    }
                }
                .padding(9)
            } else {
                ForEach(0..<3) { index in
                    VStack(spacing: 6) {
                        Text(L(["Pzt", "Sal", "Çar"][index])).font(.system(size: 9, weight: .medium))
                        RoundedRectangle(cornerRadius: 4).fill(SadePalette.mint.opacity(0.24)).frame(height: 17)
                        Spacer(minLength: 0)
                    }
                    .padding(5)
                    .background(SadePalette.paper, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .frame(height: 85)
        .padding(9)
        .background(SadePalette.canvas, in: RoundedRectangle(cornerRadius: 9))
        .accessibilityHidden(true)
    }
}

struct WeekPlanner: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("agendaCoverStyles") private var coverStyles = Data()
    let tasks: [TaskItem]
    let filter: String
    let now: Date
    let focusDay: Date
    let onAdd: (Date) -> Void
    let onOpen: (TaskItem) -> Void
    let onComplete: (UUID) -> Void
    @State private var anchor = Date()
    @State private var search = ""
    @State private var showDone = true

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    private var days: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var scopedTasks: [TaskItem] {
        tasks.filter { task in
            let matchesAgenda = ["Bugün", "Tüm görevler", "Tamamlananlar"].contains(filter) || task.category == filter
            return matchesAgenda
                && (filter != "Tamamlananlar" || task.done)
                && (showDone || !task.done)
                && (search.isEmpty || task.title.localizedCaseInsensitiveContains(search) || task.notes.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                if !["Bugün", "Tüm görevler", "Tamamlananlar"].contains(filter) {
                    let cover = AgendaCover.load(filter, from: coverStyles)
                    Image(systemName: cover.safeSymbol)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(cover.tint)
                        .frame(width: 49, height: 60)
                        .background(cover.tint.opacity(0.13), in: UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(filter == "Bugün" ? L("Haftanın planı") : filterTitle(filter))
                        .font(.system(size: 29, weight: .medium, design: .serif))
                    HStack(spacing: 4) {
                        Text(days[0], format: .dateTime.day().month(.abbreviated))
                        Text("–")
                        Text(days[6], format: .dateTime.day().month(.abbreviated).year())
                    }
                    .font(.callout).foregroundStyle(SadePalette.secondaryInk)
                }
                Spacer()
                HStack(spacing: 2) {
                    Button { changeWeek(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(L("Önceki hafta"))
                    Button(L("Bu hafta")) { anchor = now }
                    Button { changeWeek(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel(L("Sonraki hafta"))
                }
                .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent))
            }
            HStack {
                TextField(L("Bu haftada ara"), text: $search)
                    .textFieldStyle(.roundedBorder)
                Toggle(L("Bitenleri göster"), isOn: $showDone)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(days, id: \.self) { day in
                            dayColumn(day).id(calendar.startOfDay(for: day))
                        }
                    }
                    .padding(.bottom, 8)
                }
                .task(id: anchor) {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    let target = days.first { calendar.isDate($0, inSameDayAs: focusDay) }
                        ?? days.first { calendar.isDate($0, inSameDayAs: now) }
                        ?? days[0]
                    scroll.scrollTo(calendar.startOfDay(for: target), anchor: .center)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 35)
        .padding(.bottom, 16)
        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SadePalette.canvas)
        .onAppear { anchor = focusDay }
        .onChange(of: focusDay) { _, date in anchor = date }
        .onChange(of: now) { previous, current in
            if !calendar.isDate(previous, inSameDayAs: current),
               calendar.isDate(previous, equalTo: anchor, toGranularity: .weekOfYear) { anchor = current }
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let items = scopedTasks.filter { calendar.isDate($0.plannerDay, inSameDayAs: day) }
            .sorted { $0.created < $1.created }
        let today = calendar.isDate(day, inSameDayAs: now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(day, format: .dateTime.weekday(.wide)).font(.caption.weight(.semibold))
                    Text(day, format: .dateTime.day()).font(.system(size: 26, weight: .medium, design: .serif))
                }
                .foregroundStyle(today ? SadePalette.accent : SadePalette.ink)
                Spacer()
                Button { onAdd(day) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent))
                .accessibilityLabel(L("Görev ekle: %@", day.formatted(.dateTime.day().month().locale(AppLanguage.current.locale))))
            }
            Rectangle().fill(today ? SadePalette.accent : SadePalette.line).frame(height: today ? 2 : 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { task in
                        HStack(alignment: .top, spacing: 7) {
                            Button { onComplete(task.id) } label: {
                                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.done ? SadePalette.mint : SadePalette.accent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(task.done ? L("Görevi yeniden aç") : L("Görevi tamamla"))
                            Button { onOpen(task) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(task.title).font(.callout.weight(.medium)).strikethrough(task.done)
                                    Text(task.category).font(.caption).foregroundStyle(.secondary)
                                    if task.priority == "Yüksek" {
                                        Label(L("Yüksek"), systemImage: "flag.fill").font(.caption).foregroundStyle(SadePalette.peach)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(11)
                        .background(SadePalette.paper, in: RoundedRectangle(cornerRadius: 11))
                    }
                    if items.isEmpty {
                        Text(search.isEmpty ? L("Henüz görev yok") : L("Eşleşen görev yok"))
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 196)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(today ? SadePalette.selection.opacity(0.24) : SadePalette.paper.opacity(0.36),
                    in: RoundedRectangle(cornerRadius: 15))
        .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(SadePalette.line.opacity(0.7)).allowsHitTesting(false) }
    }

    private func changeWeek(_ amount: Int) {
        if let date = calendar.date(byAdding: .weekOfYear, value: amount, to: anchor) { anchor = date }
    }
}
