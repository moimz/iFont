import Foundation
import Observation

/// 앱 전체 데이터. 폰트·아이콘그룹을 하나씩 파일로 저장한다.
/// iCloud 를 쓸 수 있으면 iCloud Drive 앱 전용 폴더(StorageLocation)에 두고, 다른 기기에서 바뀐 파일은 CloudWatcher 가 알려 준다.
@Observable
final class Store {
	var groups: [IconGroup] = []
	var fonts: [FontDoc] = []
	/// "원본 보기"로 그룹 화면에서 골라 보여 줄 아이콘 (저장하지 않는 화면 상태)
	var revealIcon: String?

	@ObservationIgnored private var savedGroups: [UUID: IconGroup] = [:]
	@ObservationIgnored private var savedFonts: [UUID: FontDoc] = [:]
	/// 파일별 마지막 수정 시각 (앱 밖에서 바뀐 파일을 알아내려고)
	@ObservationIgnored private var fileDates: [URL: Date] = [:]

	// MARK: - 찾기·추가·삭제

	func group(_ id: UUID?) -> IconGroup? {
		groups.first { $0.id == id }
	}

	@discardableResult
	func addFont() -> FontDoc {
		let font = FontDoc(name: uniqueName("새 폰트", in: fonts.map(\.name)))
		fonts.append(font)
		return font
	}

	@discardableResult
	func addGroup() -> IconGroup {
		let group = IconGroup(name: uniqueName("새 아이콘그룹", in: groups.map(\.name)))
		groups.append(group)
		return group
	}

	/// 아이콘그룹 전체로 새 폰트를 만든다. 원래 코드가 있으면 그대로 쓰고, 없거나 겹치면 빈 코드를 붙인다.
	@discardableResult
	func makeFont(from group: IconGroup) -> FontDoc {
		var font = FontDoc(name: uniqueName(group.name, in: fonts.map(\.name)))
		if !group.prefix.isEmpty { font.prefix = group.prefix }
		var used = Set<UInt32>()
		for icon in group.icons {
			if let code = icon.code, used.insert(code).inserted {
				font.glyphs.append(FontGlyph(id: makeUID(), groupID: group.id, iconID: icon.id, name: icon.name, code: code, path: IconShape.fontPathString(icon), width: icon.width))
			}
		}
		for icon in group.icons where !font.glyphs.contains(where: { $0.iconID == icon.id }) {
			font.glyphs.append(FontGlyph(id: makeUID(), groupID: group.id, iconID: icon.id, name: icon.name, code: font.nextCode(), path: IconShape.fontPathString(icon), width: icon.width))
		}
		// 아이콘그룹 순서대로
		let order = Dictionary(uniqueKeysWithValues: group.icons.enumerated().map { ($1.id, $0) })
		font.glyphs.sort { order[$0.iconID] ?? 0 < order[$1.iconID] ?? 0 }
		fonts.append(font)
		return font
	}

	/// 아이콘그룹의 아이콘들을 폰트에 넣는다. 이미 들어 있는 아이콘은 건너뛰고,
	/// 원래 코드가 폰트에서 비어 있으면 그대로 쓰고 아니면 빈 코드를 붙인다. 그룹 굵기 설정을 적용한 모양을 복사한다.
	@discardableResult
	func addIcons(_ iconIDs: [String], from groupID: UUID, to fontID: UUID) -> (added: Int, skipped: Int) {
		guard let group = group(groupID), let f = fonts.firstIndex(where: { $0.id == fontID }) else { return (0, 0) }
		var added = 0, skipped = 0
		let byID = Dictionary(uniqueKeysWithValues: group.icons.map { ($0.id, $0) })
		for id in iconIDs {
			guard let icon = byID[id] else { continue }
			if fonts[f].glyphs.contains(where: { $0.groupID == groupID && $0.iconID == id }) { skipped += 1; continue }
			let used = Set(fonts[f].glyphs.map(\.code))
			let code = icon.code.flatMap { used.contains($0) ? nil : $0 } ?? fonts[f].nextCode()
			fonts[f].glyphs.append(FontGlyph(id: makeUID(), groupID: groupID, iconID: id, name: icon.name, code: code,
			                                 path: IconShape.fontPathString(icon), width: icon.width))
			added += 1
		}
		return (added, skipped)
	}

	/// 폰트 아이콘의 모양을 아이콘그룹 아이콘으로 바꾼다. 이름·코드·폰트 안 그룹은 그대로 둔다
	func replace(_ glyphID: String, in fontID: UUID, with iconID: String, from groupID: UUID) {
		guard let f = fonts.firstIndex(where: { $0.id == fontID }), let g = fonts[f].glyphs.firstIndex(where: { $0.id == glyphID }),
		      let group = group(groupID), let icon = group.icons.first(where: { $0.id == iconID }) else { return }
		fonts[f].glyphs[g].path = IconShape.fontPathString(icon)
		fonts[f].glyphs[g].width = icon.width
		fonts[f].glyphs[g].groupID = groupID
		fonts[f].glyphs[g].iconID = iconID
	}

	func deleteFont(_ id: UUID) { fonts.removeAll { $0.id == id } }

	/// 원본(그룹 전체 또는 그룹 안 아이콘들)을 쓰는 폰트와 아이콘 수. 지우기 전에 경고로 보여 준다
	func fontsUsing(_ groupID: UUID, icons: Set<String>? = nil) -> [(name: String, count: Int)] {
		fonts.compactMap { f in
			let n = f.glyphs.filter { $0.groupID == groupID && (icons?.contains($0.iconID) ?? true) }.count
			return n > 0 ? (f.name, n) : nil
		}
	}

	/// 원본 아이콘을 지운다. 그 원본을 쓰는 폰트 아이콘도 함께 빠진다
	func deleteIcons(_ ids: Set<String>, from groupID: UUID) {
		if let g = groups.firstIndex(where: { $0.id == groupID }) { groups[g].icons.removeAll { ids.contains($0.id) } }
		for f in fonts.indices { fonts[f].glyphs.removeAll { $0.groupID == groupID && ids.contains($0.iconID) } }
	}

	/// 아이콘을 다른 그룹으로 옮긴다. 폰트 아이콘은 옮긴 그룹을 원본으로 계속 가리킨다.
	/// - 선 그룹으로는 선 아이콘만 (채우기 아이콘은 남긴다), 채우기 그룹으로 가는 선 아이콘은 채우기로 바뀐다
	/// - 옮긴 그룹에서 이미 쓰는 코드면 빈 코드를 새로 붙인다. 분류는 옮긴 그룹에 없으면 만든다
	@discardableResult
	func moveIcons(_ ids: [String], from sourceID: UUID, to targetID: UUID) -> (moved: Int, rejected: Int, converted: Int) {
		guard sourceID != targetID, let s = groups.firstIndex(where: { $0.id == sourceID }),
		      let t = groups.firstIndex(where: { $0.id == targetID }) else { return (0, 0, 0) }
		let wanted = Set(ids)
		let used = Set(groups[t].icons.compactMap(\.code))
		var r = IconImport.Result()
		r.icons = groups[s].icons.filter { wanted.contains($0.id) }.map { icon in
			var icon = icon
			if let c = icon.code, used.contains(c) { icon.code = nil }
			return icon
		}
		groups[t].add(&r)
		let moved = Set(r.icons.map(\.id))
		for c in r.icons.compactMap(\.category) where !groups[t].categories.contains(c) { groups[t].categories.append(c) }
		groups[s].icons.removeAll { moved.contains($0.id) }
		if groups[s].style == .fill { groups[s].baseWeight = IconShape.measureBase(groups[s].icons) }
		for f in fonts.indices {
			for g in fonts[f].glyphs.indices where fonts[f].glyphs[g].groupID == sourceID && moved.contains(fonts[f].glyphs[g].iconID) {
				fonts[f].glyphs[g].groupID = targetID
			}
		}
		return (moved.count, r.rejected.count, r.converted)
	}

	/// 그룹을 지운다. 그 그룹의 원본을 쓰는 폰트 아이콘도 함께 빠진다
	func deleteGroup(_ id: UUID) {
		groups.removeAll { $0.id == id }
		for f in fonts.indices { fonts[f].glyphs.removeAll { $0.groupID == id } }
	}

	/// 폰트 아이콘의 원본 아이콘
	func icon(of glyph: FontGlyph) -> Icon? {
		group(glyph.groupID)?.icons.first { $0.id == glyph.iconID }
	}

	/// Fontello 설정을 가져온다. 원본을 못 찾은 아이콘은 폰트 이름의 새 채우기 그룹에 원본으로 넣는다
	func importFontello(_ url: URL) throws -> (FontDoc, FontelloImport.Report) {
		let (font, newGroup, report) = try FontelloImport.load(url, groups: groups)
		if var newGroup {
			newGroup.name = uniqueName(newGroup.name, in: groups.map(\.name))
			newGroup.baseWeight = IconShape.measureBase(newGroup.icons)
			groups.append(newGroup)
		}
		fonts.append(font)
		return (font, report)
	}

	private func uniqueName(_ base: String, in names: [String]) -> String {
		var name = base, n = 2
		while names.contains(name) { name = "\(base) \(n)"; n += 1 }
		return name
	}

	// MARK: - 저장

	/// 저장 위치. iCloud 를 쓸 수 있으면 iCloud Drive 의 앱 전용 폴더, 아니면 이 맥 Application Support/iFont
	private static var root: URL { StorageLocation.shared.url }

	private static func fileURL(_ kind: String, _ id: UUID) -> URL {
		root.appendingPathComponent(kind).appendingPathComponent(id.uuidString + ".json")
	}

	func load() {
		let decoder = JSONDecoder()
		func read<T: Decodable>(_ kind: String) -> [T] {
			let dir = Self.root.appendingPathComponent(kind)
			let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
			return files.filter { $0.pathExtension == "json" }.compactMap { try? decoder.decode(T.self, from: Data(contentsOf: $0)) }
		}
		groups = (read("IconGroups") as [IconGroup]).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		fonts = (read("Fonts") as [FontDoc]).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		savedGroups = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
		// 예전 버전이 코드 없이 저장한 아이콘은 uE600 같은 이름에서 코드를 채운다
		for g in groups.indices {
			for i in groups[g].icons.indices where groups[g].icons[i].code == nil {
				groups[g].icons[i].code = Icon.codeFromPlaceholder(groups[g].icons[i].name)
			}
			// 원래 굵기를 아직 안 잰 채우기 그룹은 한 번 잰다
			if groups[g].style == .fill, groups[g].baseWeight == nil, !groups[g].icons.isEmpty {
				groups[g].baseWeight = IconShape.measureBase(groups[g].icons)
			}
		}
		savedFonts = Dictionary(uniqueKeysWithValues: fonts.map { ($0.id, $0) })
		save()
		fileDates = Self.currentDates()
		StorageLocation.shared.downloadAll()
	}

	private static func currentDates() -> [URL: Date] {
		var out: [URL: Date] = [:]
		for kind in ["IconGroups", "Fonts"] {
			let dir = root.appendingPathComponent(kind)
			for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where f.pathExtension == "json" {
				out[f] = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
			}
		}
		return out
	}

	/// 앱 밖에서 바뀐(생기거나 지워진) 파일이 있으면 전체를 다시 읽는다. 앱이 앞으로 올 때 부른다
	@discardableResult
	func reloadIfChangedOutside() -> Bool {
		let now = Self.currentDates()
		guard now != fileDates else { return false }
		_ = reloadAll()
		return true
	}

	// MARK: - 다시 읽기 (앱 밖에서 파일을 고쳤을 때)

	private static func readFile<T: Decodable>(_ kind: String, _ id: UUID) -> T? {
		try? JSONDecoder().decode(T.self, from: Data(contentsOf: fileURL(kind, id)))
	}

	/// 그룹 하나를 파일에서 다시 읽는다. 파일이 없으면 false
	@discardableResult
	func reloadGroup(_ id: UUID) -> Bool {
		guard let g: IconGroup = Self.readFile("IconGroups", id) else { return false }
		if let i = groups.firstIndex(where: { $0.id == id }) { groups[i] = g } else { groups.append(g) }
		savedGroups[id] = g
		let url = Self.fileURL("IconGroups", id)
		fileDates[url] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
		return true
	}

	/// 폰트·그룹 전체를 파일에서 다시 읽는다. 새로 생긴 파일은 더하고, 없어진 파일은 뺀다
	func reloadAll() -> (groups: Int, fonts: Int) {
		let decoder = JSONDecoder()
		func read<T: Decodable & Identifiable>(_ kind: String) -> [T] where T.ID == UUID {
			let dir = Self.root.appendingPathComponent(kind)
			let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
			return files.filter { $0.pathExtension == "json" }.compactMap { try? decoder.decode(T.self, from: Data(contentsOf: $0)) }
		}
		// 지금 순서는 지키고 새 것은 뒤에 붙인다. iCloud 에서 아직 안 받은(잠시 내려 둔) 파일은 지금 것을 그대로 둔다
		func merge<T: Identifiable>(_ old: [T], _ new: [T], kind: String) -> [T] where T.ID == UUID {
			let byID = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
			let waiting = StorageLocation.shared.placeholderIDs(kind)
			var out = old.compactMap { byID[$0.id] ?? (waiting.contains($0.id) ? $0 : nil) }
			let known = Set(out.map(\.id))
			out += new.filter { !known.contains($0.id) }
			return out
		}
		let g: [IconGroup] = read("IconGroups"), f: [FontDoc] = read("Fonts")
		groups = merge(groups, g, kind: "IconGroups")
		fonts = merge(fonts, f, kind: "Fonts")
		savedGroups = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
		savedFonts = Dictionary(uniqueKeysWithValues: fonts.map { ($0.id, $0) })
		fileDates = Self.currentDates()
		return (groups.count, fonts.count)
	}

	/// 바뀐 것만 파일로 쓰고, 없어진 것은 파일을 지운다.
	func save() {
		sync(groups, &savedGroups, kind: "IconGroups")
		sync(fonts, &savedFonts, kind: "Fonts")
	}

	private func sync<T: Identifiable & Codable & Hashable>(_ items: [T], _ saved: inout [UUID: T], kind: String) where T.ID == UUID {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		for item in items where saved[item.id] != item {
			if let data = try? encoder.encode(item) {
				let url = Self.fileURL(kind, item.id)
				StorageLocation.write(data, to: url)
				saved[item.id] = item
				fileDates[url] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
			}
		}
		let alive = Set(items.map(\.id))
		for id in saved.keys where !alive.contains(id) {
			StorageLocation.remove(Self.fileURL(kind, id))
			fileDates[Self.fileURL(kind, id)] = nil
			saved[id] = nil
		}
	}
}
