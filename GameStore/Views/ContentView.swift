import SwiftUI

/// Floating capsule navigation. Existing feature views remain unchanged.
struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
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

            floatingTabBar
                .padding(.horizontal, 36)
                .padding(.bottom, 12)
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, label: "应用", symbol: "square.grid.3x3.fill")
            tabButton(index: 1, label: "搜索", symbol: "magnifyingglass")
            tabButton(index: 2, label: "下载", symbol: "puzzlepiece.extension.fill")
            tabButton(index: 3, label: "设置", symbol: "gearshape.fill")
        }
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(red: 0.95, green: 0.95, blue: 0.96))
                .overlay(Capsule().stroke(Color.gray.opacity(0.30), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 7)
        )
    }

    private func tabButton(index: Int, label: String, symbol: String) -> some View {
        let active = selectedTab == index
        return Button(action: { selectedTab = index }) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 27, weight: .semibold))
                    .frame(height: 32)
                Text(label)
                    .font(.system(size: 12, weight: active ? .semibold : .medium))
            }
            .foregroundColor(active ? Color.blue : Color.gray)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}
