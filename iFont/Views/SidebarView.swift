import SwiftUI

struct SidebarView: View {
	@Environment(Store.self) private var store
	@Binding var selection: SidebarItem?
	@State private var pendingDelete: SidebarItem?
	/// 이름을 고치는 중인 항목 (Finder 처럼 그 자리에서 고친다)
	@State private var renaming: SidebarItem?
	@State private var newName = ""
	@FocusState private var nameFocused: Bool
	@State private var dropTarget: UUID?
	@State private var dropNote: String?

	var body: some View {
		List(selection: $selection) {
			Label("전체 검색", systemImage: "magnifyingglass")
				.tag(SidebarItem.search)
			Section("폰트") {
				ForEach(store.fonts) { font in
					let item = SidebarItem.font(font.id)
					row(item, name: font.name, count: font.glyphs.count, icon: "textformat")
						.tag(item)
						.contextMenu { menu(item, name: font.name) }
						// 아이콘그룹에서 끌어온 아이콘을 이 폰트에 넣는다
						.dropDestination(for: String.self) { items, _ in
							var added = 0
							for s in items {
								if let d = IconDrag.decode(s) { added += store.addIcons(d.iconIDs, from: d.groupID, to: font.id).added }
							}
							if added > 0 { dropNote = "\(font.name) 폰트에 \(added)개를 추가했습니다." }
							return added > 0
						} isTargeted: { on in dropTarget = on ? font.id : (dropTarget == font.id ? nil : dropTarget) }
						.listRowBackground(dropTarget == font.id ? Color.accentColor.opacity(0.25) : nil)
				}
			}
			Section("아이콘그룹") {
				ForEach(store.groups) { group in
					let item = SidebarItem.group(group.id)
					row(item, name: group.name, count: group.icons.count, icon: "square.grid.3x3")
						.tag(item)
						.contextMenu { menu(item, name: group.name) }
						// 다른 아이콘그룹에서 끌어온 아이콘을 이 그룹으로 옮긴다
						.dropDestination(for: String.self) { items, _ in
							var moved = 0, rejected = 0, converted = 0
							for s in items {
								guard let d = IconDrag.decode(s), d.groupID != group.id else { continue }
								let r = store.moveIcons(d.iconIDs, from: d.groupID, to: group.id)
								moved += r.moved; rejected += r.rejected; converted += r.converted
							}
							var note = moved > 0 ? "\(group.name) 그룹으로 \(moved)개를 옮겼습니다." : ""
							if converted > 0 { note += " 선 아이콘 \(converted)개는 채우기로 바꿨습니다." }
							if rejected > 0 { note += " 채우기 아이콘 \(rejected)개는 선 그룹이라 옮기지 않았습니다." }
							if !note.isEmpty { dropNote = note.trimmingCharacters(in: .whitespaces) }
							return moved > 0
						} isTargeted: { on in dropTarget = on ? group.id : (dropTarget == group.id ? nil : dropTarget) }
						.listRowBackground(dropTarget == group.id ? Color.accentColor.opacity(0.25) : nil)
				}
			}
		}
		.onKeyPress(.return) {
			guard renaming == nil, let selection else { return .ignored }
			startRename(selection)
			return .handled
		}
		.onDeleteCommand { if renaming == nil, selection != .search { pendingDelete = selection } }
		.safeAreaInset(edge: .bottom) {
			if dropNote == nil {
				Label(StorageLocation.shared.isCloud ? "iCloud 동기화" : "이 맥에만 저장", systemImage: StorageLocation.shared.isCloud ? "icloud" : "internaldrive")
					.font(.caption).foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 12).padding(.vertical, 8)
					.help(StorageLocation.shared.isCloud ? "폰트·아이콘그룹을 iCloud Drive 의 iFont 전용 폴더에 두고 다른 맥과 맞춥니다" : "iCloud 에 로그인돼 있지 않거나 앱 서명에 iCloud 가 없어 이 맥 Application Support/iFont 에 저장합니다")
			}
			if let dropNote {
				Text(dropNote)
					.font(.caption)
					.padding(.horizontal, 10).padding(.vertical, 6)
					.background(.regularMaterial, in: .capsule)
					.padding(8)
					.transition(.opacity)
					.task(id: dropNote) {
						try? await Task.sleep(for: .seconds(2))
						self.dropNote = nil
					}
			}
		}
		.confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
			Button("삭제", role: .destructive) {
				switch pendingDelete {
				case .font(let id): store.deleteFont(id)
				case .group(let id): store.deleteGroup(id)
				case .search, nil: break
				}
				if selection == pendingDelete { selection = nil }
				pendingDelete = nil
			}
		} message: {
			if case .group(let id) = pendingDelete {
				let using = store.fontsUsing(id)
				if using.isEmpty {
					Text("이 그룹의 아이콘을 쓰는 폰트는 없습니다.")
				} else {
					Text("이 그룹의 아이콘을 쓰는 폰트에서도 그 아이콘이 함께 빠집니다: " + using.map { "\($0.name) \($0.count)개" }.joined(separator: ", "))
				}
			}
		}
	}

	@ViewBuilder
	private func menu(_ item: SidebarItem, name: String) -> some View {
		Button("이름 바꾸기") { startRename(item) }
		if case .group(let id) = item {
			Button("다시 읽기") { store.reloadGroup(id) }
		}
		Button("삭제…", role: .destructive) { pendingDelete = item }
	}

	private func row(_ item: SidebarItem, name: String, count: Int, icon: String) -> some View {
		Label {
			HStack {
				if renaming == item {
					TextField("이름", text: $newName)
						.textFieldStyle(.plain)
						.focused($nameFocused)
						.onSubmit(commitRename)
						.onExitCommand { renaming = nil }
						.onChange(of: nameFocused) { if !nameFocused { commitRename() } }
				} else {
					Text(name)
				}
				Spacer()
				Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
			}
		} icon: {
			Image(systemName: icon)
		}
	}

	private func startRename(_ item: SidebarItem) {
		switch item {
		case .font(let id): newName = store.fonts.first { $0.id == id }?.name ?? ""
		case .group(let id): newName = store.group(id)?.name ?? ""
		case .search: return
		}
		selection = item
		renaming = item
		DispatchQueue.main.async { nameFocused = true }
	}

	private func commitRename() {
		guard let item = renaming else { return }
		renaming = nil
		let name = newName.trimmingCharacters(in: .whitespaces)
		guard !name.isEmpty else { return }
		switch item {
		case .font(let id): if let i = store.fonts.firstIndex(where: { $0.id == id }) { store.fonts[i].name = name }
		case .group(let id): if let i = store.groups.firstIndex(where: { $0.id == id }) { store.groups[i].name = name }
		case .search: break
		}
	}

	private var deleteTitle: String {
		switch pendingDelete {
		case .font(let id): "\"\(store.fonts.first { $0.id == id }?.name ?? "")\" 폰트를 삭제할까요?"
		case .group(let id): "\"\(store.group(id)?.name ?? "")\" 아이콘그룹을 삭제할까요?"
		case .search, nil: ""
		}
	}
}
