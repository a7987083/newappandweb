import SwiftUI

/// Single-owner floating navigation shell. iOS 13 compatible.
struct ContentView: View {
    @State private var selectedTab = 0

    private let background = Color(red: 0.95, green: 0.95, blue: 0.97)

    var body: some View {
        ZStack(alignment: .bottom) {
            background.edgesIgnoringSafeArea(.all)

            Group {
                switch selectedTab {
                case 0: SoftwareView()
                case 1: DownloadCenterView()
                case 2: GameStorePluginsView()
                default: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 82)

            floatingTabBar
                .padding(.horizontal, 36)
                .padding(.bottom, 12)
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, label: "应用", symbol: "square.grid.3x3.fill")
            tabButton(index: 1, label: "安装包", symbol: "square.stack.fill")
            tabButton(index: 2, label: "插件", symbol: "puzzlepiece.extension.fill")
            tabButton(index: 3, label: "设置", symbol: "gearshape.fill")
        }
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(red: 0.96, green: 0.96, blue: 0.97))
                .overlay(Capsule().stroke(Color.gray.opacity(0.30), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.09), radius: 14, x: 0, y: 5)
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
            .foregroundColor(active ? Color(red: 0.21, green: 0.47, blue: 0.98) : .gray)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Plugin management is intentionally separate from IPA signing. No fake items.
private struct GameStorePluginsView: View {
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.95, green: 0.95, blue: 0.97).edgesIgnoringSafeArea(.all)
                VStack(spacing: 10) {
                    Text("插件")
                        .font(.system(size: 40, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                    Spacer()
                    Text("暂无插件")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 12)
            }
            .navigationBarTitle("", displayMode: .inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
