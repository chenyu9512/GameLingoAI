import SwiftUI

/// Browse curated Japanese RPG terminology without accessing the network.
@available(iOS 27.0, *)
@MainActor
struct GameRPGDictionaryView: View {
    let onInsert: (RPGGameTerm) -> Void
    @State private var search = ""
    @State private var category = "全部"

    private var visible: [RPGGameTerm] {
        GameRPGDictionary.terms.filter { term in
            (category == "全部" || term.category == category)
            && (search.isEmpty
                || term.japanese.localizedCaseInsensitiveContains(search)
                || term.chinese.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("内置日语游戏术语（\(GameRPGDictionary.terms.count) 条）",
                  systemImage: "character.book.closed")
                .font(.headline)
            Text("包含 RPG 菜单、战斗、任务、道具、原创常见台词及《勇者斗恶龙》专用术语；无需下载。用户自定义词条优先。")
                .font(.caption).foregroundStyle(.secondary)
            TextField("搜索日语 / 中文词条", text: $search)
                .textFieldStyle(.roundedBorder)
            Picker("分类", selection: $category) {
                Text("全部").tag("全部")
                ForEach(GameRPGDictionary.categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }.pickerStyle(.menu)
            Text("匹配 \(visible.count) 条。以下最多展示前 80 条，可搜索筛选；术语库全部参与翻译。")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(Array(visible.prefix(80))) { term in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(term.japanese).font(.subheadline.bold())
                        Text(term.chinese).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button {
                        onInsert(term)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("加入自定义术语")
                }
                Divider()
            }
        }
    }
}
