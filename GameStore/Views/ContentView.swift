import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SoftwareView()
                .tabItem {
                    Image(systemName: "square.grid.2x2")
                    Text("软件")
                }

            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("搜索")
                }

            DownloadCenterView()
                .tabItem {
                    Image(systemName: "arrow.down.circle")
                    Text("下载")
                }

            ProfileView()
                .tabItem {
                    Image(systemName: "person.crop.circle")
                    Text("我的")
                }
        }
    }
}
