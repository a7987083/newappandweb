import UIKit

/// Unified four-selectedTab Swift/UIKit shell. The dock stays fixed above each selectedTab's scroll view.
final class MainShellViewController: UIViewController, UISearchBarDelegate, UIScrollViewDelegate, UITableViewDataSource, UITableViewDelegate {
    private var selectedTab = 0
    private var child: UIViewController?
    private var currentTable: UITableView?
    private var catalog: AppCatalogViewController?
    private var searchBar: UISearchBar?
    private var header: UIView?
    private var headerHeight: CGFloat = 0
    private var dock = UIView()
    private var compact = UIView()
    private var searching = false
    private var overlay: UIView?
    private var oldSearchFrame = CGRect.zero
    private var normalTableFrame = CGRect.zero
    private var savedBrowseOffset: CGFloat = 0
    private var savedBrowseRow: Int?
    private var savedBrowseRowTopDelta: CGFloat = 0
    private var initialSize = CGSize.zero
    private var savedBottomInset: CGFloat = 100
    private var keyboardObserver: NSObjectProtocol?
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

    deinit { if let keyboardObserver = keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) } }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if initialSize != view.bounds.size && !searching {
            initialSize = view.bounds.size
            showTab(selectedTab)
        }
    }

    private func showTab(_ index: Int) {
        if searching { closeSearch(animated: false) }
        child?.willMove(toParent: nil)
        child?.view.removeFromSuperview()
        child?.removeFromParent()
        child = nil
        view.subviews.forEach { $0.removeFromSuperview() }
        selectedTab = index
        currentTable = nil
        catalog = nil
        searchBar = nil
        header = nil
        compact = UIView()
        if index == 3 {
            install(SettingsViewController())
        } else {
            let table: UITableView
            if index == 0 {
                let c = AppCatalogViewController()
                install(c)
                catalog = c
                table = c.tableView
            } else {
                let c = UIViewController()
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
            table.delegate = self
            let head = buildHeader(index)
            header = head
            headerHeight = head.bounds.height
            if index == 0 { catalog?.setCatalogHeader(head,height: headerHeight) }
            else { table.tableHeaderView = head }
            buildCompact(["应用","安装包","插件"][index])
            buildActions(index)
        }
        buildDock()
    }

    private func install(_ controller: UIViewController) {
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        child = controller
    }

    private func buildHeader(_ index: Int) -> UIView {
        let w = view.bounds.width
        let titleY = view.safeAreaInsets.top+66
        let h = titleY+123
        let panel = UIView(frame: CGRect(x: 0,y: 0,width: w,height: h))
        panel.backgroundColor = bg
        let title = UILabel(frame: CGRect(x: 20,y: titleY,width: w-40,height: 53))
        title.text = ["应用","安装包","插件"][index]
        title.font = .boldSystemFont(ofSize: 37)
        panel.addSubview(title)
        let search = UISearchBar(frame: CGRect(x: 12,y: titleY+61,width: w-24,height: 52))
        search.searchBarStyle = .minimal
        search.placeholder = "搜索"
        search.searchTextField.backgroundColor = UIColor(red: 229/255,green: 229/255,blue: 234/255,alpha: 1)
        search.searchTextField.layer.cornerRadius = 12
        search.searchTextField.clipsToBounds = true
        search.delegate = self
        panel.addSubview(search)
        searchBar = search
        return panel
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
        let w = view.bounds.width
        let dw = min(w-112,320)
        dock = UIView(frame: CGRect(x: (w-dw)/2,y: view.bounds.height-view.safeAreaInsets.bottom-72,width: dw,height: 60))
        dock.autoresizingMask = [.flexibleTopMargin,.flexibleLeftMargin,.flexibleRightMargin]
        dock.layer.cornerRadius = 30
        dock.layer.borderWidth = 0.5
        dock.layer.borderColor = UIColor.lightGray.cgColor
        dock.backgroundColor = UIColor(red: 249/255,green: 249/255,blue: 251/255,alpha: 1)
        dock.layer.shadowColor = UIColor.black.cgColor
        dock.layer.shadowOpacity = 0.08
        dock.layer.shadowRadius = 11
        view.addSubview(dock)
        let titles = ["应用","安装包","插件","设置"]
        let icons = ["square.grid.3x3.fill","shippingbox.fill","puzzlepiece.fill","gearshape.fill"]
        for i in 0..<4 {
            let col = dw/4
            let b = UIButton(type: .system)
            b.tag = i
            b.frame = CGRect(x: CGFloat(i)*col,y: 2,width: col,height: 38)
            b.tintColor = i == selectedTab ? blue : .gray
            b.setImage(UIImage(systemName: icons[i],withConfiguration: UIImage.SymbolConfiguration(pointSize: 19)),for: .normal)
            b.addTarget(self,action: #selector(tapTab(_:)),for: .touchUpInside)
            dock.addSubview(b)
            let label = UILabel(frame: CGRect(x: CGFloat(i)*col,y: 38,width: col,height: 17))
            label.text = titles[i]
            label.textAlignment = .center
            label.textColor = b.tintColor
            label.font = i == selectedTab ? .boldSystemFont(ofSize: 10) : .systemFont(ofSize: 10)
            dock.addSubview(label)
        }
    }

    @objc private func tapTab(_ b: UIButton) { showTab(b.tag) }
    @objc private func refresh() { catalog?.refreshSourceCatalog() }
    @objc private func demo() {
        let a = UIAlertController(title: "界面演示",message: "当前仅为 UI 占位。",preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "知道了",style: .default))
        present(a,animated: true)
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
        guard !searching,let table = currentTable else { return true }
        searching = true
        normalTableFrame = table.frame
        // Preserve the browsing anchor before filtering, collapsing the header
        // or changing the table viewport. Never use the search result offset.
        table.layoutIfNeeded()
        savedBrowseOffset = table.contentOffset.y
        savedBrowseRow = table.indexPathsForVisibleRows?
            .filter { $0.section == 0 }
            .sorted { $0.row < $1.row }
            .first?.row
        if let row = savedBrowseRow {
            savedBrowseRowTopDelta = table.rectForRow(at: IndexPath(row: row, section: 0)).minY - savedBrowseOffset
        } else {
            savedBrowseRowTopDelta = 0
        }
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
        let searchBottom = safe + 61
        table.frame = CGRect(x: normalTableFrame.minX,
                             y: searchBottom,
                             width: normalTableFrame.width,
                             height: max(0, normalTableFrame.height - searchBottom))
        table.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        savedBottomInset = table.contentInset.bottom
        keyboardObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self, self.searching, let table = self.currentTable,
                  let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let local = self.view.convert(frame, from: nil)
            let overlap = max(0, self.view.bounds.maxY - max(self.view.bounds.minY, local.minY))
            table.contentInset.bottom = max(self.savedBottomInset, overlap + 12)
            table.scrollIndicatorInsets.bottom = table.contentInset.bottom
        }
        UIView.animate(withDuration: 0.28) {
            panel.alpha = 1
            bar.frame = CGRect(x: 12,y: safe+5,width: self.view.bounds.width-93,height: 49)
            self.dock.alpha = 0
        } completion: { _ in if self.searching { self.dock.isHidden = true } }
        return true
    }

    @objc private func cancelSearch() { closeSearch(animated: true) }
    private func closeSearch(animated: Bool) {
        guard searching,let bar = searchBar,let table = currentTable else { return }
        searching = false
        if let observer = keyboardObserver { NotificationCenter.default.removeObserver(observer); keyboardObserver = nil }
        table.contentInset.bottom = savedBottomInset
        table.scrollIndicatorInsets.bottom = savedBottomInset
        table.frame = normalTableFrame
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
        let restoreOffset: CGFloat
        if let row = savedBrowseRow, row < table.numberOfRows(inSection: 0) {
            restoreOffset = table.rectForRow(at: IndexPath(row: row, section: 0)).minY - savedBrowseRowTopDelta
        } else {
            restoreOffset = savedBrowseOffset
        }
        let restoreBrowsePosition = {
            table.layoutIfNeeded()
            let minimum = -table.adjustedContentInset.top
            let maximum = max(minimum, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
            table.setContentOffset(CGPoint(x: 0, y: min(max(restoreOffset, minimum), maximum)), animated: false)
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
        } else {
            let q = value.trimmingCharacters(in: .whitespacesAndNewlines)
            filtered = q.isEmpty ? rows : rows.filter { ($0.0+" "+$0.1).localizedCaseInsensitiveContains(q) }
            currentTable?.reloadData()
        }
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
}

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
