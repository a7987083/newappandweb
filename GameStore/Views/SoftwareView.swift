import SwiftUI

/// Source-backed app listing is intentionally not implemented.
struct SoftwareView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 38))
                    .foregroundColor(.secondary)
                Text("暂无软件")
                    .font(.headline)
                Text("当前仅保留添加软件源功能，尚未启用软件列表。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .navigationBarTitle("精品软件")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
