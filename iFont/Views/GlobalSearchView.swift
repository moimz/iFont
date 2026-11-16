import SwiftUI

/// 모든 폰트·아이콘그룹에서 이름·키워드·\e600 코드로 찾는다. 결과가 없는 폰트·그룹은 숨긴다.
/// 아이콘을 누르면 그 폰트나 그룹으로 가서 보여 준다
struct GlobalSearchView: View {
	@Environment(Store.self) private var store
	@Binding var selection: SidebarItem?
	/// 다른 화면에 다녀와도 검색어가 남게
	@SceneStorage("globalSearch") private var query = ""
	@State private var searching = true
	@State private var collapsed: Set<UUID> = []

	private let columns = [GridItem(.adaptive(minimum: IconCell.size, maximum: IconCell.size), spacing: 8)]

	private struct FontHit { var font: FontDoc; var glyphs: [FontGlyph] }
	private struct GroupHit { var group: IconGroup; var icons: [Icon] }

	var body: some View {
		let q = query.trimmingCharacters(in: .whitespaces)
		let fonts = q.isEmpty ? [] : store.fonts.compactMap { f -> FontHit? in
			let g = f.orderedGlyphs.filter { matches($0, in: f, q) }
			return g.isEmpty ? nil : FontHit(font: f, glyphs: g)
		}
		let groups = q.isEmpty ? [] : store.groups.compactMap { g -> GroupHit? in
			let i = g.icons.filter { $0.matches(q, prefix: g.prefix) }
			return i.isEmpty ? nil : GroupHit(group: g, icons: i)
		}
		let total = fonts.reduce(0) { $0 + $1.glyphs.count } + groups.reduce(0) { $0 + $1.icons.count }

		Group {
			if q.isEmpty {
				ContentUnavailableView("전체 검색", systemImage: "magnifyingglass",
				                       description: Text("모든 폰트와 아이콘그룹에서 이름, 키워드, \\e600 코드로 찾습니다."))
			} else if total == 0 {
				ContentUnavailableView.search(text: q)
			} else {
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
						ForEach(fonts, id: \.font.id) { hit in
							Section {
								if !collapsed.contains(hit.font.id) {
									grid(hit.glyphs.map { g in cell(g, in: hit.font) })
								}
							} header: {
								header(hit.font.id, title: hit.font.name, kind: "폰트", icon: "textformat", count: hit.glyphs.count) {
									selection = .font(hit.font.id)
								}
							}
						}
						ForEach(groups, id: \.group.id) { hit in
							Section {
								if !collapsed.contains(hit.group.id) {
									grid(hit.icons.map { i in cell(i, in: hit.group) })
								}
							} header: {
								header(hit.group.id, title: hit.group.name, kind: "아이콘그룹", icon: "square.grid.3x3", count: hit.icons.count) {
									selection = .group(hit.group.id)
								}
							}
						}
					}
					.padding(.bottom, 16)
				}
			}
		}
		.navigationTitle("전체 검색")
		.navigationSubtitle(q.isEmpty ? "" : "\(total)개 · 폰트 \(fonts.count) · 아이콘그룹 \(groups.count)")
		.searchable(text: $query, isPresented: $searching, placement: .toolbar, prompt: "이름, 키워드, \\e600 검색")
	}

	// MARK: - 칸

	private struct Cell: Identifiable {
		var id: String
		var shape: CGPath
		var width: Double
		var em: Double
		var label: String
		var tooltip: String
		var open: () -> Void
	}

	private func cell(_ g: FontGlyph, in font: FontDoc) -> Cell {
		let shape = FontExport.shape(g, in: font, store: store)
		let source = store.group(g.groupID).map { "\n원본: \($0.name)" } ?? ""
		return Cell(id: "f" + g.id, shape: shape, width: g.width, em: Double(font.unitsPerEm), label: font.prefix + g.name,
		            tooltip: "\(font.prefix)\(g.name)  \(g.code.cssEscape)" + (g.section.map { "\n폰트 안 그룹: \($0)" } ?? "") + source) {
			selection = .font(font.id)
		}
	}

	private func cell(_ i: Icon, in group: IconGroup) -> Cell {
		var tip = group.prefix + i.name
		if let c = i.code { tip += "  " + c.cssEscape }
		if let t = i.tags, !t.isEmpty { tip += "\n키워드: " + t.joined(separator: ", ") }
		return Cell(id: "g" + i.id, shape: IconShape.path(i, in: group), width: i.width, em: 1000, label: group.prefix + i.name, tooltip: tip) {
			store.revealIcon = i.id
			selection = .group(group.id)
		}
	}

	private func grid(_ cells: [Cell]) -> some View {
		LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
			ForEach(cells) { c in
				IconCell(shape: c.shape, width: c.width, em: c.em, label: c.label, copyValue: c.label, tooltip: c.tooltip)
					.contentShape(.rect)
					.onTapGesture(perform: c.open)
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
	}

	private func header(_ id: UUID, title: String, kind: String, icon: String, count: Int, open: @escaping () -> Void) -> some View {
		HStack(spacing: 8) {
			Button {
				if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
			} label: {
				Image(systemName: "chevron.right")
					.rotationEffect(.degrees(collapsed.contains(id) ? 0 : 90))
					.frame(width: 14)
			}
			.buttonStyle(.plain)
			Image(systemName: icon).foregroundStyle(.secondary)
			Text(title).font(.headline)
			Text(kind).font(.caption).foregroundStyle(.secondary)
			Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
			Spacer()
			Button("열기", action: open).buttonStyle(.link)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.background(.bar)
	}

	/// 폰트 아이콘: 이름(접두어 포함)·코드, 원본 아이콘의 키워드
	private func matches(_ g: FontGlyph, in font: FontDoc, _ q: String) -> Bool {
		let q = q.lowercased()
		if (font.prefix + g.name).lowercased().contains(q) || g.code.cssEscape.contains(q) { return true }
		return store.icon(of: g)?.tags?.contains { $0.lowercased().contains(q) } ?? false
	}
}
