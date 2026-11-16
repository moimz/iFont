import SwiftUI

/// 폰트 화면: 그 폰트에 들어 있는 아이콘만 그룹별로 보여 준다.
/// 그룹 순서와 그룹 안 아이콘 순서가 곧 CSS 순서다.
/// 아이콘은 아이콘그룹에서 우클릭·끌어다 놓기로만 넣는다. 폰트 아이콘은 언제나 아이콘그룹의 원본을 쓴다.
struct FontEditorView: View {
	@Environment(Store.self) private var store
	@Binding var font: FontDoc
	@Binding var selection: SidebarItem?
	@State private var search = ""
	@State private var selected: Set<String> = []
	/// 아이콘 대치 시트를 띄운 아이콘
	@State private var replacing: FontGlyph?
	@State private var showSettings = true
	@State private var exportResult: (title: String, text: String, folder: URL?)?
	@State private var askSectionName = false
	@State private var sectionName = ""

	var body: some View {
		FontGlyphGrid(font: $font, search: search, selected: $selected,
		              onReveal: reveal, onReplace: { replacing = $0 })
			.navigationTitle(font.name)
			.navigationSubtitle("아이콘 \(font.glyphs.count)개")
			.searchable(text: $search, placement: .toolbar, prompt: "이름, 키워드, \\e600 검색")
			.toolbar {
				ToolbarItem {
					Button { sectionName = ""; askSectionName = true } label: {
						Label("그룹 추가", systemImage: "plus")
					}
					.help("폰트 안 그룹 추가")
				}
				ToolbarSpacer(.fixed)
				ToolbarItemGroup {
					EmBoxToggle()
					Button { showSettings.toggle() } label: { Label("폰트 설정", systemImage: "sidebar.right") }
						.help("폰트 설정")
				}
			}
			.inspector(isPresented: $showSettings) {
				FontSettingsPanel(font: $font, onExport: export)
					.inspectorColumnWidth(min: 280, ideal: 320, max: 400)
			}
			.alert("그룹 추가", isPresented: $askSectionName) {
				TextField("그룹 이름", text: $sectionName)
				Button("취소", role: .cancel) {}
				Button("추가") {
					let name = sectionName.trimmingCharacters(in: .whitespaces)
					font.addSection(name.isEmpty ? "새 그룹" : name)
				}
			} message: {
				Text("폰트 안에서 아이콘을 나눠 둘 그룹입니다. 그룹 순서와 그룹 안 아이콘 순서가 CSS 순서가 됩니다.")
			}
			.sheet(item: $replacing) { glyph in
				ReplaceIconSheet(font: font, glyph: glyph)
			}
			.alert(exportResult?.title ?? "", isPresented: Binding(get: { exportResult != nil }, set: { if !$0 { exportResult = nil } })) {
				if let folder = exportResult?.folder {
					Button("Finder 에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
				}
				Button("확인", role: .cancel) {}
			} message: {
				Text(exportResult?.text ?? "")
			}
	}

	/// 폴더를 골라 woff2 · SVG 폰트 · CSS · 미리보기 HTML 을 내보낸다
	private func export() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.canCreateDirectories = true
		panel.prompt = "내보내기"
		panel.message = "\(font.name) 폰트를 내보낼 폴더를 고르세요. 같은 이름 파일은 덮어씁니다."
		if let last = font.exportFolder { panel.directoryURL = URL(fileURLWithPath: last) }
		guard panel.runModal() == .OK, let folder = panel.url else { return }
		do {
			// 내려받을 때마다 끝자리(내려받은 횟수)를 하나 늘린다. 실패하면 늘리지 않는다
			var next = font
			next.downloads += 1
			let files = try FontExport.write(next, store: store, to: folder)
			font.downloads = next.downloads
			font.exportFolder = folder.path
			exportResult = ("\(font.name) \(FontExport.version(font)) 내보냄",
			                files.map(\.lastPathComponent).joined(separator: "\n") + "\n\n" + folder.path, files.first)
		} catch {
			exportResult = ("내보내지 못했습니다", error.localizedDescription, nil)
		}
	}

	/// 원본 아이콘그룹을 열고 그 아이콘을 골라 보여 준다
	private func reveal(_ glyph: FontGlyph) {
		guard store.icon(of: glyph) != nil else { return }
		store.revealIcon = glyph.iconID
		selection = .group(glyph.groupID)
	}
}

/// 폰트 아이콘을 그룹별 격자로 보여 준다.
/// 칸 위쪽은 유니코드, 아래쪽은 접두어 + 이름 입력칸. 아이콘을 끌어 다른 아이콘 앞이나 그룹 안 빈 곳·그룹 머리에 놓아 옮긴다.
struct FontGlyphGrid: View {
	@Environment(Store.self) private var store
	@Binding var font: FontDoc
	var search: String
	@Binding var selected: Set<String>
	var onReveal: (FontGlyph) -> Void
	var onReplace: (FontGlyph) -> Void
	@FocusState private var focused: Bool
	@State private var collapsed: Set<String> = []
	@State private var renamingSection: String?
	@State private var sectionName = ""
	/// 끌어다 놓을 자리 표시: 그룹 키("" 는 그룹 없음) 또는 아이콘 id
	@State private var dropSection: String?
	@State private var dropBefore: String?
	/// ⇧ 클릭 범위의 시작 칸
	@State private var anchor: String?
	/// 코드 다시 매기기 중인 그룹 (안쪽 nil 은 그룹 없음)
	@State private var renumbering: String??
	@State private var renumberStart = ""
	@State private var renumberConflicts: [UInt32] = []

	private let columns = [GridItem(.adaptive(minimum: FontGlyphCell.width, maximum: FontGlyphCell.width), spacing: 8)]

	var body: some View {
		let glyphs = font.glyphs.filter(matches)
		let dupCodes = duplicates(font.glyphs.map(\.code))
		let dupNames = duplicates(font.glyphs.map(\.name))
		if font.glyphs.isEmpty {
			ContentUnavailableView {
				Label("아이콘이 없습니다", systemImage: "textformat")
			} description: {
				Text("아이콘그룹에서 아이콘을 우클릭해 \"폰트에 추가\"를 고르거나, 골라서 왼쪽 폰트 이름으로 끌어다 놓으세요.\n새 SVG 는 아이콘그룹에 먼저 넣습니다.")
			}
		} else {
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
					// 검색 중에는 결과가 없는 그룹을 숨긴다
					ForEach(font.grouped(glyphs).filter { search.isEmpty || !$0.glyphs.isEmpty }, id: \.section) { part in
						let key = part.section ?? ""
						Section {
							if !collapsed.contains(key) {
								grid(part.glyphs, section: part.section, dupCodes: dupCodes, dupNames: dupNames)
							}
						} header: {
							if !font.sections.isEmpty { sectionHeader(part.section, count: part.glyphs.count) }
						}
					}
				}
				.padding(.bottom, 16)
			}
			.focusable()
			.focusEffectDisabled()
			.focused($focused)
			.onDeleteCommand { remove(selected) }
			.onCopyCommand {
				let values = font.orderedGlyphs.filter { selected.contains($0.id) }.map { font.prefix + $0.name }
				return values.isEmpty ? [] : [NSItemProvider(object: values.joined(separator: "\n") as NSString)]
			}
			.alert("코드 다시 매기기", isPresented: Binding(get: { renumbering != nil && renumberConflicts.isEmpty }, set: { if !$0 { renumbering = nil } })) {
				TextField("시작 코드 (예: e100)", text: $renumberStart)
				Button("취소", role: .cancel) {}
				Button("적용") { tryRenumber() }
			} message: {
				if let sec = renumbering {
					Text("\(sec ?? "그룹 없음") 그룹 아이콘 \(font.glyphs(in: sec).count)개에 지금 순서대로 시작 코드부터 1씩 늘려 붙입니다.")
				}
			}
			.alert("코드가 겹칩니다", isPresented: Binding(get: { renumbering != nil && !renumberConflicts.isEmpty }, set: { if !$0 { renumbering = nil; renumberConflicts = [] } })) {
				Button("취소", role: .cancel) { renumberConflicts = [] }
				Button("그래도 바꾸기", role: .destructive) {
					if let sec = renumbering, let start = parsedStart { font.renumber(sec, from: start) }
					renumberConflicts = []
				}
			} message: {
				let list = renumberConflicts.prefix(6).map(\.cssEscape).joined(separator: ", ")
				Text("다른 그룹 아이콘이 이미 쓰는 코드 \(renumberConflicts.count)개와 겹칩니다: \(list)\(renumberConflicts.count > 6 ? " 외" : "")\n겹친 코드는 빨간색으로 표시됩니다.")
			}
			.alert("그룹 이름 바꾸기", isPresented: Binding(get: { renamingSection != nil }, set: { if !$0 { renamingSection = nil } })) {
				TextField("그룹 이름", text: $sectionName)
				Button("취소", role: .cancel) {}
				Button("바꾸기") { if let old = renamingSection { font.renameSection(old, to: sectionName) } }
			}
		}
	}

	private func grid(_ glyphs: [FontGlyph], section: String?, dupCodes: Set<UInt32>, dupNames: Set<String>) -> some View {
		LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
			ForEach(glyphs) { glyph in
				if let i = font.glyphs.firstIndex(where: { $0.id == glyph.id }) {
					FontGlyphCell(glyph: $font.glyphs[i], shape: shape(glyph), prefix: font.prefix, em: Double(font.unitsPerEm),
					              selected: selected.contains(glyph.id),
					              codeDup: dupCodes.contains(glyph.code), nameDup: dupNames.contains(glyph.name),
					              dropBefore: dropBefore == glyph.id,
					              dragValue: FontDrag.glyphs(dragTargets(glyph)),
					              tooltip: tooltip(glyph),
					              onTap: { click(glyph) })
						.contextMenu { menu(glyph) }
						// 아이콘 위에 놓으면 그 아이콘 앞으로
						.dropDestination(for: String.self) { items, _ in
							drop(items, before: glyph.id, in: section)
						} isTargeted: { on in dropBefore = on ? glyph.id : (dropBefore == glyph.id ? nil : dropBefore) }
				}
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
		.background(dropSection == (section ?? "") && dropBefore == nil ? Color.accentColor.opacity(0.08) : Color.clear)
		.contentShape(.rect)
		// 그룹 안 빈 곳에 놓으면 그 그룹 맨 뒤로
		.dropDestination(for: String.self) { items, _ in
			drop(items, before: nil, in: section)
		} isTargeted: { on in
			let key = section ?? ""
			dropSection = on ? key : (dropSection == key ? nil : dropSection)
		}
	}

	/// 아이콘을 놓는다. 그룹 머리를 아이콘 자리에 놓은 경우는 무시
	private func drop(_ items: [String], before target: String?, in section: String?) -> Bool {
		var handled = false
		for item in items {
			if let ids = FontDrag.decodeGlyphs(item) {
				font.place(ids, before: target, in: section)
				handled = true
			}
		}
		dropBefore = nil
		dropSection = nil
		return handled
	}

	private func dragTargets(_ glyph: FontGlyph) -> [String] {
		guard selected.contains(glyph.id), selected.count > 1 else { return [glyph.id] }
		return font.orderedGlyphs.map(\.id).filter(selected.contains)
	}

	private func sectionHeader(_ section: String?, count: Int) -> some View {
		let key = section ?? ""
		return HStack(spacing: 8) {
			Button {
				if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
			} label: {
				Image(systemName: "chevron.right")
					.rotationEffect(.degrees(collapsed.contains(key) ? 0 : 90))
					.frame(width: 14)
			}
			.buttonStyle(.plain)
			Text(section ?? "그룹 없음").font(.headline)
				.foregroundStyle(section == nil ? .secondary : .primary)
			Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
			Spacer()
			if section != nil {
				Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
					.help("끌어서 그룹 순서 바꾸기")
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.background(dropSection == "#" + key ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.bar))
		.contentShape(.rect)
		.modifier(SectionDragModifier(section: section))
		.dropDestination(for: String.self) { items, _ in
			var handled = false
			for item in items {
				if let ids = FontDrag.decodeGlyphs(item) {
					font.place(ids, before: nil, in: section)
					handled = true
				} else if let name = FontDrag.decodeSection(item), let section {
					font.moveSection(name, onto: section)
					handled = true
				}
			}
			dropSection = nil
			return handled
		} isTargeted: { on in
			dropSection = on ? "#" + key : (dropSection == "#" + key ? nil : dropSection)
		}
		.contextMenu {
			Button("코드 다시 매기기…") {
				renumberStart = font.glyphs(in: section).first.map { String($0.code, radix: 16) } ?? "e600"
				renumberConflicts = []
				renumbering = .some(section)
			}
			.disabled(count == 0)
			Divider()
			if let section {
				Button("그룹 이름 바꾸기…") { sectionName = section; renamingSection = section }
				Button("위로 옮기기") { font.moveSection(section, by: -1) }
				Button("아래로 옮기기") { font.moveSection(section, by: 1) }
				Divider()
				Button("그룹 지우기 (아이콘은 남김)", role: .destructive) { font.deleteSection(section) }
			}
			Button("모두 펼치기") { collapsed = [] }
			Button("모두 접기") { collapsed = Set(font.sections + [""]) }
		}
	}

	private var parsedStart: UInt32? {
		UInt32(renumberStart.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: ""), radix: 16)
	}

	/// 시작 코드가 올바르면 겹치는지 보고, 안 겹치면 바로 바꾸고 겹치면 경고를 띄운다
	private func tryRenumber() {
		guard let sec = renumbering else { return }
		guard let start = parsedStart, start <= 0x10FFFF else { renumbering = nil; return }
		let conflicts = font.renumberConflicts(sec, from: start)
		if conflicts.isEmpty {
			font.renumber(sec, from: start)
			renumbering = nil
		} else {
			// 경고 창이 이어서 뜨도록 다음 차례에 넣는다
			DispatchQueue.main.async {
				renumbering = .some(sec)
				renumberConflicts = conflicts
			}
		}
	}

	@ViewBuilder
	private func menu(_ glyph: FontGlyph) -> some View {
		let targets = selected.contains(glyph.id) ? selected : [glyph.id]
		Button("원본 보기") { onReveal(glyph) }
			.disabled(store.icon(of: glyph) == nil)
		Button("아이콘 대치…") { onReplace(glyph) }
		Button(targets.count > 1 ? "SVG 다운로드… (\(targets.count)개, zip)" : "SVG 다운로드…") { downloadSVG(targets) }
		Menu("애니메이션") {
			Button { setAnimation(nil, targets) } label: {
				if glyph.animation == nil { Label("없음", systemImage: "checkmark") } else { Text("없음") }
			}
			Divider()
			ForEach(GlyphAnimation.allCases, id: \.self) { a in
				Button { setAnimation(a, targets) } label: {
					if glyph.animation == a { Label(a.title, systemImage: "checkmark") } else { Text(a.title) }
				}
			}
		}
		Divider()
		Button("\(glyph.code.cssEscape) 복사") { copy(glyph.code.cssEscape) }
		Button("\(font.prefix + glyph.name) 복사") { copy(font.prefix + glyph.name) }
		Divider()
		Menu(targets.count > 1 ? "그룹 (\(targets.count)개)" : "그룹") {
			ForEach(font.sections, id: \.self) { sec in
				Button { font.place(font.orderedGlyphs.map(\.id).filter(targets.contains), before: nil, in: sec) } label: {
					if glyph.section == sec { Label(sec, systemImage: "checkmark") } else { Text(sec) }
				}
			}
			if !font.sections.isEmpty { Divider() }
			Button("그룹 없음") { font.place(font.orderedGlyphs.map(\.id).filter(targets.contains), before: nil, in: nil) }
			Button("새 그룹으로") {
				let sec = font.addSection()
				font.place(font.orderedGlyphs.map(\.id).filter(targets.contains), before: nil, in: sec)
			}
		}
		Divider()
		Button(targets.count > 1 ? "폰트에서 빼기 (\(targets.count)개)" : "폰트에서 빼기", role: .destructive) { remove(targets) }
	}

	/// 이름·코드, 그리고 원본 아이콘의 키워드로 찾는다
	private func matches(_ glyph: FontGlyph) -> Bool {
		let q = search.trimmingCharacters(in: .whitespaces).lowercased()
		if q.isEmpty { return true }
		if (font.prefix + glyph.name).lowercased().contains(q) || glyph.code.cssEscape.contains(q) { return true }
		guard let icon = store.icon(of: glyph) else { return false }
		return icon.tags?.contains { $0.lowercased().contains(q) } ?? false
	}

	/// 폰트 선 굵기·크기 배율을 적용한 모양 (내보낼 모양과 같다)
	private func shape(_ glyph: FontGlyph) -> CGPath {
		FontExport.shape(glyph, in: font, store: store)
	}

	private func tooltip(_ glyph: FontGlyph) -> String {
		guard let group = store.group(glyph.groupID), let icon = store.icon(of: glyph) else { return "원본을 찾을 수 없습니다" }
		return "원본: \(group.name) · \(group.prefix + icon.name)"
	}

	private func click(_ glyph: FontGlyph) {
		focused = true
		// 보이는 순서 (검색 결과, 접힌 그룹은 뺀다)
		let order = font.grouped(font.glyphs.filter(matches)).filter { !collapsed.contains($0.section ?? "") }.flatMap(\.glyphs).map(\.id)
		let flags = NSEvent.modifierFlags
		ClickSelect.click(glyph.id, order: order, selected: &selected, anchor: &anchor,
		                  command: flags.contains(.command), shift: flags.contains(.shift))
	}

	/// 고른 아이콘을 폰트 순서대로, 폰트 선 굵기를 적용해 SVG 로 내려받는다
	private func downloadSVG(_ ids: Set<String>) {
		let items = font.orderedGlyphs.filter { ids.contains($0.id) }.map { g -> SVGExport.Item in
			// 선 그룹 원본이면 선 그대로(폰트 굵기 적용), 아니면 폰트에 복사해 둔 모양
			if let group = store.group(g.groupID), group.style == .stroke, let icon = store.icon(of: g), icon.hasStrokes {
				return SVGExport.Item(name: g.name, svg: SVGExport.svg(icon, weight: font.weight))
			}
			return SVGExport.Item(name: g.name, svg: SVGExport.svg(path: g.path, width: g.width))
		}
		SVGExport.save(items, zipName: "\(font.name) 아이콘 \(items.count)개")
	}

	private func setAnimation(_ a: GlyphAnimation?, _ ids: Set<String>) {
		for i in font.glyphs.indices where ids.contains(font.glyphs[i].id) { font.glyphs[i].animation = a }
	}

	private func remove(_ ids: Set<String>) {
		font.glyphs.removeAll { ids.contains($0.id) }
		selected.subtract(ids)
	}

	private func copy(_ s: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(s, forType: .string)
	}
}

/// 폰트 아이콘 칸: 위 유니코드 입력, 가운데 아이콘(클릭으로 고르고 끌어서 옮김), 아래 접두어 + 이름 입력
struct FontGlyphCell: View {
	/// 아이콘그룹 칸과 같은 정사각형
	static let width: CGFloat = IconCell.size

	@Binding var glyph: FontGlyph
	/// 보여 줄 모양 (폰트 선 굵기를 적용한 것)
	var shape: CGPath
	var prefix: String
	var em: Double
	var selected: Bool
	var codeDup: Bool
	var nameDup: Bool
	/// 이 칸 앞에 놓일 자리면 왼쪽에 표시
	var dropBefore: Bool
	var dragValue: String
	var tooltip: String
	var onTap: () -> Void

	var body: some View {
		VStack(spacing: 6) {
			// \e100 그대로 CSS 에 붙일 수 있는 모양으로 가운데에
			CodeField(code: $glyph.code)
				.foregroundStyle(codeDup ? .red : (selected ? .white : .primary))
				.font(.system(size: 12, design: .monospaced))
				.padding(.horizontal, 10)

			AnimatedGlyph(animation: glyph.animation) { angle in
				GlyphView(shape: shape, width: glyph.width, em: em, rotation: angle)
			}
				.frame(width: IconCell.glyph, height: IconCell.glyph)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.contentShape(.rect)
				.foregroundStyle(selected ? Color.white : Color.primary)
				.onTapGesture(perform: onTap)
				.draggable(dragValue) {
					GlyphView(shape: shape, width: glyph.width, em: em)
						.frame(width: 36, height: 36).padding(8)
						.background(.regularMaterial, in: .rect(cornerRadius: 8))
				}
				.help(tooltip)

			// 접두어 + 이름을 한 덩어리로 가운데에. 입력칸 폭은 글자 길이에 맞추고,
			// 칸보다 길면 글자를 조금 줄여서 양쪽이 잘리지 않게 한다
			ViewThatFits(in: .horizontal) {
				nameLine(size: 12)
				nameLine(size: 11)
				nameLine(size: 10)
				nameLine(size: 9)
			}
			.frame(maxWidth: Self.width - 12)
			.clipped()
		}
		.padding(.vertical, 10)
		.frame(width: Self.width, height: Self.width)
		.background(selected ? Color.accentColor : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 10))
		.overlay(alignment: .leading) {
			if dropBefore {
				Capsule().fill(Color.accentColor).frame(width: 4).padding(.vertical, 6).offset(x: -6)
			}
		}
	}

	private func nameLine(size: CGFloat) -> some View {
		HStack(spacing: 0) {
			Text(prefix).foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
			ZStack(alignment: .leading) {
				Text(glyph.name.isEmpty ? "이름" : glyph.name).hidden()
				TextField("이름", text: $glyph.name)
					.textFieldStyle(.plain)
					.foregroundStyle(nameDup ? .red : (selected ? .white : .primary))
			}
			.padding(.trailing, 2)
		}
		.font(.system(size: size))
		.fixedSize()
	}
}

/// 유니코드 입력칸 (e600 처럼 소문자 16진수). 올바른 값일 때만 반영한다
struct CodeField: View {
	@Binding var code: UInt32
	@State private var text = ""
	@FocusState private var focused: Bool

	var body: some View {
		TextField("코드", text: $text)
			.textFieldStyle(.plain)
			.multilineTextAlignment(.center)
			.focused($focused)
			.onAppear { text = code.cssEscape }
			.onChange(of: code) { if !focused { text = code.cssEscape } }
			.onSubmit(commit)
			.onChange(of: focused) { if !focused { commit() } }
	}

	private func commit() {
		let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "")
		if let v = UInt32(t, radix: 16), v <= 0x10FFFF { code = v }
		text = code.cssEscape
	}
}

/// 폰트 화면 안에서 끌어다 놓는 값: 아이콘 "ifont-glyphs:id,…", 그룹 "ifont-section:이름"
enum FontDrag {
	static func glyphs(_ ids: [String]) -> String { "ifont-glyphs:" + ids.joined(separator: ",") }
	static func section(_ name: String) -> String { "ifont-section:" + name }

	static func decodeGlyphs(_ s: String) -> [String]? {
		guard s.hasPrefix("ifont-glyphs:") else { return nil }
		return s.dropFirst("ifont-glyphs:".count).split(separator: ",").map(String.init)
	}

	static func decodeSection(_ s: String) -> String? {
		guard s.hasPrefix("ifont-section:") else { return nil }
		return String(s.dropFirst("ifont-section:".count))
	}
}

/// 그룹 머리를 끌 수 있게 한다 (그룹 없음은 끌지 않는다)
private struct SectionDragModifier: ViewModifier {
	var section: String?

	func body(content: Content) -> some View {
		if let section {
			content.draggable(FontDrag.section(section)) {
				Text(section).font(.headline).padding(.horizontal, 10).padding(.vertical, 6)
					.background(.regularMaterial, in: .capsule)
			}
		} else {
			content
		}
	}
}

/// 애니메이션이 있으면 CSS 와 같은 방식으로 계속 돌린다 (회전: 2초 한 바퀴, 8단계 회전: 1초 한 바퀴 45도씩)
/// 각도만 넘겨주므로 칸·여백 표시는 가만히 있고 아이콘만 돈다
struct AnimatedGlyph<Content: View>: View {
	var animation: GlyphAnimation?
	@ViewBuilder var content: (Angle) -> Content

	var body: some View {
		if let animation {
			TimelineView(.animation) { context in
				content(.degrees(animation.angle(at: context.date.timeIntervalSinceReferenceDate)))
			}
			.help("애니메이션: \(animation.title)")
		} else {
			content(.zero)
		}
	}
}
