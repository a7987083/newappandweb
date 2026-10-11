import UIKit

/// Shared large-title header for the app, package, and plugin pages.
/// The search bar is intentionally reparented by the existing search animation.
final class ShellHeaderView: UIView {
    let searchBar: UISearchBar
    private let titleLabel = UILabel()

    init(title: String, width: CGFloat, safeTop: CGFloat, background: UIColor) {
        searchBar = UISearchBar(frame: .zero)
        super.init(frame: .zero)
        backgroundColor = background
        titleLabel.text = title
        titleLabel.font = .boldSystemFont(ofSize: 37)
        addSubview(titleLabel)

        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = "搜索"
        searchBar.searchTextField.backgroundColor = UIColor(
            red: 229/255, green: 229/255, blue: 234/255, alpha: 1)
        searchBar.searchTextField.layer.cornerRadius = 12
        searchBar.searchTextField.clipsToBounds = true
        addSubview(searchBar)
        updateLayout(width: width, safeTop: safeTop)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic only") }

    /// Do not reattach the search bar during an active search transition.
    func updateLayout(width: CGFloat, safeTop: CGFloat) {
        frame = CGRect(x: 0, y: 0, width: width, height: safeTop + 189)
        titleLabel.frame = CGRect(x: 20, y: safeTop + 66,
                                  width: width - 40, height: 53)
        searchBar.frame = CGRect(x: 12, y: safeTop + 127,
                                 width: width - 24, height: 52)
    }
}
