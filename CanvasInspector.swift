import SwiftUI

extension WorkspaceBlockKind {
    var libraryDescription: String {
        switch self {
        case .heading: L("Bölümlere isim ver")
        case .text: L("Fikrini veya notunu yaz")
        case .checklist: L("Adımları tek tek tamamla")
        case .table: L("Bilgileri satırlarda düzenle")
        case .board: L("Projenin aşamalarını gör")
        case .task: L("Sade’deki bir göreve bağlan")
        }
    }
}

struct CanvasBlockInspector: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    let kind: WorkspaceBlockKind
    let position: CanvasPlacement
    let size: CGSize
    let onPosition: (CGPoint) -> Void
    let onSize: (CGSize?) -> Void
    let onDuplicate: () -> Void
    let onLink: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                Label(kind.title, systemImage: kind.icon)
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(kind.accent)
                VStack(alignment: .leading, spacing: 9) {
                    Text(L("Konum")).font(.callout.weight(.semibold))
                    measurement("X", value: Double(position.x)) { onPosition(CGPoint(x: $0, y: position.y)) }
                    measurement("Y", value: Double(position.y)) { onPosition(CGPoint(x: position.x, y: $0)) }
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text(L("Boyut")).font(.callout.weight(.semibold))
                    measurement(L("Genişlik"), value: Double(size.width)) { value in
                        onSize(CGSize(width: min(1400, max(kind == .board ? 280 : 170, value)), height: size.height))
                    }
                    measurement(L("Yükseklik"), value: Double(size.height)) { value in
                        onSize(CGSize(width: size.width, height: min(1000, max(54, value))))
                    }
                    Button(L("Varsayılan boyuta dön")) { onSize(nil) }
                        .buttonStyle(CanvasToolButtonStyle(accent: kind.accent))
                }
                Divider()
                Button(action: onLink) { Label(L("Bir bloğa bağla"), systemImage: "link") }
                    .buttonStyle(CanvasToolButtonStyle(accent: kind.accent))
                Button(action: onDuplicate) { Label(L("Bloğu çoğalt"), systemImage: "square.on.square") }
                    .buttonStyle(CanvasToolButtonStyle(accent: kind.accent))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func measurement(_ title: String, value: Double, update: @escaping (CGFloat) -> Void) -> some View {
        CanvasMeasurementField(title: title, value: value, update: update)
    }
}

private struct CanvasMeasurementField: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    let title: String
    let value: Double
    let update: (CGFloat) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer()
            TextField(title, text: $draft)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 73)
                .accessibilityLabel(title)
                .focused($focused)
                .onSubmit { commit(); focused = false }
                .onChange(of: focused) { _, active in
                    if !active { commit() }
                }
                .onAppear { refresh() }
                .onChange(of: value) { _, _ in
                    if !focused { refresh() }
                }
        }
    }

    private func refresh() { draft = String(Int(value.rounded())) }

    private func commit() {
        if let number = Double(draft.replacingOccurrences(of: ",", with: ".")), number.isFinite {
            update(CGFloat(max(0, min(100000, number))))
        } else {
            refresh()
        }
    }
}
