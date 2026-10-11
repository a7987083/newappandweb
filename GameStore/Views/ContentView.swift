import SwiftUI

/// TrollSkin-inspired presentation shell. Feature services and view models stay untouched.
/// Uses only SwiftUI APIs available on iOS 13.
struct ContentView: View {
    @State private var selectedTab = 0

    private let canvas = Color(red: 0.055, green: 0.070, blue: 0.095)
    private let panel = Color(red: 0.11, green: 0.14, blue: 0.19)
    private let highlight = Color(red: 0.38, green: 0.79, blue: 0.98)

    var body: some View {
        ZStack(alignment: .bottom) {
            canvas.edgesIgnoringSafeArea(.all)
            Group {
                if selectedTab == 0 {
                    SoftwareView()
                } else if selectedTab == 1 {
                    SearchView()
                } else if selectedTab == 2 {
                    DownloadCenterView()
                } else {
                    ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 78)

            navigationBar
                .padding(.horizontal, 18)
                .padding(.bottom, 9)
        }
        .environment(\.colorScheme, .dark)
        .accentColor(highlight)
    }

    private var navigationBar: some View {
        HStack(spacing: 2) {
            tab(index: 0, title: "应用", icon: "square.grid.2x2.fill")
            tab(index: 1, title: "搜索", icon: "magnifyingglass")
            tab(index: 2, title: "下载", icon: "arrow.down.circle.fill")
            tab(index: 3, title: "我的", icon: "person.crop.circle.fill")
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 21)
                .fill(panel)
                .overlay(RoundedRectangle(cornerRadius: 21)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.30), radius: 16, x: 0, y: 6)
        )
    }

    private func tab(index: Int, title: String, icon: String) -> some View {
        let selected = selectedTab == index
        return Button(action: { selectedTab = index }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(height: 24)
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(selected ? highlight : Color.white.opacity(0.50))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 15)
                .fill(selected ? highlight.opacity(0.11) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
