import UIKit
import Combine

/// Standalone secondary page; the catalog and its scroll position stay mounted behind it.
final class AppDetailViewController: UIViewController {
    private let app: SourceCatalogApp
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let iconView = UIImageView()
    private let actionButton = UIButton(type: .system)
    private let progress = UIProgressView(progressViewStyle: .default)
    private var downloadSubscription: AnyCancellable?
    var onAction: (() -> Void)?
    var onClose: (() -> Void)?
    private let blue = UIColor(red: 51/255, green: 124/255, blue: 250/255, alpha: 1)

    init(app: SourceCatalogApp, actionTitle: String, actionEnabled: Bool) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.isEnabled = actionEnabled
    }

    required init?(coder: NSCoder) { fatalError("Programmatic only") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1)

        let bar = UIView()
        bar.backgroundColor = .white
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.setTitle(" 返回", for: .normal)
        back.tintColor = blue
        back.addTarget(self, action: #selector(closePage), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(back)

        let title = UILabel()
        title.text = "应用详情"
        title.textAlignment = .center
        title.font = .boldSystemFont(ofSize: 17)
        title.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(title)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        content.axis = .vertical
        content.spacing = 16
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        let summary = UIView()
        summary.backgroundColor = .white
        summary.layer.cornerRadius = 16
        content.addArrangedSubview(summary)
        summary.translatesAutoresizingMaskIntoConstraints = false

        let iconBackground = UIView()
        iconBackground.backgroundColor = UIColor(red: 230/255, green: 240/255, blue: 1, alpha: 1)
        iconBackground.layer.cornerRadius = 14
        iconBackground.clipsToBounds = true
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        summary.addSubview(iconBackground)

        iconView.image = UIImage(systemName: "square.grid.2x2.fill")
        iconView.tintColor = blue
        iconView.contentMode = .scaleAspectFit
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.addSubview(iconView)
        if let url = app.iconURL {
            SourceIconCache.shared.load(url) { [weak self] image in
                DispatchQueue.main.async { if let image = image { self?.iconView.image = image } }
            }
        }

        let appName = UILabel()
        appName.text = app.name
        appName.font = .boldSystemFont(ofSize: 20)
        appName.numberOfLines = 2
        appName.translatesAutoresizingMaskIntoConstraints = false
        summary.addSubview(appName)

        let metadata = UILabel()
        let size = app.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
        metadata.text = "版本 \(app.version.isEmpty ? "—" : app.version)  ·  \(size)"
        metadata.font = .systemFont(ofSize: 13)
        metadata.textColor = .secondaryLabel
        metadata.translatesAutoresizingMaskIntoConstraints = false
        summary.addSubview(metadata)

        actionButton.backgroundColor = blue
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.titleLabel?.font = .boldSystemFont(ofSize: 15)
        actionButton.layer.cornerRadius = 16
        actionButton.addTarget(self, action: #selector(performAction), for: .touchUpInside)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        summary.addSubview(actionButton)
        progress.translatesAutoresizingMaskIntoConstraints = false
        summary.addSubview(progress)
        downloadSubscription = AppStoreViewModel.shared.downloadCenter.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshDownloadStatus() }
            }
        refreshDownloadStatus()

        content.addArrangedSubview(section("应用介绍", text: app.description))
        content.addArrangedSubview(section("更新日志", text: app.releaseNotes))
        let developer = app.developer.isEmpty ? "—" : app.developer
        let bundle = app.bundleIdentifier.isEmpty ? "—" : app.bundleIdentifier
        content.addArrangedSubview(section("应用信息", text: "开发者：\(developer)\nBundle ID：\(bundle)"))

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52),
            back.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 18),
            back.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            title.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            scrollView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -40),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -18),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36),
            iconBackground.topAnchor.constraint(equalTo: summary.topAnchor, constant: 18),
            iconBackground.leadingAnchor.constraint(equalTo: summary.leadingAnchor, constant: 18),
            iconBackground.widthAnchor.constraint(equalToConstant: 68),
            iconBackground.heightAnchor.constraint(equalToConstant: 68),
            iconView.leadingAnchor.constraint(equalTo: iconBackground.leadingAnchor, constant: 8),
            iconView.trailingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: -8),
            iconView.topAnchor.constraint(equalTo: iconBackground.topAnchor, constant: 8),
            iconView.bottomAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: -8),
            appName.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 14),
            appName.trailingAnchor.constraint(equalTo: summary.trailingAnchor, constant: -16),
            appName.topAnchor.constraint(equalTo: summary.topAnchor, constant: 19),
            metadata.leadingAnchor.constraint(equalTo: appName.leadingAnchor),
            metadata.trailingAnchor.constraint(equalTo: appName.trailingAnchor),
            metadata.topAnchor.constraint(equalTo: appName.bottomAnchor, constant: 7),
            actionButton.topAnchor.constraint(greaterThanOrEqualTo: iconBackground.bottomAnchor, constant: 18),
            actionButton.topAnchor.constraint(greaterThanOrEqualTo: metadata.bottomAnchor, constant: 18),
            actionButton.leadingAnchor.constraint(equalTo: summary.leadingAnchor, constant: 18),
            actionButton.trailingAnchor.constraint(equalTo: summary.trailingAnchor, constant: -18),
            actionButton.heightAnchor.constraint(equalToConstant: 44),
            progress.topAnchor.constraint(equalTo: actionButton.bottomAnchor, constant: 8),
            progress.leadingAnchor.constraint(equalTo: actionButton.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor),
            progress.bottomAnchor.constraint(equalTo: summary.bottomAnchor, constant: -18)
        ])
    }

    private func section(_ title: String, text: String) -> UIView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 12
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        card.backgroundColor = .white
        card.layer.cornerRadius = 16

        let heading = UILabel()
        heading.text = title
        heading.font = .boldSystemFont(ofSize: 16)
        card.addArrangedSubview(heading)

        let body = UILabel()
        body.text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "暂无介绍" : text
        body.font = .systemFont(ofSize: 14)
        body.textColor = .secondaryLabel
        body.numberOfLines = 0
        card.addArrangedSubview(body)
        return card
    }

    private func refreshDownloadStatus() {
        guard let url = app.downloadURL,
              let item = AppStoreViewModel.shared.downloadCenter.item(for: url) else {
            progress.isHidden = true
            return
        }
        switch item.state {
        case .queued: actionButton.setTitle("等待下载", for: .normal); actionButton.isEnabled = false
        case .downloading:
            actionButton.setTitle("\(Int(item.progress * 100))% · 下载中", for: .normal)
            actionButton.isEnabled = false
        case .paused: actionButton.setTitle("继续", for: .normal); actionButton.isEnabled = true
        case .completed: actionButton.setTitle("已下载", for: .normal); actionButton.isEnabled = false
        case .failed, .cancelled: actionButton.setTitle("重试", for: .normal); actionButton.isEnabled = true
        }
        progress.isHidden = item.state == .completed
        progress.progress = Float(min(1, max(0, item.progress)))
    }

    @objc private func performAction() { onAction?() }
    @objc private func closePage() {
        dismiss(animated: true) { [weak self] in self?.onClose?() }
    }
}
