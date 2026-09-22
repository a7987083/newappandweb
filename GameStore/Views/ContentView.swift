import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SoftwareView()
                .tabItem { Label("软件", systemImage: "square.grid.2x2") }

            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }

            DownloadCenterView()
                .tabItem { Label("下载", systemImage: "arrow.down.circle") }

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}
