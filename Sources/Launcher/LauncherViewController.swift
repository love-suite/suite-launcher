import AppKit
import LauncherCore

// MARK: Grid item

/// Custom: the order given by dragging items between others.
enum SortMode { case name, date, custom }

enum LauncherGridItem {
    case app(AppItem)
    case folder(LauncherFolder)

    var entry: GridEntry {
        switch self {
        case .app(let app): return .app(app.id)
        case .folder(let folder): return .folder(folder.id)
        }
    }
}

/// What is being dragged over the grid: one of its own items, or an app out of a folder.
private enum DraggedItem {
    case grid(GridEntry)
    case folderApp(appID: String, folderID: String)

    var entry: GridEntry {
        switch self {
        case .grid(let entry): return entry
        case .folderApp(let appID, _): return .app(appID)
        }
    }

    init?(_ pasteboard: NSPasteboard) {
        if let key = pasteboard.string(forType: .launcherGridEntry), let entry = GridEntry(key: key) {
            self = .grid(entry)
        } else if let value = pasteboard.string(forType: .launcherFolderItem),
                  let bar = value.lastIndex(of: "|") {
            self = .folderApp(appID: String(value[..<bar]), folderID: String(value[value.index(after: bar)...]))
        } else {
            return nil
        }
    }
}

// MARK: View controller

final class LauncherViewController: NSViewController {
    var onDismiss: (() -> Void)?
    var settings = LauncherSettings() { didSet { applySettings() } }

    private var allApps: [AppItem] = []
    private var filteredItems: [LauncherGridItem] = []
    let folderStore = LauncherFolderStore()
    private var folderPanel: FolderPanelView?

    private var sortMode: SortMode = .name
    private let sortLabel: NSTextField = {
        let f = NSTextField(labelWithString: "Sort By")
        f.textColor = NSColor.white.withAlphaComponent(0.7)
        f.font = .systemFont(ofSize: 12)
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }()
    private let sortControl = NSSegmentedControl(labels: ["Name", "Date", "Custom"],
                                                  trackingMode: .selectOne,
                                                  target: nil, action: nil)
    private var draggingSourceIndexPath: IndexPath?
    private var hoveredIndexPath: IndexPath?

    private let searchField = NSSearchField()
    private let collectionView = GridCollectionView()
    private let dropMarker = DropMarker()
    private let scrollView = NSScrollView()

    override func loadView() {
        let bg = BackgroundView(
            onClickOutside: { [weak self] in
                guard self?.settings.dismissOnClickOutside == true else { return }
                self?.onDismiss?()
            },
            onRightClick: { [weak self] event in self?.showBackgroundMenu(at: event) }
        )
        view = bg

        let fx = PassthroughEffectView()
        fx.material = .fullScreenUI
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.appearance = NSAppearance(named: .darkAqua)
        fx.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fx)

        let dim = PassthroughView()
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        dim.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dim)

        searchField.placeholderString = "Search"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.isContinuous = true
        searchField.delegate = self
        view.addSubview(searchField)

        sortControl.selectedSegment = 0
        sortControl.translatesAutoresizingMaskIntoConstraints = false
        sortControl.target = self
        sortControl.action = #selector(sortChanged)
        view.addSubview(sortLabel)
        view.addSubview(sortControl)

        view.addTrackingArea(NSTrackingArea(rect: .zero,
                                             options: [.mouseMoved, .mouseEnteredAndExited,
                                                       .activeAlways, .inVisibleRect],
                                             owner: self, userInfo: nil))

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 90, height: 100)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 16
        layout.sectionInset = NSEdgeInsets(top: 20, left: 40, bottom: 40, right: 40)

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(AppCell.self, forItemWithIdentifier: AppCell.identifier)
        collectionView.register(FolderCell.self, forItemWithIdentifier: FolderCell.identifier)
        collectionView.addSubview(dropMarker)
        collectionView.onDragGone = { [weak self] in self?.showDropMarker(before: nil) }
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.setDraggingSourceOperationMask(.every, forLocal: true)
        collectionView.registerForDraggedTypes([.launcherGridEntry, .launcherFolderItem])

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            fx.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fx.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fx.topAnchor.constraint(equalTo: view.topAnchor),
            fx.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dim.topAnchor.constraint(equalTo: view.topAnchor),
            dim.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            searchField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 60),
            searchField.widthAnchor.constraint(equalToConstant: 300),

            sortLabel.trailingAnchor.constraint(equalTo: sortControl.leadingAnchor, constant: -6),
            sortLabel.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            sortControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            sortControl.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        allApps = AppScanner.scan()
        restoreSortMode()
        applyFilter()
    }

    func prepareToShow() {
        folderStore.reload()
        allApps = AppScanner.scan()
        searchField.stringValue = ""
        restoreSortMode()
        applyFilter()
        view.window?.makeFirstResponder(searchField)
    }

    private func applySettings() {}

    @objc private func searchChanged() { applyFilter() }

    private func restoreSortMode() {
        if folderStore.layout.isCustom { setSortMode(.custom) } else if sortMode == .custom { setSortMode(.name) }
    }

    private func setSortMode(_ mode: SortMode) {
        sortMode = mode
        sortControl.selectedSegment = [SortMode.name, .date, .custom].firstIndex(of: mode) ?? 0
    }

    @objc private func sortChanged() {
        let mode: SortMode = [.name, .date, .custom][max(0, sortControl.selectedSegment)]
        sortMode = mode
        var layout = folderStore.layout
        layout.isCustom = mode == .custom
        folderStore.setLayout(layout)
        applyFilter()
    }

    override func mouseMoved(with event: NSEvent) {
        guard folderPanel == nil else { return }
        let pt = collectionView.convert(event.locationInWindow, from: nil)
        updateHovered(to: collectionView.indexPathForItem(at: pt))
    }

    override func mouseExited(with event: NSEvent) {
        updateHovered(to: nil)
    }

    private func updateHovered(to path: IndexPath?) {
        if path == hoveredIndexPath { return }
        if let old = hoveredIndexPath {
            (collectionView.item(at: old) as? AppCell)?.setHovered(false)
            (collectionView.item(at: old) as? FolderCell)?.setHovered(false)
        }
        hoveredIndexPath = path
        if let new = path {
            (collectionView.item(at: new) as? AppCell)?.setHovered(true)
            (collectionView.item(at: new) as? FolderCell)?.setHovered(true)
        }
    }

    func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        let inFolders = folderStore.appIDsInFolders()
        var sorted = allApps
        if sortMode == .date {
            sorted.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        } else {
            sorted.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        if query.isEmpty {
            let folderItems = folderStore.folders.map { LauncherGridItem.folder($0) }
            let appItems = sorted.filter { !inFolders.contains($0.id) }.map { LauncherGridItem.app($0) }
            let items = folderItems + appItems
            if sortMode == .custom {
                let byEntry = Dictionary(items.map { ($0.entry, $0) }, uniquingKeysWith: { a, _ in a })
                filteredItems = folderStore.layout.arrange(items.map(\.entry)).compactMap { byEntry[$0] }
            } else {
                filteredItems = items
            }
        } else {
            filteredItems = sorted
                .filter { $0.name.localizedCaseInsensitiveContains(query) }
                .map { LauncherGridItem.app($0) }
        }
        updateHovered(to: nil)
        collectionView.reloadData()
    }

    // MARK: Context menus

    func showContextMenu(for item: LauncherGridItem, at event: NSEvent) {
        let menu = NSMenu()
        switch item {
        case .app(let app):
            addItem(menu, "Open", #selector(menuOpen), app)
            menu.addItem(.separator())
            addItem(menu, "Show in Applications Folder", #selector(menuReveal), app)
            if !folderStore.folders.isEmpty {
                menu.addItem(.separator())
                let sub = NSMenu()
                for f in folderStore.folders {
                    addItem(sub, f.name, #selector(menuAddToFolder), FolderAssignmentBox(app, f))
                }
                let mi = NSMenuItem(title: "Add to Folder", action: nil, keyEquivalent: "")
                mi.submenu = sub
                menu.addItem(mi)
            }
        case .folder(let folder):
            addItem(menu, "Open", #selector(menuOpenFolder), folder)
            addItem(menu, "Open All", #selector(menuOpenAll), folder)
            menu.addItem(.separator())
            addItem(menu, "Rename", #selector(menuRenameFolder), folder)
            menu.addItem(.separator())
            addItem(menu, "Remove Folder", #selector(menuRemoveFolder), folder)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func showBackgroundMenu(at event: NSEvent) {
        let menu = NSMenu()
        addItem(menu, "New Folder", #selector(menuNewFolder), nil)
        menu.addItem(.separator())
        addItem(menu, "Sort By Name", #selector(menuSortByName), nil)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @discardableResult
    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector,
                         _ rep: Any?) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.representedObject = rep
        menu.addItem(mi)
        return mi
    }

    @objc private func menuOpen(_ sender: NSMenuItem) {
        (sender.representedObject as? AppItem).map { launch($0) }
    }

    @objc private func menuReveal(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? AppItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    @objc private func menuAddToFolder(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? FolderAssignmentBox else { return }
        var folder = box.folder
        guard !folder.appIDs.contains(box.app.id) else { return }
        folder.appIDs.append(box.app.id)
        folderStore.update(folder)
        applyFilter()
    }

    @objc private func menuOpenFolder(_ sender: NSMenuItem) {
        (sender.representedObject as? LauncherFolder).map { openFolder($0) }
    }

    @objc private func menuOpenAll(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? LauncherFolder else { return }
        allApps.filter { folder.appIDs.contains($0.id) }.forEach { launch($0) }
    }

    @objc private func menuRenameFolder(_ sender: NSMenuItem) {
        guard var folder = sender.representedObject as? LauncherFolder else { return }
        promptText(title: "Rename Folder", placeholder: folder.name) { [weak self] name in
            folder.name = name; self?.folderStore.update(folder); self?.applyFilter()
        }
    }

    @objc private func menuRemoveFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? LauncherFolder else { return }
        folderStore.remove(id: folder.id)
        applyFilter()
    }

    @objc private func menuNewFolder(_ sender: NSMenuItem) {
        promptText(title: "New Folder", placeholder: "Folder name") { [weak self] name in
            self?.folderStore.add(LauncherFolder(name: name)); self?.applyFilter()
        }
    }

    @objc private func menuSortByName(_ sender: NSMenuItem) {
        sortControl.selectedSegment = 0
        sortChanged()
    }

    private func promptText(title: String, placeholder: String, completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = placeholder
        field.stringValue = placeholder == field.stringValue ? "" : placeholder
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        completion(name)
    }

    // MARK: Launch + folder open

    func launch(_ app: AppItem) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, _ in }
        onDismiss?()
    }

    func openFolder(_ folder: LauncherFolder) {
        let apps = allApps.filter { folder.appIDs.contains($0.id) }
        folderPanel?.removeFromSuperview()
        let panel = FolderPanelView(folder: folder, apps: apps, viewController: self)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        folderPanel = panel
    }

    func closeFolderPanel() {
        folderPanel?.removeFromSuperview()
        folderPanel = nil
    }

    /// The app leaves its folder for the grid: right after the folder in the custom order (the folder
    /// itself goes when a single app is left in it, that app in its place).
    func takeOutOfFolder(_ appID: String, folderID: String) {
        if sortMode == .custom, let i = filteredItems.firstIndex(where: { $0.entry == .folder(folderID) }) {
            folderStore.setLayout(LauncherLayout.moving(.app(appID), before: i + 1,
                                                        in: filteredItems.map(\.entry)))
        }
        folderStore.takeApp(appID, outOf: folderID)
        applyFilter()
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, settings.dismissOnEsc {
            if folderPanel != nil { closeFolderPanel() } else { onDismiss?() }
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: Pasteboard type

extension NSPasteboard.PasteboardType {
    /// An app or a folder of the grid, as its `GridEntry.key`.
    static let launcherGridEntry = NSPasteboard.PasteboardType("local.suite.launcher.gridEntry")
    /// An app in a folder: "appID|folderID".
    static let launcherFolderItem = NSPasteboard.PasteboardType("local.suite.launcher.folderItem")
}

// MARK: NSSearchFieldDelegate

extension LauncherViewController: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(cancelOperation(_:)),
              settings.dismissOnEsc else { return false }
        if folderPanel != nil { closeFolderPanel(); return true }
        if searchField.stringValue.isEmpty { onDismiss?() }
        else { searchField.stringValue = ""; applyFilter() }
        return true
    }
}

// MARK: NSCollectionViewDataSource

extension LauncherViewController: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView,
                        numberOfItemsInSection section: Int) -> Int { filteredItems.count }

    func collectionView(_ collectionView: NSCollectionView,
                        pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(filteredItems[indexPath.item].entry.key, forType: .launcherGridEntry)
        return item
    }


    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        switch filteredItems[indexPath.item] {
        case .app(let app):
            let cell = collectionView.makeItem(withIdentifier: AppCell.identifier,
                                               for: indexPath) as! AppCell
            cell.configure(with: app)
            cell.onRightClick = { [weak self] event in
                self?.showContextMenu(for: .app(app), at: event)
            }
            return cell
        case .folder(let folder):
            let cell = collectionView.makeItem(withIdentifier: FolderCell.identifier,
                                               for: indexPath) as! FolderCell
            let folderApps = allApps.filter { folder.appIDs.contains($0.id) }
            cell.configure(with: folder, apps: folderApps)
            cell.onRightClick = { [weak self] event in
                self?.showContextMenu(for: .folder(folder), at: event)
            }
            return cell
        }
    }
}

// MARK: NSCollectionViewDelegate

extension LauncherViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView,
                        didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let i = indexPaths.first?.item else { return }
        collectionView.deselectAll(nil)
        let item = filteredItems[i]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.draggingSourceIndexPath == nil else { return }
            switch item {
            case .app(let app): self.launch(app)
            case .folder(let folder): self.openFolder(folder)
            }
        }
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint,
                        forItemsAt indexPaths: Set<IndexPath>) {
        draggingSourceIndexPath = indexPaths.first
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint,
                        dragOperation operation: NSDragOperation) {
        draggingSourceIndexPath = nil
    }

    func collectionView(_ collectionView: NSCollectionView,
                        validateDrop draggingInfo: NSDraggingInfo,
                        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        showDropMarker(before: nil)
        // The folder's box still shows: the drop is for it, not for the grid underneath.
        if let panel = folderPanel, !panel.isHidden { return [] }
        guard let dragged = DraggedItem(draggingInfo.draggingPasteboard) else { return [] }
        var (index, on) = dropTarget(draggingInfo, proposed: proposedDropIndexPath.pointee.item)
        if on, !canDrop(dragged, onto: filteredItems[index]) { on = false }
        if !on, isSearching { return [] }
        proposedDropIndexPath.pointee = IndexPath(item: index, section: 0) as NSIndexPath
        proposedDropOperation.pointee = on ? .on : .before
        if !on { showDropMarker(before: index) }
        return .move
    }

    /// A white bar in the gap the item will be dropped into; nil hides it.
    private func showDropMarker(before index: Int?) {
        guard let index, !filteredItems.isEmpty else { dropMarker.isHidden = true; return }
        func frame(_ i: Int) -> NSRect? {
            collectionView.layoutAttributesForItem(at: IndexPath(item: i, section: 0))?.frame
        }
        let next = index < filteredItems.count ? frame(index) : nil
        let previous = index > 0 ? frame(index - 1) : nil
        let x: CGFloat
        let row: NSRect
        if let next, let previous, abs(previous.midY - next.midY) < 1 {
            x = (previous.maxX + next.minX) / 2; row = next
        } else if let next {
            x = next.minX - 6; row = next
        } else if let previous {
            x = previous.maxX + 6; row = previous
        } else {
            dropMarker.isHidden = true; return
        }
        // Along the icon, at the top of the cell (the grid is flipped).
        dropMarker.frame = NSRect(x: (x - 2).rounded(), y: row.minY + 4, width: 4, height: 56)
        dropMarker.isHidden = false
    }

    func collectionView(_ collectionView: NSCollectionView,
                        acceptDrop draggingInfo: NSDraggingInfo,
                        indexPath: IndexPath,
                        dropOperation: NSCollectionView.DropOperation) -> Bool {
        showDropMarker(before: nil)
        guard let dragged = DraggedItem(draggingInfo.draggingPasteboard) else { return false }
        let shown = filteredItems.map(\.entry)
        if dropOperation == .on {
            guard indexPath.item < filteredItems.count, canDrop(dragged, onto: filteredItems[indexPath.item]),
                  case .app(let appID) = dragged.entry else { return false }
            switch filteredItems[indexPath.item] {
            case .app(let target):
                let name = allApps.first { $0.id == appID }?.categoryName ?? "Folder"
                let folder = LauncherFolder(name: name, appIDs: [target.id, appID])
                folderStore.add(folder)
                if sortMode == .custom {
                    folderStore.setLayout(LauncherLayout(isCustom: true, order: shown.map(\.key))
                        .replacing(.app(target.id), with: .folder(folder.id)))
                }
            case .folder(var folder):
                folder.appIDs.append(appID)
                folderStore.update(folder)
            }
        } else {
            guard !isSearching else { return false }
            folderStore.setLayout(LauncherLayout.moving(dragged.entry, before: indexPath.item, in: shown))
            setSortMode(.custom)
        }
        // Last, so that a folder left with a single app is replaced by it where the folder now is.
        if case .folderApp(let appID, let folderID) = dragged { folderStore.takeApp(appID, outOf: folderID) }
        applyFilter()
        return true
    }

    private var isSearching: Bool { !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Over the middle of an item, on it (an app on an app makes a folder, on a folder goes into it);
    /// over its left or right quarter, or in a gap, between items.
    private func dropTarget(_ info: NSDraggingInfo, proposed: Int) -> (index: Int, on: Bool) {
        let point = collectionView.convert(info.draggingLocation, from: nil)
        guard let path = collectionView.indexPathForItem(at: point),
              let frame = collectionView.layoutAttributesForItem(at: path)?.frame, frame.width > 0
        else { return (min(proposed, filteredItems.count), false) }
        let x = (point.x - frame.minX) / frame.width
        if x < 0.25 { return (path.item, false) }
        if x > 0.75 { return (path.item + 1, false) }
        return (path.item, true)
    }

    private func canDrop(_ dragged: DraggedItem, onto target: LauncherGridItem) -> Bool {
        guard case .app(let appID) = dragged.entry else { return false }
        switch target {
        case .app(let app): return app.id != appID
        case .folder(let folder): return !folder.appIDs.contains(appID)
        }
    }
}

// MARK: The grid, telling when a drag leaves it

private final class GridCollectionView: NSCollectionView {
    var onDragGone: (() -> Void)?
    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        onDragGone?()
    }
    override func draggingEnded(_ sender: NSDraggingInfo) {
        super.draggingEnded(sender)
        onDragGone?()
    }
}

// MARK: Where a dragged item will land between two others

private final class DropMarker: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 2
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.6
        layer?.shadowRadius = 3
        layer?.shadowOffset = .zero
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: Passthrough (non-interactive background) views

private final class PassthroughEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: Background view

private final class BackgroundView: NSView {
    var onClickOutside: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    init(onClickOutside: @escaping () -> Void, onRightClick: @escaping (NSEvent) -> Void) {
        self.onClickOutside = onClickOutside; self.onRightClick = onRightClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hitTest(p) === self { onClickOutside?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hitTest(p) === self { onRightClick?(event) }
    }
}

// MARK: Folder collection view (apps open on release, not on press)

private final class FolderCollectionView: NSCollectionView {
    var onMouseDown: (() -> Void)?
    var onMouseUp: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onMouseUp?()
    }
}

// MARK: Hover view (used as cell root view)

final class HoverView: NSView {
    var onRightClick: ((NSEvent) -> Void)?
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }
}

// MARK: App cell

final class AppCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("AppCell")
    var onRightClick: ((NSEvent) -> Void)?
    private var isHovered = false

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let v = HoverView()
        view = v
        view.wantsLayer = true
        view.layer?.cornerRadius = 8

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(iconView)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.alignment = .center
        nameLabel.textColor = .white
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 2
        view.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
        ])

        v.onRightClick = { [weak self] event in self?.onRightClick?(event) }
    }

    func configure(with app: AppItem) {
        isHovered = false
        updateBg()
        nameLabel.stringValue = app.name
        iconView.image = NSWorkspace.shared.icon(forFile: app.url.path)
    }

    func setHovered(_ hovered: Bool) { isHovered = hovered; updateBg() }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
        updateBg()
    }

    override var isSelected: Bool { didSet { updateBg() } }

    private func updateBg() {
        view.layer?.backgroundColor = isSelected
            ? NSColor.white.withAlphaComponent(0.3).cgColor
            : isHovered ? NSColor.white.withAlphaComponent(0.15).cgColor : .clear
    }
}

// MARK: Folder cell

final class FolderCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FolderCell")
    var onRightClick: ((NSEvent) -> Void)?
    private var isHovered = false

    private let iconGrid = FolderIconGridView()
    private let nameLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let v = HoverView()
        view = v
        view.wantsLayer = true
        view.layer?.cornerRadius = 8

        iconGrid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconGrid)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.alignment = .center
        nameLabel.textColor = .white
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 2
        view.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconGrid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconGrid.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            iconGrid.widthAnchor.constraint(equalToConstant: 56),
            iconGrid.heightAnchor.constraint(equalToConstant: 56),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
            nameLabel.topAnchor.constraint(equalTo: iconGrid.bottomAnchor, constant: 4),
        ])

        v.onRightClick = { [weak self] event in self?.onRightClick?(event) }
    }

    func configure(with folder: LauncherFolder, apps: [AppItem]) {
        isHovered = false
        view.layer?.backgroundColor = .clear
        nameLabel.stringValue = folder.name
        iconGrid.icons = Array(apps.prefix(4).map { NSWorkspace.shared.icon(forFile: $0.url.path) })
        iconGrid.needsDisplay = true
    }

    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        view.layer?.backgroundColor = hovered
            ? NSColor.white.withAlphaComponent(0.15).cgColor : .clear
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
        view.layer?.backgroundColor = .clear
    }
}

// MARK: 2×2 mini-icon grid for folder cells

final class FolderIconGridView: NSView {
    var icons: [NSImage] = []

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor.white.withAlphaComponent(0.2).setFill()
        path.fill()

        let count = min(icons.count, 4)
        guard count > 0 else { return }
        let cols: CGFloat = 2, rows: CGFloat = count <= 2 ? 1 : 2
        let pad: CGFloat = 6, gap: CGFloat = 2
        let cw = (bounds.width  - pad * 2 - gap * (cols - 1)) / cols
        let ch = (bounds.height - pad * 2 - gap * (rows - 1)) / rows
        for i in 0..<count {
            let col = CGFloat(i % 2), row = CGFloat(i / 2)
            let x = pad + col * (cw + gap)
            let y = bounds.height - pad - ch - row * (ch + gap)
            icons[i].draw(in: CGRect(x: x, y: y, width: cw, height: ch),
                          from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}

// MARK: "Add to Folder" menu item payload

private final class FolderAssignmentBox: NSObject {
    let app: AppItem
    let folder: LauncherFolder
    init(_ app: AppItem, _ folder: LauncherFolder) { self.app = app; self.folder = folder }
}

// MARK: Folder panel overlay

final class FolderPanelView: NSView {
    private let folder: LauncherFolder
    private let apps: [AppItem]
    private weak var vc: LauncherViewController?

    private let collectionView = FolderCollectionView()
    private var panelBox: NSView?
    private var draggingFolderAppID: String?
    private var pressedItemIndex: Int?
    private var draggedSincePress = false
    private var leaveTimer: Timer?

    init(folder: LauncherFolder, apps: [AppItem], viewController: LauncherViewController) {
        self.folder = folder; self.apps = apps; self.vc = viewController
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor

        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.9).cgColor
        panel.layer?.cornerRadius = 20
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        panelBox = panel

        let title = NSTextField(labelWithString: folder.name)
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .white
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(title)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 90, height: 100)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 16
        layout.sectionInset = NSEdgeInsets(top: 16, left: 20, bottom: 20, right: 20)

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(AppCell.self, forItemWithIdentifier: AppCell.identifier)
        collectionView.isSelectable = true
        collectionView.backgroundColors = [.clear]
        collectionView.setDraggingSourceOperationMask(.every, forLocal: true)

        let sv = NSScrollView()
        sv.documentView = collectionView
        sv.hasVerticalScroller = true
        sv.drawsBackground = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(sv)

        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: centerYAnchor),
            panel.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.55),
            panel.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.55),

            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: panel.trailingAnchor),

            sv.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            sv.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            sv.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])

        collectionView.onMouseDown = { [weak self] in
            self?.pressedItemIndex = nil
            self?.draggedSincePress = false
        }
        collectionView.onMouseUp = { [weak self] in
            guard let self else { return }
            defer { self.pressedItemIndex = nil }
            guard !self.draggedSincePress,
                  let idx = self.pressedItemIndex, idx < self.apps.count else { return }
            self.vc?.launch(self.apps[idx])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hitTest(p) === self { vc?.closeFolderPanel() }
        else { super.mouseDown(with: event) }
    }
}

extension FolderPanelView: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView,
                        numberOfItemsInSection section: Int) -> Int { apps.count }

    func collectionView(_ collectionView: NSCollectionView,
                        pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        let app = apps[indexPath.item]
        let item = NSPasteboardItem()
        item.setString("\(app.id)|\(folder.id)", forType: .launcherFolderItem)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: AppCell.identifier,
                                           for: indexPath) as! AppCell
        let app = apps[indexPath.item]
        cell.configure(with: app)
        cell.onRightClick = { [weak self] event in
            guard let self else { return }
            let menu = NSMenu()
            let open = NSMenuItem(title: "Open", action: #selector(self.panelOpen), keyEquivalent: "")
            open.target = self; open.representedObject = app; menu.addItem(open)
            menu.addItem(.separator())
            let rem = NSMenuItem(title: "Remove from Folder",
                                 action: #selector(self.panelRemove), keyEquivalent: "")
            rem.target = self; rem.representedObject = app; menu.addItem(rem)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
        return cell
    }

    @objc private func panelOpen(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? AppItem else { return }
        vc?.launch(app)
    }

    @objc private func panelRemove(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? AppItem else { return }
        vc?.takeOutOfFolder(app.id, folderID: folder.id)
        vc?.closeFolderPanel()
    }
}

extension FolderPanelView: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView,
                        didSelectItemsAt indexPaths: Set<IndexPath>) {
        collectionView.deselectAll(nil)
        if let i = indexPaths.first?.item, i < apps.count {
            pressedItemIndex = i
        }
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint,
                        forItemsAt indexPaths: Set<IndexPath>) {
        draggedSincePress = true
        draggingFolderAppID = indexPaths.first.map { apps[$0.item].id }
        watchPointerLeaving()
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint,
                        dragOperation operation: NSDragOperation) {
        leaveTimer?.invalidate()
        leaveTimer = nil
        defer { draggingFolderAppID = nil }
        guard let appID = draggingFolderAppID else { return }
        let outside = isHidden || boxOnScreen.map { !$0.contains(screenPoint) } ?? true
        guard outside else { return }
        let folderID = folder.id
        DispatchQueue.main.async { [weak self] in
            // Dropped in the grid, which has placed it; anywhere else, it just leaves the folder.
            if operation.isEmpty { self?.vc?.takeOutOfFolder(appID, folderID: folderID) }
            self?.vc?.closeFolderPanel()
        }
    }

    private var boxOnScreen: NSRect? {
        guard let box = panelBox, let window else { return nil }
        return window.convertToScreen(box.convert(box.bounds, to: nil))
    }

    /// Once the dragged app leaves the folder's box, the folder closes so that the grid underneath takes
    /// the drop. The drag runs its own event loop, so the pointer is looked at on a timer.
    private func watchPointerLeaving() {
        leaveTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self, let box = self.boxOnScreen else { timer.invalidate(); return }
            guard !box.contains(NSEvent.mouseLocation) else { return }
            timer.invalidate()
            self.isHidden = true
        }
        RunLoop.main.add(timer, forMode: .common)
        leaveTimer = timer
    }
}
