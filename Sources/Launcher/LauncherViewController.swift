import AppKit
import LauncherCore

/// The Launcher's full-screen grid: search field at the top, app icons below.
final class LauncherViewController: NSViewController {
    var onDismiss: (() -> Void)?
    var settings = LauncherSettings() { didSet { applySettings() } }

    private var allApps: [AppItem] = []
    private var filteredApps: [AppItem] = []

    private let searchField = NSSearchField()
    private let collectionView = NSCollectionView()
    private let scrollView = NSScrollView()

    override func loadView() {
        view = BackgroundView(onClickOutside: { [weak self] in
            guard self?.settings.dismissOnClickOutside == true else { return }
            self?.onDismiss?()
        })
        view.wantsLayer = true

        searchField.placeholderString = "Search"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.isContinuous = true
        view.addSubview(searchField)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 90, height: 100)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 16
        layout.sectionInset = NSEdgeInsets(top: 20, left: 40, bottom: 40, right: 40)

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(AppCell.self, forItemWithIdentifier: AppCell.identifier)
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 60),
            searchField.widthAnchor.constraint(equalToConstant: 300),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 20),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        allApps = AppScanner.scan()
        applyFilter()
    }

    func prepareToShow() {
        allApps = AppScanner.scan()
        searchField.stringValue = ""
        applyFilter()
        view.window?.makeFirstResponder(searchField)
    }

    private func applySettings() {}

    @objc private func searchChanged() { applyFilter() }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        filteredApps = query.isEmpty ? allApps
            : allApps.filter { $0.name.localizedCaseInsensitiveContains(query) }
        collectionView.reloadData()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, settings.dismissOnEsc {
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: NSCollectionViewDataSource

extension LauncherViewController: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredApps.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: AppCell.identifier, for: indexPath) as! AppCell
        item.configure(with: filteredApps[indexPath.item])
        return item
    }
}

// MARK: NSCollectionViewDelegate

extension LauncherViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first else { return }
        let app = filteredApps[indexPath.item]
        collectionView.deselectAll(nil)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, _ in }
        onDismiss?()
    }
}

// MARK: Background view

/// Full-screen dark background. Clicks that miss every icon close the Launcher.
private final class BackgroundView: NSView {
    var onClickOutside: (() -> Void)?

    init(onClickOutside: @escaping () -> Void) {
        self.onClickOutside = onClickOutside
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Only fire when no subview handled the click.
        if hitTest(point) === self { onClickOutside?() }
    }
}

// MARK: App cell

final class AppCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("AppCell")

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

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
    }

    func configure(with app: AppItem) {
        nameLabel.stringValue = app.name
        iconView.image = NSWorkspace.shared.icon(forFile: app.url.path)
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected
                ? NSColor.white.withAlphaComponent(0.2).cgColor : .clear
            view.layer?.cornerRadius = 8
        }
    }
}
