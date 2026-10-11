import SwiftUI

/// Search presentation only; source filtering and detail navigation are unchanged.
struct SearchView: View {
    @ObservedObject private var sources = SoftwareSourceStore.shared
    @State private var query = ""

    private var matches: [SourceCatalogApp] {
        guard !query.isEmpty else { return [] }
        return sources.catalogApps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(query) ||
            $0.category.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.55))
                    TextField("搜索软件、Bundle ID 或分类", text: $query)
                        .autocapitalization(.none)
                        .textFieldStyle(PlainTextFieldStyle())
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(15)
                .background(RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.11, green: 0.14, blue: 0.19)))

                HStack {
                    Text("搜索结果").font(.system(size: 17, weight: .bold))
                    Spacer()
                    Text("\(matches.count) 项")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                ScrollView {
                    VStack(spacing: 9) {
                        ForEach(matches) { app in
                            NavigationLink(destination: SourceAppDetailView(app: app)) {
                                HStack(spacing: 12) {
                                    SourceAppRow(app: app)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(13)
                                .background(RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(red: 0.11, green: 0.14, blue: 0.19)))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if matches.isEmpty {
                            Text(query.isEmpty ? "输入关键词开始搜索" : "没有匹配的软件")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 44)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .background(Color(red: 0.055, green: 0.070, blue: 0.095).edgesIgnoringSafeArea(.all))
            .navigationBarTitle("搜索")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
