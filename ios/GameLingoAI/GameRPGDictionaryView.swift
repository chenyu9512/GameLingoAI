import SwiftUI

/// Read-only preview of the built-in RPG lexicon. Enabling the complete
/// Dragon Quest pack happens through a single button in the game settings.
/// No per-term importing into the editable glossary is necessary.
@available(iOS 27.0, *)
@MainActor
struct GameRPGDictionaryView: View {
    @State private var isExpanded = false
    @State private var search = ""
    @State private var category = GameRPGDictionary.dragonQuestCategory

    private var visible: [RPGGameTerm] {
        GameRPGDictionary.terms.filter { term in
            (category == "全部" || term.category == category)
            && (search.isEmpty
                || term.japanese.localizedCaseInsensitiveContains(search)
                || term.chinese.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("词库仅用于查询；整套启用后，无需逐条添加。原有自定义术语照常生效。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("搜索日语 / 中文词条", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("查看分类", selection: $category) {
                    Text("全部").tag("全部")
                    ForEach(GameRPGDictionary.categories, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }.pickerStyle(.menu)
                Text("符合条件：\(visible.count) 条，以下展示前 80 条。")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(Array(visible.prefix(80))) { term in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(term.japanese).font(.subheadline.bold())
                        Text(term.chinese).font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
            .padding(.top, 8)
        } label: {
            Label("按需查看术语内容（无需逐条添加）", systemImage: "text.book.closed")
                .font(.subheadline)
        }
    }
}
