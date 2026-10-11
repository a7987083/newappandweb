import UIKit

/// Four-item floating capsule. Each shell page retains its own bar instance.
final class ShellTabBar: UIView {
    var onSelect: ((Int) -> Void)?
    private let titles = ["应用", "安装包", "插件", "设置"]
    private let icons = ["square.grid.3x3.fill", "shippingbox.fill", "puzzlepiece.fill", "gearshape.fill"]

    init(width: CGFloat, height: CGFloat, bottomInset: CGFloat, selectedTab: Int, tint: UIColor) {
        let barWidth = min(width - 112, 320)
        super.init(frame: CGRect(x: (width - barWidth)/2,
                                 y: height - bottomInset - 72,
                                 width: barWidth, height: 60))
        autoresizingMask = [.flexibleTopMargin, .flexibleLeftMargin, .flexibleRightMargin]
        layer.cornerRadius = 30
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.lightGray.cgColor
        backgroundColor = UIColor(red: 249/255, green: 249/255, blue: 251/255, alpha: 1)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 11
        for index in 0..<4 {
            let column = barWidth / 4
            let button = UIButton(type: .system)
            button.tag = index
            button.frame = CGRect(x: CGFloat(index)*column, y: 2, width: column, height: 38)
            button.tintColor = index == selectedTab ? tint : .gray
            button.setImage(UIImage(systemName: icons[index],
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 19)), for: .normal)
            button.addTarget(self, action: #selector(selectTab(_:)), for: .touchUpInside)
            addSubview(button)
            let label = UILabel(frame: CGRect(x: CGFloat(index)*column, y: 38,
                                              width: column, height: 17))
            label.text = titles[index]
            label.textAlignment = .center
            label.textColor = button.tintColor
            label.font = index == selectedTab ? .boldSystemFont(ofSize: 10) : .systemFont(ofSize: 10)
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("Programmatic only") }

    @objc private func selectTab(_ sender: UIButton) {
        onSelect?(sender.tag)
    }
}
