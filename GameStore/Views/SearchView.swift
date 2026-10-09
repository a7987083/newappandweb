import SwiftUI

/// Software-source search is removed until a new catalog is implemented.
struct SearchView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 38))
                    .foregroundColor(.secondary)
                Text("暂无可搜索的软件")
                    .font(.headline)
                Text("当前仅保留添加软件源功能。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .navigationBarTitle("搜索")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
