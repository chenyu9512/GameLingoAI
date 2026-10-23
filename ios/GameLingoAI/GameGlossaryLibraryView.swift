import SwiftUI
import UniformTypeIdentifiers

@available(iOS 27.0, *)
@MainActor
struct GameGlossaryLibraryView: View {
    let gameID: UUID
    @ObservedObject private var library = GameGlossaryLibrary.shared
    @State private var importing = false
    @State private var search = ""
    @State private var showFormat = false
    @State private var errorText = ""

    private var results: [(String, String, String)] {
        Array(library.search(search).prefix(40))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("TXT 游戏词库", systemImage: "books.vertical.fill")
                    .font(.headline)
                Spacer()
                Text("\(library.packs.count) 套 · \(library.totalTerms) 词")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("支持多个词库同时使用；保存于本机。已启用词库立即参与 PiP、整屏菜单和截图翻译，不用逐条添加。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button {
                    importing = true
                } label: {
                    Label("导入 TXT 词库", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                Button("全部启用") { library.setAll(true, game: gameID) }
                    .buttonStyle(.bordered)
                Button("全部停用") { library.setAll(false, game: gameID) }
                    .buttonStyle(.bordered)
            }
            DisclosureGroup(isExpanded: $showFormat) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("文件编码：UTF-8（也接受 UTF-16）")
                    Text("第一种格式：日语=中文")
                    Text("第二种格式：日语[Tab]中文")
                    Text("以 # 开头的行可写备注，例如 # 词库名称：我的游戏")
                    Text("示例：")
                    Text("# 词库名称：DQ 补充\nホイミ=霍伊米\nスライム=史莱姆\n攻撃力=攻击力")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }
                .font(.caption).foregroundStyle(.secondary)
            } label: {
                Label("查看 TXT 格式和示例", systemImage: "doc.text")
            }
            if !library.lastNotice.isEmpty {
                Text(library.lastNotice).font(.caption).foregroundStyle(.mint)
            }
            if !errorText.isEmpty {
                Text(errorText).font(.caption).foregroundStyle(.orange)
            }
            ForEach(library.packs) { pack in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pack.title).font(.subheadline.bold())
                        Text("\(pack.entries.count) 条 · \(pack.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Toggle(pack.title, isOn: Binding(
                        get: { library.isEnabled(pack.id, game: gameID) },
                        set: { library.setEnabled($0, pack: pack.id, game: gameID) }
                    )).labelsHidden().tint(.mint)
                    Button(role: .destructive) {
                        library.remove(pack.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("删除 \(pack.title)")
                }
                Divider()
            }
            if library.packs.isEmpty {
                Text("还没有自定义 TXT 词库。内置日语 RPG 和勇者斗恶龙术语可继续使用。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("统一搜索所有已导入词条", text: $search)
                .textFieldStyle(.roundedBorder)
            if !search.isEmpty {
                ForEach(results.indices, id: \.self) { i in
                    let result = results[i]
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(result.0) → \(result.1)").font(.caption.bold())
                        Text(result.2).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if results.isEmpty {
                    Text("没有匹配词条").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.plainText], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                _ = try library.importText(data, suggestedName: url.lastPathComponent,
                                           game: gameID)
                errorText = ""
            } catch {
                errorText = "导入失败：\(error.localizedDescription)"
            }
        }
    }
}
