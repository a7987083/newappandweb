import UIKit

/// Four-tab UIKit shell: retains page controllers and coordinates shared UI.
final class MainShellViewController: UIViewController, UISearchBarDelegate, UIScrollViewDelegate, UITableViewDataSource, UITableViewDelegate {
    private var selectedTab = 0
    private struct TabPage {
        let controller: UIViewController
        let views: [UIView]
        let table: UITableView?
        let catalog: AppCatalogViewController?
        let packages: PackageListViewController?
        let searchBar: UISearchBar?
        let header: UIView?
        let headerHeight: CGFloat
        let compact: UIView
        let dock: UIView
        let rows: [(String,String,String)]
        let filtered: [(String,String,String)]
    }
    private var pages = [Int: TabPage]()
    private var currentTable: UITableView?
    private var catalog: AppCatalogViewController?
    private var packages: PackageListViewController?
    private var searchBar: UISearchBar?
    private var header: UIView?
    private var headerHeight: CGFloat = 0
    private var dock = UIView()
    private var compact = UIView()
    private let searchPhase = ShellSearchPhaseMachine()
    private var searching: Bool { searchPhase.isSearching }
    private var overlay: UIView?
    private var oldSearchFrame = CGRect.zero
    private let searchSession = ShellSearchSession()
    private var initialSize = CGSize.zero
    private let blue = UIColor(red: 51/255, green: 124/255, blue: 250/255, alpha: 1)
    private let bg = UIColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1)
    private var rows: [(String,String,String)] = []
    private var filtered: [(String,String,String)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bg
        SourceCatalogUIBridge.start()
        showTab(0)
        if !SoftwareSourceStore.shared.sources.isEmpty && SoftwareSourceStore.shared.catalogApps.isEmpty && !SoftwareSourceStore.shared.isCatalogLoading {
            SoftwareSourceStore.shared.refreshCatalog()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let sizeChanged = initialSize != view.bounds.size
        if sizeChanged { initialSize = view.bounds.size }
        // This callback also runs when safe-area insets become available after
        // viewDidLoad. Never assume safeAreaInsets.top was valid at construction.
        let width = view.bounds.width
        let safeTop = view.safeAreaInsets.top
        for (index, page) in pages {
            if sizeChanged { page.controller.view.frame = view.bounds }
            page.dock.frame.origin.y = view.bounds.height - view.safeAreaInsets.bottom - 72
            page.dock.center.x = view.bounds.midX
            for case let button as UIButton in page.views {
                let isEdit = button.title(for: .normal) == "编辑"
                button.frame.origin = CGPoint(x: width - (isEdit ? 108 : 53), y: safeTop + 8)
            }
            guard index != 3, let head = page.header, let table = page.table else { continue }
            // Do not modify the active search header until its overlay closes.
            if searching && index == selectedTab { continue }
            let newHeight = safeTop + 189
            let delta = newHeight - head.frame.height
            if abs(delta) > 0.5 || sizeChanged {
                if let shellHeader = head as? ShellHeaderView {
                    shellHeader.updateLayout(width: width, safeTop: safeTop)
                }
                if index == 0 {
                    page.catalog?.setCatalogHeader(head, height: newHeight)
                } else {
                    table.tableHeaderView = head
                }
                if index == selectedTab { headerHeight = newHeight }
                // An expanded header changes content coordinates; preserve the
                // visible cell when safe-area values arrive after first layout.
                if table.contentOffset.y > 0 && abs(delta) > 0.5 {
                    table.contentOffset.y += delta
                }
            }
            page.compact.frame = CGRect(x: 0, y: 0, width: width, height: safeTop + 52)
            for case let label as UILabel in page.compact.subviews {
                label.frame = CGRect(x: 65, y: safeTop + 5, width: width - 130, height: 36)
            }
        }
    }

    private func showTab(_ index: Int) {
        guard (0..<4).contains(index), searchPhase.phase != .restoring else { return }
        if searching { closeSearch(animated: false) }
        if let current = pages[selectedTab] {
            pages[selectedTab] = TabPage(
                controller: current.controller, views: current.views,
                table: currentTable, catalog: catalog, packages: packages, searchBar: searchBar,
                header: header, headerHeight: headerHeight, compact: compact,
                dock: dock, rows: rows, filtered: filtered)
        }
        for page in pages.values {
            page.views.forEach { $0.isHidden = true }
        }
        selectedTab = index
        if let existing = pages[index] {
            currentTable = existing.table
            catalog = existing.catalog
            packages = existing.packages
            searchBar = existing.searchBar
            header = existing.header
            headerHeight = existing.headerHeight
            compact = existing.compact
            dock = existing.dock
            rows = existing.rows
            filtered = existing.filtered
            existing.views.forEach { $0.isHidden = false }
            if let table = currentTable { scrollViewDidScroll(table) }
            return
        }
        let previousViews = Set(view.subviews.map(ObjectIdentifier.init))
        currentTable = nil
        catalog = nil
        packages = nil
        searchBar = nil
        header = nil
        rows = []
        filtered = []
        compact = UIView()
        let controller: UIViewController
        if index == 3 {
            controller = SettingsViewController()
            install(controller)
        } else {
            let table: UITableView
            if index == 0 {
                let c = AppCatalogViewController()
                controller = c
                install(c)
                catalog = c
                table = c.tableView
            } else if index == 1 {
                let c = PackageListViewController()
                controller = c
                install(c)
                packages = c
                table = c.tableView
            } else {
                let c = UIViewController()
                controller = c
                c.view.backgroundColor = bg
                install(c)
                table = UITableView(frame: c.view.bounds, style: .plain)
                table.autoresizingMask = [.flexibleWidth,.flexibleHeight]
                table.separatorStyle = .none
                table.backgroundColor = .clear
                table.contentInsetAdjustmentBehavior = .never
                table.rowHeight = 78
                table.contentInset = UIEdgeInsets(top: 0,left: 0,bottom: 100,right: 0)
                table.dataSource = self
                table.register(ShellPlaceholderCell.self, forCellReuseIdentifier: "Demo")
                c.view.addSubview(table)
                rows = index == 1 ? [
                    ("1","文件夹 · 2026-10-11 09:21（演示）","folder.fill"),
                    ("Random Dice 2.ipa","273.6 MB · 2026-10-10 02:35（演示）","doc.fill"),
                    ("test.ipa","960 KB · 2026-10-11 06:42（演示）","doc.fill")
                ] : []
                filtered = rows
            }
            currentTable = table
            if index != 1 { table.delegate = self }
            let head = buildHeader(index)
            header = head
            headerHeight = head.bounds.height
            if index == 0 { catalog?.setCatalogHeader(head,height: headerHeight) }
            else { table.tableHeaderView = head }
            buildCompact(["应用","安装包","插件"][index])
            buildActions(index)
        }
        buildDock()
        let ownedViews = view.subviews.filter { !previousViews.contains(ObjectIdentifier($0)) }
        pages[index] = TabPage(controller: controller, views: ownedViews,
                               table: currentTable, catalog: catalog, packages: packages,
                               searchBar: searchBar, header: header,
                               headerHeight: headerHeight, compact: compact,
                               dock: dock, rows: rows, filtered: filtered)
    }

    private func install(_ controller: UIViewController) {
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    private func buildHeader(_ index: Int) -> UIView {
        let head = ShellHeaderView(title: ["应用", "安装包", "插件"][index],
                                   width: view.bounds.width,
                                   safeTop: view.safeAreaInsets.top,
                                   background: bg)
        head.searchBar.delegate = self
        searchBar = head.searchBar
        return head
    }

    private func buildCompact(_ name: String) {
        let safe = view.safeAreaInsets.top
        compact = UIView(frame: CGRect(x: 0,y: 0,width: view.bounds.width,height: safe+52))
        compact.backgroundColor = UIColor(red: 247/255,green: 248/255,blue: 250/255,alpha: 1)
        let title = UILabel(frame: CGRect(x: 65,y: safe+5,width: view.bounds.width-130,height: 36))
        title.text = name
        title.textAlignment = .center
        title.font = .boldSystemFont(ofSize: 20)
        compact.addSubview(title)
        compact.alpha = 0
        compact.isUserInteractionEnabled = false
        view.addSubview(compact)
    }

    private func buildActions(_ index: Int) {
        let w = view.bounds.width
        let y = view.safeAreaInsets.top+8
        if index != 0 {
            let edit = UIButton(type: .system)
            edit.frame = CGRect(x: w-108,y: y,width: 42,height: 34)
            edit.setTitle("编辑",for: .normal)
            edit.addTarget(self,action: #selector(demo),for: .touchUpInside)
            view.addSubview(edit)
        }
        let action = UIButton(type: .system)
        action.frame = CGRect(x: w-53,y: y,width: 42,height: 42)
        action.tintColor = blue
        action.setImage(UIImage(systemName: index == 0 ? "arrow.clockwise.circle.fill" : "plus.circle.fill",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 29)),for: .normal)
        action.addTarget(self,action: index == 0 ? #selector(refresh) : #selector(demo),for: .touchUpInside)
        view.addSubview(action)
    }

    private func buildDock() {
        let bar = ShellTabBar(width: view.bounds.width,
                              height: view.bounds.height,
                              bottomInset: view.safeAreaInsets.bottom,
                              selectedTab: selectedTab,
                              tint: blue)
        bar.onSelect = { [weak self] index in self?.showTab(index) }
        dock = bar
        view.addSubview(bar)
    }

    @objc private func refresh() { catalog?.refreshSourceCatalog() }
    @objc private func demo() {
        let a = UIAlertController(title: "界面演示",message: "当前仅为 UI 占位。",preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "知道了",style: .default))
        present(a,animated: true)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard selectedTab == 0 else { return }
        catalog?.openDetail(atVisibleRow: indexPath.row)
    }

    func tableView(_ tableView: UITableView,numberOfRowsInSection section: Int) -> Int { filtered.count }
    func tableView(_ tableView: UITableView,cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Demo",for: indexPath) as! ShellPlaceholderCell
        let row = filtered[indexPath.row]
        cell.configure(title: row.0,detail: row.1,symbol: row.2)
        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if !searching {
            compact.alpha = min(1,max(0,(scrollView.contentOffset.y-18)/28))
        }
    }

    func searchBarShouldBeginEditing(_ bar: UISearchBar) -> Bool {
        guard let table = currentTable, searchPhase.begin() else { return false }
        searchSession.begin(on: table)
        oldSearchFrame = bar.frame
        let origin = bar.superview?.convert(bar.frame,to: view) ?? bar.frame
        let safe = view.safeAreaInsets.top
        let panel = UIView(frame: CGRect(x: 0,y: 0,width: view.bounds.width,height: safe+61))
        panel.backgroundColor = UIColor(red: 247/255,green: 248/255,blue: 250/255,alpha: 1)
        panel.alpha = 0
        view.addSubview(panel)
        overlay = panel
        bar.removeFromSuperview()
        bar.frame = origin
        panel.addSubview(bar)
        let cancel = UIButton(type: .system)
        cancel.setTitle("取消",for: .normal)
        cancel.frame = CGRect(x: view.bounds.width-75,y: safe+5,width: 68,height: 49)
        cancel.addTarget(self,action: #selector(cancelSearch),for: .touchUpInside)
        panel.addSubview(cancel)
        compact.isHidden = true
        header?.clipsToBounds = true
        header?.subviews.forEach { $0.isHidden = true }
        if let h = header {
            var f = h.frame
            f.size.height = 0
            h.frame = f
            if selectedTab == 0 { catalog?.setHeaderCollapsed(true) }
            else { table.tableHeaderView = h }
        }
        // Keep the scrollable viewport below the fixed search overlay.
        // Insets alone would let cells continue scrolling behind the overlay.
        searchSession.activateViewport(on: table, in: view, safeTop: safe)
        UIView.animate(withDuration: 0.28) {
            panel.alpha = 1
            bar.frame = CGRect(x: 12,y: safe+5,width: self.view.bounds.width-93,height: 49)
            self.dock.alpha = 0
        } completion: { _ in
            if self.searchPhase.activate() { self.dock.isHidden = true }
        }
        return true
    }

    @objc private func cancelSearch() { closeSearch(animated: true) }
    private func closeSearch(animated: Bool) {
        guard let bar = searchBar, let table = currentTable, searchPhase.startRestoring() else { return }
        let anchor = searchSession.captureCurrent(on: table)
        let searchRow = anchor.row
        let searchAppID = searchRow.flatMap { selectedTab == 0 ? catalog?.appID(atVisibleRow: $0) : nil }
        let searchDemoName = searchRow.flatMap { selectedTab > 1 && $0 < filtered.count ? filtered[$0].0 : nil }
        searchSession.restoreViewport(on: table)
        bar.resignFirstResponder()
        bar.text = ""
        searchBar(bar,textDidChange: "")
        if let h = header {
            var f = h.frame
            f.size.height = headerHeight
            h.frame = f
            if selectedTab == 0 { catalog?.setHeaderCollapsed(false) }
            else { table.tableHeaderView = h }
        }
        // The unfiltered row set and full header must be installed before
        // resolving the pre-search browsing position.
        table.layoutIfNeeded()
        let targetRow: Int? = {
            if let id = searchAppID { return catalog?.visibleRow(forAppID: id) }
            if let name = searchDemoName { return filtered.firstIndex { $0.0 == name } }
            return searchRow
        }()
        let restoreBrowsePosition = { [weak self] in
            self?.searchSession.restoreAnchor(on: table, row: targetRow, anchor: anchor)
        }
        restoreBrowsePosition()
        let destination = header?.convert(oldSearchFrame,to: view) ?? oldSearchFrame
        dock.isHidden = false
        let finish = {
            bar.removeFromSuperview()
            bar.frame = self.oldSearchFrame
            self.header?.addSubview(bar)
            self.header?.subviews.forEach { $0.isHidden = false }
            self.overlay?.removeFromSuperview()
            self.overlay = nil
            self.compact.isHidden = false
            self.dock.alpha = 1
            restoreBrowsePosition()
            self.searchPhase.finishRestoring()
            self.scrollViewDidScroll(table)
        }
        if animated {
            UIView.animate(withDuration: 0.28,animations: {
                bar.frame = destination
                self.overlay?.alpha = 0
                self.dock.alpha = 1
            },completion: { _ in finish() })
        } else { finish() }
    }

    func searchBar(_ searchBar: UISearchBar,textDidChange value: String) {
        if selectedTab == 0 {
            catalog?.filter(query: value)
        } else if selectedTab == 1 {
            packages?.filter(query: value)
        } else {
            let q = value.trimmingCharacters(in: .whitespacesAndNewlines)
            filtered = q.isEmpty ? rows : rows.filter { ($0.0+" "+$0.1).localizedCaseInsensitiveContains(q) }
            currentTable?.reloadData()
        }
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
}

/// Card used by the temporary package and plugin demo lists.
private final class ShellPlaceholderCell: UITableViewCell {
    private let card = UIView()
    private let iconBackground = UIView()
    private let image = UIImageView()
    private let name = UILabel()
    private let detail = UILabel()

    override init(style: UITableViewCell.CellStyle,reuseIdentifier: String?) {
        super.init(style: style,reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.backgroundColor = .white
        card.layer.cornerRadius = 16
        contentView.addSubview(card)
        iconBackground.backgroundColor = UIColor(red: 230/255,green: 240/255,blue: 1,alpha: 1)
        iconBackground.layer.cornerRadius = 11
        card.addSubview(iconBackground)
        image.tintColor = UIColor(red: 51/255,green: 124/255,blue: 250/255,alpha: 1)
        image.contentMode = .scaleAspectFit
        iconBackground.addSubview(image)
        name.font = .boldSystemFont(ofSize: 15)
        name.textColor = .black
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabel
        detail.adjustsFontSizeToFitWidth = true
        detail.minimumScaleFactor = 0.75
        card.addSubview(name)
        card.addSubview(detail)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic only") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        card.frame = CGRect(x: 18,y: 0,width: max(0,w-36),height: 70)
        iconBackground.frame = CGRect(x: 13,y: 12,width: 46,height: 46)
        image.frame = iconBackground.bounds.insetBy(dx: 10,dy: 10)
        name.frame = CGRect(x: 72,y: 8,width: max(0,w-118),height: 22)
        detail.frame = CGRect(x: 72,y: 28,width: max(0,w-116),height: 17)
    }
    func configure(title: String,detail: String,symbol: String) {
        name.text = title
        self.detail.text = detail
        image.image = UIImage(systemName: symbol)
    }
}
