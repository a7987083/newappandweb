import UIKit

@objc(AppCatalogCell)
final class AppCatalogCell: UITableViewCell {
    private let card = UIView()
    private let iconBacking = UIView()
    private let placeholder = UIImageView(image: UIImage(systemName: "square.grid.2x2.fill"))
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let metadataLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let downloadButton = UIButton(type: .system)
    private var representedIconURL = ""
    var onAction: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.backgroundColor = .white
        card.layer.cornerRadius = 16
        contentView.addSubview(card)
        iconBacking.backgroundColor = UIColor(red: 230/255, green: 240/255, blue: 1, alpha: 1)
        iconBacking.layer.cornerRadius = 11
        iconBacking.clipsToBounds = true
        card.addSubview(iconBacking)
        placeholder.contentMode = .scaleAspectFit
        placeholder.tintColor = UIColor(red: 51/255, green: 124/255, blue: 250/255, alpha: 1)
        iconBacking.addSubview(placeholder)
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconBacking.addSubview(iconView)
        nameLabel.font = .boldSystemFont(ofSize: 15)
        nameLabel.textColor = .black
        nameLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.font = .systemFont(ofSize: 11)
        metadataLabel.textColor = .secondaryLabel
        metadataLabel.adjustsFontSizeToFitWidth = true
        metadataLabel.minimumScaleFactor = 0.8
        descriptionLabel.font = .systemFont(ofSize: 10)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.lineBreakMode = .byTruncatingTail
        [nameLabel, metadataLabel, descriptionLabel].forEach(card.addSubview)
        downloadButton.setTitle("获取", for: .normal)
        downloadButton.titleLabel?.font = .boldSystemFont(ofSize: 12)
        downloadButton.setTitleColor(.white, for: .normal)
        downloadButton.backgroundColor = UIColor(red: 51/255, green: 124/255, blue: 250/255, alpha: 1)
        downloadButton.layer.cornerRadius = 15
        downloadButton.isEnabled = false
        downloadButton.addTarget(self, action: #selector(requestAction), for: .touchUpInside)
        card.addSubview(downloadButton)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic cell only") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        card.frame = CGRect(x: 18, y: 0, width: max(0, width - 36), height: 86)
        iconBacking.frame = CGRect(x: 13, y: 20, width: 46, height: 46)
        placeholder.frame = iconBacking.bounds.insetBy(dx: 10, dy: 10)
        iconView.frame = iconBacking.bounds
        let textWidth = max(0, card.bounds.width - 72 - 88)
        nameLabel.frame = CGRect(x: 72, y: 10, width: textWidth, height: 23)
        metadataLabel.frame = CGRect(x: 72, y: 34, width: textWidth, height: 17)
        descriptionLabel.frame = CGRect(x: 72, y: 55, width: max(0, card.bounds.width - 85), height: 17)
        downloadButton.frame = CGRect(x: max(72, card.bounds.width - 80), y: 20, width: 68, height: 30)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedIconURL = ""
        onAction = nil
        iconView.image = nil
    }

    @objc private func requestAction() { onAction?() }

    func configureAction(title: String, enabled: Bool) {
        downloadButton.setTitle(title, for: .normal)
        // Keep the button hit-testable even when its action is unavailable.
        // Otherwise a disabled button forwards taps to the table row.
        downloadButton.isEnabled = true
        downloadButton.isUserInteractionEnabled = true
        downloadButton.accessibilityTraits = enabled ? [.button] : [.button, .notEnabled]
        downloadButton.backgroundColor = title == "重试" ? .systemOrange :
            (enabled ? UIColor(red: 51/255, green: 124/255, blue: 250/255, alpha: 1) : .systemGray3)
    }

    @objc(configureWithName:metadata:descriptionText:iconURL:)
    func configure(name: String, metadata: String, descriptionText: String, iconURL: String) {
        nameLabel.text = name
        metadataLabel.text = metadata
        descriptionLabel.text = descriptionText
        representedIconURL = iconURL
        iconView.image = nil
        guard let url = URL(string: iconURL),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else { return }
        if let cached = SourceIconCache.shared.cachedMemoryImage(for: url) {
            iconView.image = cached
            return
        }
        SourceIconCache.shared.load(url) { [weak self] image in
            guard let self = self, self.representedIconURL == iconURL,
                  let image = image else { return }
            self.iconView.image = image
        }
    }
}
