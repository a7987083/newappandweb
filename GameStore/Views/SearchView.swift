import SwiftUI
import UIKit

struct SearchView: View {
    @EnvironmentObject private var store: AppStoreViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                if store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchPrompt
                } else if store.filteredApps.isEmpty {
                    emptyResults
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(store.filteredApps.enumerated()), id: \.element.id) { index, app in
                                NavigationLink(destination: AppDetailView(app: app)) {
                                    AppRowView(app: app)
                                }
                                .buttonStyle(PlainButtonStyle())

                                if index != store.filteredApps.count - 1 {
                                    Divider().padding(.leading, 86)
                                }
                            }
                        }
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                        .padding(16)
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
            .navigationBarTitle("搜索")
            .onAppear {
                if store.apps.isEmpty {
                    store.reload()
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("游戏、应用、开发者", text: $store.searchText)
                .disableAutocorrection(true)

            if !store.searchText.isEmpty {
                Button(action: { store.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }

    private var searchPrompt: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("搜索 GameStore")
                .font(.headline)
            Text("游戏、应用、开发者")
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("未找到相关内容")
                .font(.headline)
            Text("尝试搜索其他游戏或关键词")
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}
