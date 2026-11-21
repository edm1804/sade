import AppKit
import SwiftUI

struct WorkspaceView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var selection: UUID?
    @State private var pageToDelete: UUID?
    @State private var showingPages = false
    var openTask: (TaskItem) -> Void

    private var currentID: UUID? {
        if let selection, workspace.pages.contains(where: { $0.id == selection }) {
            return selection
        }
        return workspace.pages.first?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = workspace.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(12)
            }
            if let id = currentID, let index = workspace.pages.firstIndex(where: { $0.id == id }) {
                WorkspaceCanvas(page: $workspace.pages[index], openTask: openTask) {
                    pagesMenu
                }
                .id(id)
            } else {
                VStack(spacing: 13) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(SadePalette.accent)
                        .accessibilityHidden(true)
                    Text("Sade Tuval").font(.system(.title2, design: .rounded).weight(.semibold))
                    Button(action: addPage) {
                        Label(L("Yeni tuval"), systemImage: "plus")
                    }
                        .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, featured: true))
                        .disabled(!workspace.canEdit)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SadePalette.canvas)
        .alert(L("Sayfa silinsin mi?"), isPresented: Binding(
            get: { pageToDelete != nil },
            set: { if !$0 { pageToDelete = nil } }
        )) {
            Button(L("Vazgeç"), role: .cancel) { pageToDelete = nil }
            Button(L("Sil"), role: .destructive) {
                if let id = pageToDelete { workspace.pages.removeAll { $0.id == id } }
                pageToDelete = nil
            }
        } message: {
            Text(L("Bu tuval ve üzerindeki bloklar kaldırılır."))
        }
    }

    private var pagesMenu: some View {
        Button {
            showingPages.toggle()
        } label: {
            Label(L("Tuvaller"), systemImage: "square.on.square")
        }
        .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.rose, selected: showingPages))
        .popover(isPresented: $showingPages, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Button {
                    addPage()
                    showingPages = false
                } label: {
                    Label(L("Yeni tuval"), systemImage: "plus")
                }
                .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, featured: true))
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(workspace.pages) { page in
                            Button {
                                selection = page.id
                                showingPages = false
                            } label: {
                                HStack {
                                    Image(systemName: currentID == page.id ? "checkmark" : "square.dashed")
                                    Text(page.displayTitle).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, selected: currentID == page.id))
                        }
                    }
                }
                .frame(maxHeight: 230)
                Button(role: .destructive) {
                    showingPages = false
                    pageToDelete = currentID
                } label: {
                    Label(L("Bu tuvali sil"), systemImage: "trash")
                }
                .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.rose))
            }
            .padding(12)
            .frame(width: 235)
            .background(SadePalette.paper)
        }
        .fixedSize()
    }

    private func addPage() {
        let page = WorkspacePage()
        workspace.pages.append(page)
        selection = page.id
    }
}

private final class CanvasViewport: ObservableObject {
    @Published var origin: CGPoint = .zero
    weak var surface: NSView?

    func reset() {
        guard let scroll = surface?.enclosingScrollView else { return }
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

private struct WorkspaceCanvas<PageMenu: View>: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    private struct MovingBlock {
        var id: UUID
        var offset: CGSize
    }

    @Binding var page: WorkspacePage
    var openTask: (TaskItem) -> Void
    @ViewBuilder var pageMenu: () -> PageMenu
    @AppStorage("workspaceShowsInsertPanel") private var showPanel = false
    @AppStorage("workspaceShowsDots") private var showDots = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewport = CanvasViewport()
    @State private var zoom: CGFloat = 1
    @State private var measuredSizes: [UUID: CGSize] = [:]
    @State private var selected: UUID?
    @State private var newestBlock: UUID?
    @State private var linkSource: UUID?
    @State private var movingBlock: MovingBlock?
    @State private var commandBlock: UUID?
    @State private var commandSelection = 0
    @State private var blockToDelete: UUID?
    @State private var showingOptions = false
    @State private var inspecting = false
    @AppStorage("canvasSnapToGrid") private var snapToGrid = false
    @FocusState private var focusedBlock: UUID?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                canvas
                if showPanel {
                    HStack(spacing: 0) {
                        Divider()
                        insertPanel
                    }
                    .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .onChange(of: selected) { _, id in
            if id == nil { inspecting = false }
        }
        .alert(L("Blok silinsin mi?"), isPresented: Binding(
            get: { blockToDelete != nil },
            set: { if !$0 { blockToDelete = nil } }
        )) {
            Button(L("Vazgeç"), role: .cancel) { blockToDelete = nil }
            Button(L("Sil"), role: .destructive) {
                if let id = blockToDelete {
                    var updated = page
                    updated.blocks.removeAll { $0.id == id }
                    updated.connections?.removeAll { $0.source == id || $0.target == id }
                    page = updated
                    measuredSizes[id] = nil
                    if selected == id { selected = nil }
                    if commandBlock == id { commandBlock = nil }
                    if linkSource == id { linkSource = nil }
                }
                blockToDelete = nil
            }
        } message: {
            Text(L("Bu bloğun içeriği tuvalden kaldırılır."))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            pageMenu()
            TextField(L("Başlıksız tuval"), text: $page.title)
                .textFieldStyle(.plain)
                .font(.system(size: 23, weight: .medium, design: .serif))
                .accessibilityLabel(L("Tuval adı"))
            Spacer(minLength: 4)
            Button {
                inspecting = selected != nil
                setInsertPanel(!showPanel)
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, selected: showPanel))
            .accessibilityLabel(showPanel ? L("Yan paneli gizle") : L("Yan paneli aç"))
        }
        .padding(.horizontal, 15)
        .padding(.top, 30)
        .padding(.bottom, 8)
        .background(SadePalette.paper)
    }

    private func tools(placements: [UUID: CanvasPlacement], size: CGSize, viewportSize: CGSize) -> some View {
        HStack(spacing: 4) {
            Button { zoom = max(0.1, zoom - 0.25) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.blue))
            .disabled(zoom <= 0.1)
            .help(L("Uzaklaştır"))
            .accessibilityLabel(L("Uzaklaştır"))
            Button { zoom = 1 } label: {
                Text("\(Int(zoom * 100))%").monospacedDigit()
            }
            .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.blue))
            .help(L("Yakınlaştırmayı sıfırla"))
            Button { zoom = min(1.5, zoom + 0.25) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.blue))
            .disabled(zoom >= 1.5)
            .help(L("Yakınlaştır"))
            .accessibilityLabel(L("Yakınlaştır"))
            Divider().frame(height: 16).padding(.horizontal, 2)
            Button {
                showingOptions.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.mint, selected: showingOptions))
            .help(L("Tuval seçenekleri"))
            .accessibilityLabel(L("Tuval seçenekleri"))
            .popover(isPresented: $showingOptions, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    optionButton(L("İçeriği ekrana sığdır"), icon: "arrow.up.left.and.down.right.magnifyingglass") {
                        viewport.reset()
                        fit(placements, in: viewportSize)
                    }
                    optionButton(L("Tuvali genişlet"), icon: "arrow.up.left.and.arrow.down.right") {
                        expand(size)
                    }
                    optionButton(L("Başlangıca dön"), icon: "arrow.uturn.backward") { viewport.reset() }
                    optionButton(showDots ? L("Noktaları gizle") : L("Noktaları göster"), icon: "circle.grid.3x3.fill") { showDots.toggle() }
                    optionButton(snapToGrid ? L("Izgaraya hizalamayı kapat") : L("Izgaraya hizala"), icon: "square.grid.3x3") { snapToGrid.toggle() }
                }
                .padding(9)
                .background(SadePalette.paper)
            }
            Button {
                inspecting = false
                setInsertPanel(!showPanel)
            } label: {
                Label(showPanel ? L("Kapat") : L("Blok ekle"), systemImage: showPanel ? "xmark" : "plus")
            }
            .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, featured: true))
            .help(showPanel ? L("Ekleme panelini gizle") : L("Ekleme panelini göster"))
            .accessibilityLabel(showPanel ? L("Ekleme panelini gizle") : L("Ekleme panelini göster"))
            if selected != nil {
                Button {
                    inspecting = true
                    setInsertPanel(true)
                } label: {
                    Image(systemName: "ruler")
                }
                .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.peach, selected: inspecting && showPanel))
                .help(L("Seçili bloğu düzenle"))
                .accessibilityLabel(L("Seçili bloğu düzenle"))
            }
        }
        .padding(6)
        .background {
            Capsule()
                .fill(SadePalette.paper)
                .overlay { Capsule().strokeBorder(SadePalette.accent.opacity(0.21)) }
                .shadow(color: .black.opacity(0.17), radius: 10, y: 5)
                .allowsHitTesting(false)
        }
    }

    private func optionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showingOptions = false
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.mint))
    }

    private func expand(_ size: CGSize) {
        page.canvasMinimumSize = CGSize(width: size.width + 750, height: size.height + 550)
    }

    private func setInsertPanel(_ isOpen: Bool) {
        guard showPanel != isOpen else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.88)) {
            showPanel = isOpen
            if !isOpen { commandBlock = nil }
        }
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let placements = layout
            let size = contentSize(placements)
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    if let links = page.connections, !links.isEmpty {
                        CanvasArrows(connections: links, frames: linkFrames(placements))
                            .equatable()
                            .allowsHitTesting(false)
                    }
                    CanvasContextSurface(
                        viewport: viewport,
                        onAdd: { kind, point in insert(kind, at: point) },
                        showDots: showDots,
                        onToggleDots: { showDots.toggle() },
                        onExpand: { expand(size) },
                        onFit: { fit(placements, in: geometry.size) },
                        onSelectBackground: {
                            selected = nil
                            focusedBlock = nil
                            commandBlock = nil
                            linkSource = nil
                        }
                    )
                    .accessibilityHidden(true)
                    ForEach($page.blocks) { $block in
                        let id = block.id
                        if let placement = placements[id] {
                            card($block, placement: placement)
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
                .coordinateSpace(name: "sade-canvas")
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(width: size.width * zoom, height: size.height * zoom, alignment: .topLeading)
                .onGeometryChange(for: CGPoint.self) { proxy in
                    proxy.frame(in: .named("sade-viewport")).origin
                } action: { origin in
                    if viewport.origin != origin { viewport.origin = origin }
                }
            }
            .coordinateSpace(name: "sade-viewport")
            .scrollIndicators(.never)
            .background {
                if showDots {
                    SadeDotGrid(viewport: viewport, zoom: zoom)
                        .allowsHitTesting(false)
                } else {
                    SadePalette.boardSurface
                }
            }
            .overlay(alignment: .topLeading) {
                if page.blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Bir fikirle başla."))
                            .font(.system(size: 31, weight: .medium, design: .serif))
                        Text(L("Notlarını, listelerini ve planlarını bu tuvalde bir araya getir."))
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: 300, alignment: .leading)
                        Button {
                            inspecting = false
                            setInsertPanel(true)
                        } label: {
                            Label(L("İlk bloğunu ekle"), systemImage: "plus")
                        }
                        .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, featured: true))
                    }
                    .padding(25)
                    .background(SadePalette.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
                    .padding(30)
                }
            }
            .overlay(alignment: .bottom) {
                tools(placements: placements, size: size, viewportSize: geometry.size)
                    .padding(.bottom, 13)
            }
            .overlay(alignment: .bottomLeading) {
                if linkSource != nil {
                    HStack(spacing: 9) {
                        Image(systemName: "link").foregroundStyle(SadePalette.accent)
                        Text(L("Bağlanacak bloğu seç"))
                        Button {
                            linkSource = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent))
                        .accessibilityLabel(L("Vazgeç"))
                    }
                    .font(.callout)
                    .padding(10)
                    .background(SadePalette.paper, in: RoundedRectangle(cornerRadius: 9))
                    .shadow(color: .black.opacity(0.13), radius: 4, y: 2)
                    .padding(.leading, 16)
                    .padding(.bottom, 66)
                }
            }
        }
    }

    private var insertPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(L("Araçlar")).font(.system(.headline, design: .rounded))
                Spacer()
                Button { setInsertPanel(false) } label: { Image(systemName: "xmark") }
                    .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.rose))
                    .accessibilityLabel(L("Paneli kapat"))
            }
            HStack(spacing: 6) {
                Button(L("Bloklar")) { inspecting = false }
                    .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, selected: !inspecting))
                Button(L("Düzenle")) { inspecting = true }
                    .buttonStyle(CanvasToolButtonStyle(accent: SadePalette.accent, selected: inspecting))
                    .disabled(selected == nil)
            }
            Divider()
            if inspecting, let id = selected,
               let block = page.blocks.first(where: { $0.id == id }), let position = layout[id] {
                CanvasBlockInspector(
                    kind: block.kind,
                    position: position,
                    size: dimensions(block),
                    onPosition: { move(id, to: $0) },
                    onSize: { size in
                        guard let index = page.blocks.firstIndex(where: { $0.id == id }) else { return }
                        page.blocks[index].size = size
                    },
                    onDuplicate: { duplicate(id) },
                    onLink: { link(id) }
                )
                .id(id)
            } else {
                blockLibrary
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(width: 250)
        .background(SadePalette.pages)
    }

    private var blockLibrary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if availableKinds.isEmpty {
                    Text(L("Eşleşen blok yok")).font(.callout).foregroundStyle(.secondary)
                }
                ForEach(Array(availableKinds.enumerated()), id: \.element) { index, kind in
                    Button {
                        if commandBlock != nil {
                            convertCommand(to: kind)
                        } else {
                            insert(kind, at: defaultInsertionPoint())
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 36, height: 36)
                                .foregroundStyle(kind.accent)
                                .background(kind.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.title).font(.callout.weight(.semibold))
                                Text(kind.libraryDescription).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CanvasToolButtonStyle(accent: kind.accent,
                                                       selected: commandBlock != nil && commandSelection == index))
                }
            }
        }
    }

    private func card(_ block: Binding<WorkspaceBlock>, placement: CanvasPlacement) -> some View {
        let id = block.wrappedValue.id
        return CanvasCard(
            kind: block.wrappedValue.kind,
            placement: placement,
            savedSize: block.wrappedValue.size,
            measuredSize: measuredSizes[id],
            animateArrival: newestBlock == id,
            isSelected: selected == id || linkSource == id,
            isLinking: linkSource != nil,
            isLinkSource: linkSource == id,
            onSelect: {
                if linkSource != nil { link(id) }
                else { selected = id }
            },
            onLink: { link(id) },
            onDrag: { translation in
                if translation == .zero {
                    if movingBlock?.id == id { movingBlock = nil }
                } else {
                    selected = id
                    movingBlock = MovingBlock(id: id, offset: translation)
                }
            },
            onMove: { translation in
                movingBlock = nil
                move(id, to: CGPoint(x: placement.x + translation.width, y: placement.y + translation.height))
            },
            onResize: { size in
                selected = id
                block.wrappedValue.size = size
            },
            onDuplicate: { duplicate(id) },
            onDelete: { blockToDelete = id },
            connections: (page.connections ?? [])
                .filter { $0.source == id || $0.target == id }
                .map { edge in
                    let other = edge.source == id ? edge.target : edge.source
                    return CanvasLinkAction(edge: edge, label: (edge.source == id ? "→ " : "← ") + blockName(other))
                },
            onUnlink: { edge in page.connections?.removeAll { $0 == edge } }
        ) {
            WorkspaceBlockEditor(block: block, openTask: openTask, focusedBlock: $focusedBlock)
                .onChange(of: block.wrappedValue.text) { previous, current in
                    if previous.isEmpty && current.hasPrefix("/") {
                        commandBlock = id
                        inspecting = false
                        setInsertPanel(true)
                    }
                    if commandBlock == id {
                        commandSelection = 0
                        if !current.hasPrefix("/") { commandBlock = nil }
                    }
                }
                .onKeyPress(keys: [.return, .escape, .upArrow, .downArrow]) { press in
                    handleKey(press, block: id, placement: placement)
                }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            measuredSizes[id] = size
        }
        .zIndex(selected == id || movingBlock?.id == id ? 1 : 0)
    }

    private func link(_ id: UUID) {
        guard let source = linkSource else {
            linkSource = id
            selected = id
            return
        }
        linkSource = nil
        guard source != id, page.blocks.contains(where: { $0.id == source }) else { return }
        let edge = CanvasConnection(source: source, target: id)
        var edges = page.connections ?? []
        if !edges.contains(edge) {
            edges.append(edge)
            page.connections = edges
        }
        selected = id
    }

    private func blockName(_ id: UUID) -> String {
        guard let block = page.blocks.first(where: { $0.id == id }) else { return L("Blok") }
        let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? block.kind.title : String(text.prefix(40))
    }

    private func linkFrames(_ placements: [UUID: CanvasPlacement]) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        for block in page.blocks {
            guard let p = placements[block.id] else { continue }
            let offset = movingBlock?.id == block.id ? movingBlock?.offset ?? .zero : .zero
            frames[block.id] = CGRect(
                x: max(12, p.x + offset.width),
                y: max(12, p.y + offset.height),
                width: dimensions(block).width,
                height: dimensions(block).height
            )
        }
        return frames
    }

    private var layout: [UUID: CanvasPlacement] {
        var nextY: CGFloat = 38
        var result: [UUID: CanvasPlacement] = [:]
        for block in page.blocks {
            if let placement = block.placement {
                result[block.id] = placement
            } else {
                result[block.id] = CanvasPlacement(x: 38, y: nextY)
                nextY += dimensions(block).height + 20
            }
        }
        return result
    }

    private func estimatedHeight(_ kind: WorkspaceBlockKind) -> CGFloat {
        switch kind {
        case .table: 172
        case .board: 170
        case .checklist: 130
        default: 100
        }
    }

    private func contentSize(_ placements: [UUID: CanvasPlacement]) -> CGSize {
        let extent = occupiedSize(placements)
        return CGSize(width: max(page.canvasMinimumSize?.width ?? 1900, extent.width + 280),
                      height: max(page.canvasMinimumSize?.height ?? 1300, extent.height + 280))
    }

    private func occupiedSize(_ placements: [UUID: CanvasPlacement]) -> CGSize {
        var width: CGFloat = 0
        var height: CGFloat = 0
        for block in page.blocks {
            guard let point = placements[block.id] else { continue }
            let size = dimensions(block)
            width = max(width, point.x + size.width)
            height = max(height, point.y + size.height)
        }
        return CGSize(width: width, height: height)
    }

    private func dimensions(_ block: WorkspaceBlock) -> CGSize {
        measuredSizes[block.id] ?? CGSize(
            width: block.size?.width ?? CanvasCard<EmptyView>.width(for: block.kind),
            height: max(block.size?.height ?? 0, estimatedHeight(block.kind))
        )
    }

    private func fit(_ placements: [UUID: CanvasPlacement], in viewportSize: CGSize) {
        guard !placements.isEmpty else { zoom = 1; return }
        let occupied = occupiedSize(placements)
        zoom = max(0.03, min(1, viewportSize.width / (occupied.width + 30),
                            viewportSize.height / (occupied.height + 30)))
    }

    private func defaultInsertionPoint() -> CGPoint {
        let start = CGPoint(x: max(22, -viewport.origin.x / zoom + 36),
                            y: max(22, -viewport.origin.y / zoom + 38))
        let placements = layout
        var y = start.y
        // Start inside the visible area, below any card occupying this spot.
        for block in page.blocks.sorted(by: { (placements[$0.id]?.y ?? 0) < (placements[$1.id]?.y ?? 0) }) {
            guard let p = placements[block.id], abs(p.x - start.x) < 290 else { continue }
            let bottom = p.y + dimensions(block).height + 18
            if p.y < y + 125 && bottom > y { y = bottom }
        }
        return CGPoint(x: start.x, y: y)
    }

    private func fixedLayout() -> [WorkspaceBlock] {
        let current = layout
        return page.blocks.map { block in
            var block = block
            block.placement = current[block.id]
            return block
        }
    }

    private func placement(at point: CGPoint) -> CanvasPlacement {
        let x = snapToGrid ? (point.x / 20).rounded() * 20 : point.x
        let y = snapToGrid ? (point.y / 20).rounded() * 20 : point.y
        return CanvasPlacement(x: max(12, x), y: max(12, y))
    }

    private func insert(_ kind: WorkspaceBlockKind, at point: CGPoint) {
        var block = WorkspaceBlock(kind: kind, placement: placement(at: point))
        if kind == .checklist { block.checklist = [Subtask(title: "")] }
        newestBlock = block.id
        page.blocks = fixedLayout() + [block]
        selected = block.id
        commandBlock = nil
        focusIfText(kind, id: block.id)
    }

    private func move(_ id: UUID, to point: CGPoint) {
        var blocks = fixedLayout()
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].placement = placement(at: point)
        page.blocks = blocks
    }

    private func duplicate(_ id: UUID) {
        var blocks = fixedLayout()
        guard var copy = blocks.first(where: { $0.id == id }), let p = copy.placement else { return }
        copy.id = UUID()
        copy.placement = placement(at: CGPoint(x: p.x + 26, y: p.y + 26))
        blocks.append(copy)
        newestBlock = copy.id
        page.blocks = blocks
        selected = copy.id
    }

    private var availableKinds: [WorkspaceBlockKind] {
        guard let commandBlock,
              let block = page.blocks.first(where: { $0.id == commandBlock }) else {
            return WorkspaceBlockKind.allCases
        }
        let query = block.text.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkspaceBlockKind.allCases.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    }

    private func handleKey(_ press: KeyPress, block id: UUID, placement: CanvasPlacement) -> KeyPress.Result {
        guard focusedBlock == id else { return .ignored }
        if commandBlock == id {
            switch press.key {
            case .escape:
                commandBlock = nil
            case .upArrow:
                commandSelection = max(0, commandSelection - 1)
            case .downArrow:
                commandSelection = max(0, min(availableKinds.count - 1, commandSelection + 1))
            case .return:
                if availableKinds.indices.contains(commandSelection) {
                    convertCommand(to: availableKinds[commandSelection])
                }
            default:
                return .ignored
            }
            return .handled
        }
        guard press.key == .return, press.modifiers.isEmpty else { return .ignored }
        let y = placement.y + (measuredSizes[id]?.height ?? 100) + 20
        insert(.text, at: CGPoint(x: placement.x, y: y))
        return .handled
    }

    private func convertCommand(to kind: WorkspaceBlockKind) {
        guard let id = commandBlock, let index = page.blocks.firstIndex(where: { $0.id == id }) else { return }
        focusedBlock = nil
        commandBlock = nil
        var block = WorkspaceBlock(id: id, kind: kind, placement: page.blocks[index].placement, size: page.blocks[index].size)
        if kind == .checklist { block.checklist = [Subtask(title: "")] }
        page.blocks[index] = block
        selected = id
        Task { @MainActor in
            await Task.yield()
            focusIfText(kind, id: id)
        }
    }

    private func focusIfText(_ kind: WorkspaceBlockKind, id: UUID) {
        focusedBlock = kind == .text || kind == .heading ? id : nil
    }
}

private struct CanvasLinkAction: Identifiable {
    let edge: CanvasConnection
    let label: String
    var id: CanvasConnection { edge }
}

private struct CanvasCard<Content: View>: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    var kind: WorkspaceBlockKind
    var placement: CanvasPlacement
    var savedSize: CGSize?
    var measuredSize: CGSize?
    var animateArrival: Bool
    var isSelected: Bool
    var isLinking: Bool
    var isLinkSource: Bool
    var onSelect: () -> Void
    var onLink: () -> Void
    var onDrag: (CGSize) -> Void
    var onMove: (CGSize) -> Void
    var onResize: (CGSize?) -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var connections: [CanvasLinkAction]
    var onUnlink: (CanvasConnection) -> Void
    @ViewBuilder var content: () -> Content
    @GestureState private var drag: CGSize = .zero
    @GestureState private var resizeDelta: CGSize = .zero
    @State private var resizeBase: CGSize?
    @State private var isHovered = false

    static func width(for kind: WorkspaceBlockKind) -> CGFloat {
        switch kind {
        case .board: 465
        case .table: 402
        default: 310
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(kind.accent.opacity(0.70))
                    Image(systemName: kind.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 21, height: 21)
                        .background(kind.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityHidden(true)
                    Text(kind.title)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(kind.accent)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .help(L("Bloğu taşımak için sürükle"))
                .onTapGesture(perform: onSelect)
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named("sade-canvas"))
                        .updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { value in onMove(value.translation) }
                )
                Button(action: onLink) {
                    Image(systemName: isLinkSource ? "xmark.circle" : "link")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(kind.accent)
                        .frame(width: 25, height: 23)
                        .background(isLinking ? kind.accent.opacity(0.18) : .clear, in: Capsule())
                }
                .buttonStyle(CanvasToolButtonStyle(accent: kind.accent, selected: isLinking, compact: true))
                .help(linkHelp)
                .accessibilityLabel(linkHelp)
                .opacity(isHovered || isSelected || isLinking ? 1 : 0.62)
                Menu {
                    cardOptions
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(kind.accent)
                        .frame(width: 22, height: 23)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(L("Blok işlemleri"))
                .opacity(isHovered || isSelected ? 1 : 0.62)
                .padding(.trailing, 7)
            }
            .background(kind.accent.opacity(isSelected ? 0.17 : 0.10))
            content()
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
        }
        .frame(width: previewSize?.width ?? savedSize?.width ?? Self.width(for: kind))
        .frame(minHeight: previewSize?.height ?? savedSize?.height ?? 0, alignment: .topLeading)
        .background {
            ZStack {
                SadePalette.paper
                kind.accent.opacity(0.045)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(kind.accent.opacity(isSelected ? 0.76 : 0.23))
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(kind.accent.opacity(isHovered || isSelected ? 1 : 0.58))
                .frame(width: 23, height: 23)
                .background(kind.accent.opacity(0.09), in: Circle())
                .contentShape(Rectangle())
                .padding(4)
                .help(L("Boyutlandırmak için sürükle"))
                .accessibilityLabel(L("Bloğu boyutlandır"))
                .gesture(resizeGesture)
        }
        .onHover { isHovered = $0 }
        .contextMenu { cardOptions }
        .shadow(color: .black.opacity(drag == .zero ? 0.10 : 0.23), radius: drag == .zero ? 7 : 13, y: 4)
        .modifier(CanvasBlockArrival(isNew: animateArrival))
        .offset(x: max(12, placement.x + drag.width), y: max(12, placement.y + drag.height))
        .onChange(of: drag) { _, translation in onDrag(translation) }
        .onChange(of: resizeDelta) { _, delta in
            if delta == .zero { resizeBase = nil }
        }
    }

    @ViewBuilder private var cardOptions: some View {
        Button(L("Bağla"), action: onLink)
        Menu(L("Boyut")) {
            Button(L("Küçük")) { onResize(CGSize(width: Self.width(for: kind) * 0.75, height: 0)) }
            Button(L("Geniş")) { onResize(CGSize(width: Self.width(for: kind) * 1.4, height: 0)) }
            Button(L("Varsayılan boyut")) { onResize(nil) }
        }
        Button(L("Çoğalt"), action: onDuplicate)
        if !connections.isEmpty {
            Menu(L("Bağlantıyı kaldır")) {
                ForEach(connections) { connection in
                    Button(connection.label) { onUnlink(connection.edge) }
                }
            }
        }
        Button(L("Sil"), role: .destructive, action: onDelete)
    }

    private var previewSize: CGSize? {
        resizeBase.map { resized(from: $0, by: resizeDelta) }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("sade-canvas"))
            .updating($resizeDelta) { value, delta, _ in delta = value.translation }
            .onChanged { _ in
                if resizeBase == nil {
                    resizeBase = measuredSize ?? savedSize ?? CGSize(width: Self.width(for: kind), height: 80)
                }
            }
            .onEnded { value in
                if let resizeBase { onResize(resized(from: resizeBase, by: value.translation)) }
                resizeBase = nil
            }
    }

    private func resized(from base: CGSize, by delta: CGSize) -> CGSize {
        let minimumWidth = kind == .board ? 280.0 : 170.0
        return CGSize(width: min(1400, max(minimumWidth, base.width + delta.width)),
                      height: min(1000, max(54, base.height + delta.height)))
    }

    private var linkHelp: String {
        if isLinkSource { return L("Bağlantıdan vazgeç") }
        return isLinking ? L("Bu bloğa bağla") : L("Bağla")
    }
}

private struct CanvasBlockArrival: ViewModifier {
    var isNew: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private var visible: Bool { hasAppeared || !isNew || reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.93, anchor: .topLeading)
            .offset(y: visible ? 0 : 7)
            .task {
                if isNew && !reduceMotion {
                    await Task.yield()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
                        hasAppeared = true
                    }
                } else {
                    hasAppeared = true
                }
            }
    }
}

private struct CanvasArrows: View, Equatable {
    var connections: [CanvasConnection]
    var frames: [UUID: CGRect]

    var body: some View {
        Canvas { context, _ in
            for edge in connections {
                guard let source = frames[edge.source], let target = frames[edge.target] else { continue }
                let line = route(from: source, to: target)
                context.stroke(line.path, with: .color(SadePalette.accent), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                context.fill(arrowhead(at: line.end, angle: line.angle), with: .color(SadePalette.accent))
            }
        }
        .accessibilityHidden(true)
    }

    private func route(from source: CGRect, to target: CGRect) -> (path: Path, end: CGPoint, angle: CGFloat) {
        var path = Path()
        if source.insetBy(dx: -6, dy: -6).intersects(target) {
            let start = CGPoint(x: source.maxX, y: source.midY - 6)
            let end = CGPoint(x: target.maxX + 2, y: target.midY + 6)
            let outerX = max(start.x, end.x) + 70
            let first = CGPoint(x: outerX, y: start.y - 24)
            let second = CGPoint(x: outerX, y: end.y)
            path.move(to: start)
            path.addCurve(to: end, control1: first, control2: second)
            return (path, end, .pi)
        }

        let dx = target.midX - source.midX
        let dy = target.midY - source.midY
        let start = boundary(of: source, dx: dx, dy: dy)
        let end = boundary(of: target.insetBy(dx: -2, dy: -2), dx: -dx, dy: -dy)
        path.move(to: start)
        path.addLine(to: end)
        return (path, end, atan2(dy, dx))
    }

    private func boundary(of rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGPoint {
        let scaleX = dx == 0 ? CGFloat.infinity : (rect.width / 2) / abs(dx)
        let scaleY = dy == 0 ? CGFloat.infinity : (rect.height / 2) / abs(dy)
        let scale = min(scaleX, scaleY)
        return CGPoint(x: rect.midX + dx * scale, y: rect.midY + dy * scale)
    }

    private func arrowhead(at end: CGPoint, angle: CGFloat) -> Path {
        let spread: CGFloat = .pi / 6
        let length: CGFloat = 10
        var path = Path()
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - cos(angle - spread) * length,
                                 y: end.y - sin(angle - spread) * length))
        path.addLine(to: CGPoint(x: end.x - cos(angle + spread) * length,
                                 y: end.y - sin(angle + spread) * length))
        path.closeSubpath()
        return path
    }
}

private struct SadeDotGrid: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @ObservedObject var viewport: CanvasViewport
    var zoom: CGFloat

    var body: some View {
        let spacing = max(8, 20 * zoom)
        let xStart = (viewport.origin.x + 10 * zoom).truncatingRemainder(dividingBy: spacing)
        let yStart = (viewport.origin.y + 10 * zoom).truncatingRemainder(dividingBy: spacing)
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: xStart, to: size.width, by: spacing) {
                for y in stride(from: yStart, to: size.height, by: spacing) {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 1.5 * zoom, height: 1.5 * zoom))
                }
            }
            context.fill(dots, with: .color(SadePalette.accent.opacity(0.16)))
        }
        .background(SadePalette.boardSurface)
        .accessibilityHidden(true)
    }
}

private struct CanvasContextSurface: NSViewRepresentable {
    var viewport: CanvasViewport
    var onAdd: (WorkspaceBlockKind, CGPoint) -> Void
    var showDots: Bool
    var onToggleDots: () -> Void
    var onExpand: () -> Void
    var onFit: () -> Void
    var onSelectBackground: () -> Void

    func makeNSView(context: Context) -> Surface { Surface() }

    func updateNSView(_ view: Surface, context: Context) {
        viewport.surface = view
        view.onAdd = onAdd
        view.showDots = showDots
        view.onToggleDots = onToggleDots
        view.onExpand = onExpand
        view.onFit = onFit
        view.onSelectBackground = onSelectBackground
    }

    final class Surface: NSView {
        var onAdd: ((WorkspaceBlockKind, CGPoint) -> Void)?
        var showDots = true
        var onToggleDots: (() -> Void)?
        var onExpand: (() -> Void)?
        var onFit: (() -> Void)?
        var onSelectBackground: (() -> Void)?
        private var menuPoint: CGPoint = .zero
        private var panStart: CGPoint?
        private var clipStart: CGPoint = .zero
        private var isPanning = false
        override var isFlipped: Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control), let menu = menu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            } else {
                onSelectBackground?()
                panStart = event.locationInWindow
                clipStart = enclosingScrollView?.contentView.bounds.origin ?? .zero
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let panStart, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            let clip = scroll.contentView
            let start = clip.convert(panStart, from: nil)
            let current = clip.convert(event.locationInWindow, from: nil)
            let dx = current.x - start.x
            let dy = current.y - start.y
            if !isPanning {
                guard abs(dx) + abs(dy) > 3 else { return }
                isPanning = true
                NSCursor.closedHand.set()
            }
            let x = min(max(0, document.frame.width - clip.bounds.width), max(0, clipStart.x - dx))
            let y = min(max(0, document.frame.height - clip.bounds.height), max(0, clipStart.y - dy))
            clip.scroll(to: CGPoint(x: x, y: y))
            scroll.reflectScrolledClipView(clip)
        }

        override func mouseUp(with event: NSEvent) {
            panStart = nil
            if isPanning {
                isPanning = false
                NSCursor.openHand.set()
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            if let menu = menu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            menuPoint = convert(event.locationInWindow, from: nil)
            let menu = NSMenu()
            for kind in WorkspaceBlockKind.allCases {
                let item = NSMenuItem(title: L("Ekle: %@", kind.title), action: #selector(addBlock(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = kind.rawValue
                item.image = NSImage(systemSymbolName: kind.icon, accessibilityDescription: nil)
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let options = NSMenu()
            addOption(L("Tuvali genişlet"), action: #selector(expand), to: options)
            addOption(L("İçeriği ekrana sığdır"), action: #selector(fit), to: options)
            addOption(L("Başlangıca dön"), action: #selector(resetPosition), to: options)
            addOption(showDots ? L("Noktaları gizle") : L("Noktaları göster"), action: #selector(toggleDots), to: options)
            let group = NSMenuItem(title: L("Tuval seçenekleri"), action: nil, keyEquivalent: "")
            group.submenu = options
            menu.addItem(group)
            return menu
        }

        private func addOption(_ title: String, action: Selector, to menu: NSMenu) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        @objc private func expand() { onExpand?() }
        @objc private func toggleDots() { onToggleDots?() }
        @objc private func fit() {
            resetPosition()
            onFit?()
        }
        @objc private func resetPosition() {
            guard let scroll = enclosingScrollView else { return }
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        @objc private func addBlock(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let kind = WorkspaceBlockKind(rawValue: rawValue) else { return }
            onAdd?(kind, menuPoint)
        }
    }
}
