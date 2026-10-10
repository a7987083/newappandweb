import SwiftUI

/// Four-tab navigation adapted from the user-supplied TrollStoreStyleUI root.
/// Reuses existing GameStore pages instead of the source archive's placeholders.
struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SoftwareView()
                .tabItem {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("应用")
                }
                .tag(0)

            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("搜索")
                }
                .tag(1)

            DownloadCenterView()
                .tabItem {
                    Image(systemName: "shippingbox.fill")
                    Text("下载")
                }
                .tag(2)

            ProfileView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("设置")
                }
                .tag(3)
        }
        .accentColor(.blue)
    }
}
