import UIKit

/// The source app card owns its image request and reuse token.
/// Only visible UITableView cells initiate image loading.
@objc(AppCatalogCell)
final class AppCatalogCell: UITableViewCell {
    private let card = UIView()
    private let iconBacking = UIView()
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let categoryLabel = UILabel()
    private var representedIconURL = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.backgroundColor = .white
        card.layer.cornerRadius = 16
        contentView.addSubview(card)
        iconBacking.backgroundColor = UIColor(red: 230/255, green: 240/255, blue: 1, alpha: 1)
        iconBacking.layer.cornerRadius = 11
        card.addSubview(iconBacking)
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor(red: 51/255, green: 124/255, blue: 250/255, alpha: 1)
        iconView.clipsToBounds = true
        iconBacking.addSubview(iconView)
        nameLabel.font = .boldSystemFont(ofSize: 15)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabel
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.75
        categoryLabel.font = .systemFont(ofSize: 10)
        categoryLabel.textColor = iconView.tintColor
        categoryLabel.backgroundColor = iconBacking.backgroundColor
        categoryLabel.textAlignment = .center
        categoryLabel.layer.cornerRadius = 5
        categoryLabel.clipsToBounds = true
        [nameLabel, detailLabel, categoryLabel].forEach(card.addSubview)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic cell only") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        card.frame = CGRect(x: 18, y: 0, width: max(0, width - 36), height: 70)
        iconBacking.frame = CGRect(x: 13, y: 12, width: 46, height: 46)
        iconView.frame = iconBacking.bounds.insetBy(dx: 10, dy: 10)
        nameLabel.frame = CGRect(x: 72, y: 8, width: max(0, width - 118), height: 22)
        detailLabel.frame = CGRect(x: 72, y: 28, width: max(0, width - 116), height: 17)
        categoryLabel.frame = CGRect(x: 72, y: 49, width: 60, height: 16)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedIconURL = ""
        iconView.image = UIImage(systemName: "square.grid.2x2.fill")
    }

    @objc(configureWithName:detail:category:iconURL:)
    func configure(name: String, detail: String, category: String, iconURL: String) {
        nameLabel.text = name
        detailLabel.text = detail
        categoryLabel.text = category
        representedIconURL = iconURL
        iconView.image = UIImage(systemName: "square.grid.2x2.fill")
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
