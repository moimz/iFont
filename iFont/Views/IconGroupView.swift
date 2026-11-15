import SwiftUI
import UniformTypeIdentifiers

/// 아이콘그룹 상세: 아이콘 추가·삭제·이름 바꾸기, CSS 이름 붙이기
struct IconGroupView: View {
	@Environment(Store.self) private var store
	@Binding var group: IconGroup
	@Binding var selection: SidebarItem?
	@State private var showSettings = true
	@AppStorage("labelMode") private var mode: LabelMode = .name
	@State private var search = ""
	@State private var importing = false
	@State private var selected: Set<String> = []
	@State private var renaming: Icon?
	@FocusState private var gridFocused: Bool
	@State private var newName = ""
	@State private var message: String?
	@State private var collapsed: Set<String> = []
	/// 새 분류 이름을 받을 아이콘들
	@State private var newCategoryFor: Set<String>?
	@State private var renamingCategory: String?
	@State private var categoryName = ""
	/// 폰트에서 쓰고 있어 지우기 전에 물어보는 아이콘들
	@State private var pendingDelete: Set<String>?
	/// ⇧ 클릭 범위의 시작 칸
	@State private var anchor: String?
	/// 여백 맞추기 비교 창에 띄울 아이콘들
	@State private var fitting: FitTarget?

	struct FitTarget: Identifiable { let id = UUID(); var ids: Set<String> }

	private let columns = [GridItem(.adaptive(minimum: IconCell.size, maximum: IconCell.size), spacing: 8)]

	static let importTypes: [UTType] = [.svg, .font, .folder] + ["woff", "woff2", "css"].compactMap { UTType(filenameExtension: $0) }

	var body: some View {
		let icons = search.isEmpty ? group.icons : group.icons.filter { $0.matches(search, prefix: group.prefix) }
		Group {
			if group.icons.isEmpty {
				ContentUnavailableView {
					Label("아이콘이 없습니다", systemImage: "square.grid.3x3")
				} description: {
					Text("SVG 파일, 폰트 파일(ttf·otf·woff·woff2·SVG 폰트), SVG 가 든 폴더를 추가하세요.\n폰트와 함께 CSS 파일을 고르면 CSS 의 클래스 이름이 아이콘 이름이 됩니다.")
				} actions: {
					Button("아이콘 추가…") { importing = true }.buttonStyle(.borderedProminent)
				}
			} else {
				ScrollViewReader { proxy in
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
						// 검색 중에는 결과가 없는 분류를 숨긴다
						ForEach(group.sections(icons).filter { search.isEmpty || !$0.icons.isEmpty }, id: \.category) { section in
							let key = section.category ?? ""
							Section {
								if !collapsed.contains(key) {
									grid(section.icons)
										.id("section:" + key)
								}
							} header: {
								if !group.categories.isEmpty {
									categoryHeader(section.category, count: section.icons.count)
								}
							}
						}
					}
					.padding(.bottom, 16)
				}
				// 폰트에서 "원본 보기"로 왔으면 그 아이콘을 골라 보여 준다
				.onAppear { reveal(proxy) }
				.onChange(of: store.revealIcon) { reveal(proxy) }
				}
				.focusable()
				.focusEffectDisabled()
				.focused($gridFocused)
				.onDeleteCommand { delete(selected) }
				.onCopyCommand {
					// 고른 아이콘들을 그룹 선 굵기를 적용한 SVG 로 복사 (여러 개면 빈 줄로 이어서)
					return SVGExport.providers(group.icons.filter { selected.contains($0.id) }.map(svg))
				}
			}
		}
		.navigationTitle(group.name)
		.navigationSubtitle("아이콘 \(group.icons.count)개")
		.confirmationDialog(pendingDelete.map { "아이콘 \($0.count)개를 삭제할까요?" } ?? "",
		                    isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
			Button("삭제", role: .destructive) {
				if let ids = pendingDelete { confirmDelete(ids) }
				pendingDelete = nil
			}
		} message: {
			let using = pendingDelete.map { store.fontsUsing(group.id, icons: $0) } ?? []
			Text("폰트에서 쓰고 있는 원본입니다. 지우면 폰트에서도 함께 빠집니다: " + using.map { "\($0.name) \($0.count)개" }.joined(separator: ", "))
		}
		.searchable(text: $search, placement: .toolbar, prompt: "이름, 키워드, \\e600 검색")
		.toolbar {
			ToolbarItem {
				Button { importing = true } label: { Label("아이콘 추가", systemImage: "plus") }
					.help("아이콘 추가 (SVG, 폰트 파일, CSS, 폴더)")
			}
			ToolbarSpacer(.fixed)
			ToolbarItemGroup {
				LabelModePicker()
				EmBoxToggle()
				Button { showSettings.toggle() } label: { Label("그룹 설정", systemImage: "sidebar.right") }
					.help("그룹 설정")
			}
		}
		.inspector(isPresented: $showSettings) {
			IconGroupSettingsPanel(group: $group, selection: $selection)
				.inspectorColumnWidth(min: 280, ideal: 320, max: 400)
		}
		.fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
			guard case .success(let urls) = result else { return }
			var r = IconImport.load(urls)
			group.add(&r)
			if group.prefix.isEmpty, let p = r.cssPrefix { group.prefix = p }
			message = r.summary
		}
		.sheet(item: $fitting) { t in FitIconsSheet(group: $group, ids: t.ids) }
		.alert("아이콘 추가", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
			Button("확인") {}
		} message: {
			Text(message ?? "")
		}
		.alert("새 분류", isPresented: Binding(get: { newCategoryFor != nil }, set: { if !$0 { newCategoryFor = nil } })) {
			TextField("분류 이름", text: $categoryName)
			Button("취소", role: .cancel) {}
			Button("만들기") {
				let name = categoryName.trimmingCharacters(in: .whitespaces)
				if !name.isEmpty, let ids = newCategoryFor { group.setCategory(name, for: ids) }
			}
		}
		.alert("분류 이름 바꾸기", isPresented: Binding(get: { renamingCategory != nil }, set: { if !$0 { renamingCategory = nil } })) {
			TextField("분류 이름", text: $categoryName)
			Button("취소", role: .cancel) {}
			Button("바꾸기") { if let old = renamingCategory { group.renameCategory(old, to: categoryName) } }
		}
		.alert("아이콘 이름 바꾸기", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
			TextField("이름", text: $newName)
			Button("취소", role: .cancel) {}
			Button("바꾸기") {
				if let id = renaming?.id, let i = group.icons.firstIndex(where: { $0.id == id }) { group.icons[i].name = newName }
			}
		}
	}

	private func grid(_ icons: [Icon]) -> some View {
		LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
			ForEach(icons) { icon in
				IconCell(shape: IconShape.path(icon, in: group), width: icon.width, label: label(icon), copyValue: nil,
				         selected: selected.contains(icon.id), monospaced: mode == .code, tooltip: tooltip(icon),
				         copyAction: { SVGExport.copy([svg(icon)]) }, copyHelp: "SVG 복사 (선 굵기 적용)")
					.id(icon.id)
					.onTapGesture { click(icon) }
					.contextMenu { iconMenu(icon) }
					// 끌어서 왼쪽 폰트 이름에 놓으면 폰트에 들어간다. 고른 아이콘 위에서 끌면 고른 것 전체
					.draggable(IconDrag.encode(groupID: group.id, iconIDs: dragTargets(icon))) {
						dragPreview(icon)
					}
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
	}

	@ViewBuilder
	private func iconMenu(_ icon: Icon) -> some View {
		// 고른 아이콘 위에서 열면 고른 것 전체에, 아니면 그 아이콘에만
		let targets = selected.contains(icon.id) ? selected : [icon.id]
		Button("이름 바꾸기…") { newName = icon.name; renaming = icon }
		if let code = icon.code { Button("\(code.cssEscape) 복사") { copy(code.cssEscape) } }
		Button("\(group.prefix + icon.name) 복사") { copy(group.prefix + icon.name) }
		Button(selected.contains(icon.id) && selected.count > 1 ? "SVG 복사 (\(selected.count)개)" : "SVG 복사") {
			let targets = selected.contains(icon.id) ? group.icons.filter { selected.contains($0.id) } : [icon]
			SVGExport.copy(targets.map(svg))
		}
		Divider()
		Menu(targets.count > 1 ? "폰트에 추가 (\(targets.count)개)" : "폰트에 추가") {
			ForEach(store.fonts) { f in
				Button(f.name) { addToFont(targets, f) }
			}
			if !store.fonts.isEmpty { Divider() }
			Button("새 폰트에 추가") {
				let f = store.addFont()
				addToFont(targets, f)
			}
		}
		Menu(targets.count > 1 ? "분류 (\(targets.count)개)" : "분류") {
			ForEach(group.categories, id: \.self) { c in
				Button { group.setCategory(c, for: targets) } label: {
					if icon.category == c { Label(c, systemImage: "checkmark") } else { Text(c) }
				}
			}
			if !group.categories.isEmpty { Divider() }
			Button("분류 없음") { group.setCategory(nil, for: targets) }
			Button("새 분류…") { categoryName = ""; newCategoryFor = targets }
		}
		Button(targets.count > 1 ? "SVG 다운로드… (\(targets.count)개, zip)" : "SVG 다운로드…") { downloadSVG(targets) }
		Button(targets.count > 1 ? "여백 맞추기… (\(targets.count)개)" : "여백 맞추기…") { fitting = FitTarget(ids: targets) }
		Divider()
		Button("삭제", role: .destructive) { delete(targets) }
	}

	/// 그룹 순서대로 정렬한 대상 아이콘 id
	private func dragTargets(_ icon: Icon) -> [String] {
		guard selected.contains(icon.id), selected.count > 1 else { return [icon.id] }
		return group.icons.map(\.id).filter(selected.contains)
	}

	private func dragPreview(_ icon: Icon) -> some View {
		let count = dragTargets(icon).count
		return GlyphView(shape: IconShape.path(icon, in: group), width: icon.width)
			.frame(width: 36, height: 36)
			.padding(8)
			.background(.regularMaterial, in: .rect(cornerRadius: 8))
			.overlay(alignment: .topTrailing) {
				if count > 1 {
					Text("\(count)").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
						.background(Color.accentColor, in: .capsule).foregroundStyle(.white)
				}
			}
	}

	private func addToFont(_ ids: Set<String>, _ font: FontDoc) {
		let ordered = group.icons.map(\.id).filter(ids.contains)
		let r = store.addIcons(ordered, from: group.id, to: font.id)
		message = "\(font.name) 폰트에 \(r.added)개를 추가했습니다." + (r.skipped > 0 ? "\n이미 들어 있는 \(r.skipped)개는 건너뛰었습니다." : "")
	}

	private func categoryHeader(_ category: String?, count: Int) -> some View {
		let key = category ?? ""
		return HStack(spacing: 8) {
			Button {
				if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
			} label: {
				Image(systemName: "chevron.right")
					.rotationEffect(.degrees(collapsed.contains(key) ? 0 : 90))
					.frame(width: 14)
			}
			.buttonStyle(.plain)
			Text(category ?? "분류 없음").font(.headline)
				.foregroundStyle(category == nil ? .secondary : .primary)
			Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
			Spacer()
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
		.background(.bar)
		.contentShape(.rect)
		.contextMenu {
			if let category {
				Button("분류 이름 바꾸기…") { categoryName = category; renamingCategory = category }
				Button("위로 옮기기") { group.moveCategory(category, by: -1) }
				Button("아래로 옮기기") { group.moveCategory(category, by: 1) }
				Divider()
				Button("분류 지우기 (아이콘은 남김)", role: .destructive) { group.deleteCategory(category) }
			}
			Button("모두 펼치기") { collapsed = [] }
			Button("모두 접기") { collapsed = Set(group.categories + [""]) }
		}
	}

	private func tooltip(_ icon: Icon) -> String {
		var s = group.prefix + icon.name
		if let code = icon.code { s += "  " + code.cssEscape }
		if let tags = icon.tags, !tags.isEmpty { s += "\n키워드: " + tags.joined(separator: ", ") }
		return s
	}

	private func label(_ icon: Icon) -> String {
		mode == .name ? group.prefix + icon.name : (icon.code?.cssEscape ?? "—")
	}

	/// 그룹 선 굵기를 적용한 SVG (채우기 그룹은 원본 그대로)
	private func svg(_ icon: Icon) -> String {
		SVGExport.svg(icon, weight: group.style == .stroke ? group.weight : nil)
	}

	private func copy(_ s: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(s, forType: .string)
	}

	private func reveal(_ proxy: ScrollViewProxy) {
		guard let id = store.revealIcon, let icon = group.icons.first(where: { $0.id == id }) else { return }
		store.revealIcon = nil
		search = ""
		collapsed.remove(icon.category.flatMap { group.categories.contains($0) ? $0 : nil } ?? "")
		selected = [id]
		gridFocused = true
		// 아래쪽 분류는 아직 그려지지 않아 아이콘으로 바로 못 간다 → 분류로 먼저 내려가고, 그려진 뒤 아이콘으로
		let key = icon.category.flatMap { group.categories.contains($0) ? $0 : nil } ?? ""
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
			proxy.scrollTo("section:" + key, anchor: .top)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
				withAnimation { proxy.scrollTo(id, anchor: .center) }
			}
		}
	}

	private func click(_ icon: Icon) {
		gridFocused = true
		// 보이는 순서 (검색 결과, 접힌 분류는 뺀다)
		let icons = search.isEmpty ? group.icons : group.icons.filter { $0.matches(search, prefix: group.prefix) }
		let order = group.sections(icons).filter { !collapsed.contains($0.category ?? "") }.flatMap(\.icons).map(\.id)
		let flags = NSEvent.modifierFlags
		ClickSelect.click(icon.id, order: order, selected: &selected, anchor: &anchor,
		                  command: flags.contains(.command), shift: flags.contains(.shift))
	}

	/// 고른 아이콘을 그룹 순서대로, 선 그룹이면 그룹 선 굵기를 적용해 SVG 로 내려받는다
	private func downloadSVG(_ ids: Set<String>) {
		let weight = group.style == .stroke ? group.weight : nil
		let items = group.icons.filter { ids.contains($0.id) }.map { SVGExport.Item(name: $0.name, svg: SVGExport.svg($0, weight: weight)) }
		SVGExport.save(items, zipName: "\(group.name) 아이콘 \(items.count)개")
	}

	/// 원본을 지운다. 폰트에서 쓰고 있으면 먼저 물어보고, 지우면 그 폰트 아이콘도 함께 빠진다
	private func delete(_ ids: Set<String>) {
		guard !ids.isEmpty else { return }
		if store.fontsUsing(group.id, icons: ids).isEmpty { confirmDelete(ids) } else { pendingDelete = ids }
	}

	private func confirmDelete(_ ids: Set<String>) {
		store.deleteIcons(ids, from: group.id)
		selected.subtract(ids)
	}
}

/// 아이콘그룹 오른쪽 패널: 접두어, 형태, 선 굵기(선 그룹만), 요약
struct IconGroupSettingsPanel: View {
	@Environment(Store.self) private var store
	@Binding var group: IconGroup
	@Binding var selection: SidebarItem?
	@State private var confirmToFill = false
	@State private var styleError = false

	var body: some View {
		Form {
			Section("기본") {
				TextField("CSS 접두어", text: $group.prefix, prompt: Text("예: xi-"))
			}
			Section {
				Picker("형태", selection: Binding(get: { group.style }, set: changeStyle)) {
					Text("채우기").tag(IconStyle.fill)
					Text("선").tag(IconStyle.stroke)
				}
				.pickerStyle(.segmented)
				// 채우기 그룹은 굵기를 바꾸지 않는다 (폰트에서도 굵기 설정이 적용되지 않는다)
				if group.style == .stroke {
					WeightPicker(weight: $group.weight)
				}
				Toggle("SVG 넣을 때 여백 맞추기", isOn: $group.autoFit)
					.help(group.style == .stroke ? "선 중심 3–21px, 선 굵기 2px 로 맞춥니다" : "모양을 20px(사방 2px 여백) 가운데에 맞춥니다")
			} header: {
				Text("형태")
			} footer: {
				Text(styleNote).font(.caption).foregroundStyle(.secondary)
			}
			Section("요약") {
				LabeledContent("아이콘", value: "\(group.icons.count)개")
				if !group.categories.isEmpty { LabeledContent("분류", value: "\(group.categories.count)개") }
				let codes = group.icons.compactMap(\.code)
				LabeledContent("코드 있는 아이콘", value: "\(codes.count)개")
				if let lo = codes.min(), let hi = codes.max() {
					LabeledContent("코드 범위", value: "\(lo.hex) – \(hi.hex)")
				}
			}
		}
		.formStyle(.grouped)
		.confirmationDialog("채우기 그룹으로 바꿀까요?", isPresented: $confirmToFill) {
			Button("채우기로 바꾸기", role: .destructive) { group.convertToFill() }
		} message: {
			Text("모든 선이 지금 굵기 그대로 외곽선으로 바뀝니다. 선 정보가 사라지므로 되돌릴 수 없습니다.")
		}
		.alert("선 그룹으로 바꿀 수 없습니다", isPresented: $styleError) {
			Button("확인") {}
		} message: {
			Text("채우기로 된 아이콘이 있습니다. 채우기 모양은 선으로 바꿀 수 없어서, 선 그룹은 비어 있거나 선 아이콘만 있을 때 고를 수 있습니다.")
		}
	}

	private var styleNote: String {
		switch group.style {
		case .stroke:
			return "선 정보를 그대로 보관합니다. 채우기 SVG 와 폰트 파일은 추가할 수 없습니다. 선 굵기는 미리보기용이고, 폰트에는 폰트 설정의 선 굵기가 적용됩니다."
		case .fill:
			let base = group.baseWeight.map { "원래 굵기 약 \($0.formatted(.number.precision(.fractionLength(0...2))))px. " } ?? ""
			return base + "채우기 아이콘은 굵기를 바꾸지 않고 폰트에서도 원본 굵기 그대로 쓰입니다. 선 SVG 를 추가하면 채우기로 바꿔 넣습니다."
		}
	}

	private func changeStyle(_ new: IconStyle) {
		guard new != group.style else { return }
		switch new {
		case .fill:
			if group.icons.isEmpty { group.style = .fill } else { confirmToFill = true }
		case .stroke:
			if group.canBecomeStroke { group.style = .stroke } else { styleError = true }
		}
	}
}

/// 선 굵기 고르기 (24px 기준 px). nil 은 원본 굵기
/// 선 굵기 (24px 기준 px) 직접 입력. 비우면 원본 굵기. 0.25~4px, 0.05 단위로 맞춘다
struct WeightPicker: View {
	@Binding var weight: Double?
	static let range: ClosedRange<Double> = 0.25...4

	var body: some View {
		SuffixField(suffix: weight == nil ? "" : "px") {
			TextField("선 굵기", value: Binding(get: { weight }, set: { weight = $0.map(Self.clean) }),
			          format: .number.precision(.fractionLength(0...2)), prompt: Text("원본"))
		}
	}

	static func clean(_ v: Double) -> Double {
		(min(max(v, range.lowerBound), range.upperBound) * 20).rounded() / 20
	}
}

/// 오른쪽 패널 맨 아래에 가로로 꽉 차게 놓는 버튼
struct PanelButton: View {
	var title: String
	var systemImage: String
	var action: () -> Void

	var body: some View {
		Button(action: action) {
			Label(title, systemImage: systemImage)
				.frame(maxWidth: .infinity)
		}
		.buttonStyle(.borderedProminent)
		.controlSize(.large)
		// 창이 비활성이면 버튼 바탕이 반투명해져 뒤로 지나가는 설정 내용이 비친다 → 불투명한 바탕을 깐다
		.background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
		.padding(.horizontal, 16)
		.padding(.bottom, 16)
	}
}
