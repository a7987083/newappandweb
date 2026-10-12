import UIKit
import Combine

/// Four-tab UIKit shell: retains page controllers and coordinates shared UI.
final class MainShellViewController: UIViewController, UISearchBarDelegate, UIScrollViewDelegate, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
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
    private var extractionSubscription: AnyCancellable?
    private var extractionAlert: UIAlertController?
    private var displayedExtraction: String?
    private var extractionNames = [String]()
    private var signedEditing = false
    private var signedSelected = Set<URL>()
    private var headerActions = [Int: [UIButton]]()
    private var signedFiles = [URL]()
    private var signedVisible = [URL]()
    private var signedQuery = ""
    private func reloadSignedFiles() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signed", isDirectory: true)
        signedFiles = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["ipa", "tipa", "zip"].contains($0.pathExtension.lowercased()) }
        rows = signedFiles.map { ($0.lastPathComponent, "已签名安装包", "doc.fill") }
        applySignedFilter()
    }
    private func applySignedFilter() {
        let q = signedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        signedVisible = q.isEmpty ? signedFiles : signedFiles.filter {
            $0.lastPathComponent.localizedCaseInsensitiveContains(q)
        }
        filtered = signedVisible.map { ($0.lastPathComponent, "已签名安装包", "doc.fill") }
        signedSelected = signedSelected.intersection(Set(signedFiles))
    }
    private func showPackageImport(_ sender: UIButton) {
        let sheet = UIAlertController(title: "导入安装包", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "从文件安装", style: .default) { [weak self] _ in
            let picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
            picker.delegate = self
            self?.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "从链接安装", style: .default) { [weak self] _ in
            self?.showLinkImport()
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.sourceView = sender
        sheet.popoverPresentationController?.sourceRect = sender.bounds
        present(sheet, animated: true)
    }
    private func showLinkImport() {
        let alert = UIAlertController(title: "从链接安装", message: "允许任意 HTTP/HTTPS 下载链接", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "https://example.com/download" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "下载", style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, let url = URL(string: text),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                self?.showImportError("链接无效"); return
            }
            AppStoreViewModel.shared.downloadCenter.enqueue(url)
        })
        present(alert, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let file = urls.first else { return }
        AppStoreViewModel.shared.downloadCenter.importLocalPackage(file) { [weak self] error in
            if let error = error { self?.showImportError(error.localizedDescription) }
        }
    }
    private func showImportError(_ message: String) {
        let alert = UIAlertController(title: "导入失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bg
        SourceCatalogUIBridge.start()
        observeExtractions()
        showTab(0)
        if !SoftwareSourceStore.shared.sources.isEmpty && SoftwareSourceStore.shared.catalogApps.isEmpty && !SoftwareSourceStore.shared.isCatalogLoading {
            SoftwareSourceStore.shared.refreshCatalog()
        }
    }

    private func observeExtractions() {
        let center = AppStoreViewModel.shared.downloadCenter
        extractionSubscription = center.$extractionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateExtractionAlert(status)
            }
    }

    private func updateExtractionAlert(_ status: [String: String]) {
        // Only foreground extraction events produce alerts; restored entries have
        // already completed by the time their UI is first observed.
        let active = status.filter { $0.value == "正在解压" }.keys.sorted()
        if let displayed = displayedExtraction {
            if let result = status[displayed], result != "正在解压" {
                displayedExtraction = nil
                let alert = extractionAlert
                extractionAlert = nil
                alert?.dismiss(animated: true) { [weak self] in
                    guard let self = self else { return }
                    if result.hasPrefix("解压失败") {
                        let error = UIAlertController(title: "解压失败", message: result, preferredStyle: .alert)
                        error.addAction(UIAlertAction(title: "确定", style: .default))
                        self.present(error, animated: true)
                    } else {
                        self.updateExtractionAlert(status)
                    }
                }
            }
            return
        }
        guard extractionAlert == nil, presentedViewController == nil,
              let name = active.first else { return }
        displayedExtraction = name
        let alert = UIAlertController(title: "正在解压安装包",
                                      message: name + "\n正在准备签名文件…",
                                      preferredStyle: .alert)
        extractionAlert = alert
        present(alert, animated: true)
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
            layoutHeaderActions(index)
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
            if index == 2 {
                reloadSignedFiles()
                currentTable?.reloadData()
            }
            layoutHeaderActions(index)
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
                reloadSignedFiles()
            }
            currentTable = table
            if index != 1 { table.delegate = self }
            let head = buildHeader(index)
            header = head
            headerHeight = head.bounds.height
            if index == 0 { catalog?.setCatalogHeader(head,height: headerHeight) }
            else { table.tableHeaderView = head }
            buildCompact(["应用","安装包","已签名"][index])
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
        let head = ShellHeaderView(title: ["应用", "安装包", "已签名"][index],
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
        let labels = index == 0 ? ["刷新"] : index == 1 ?
            ["编辑", "+", "全选", "签名", "删除", "完成"] :
            ["编辑", "全选", "删除", "完成"]
        let buttons = labels.map { label -> UIButton in
            let button = UIButton(type: .system)
            if label == "+" {
                button.setImage(UIImage(systemName: "plus.circle.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 27)), for: .normal)
                button.tintColor = blue
            } else {
                button.setTitle(label, for: .normal)
                button.setTitleColor(label == "删除" ? .systemRed : blue, for: .normal)
            }
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.accessibilityIdentifier = "\(index):\(label)"
            button.addTarget(self, action: #selector(headerTapped(_:)), for: .touchUpInside)
            view.addSubview(button)
            return button
        }
        headerActions[index] = buttons
        layoutHeaderActions(index)
    }

    private func layoutHeaderActions(_ index: Int) {
        guard let buttons = headerActions[index] else { return }
        let editing = index == 1 ? (pages[index]?.packages?.isSelecting ?? packages?.isSelecting ?? false) : signedEditing
        let names = index == 0 ? ["刷新"] : editing ?
            (index == 1 ? ["全选","签名","删除","完成"] : ["全选","删除","完成"]) :
            (index == 1 ? ["编辑","+"] : ["编辑"])
        let visible = buttons.filter { button in
            let token = button.accessibilityIdentifier?.split(separator: ":").last.map(String.init) ?? ""
            return names.contains(token)
        }
        for button in buttons { button.isHidden = index != selectedTab || !visible.contains(button) }
        for (i, button) in visible.enumerated() {
            button.frame = CGRect(x: view.bounds.width - 9 - CGFloat(visible.count-i)*56,
                                  y: view.safeAreaInsets.top + 8, width: 52, height: 36)
        }
    }

    @objc private func headerTapped(_ sender: UIButton) {
        guard let tag = sender.accessibilityIdentifier else { return }
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let index = Int(parts[0]) else { return }
        let action = String(parts[1])
        switch action {
        case "刷新": refresh()
        case "+": showPackageImport(sender)
        case "编辑":
            if index == 1 { packages?.setSelecting(true) }
            else { signedEditing = true; signedSelected.removeAll(); currentTable?.reloadData() }
        case "完成":
            if index == 1 { packages?.setSelecting(false) }
            else { signedEditing = false; signedSelected.removeAll(); currentTable?.reloadData() }
        case "全选":
            if index == 1 { packages?.toggleSelectAll() }
            else {
                let visibleSet = Set(signedVisible)
                if visibleSet.isSubset(of: signedSelected) { signedSelected.subtract(visibleSet) }
                else { signedSelected.formUnion(visibleSet) }
                currentTable?.reloadData()
            }
        case "删除":
            if index == 1 { packages?.deleteSelected() }
            else { deleteSignedSelection() }
        case "签名":
            let selected = packages?.selectedPackages().filter { $0.state == .completed } ?? []
            guard !selected.isEmpty else {
                showImportError("请先选择已下载的安装包")
                return
            }
            showSigningCertificateSelection(selected.compactMap { $0.localURL })
        default: break
        }
        layoutHeaderActions(index)
    }

    private func deleteSignedSelection() {
        let targets = signedFiles.filter { signedSelected.contains($0) }
        guard !targets.isEmpty else {
            showImportError("请先选择要删除的文件")
            return
        }
        let alert = UIAlertController(title: "删除已签名文件", message: "确定删除 \(targets.count) 个文件？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            var failures = [String]()
            for url in targets {
                do { try FileManager.default.removeItem(at: url) }
                catch { failures.append(url.lastPathComponent + "：" + error.localizedDescription) }
            }
            self?.signedSelected.removeAll()
            self?.reloadSignedFiles()
            self?.currentTable?.reloadData()
            if !failures.isEmpty { self?.showImportError(failures.joined(separator: "\n")) }
        })
        present(alert, animated: true)
    }

    private func showSigningCertificateSelection(_ files: [URL]) {
        let store = CertificateStore.shared
        store.reload()
        let picker = UIAlertController(title: "选择签名证书", message: nil, preferredStyle: .actionSheet)
        for cert in store.certificates {
            picker.addAction(UIAlertAction(title: cert.name, style: .default) { [weak self] _ in
                self?.signSequentially(files, certificate: cert)
            })
        }
        if store.certificates.isEmpty {
            picker.message = "请先在设置中导入 P12 与 mobileprovision"
        }
        picker.addAction(UIAlertAction(title: "取消", style: .cancel))
        picker.popoverPresentationController?.sourceView = view
        picker.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: 50, width: 1, height: 1)
        present(picker, animated: true)
    }

    private var signingService: AppSigningService?
    private func signSequentially(_ files: [URL], certificate: DeviceCertificate) {
        guard let first = files.first else { return }
        guard signingService == nil else { return }
        let dialog = UIAlertController(title: "正在签名", message: first.lastPathComponent, preferredStyle: .alert)
        present(dialog, animated: true)
        let service = AppSigningService()
        signingService = service
        let password = CertificatePasswordKeychain.read(for: certificate.id) ?? ""
        service.sign(request: SigningRequest(ipaURL: first, certificate: certificate, password: password),
            progress: { state in dialog.message = first.lastPathComponent + "\n" + state.rawValue },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.signingService = nil
                dialog.dismiss(animated: true) {
                    switch result {
                    case .success:
                        self.signSequentially(Array(files.dropFirst()), certificate: certificate)
                    case .failure(let error):
                        let notice = UIAlertController(title: "签名失败", message: error.localizedDescription, preferredStyle: .alert)
                        notice.addAction(UIAlertAction(title: "确定", style: .default))
                        self.present(notice, animated: true)
                    }
                }
            })
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
    @objc private func importPackageTapped(_ sender: UIButton) { showPackageImport(sender) }
    @objc private func demo() {
        let a = UIAlertController(title: "界面演示",message: "当前仅为 UI 占位。",preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "知道了",style: .default))
        present(a,animated: true)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if selectedTab == 0 { catalog?.openDetail(atVisibleRow: indexPath.row) }
        else if selectedTab == 2 && signedVisible.indices.contains(indexPath.row) {
            let file = signedVisible[indexPath.row]
            if signedEditing {
                if !signedSelected.insert(file).inserted { signedSelected.remove(file) }
                tableView.reloadRows(at: [indexPath], with: .none)
            } else {
                let activity = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                activity.popoverPresentationController?.sourceView = tableView
                activity.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
                present(activity, animated: true)
            }
        }
    }

    func tableView(_ tableView: UITableView,numberOfRowsInSection section: Int) -> Int { filtered.count }
    func tableView(_ tableView: UITableView,cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Demo",for: indexPath) as! ShellPlaceholderCell
        guard filtered.indices.contains(indexPath.row) else { return UITableViewCell() }
        let row = filtered[indexPath.row]
        cell.configure(title: row.0,detail: row.1,symbol: row.2)
        cell.accessoryType = selectedTab == 2 && signedEditing && signedVisible.indices.contains(indexPath.row) &&
            signedSelected.contains(signedVisible[indexPath.row]) ? .checkmark : .none
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
            signedQuery = value
            applySignedFilter()
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
