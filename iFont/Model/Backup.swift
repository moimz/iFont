import AppKit
import UniformTypeIdentifiers

/// 모든 폰트·아이콘그룹을 JSON 하나로 내보내고, 불러올 때는 항상 병합한다
struct Backup: Codable {
	var app = "iFont"
	var format = 1
	var exported = Date()
	var groups: [IconGroup]
	var fonts: [FontDoc]

	/// 불러오기 결과
	struct Report {
		var groupsAdded = 0, groupsUpdated = 0
		var iconsAdded = 0, iconsUpdated = 0
		var fontsAdded = 0, fontsUpdated = 0
		var glyphsAdded = 0, glyphsUpdated = 0
		/// 병합 뒤 한 폰트 안에서 코드가 겹친 아이콘 수
		var codeConflicts = 0

		var text: String {
			var lines = [
				"아이콘그룹: 새로 \(groupsAdded)개, 바뀜 \(groupsUpdated)개 (아이콘 새로 \(iconsAdded)개, 바뀜 \(iconsUpdated)개)",
				"폰트: 새로 \(fontsAdded)개, 바뀜 \(fontsUpdated)개 (아이콘 새로 \(glyphsAdded)개, 바뀜 \(glyphsUpdated)개)",
				"같은 것은 불러온 내용으로 덮어쓰고, 불러온 파일에 없는 기존 폰트·그룹·아이콘은 그대로 두었습니다.",
			]
			if codeConflicts > 0 { lines.append("코드가 겹친 폰트 아이콘이 \(codeConflicts)개 있습니다. 폰트 화면에서 빨간 코드를 확인하세요.") }
			return lines.joined(separator: "\n")
		}
	}

	static func encode(_ store: Store) throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		encoder.dateEncodingStrategy = .iso8601
		return try encoder.encode(Backup(groups: store.groups, fonts: store.fonts))
	}

	static func decode(_ data: Data) throws -> Backup {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try decoder.decode(Backup.self, from: data)
	}
}

extension Store {
	/// 병합해서 불러온다.
	/// - 그룹·폰트는 id 로, 없으면 이름으로 같은 것을 찾는다. 없으면 추가, 있으면 설정을 덮어쓰고 안의 아이콘을 병합한다
	/// - 아이콘은 id 로(이름으로 찾은 그룹이면 이름으로도) 찾아 덮어쓰고, 없으면 추가한다
	/// - 불러온 파일에 없는 기존 것은 지우지 않는다
	func merge(_ backup: Backup) -> Backup.Report {
		var report = Backup.Report()
		// 불러온 그룹 id → 이 앱 그룹 id, (그룹 id, 불러온 아이콘 id) → 이 앱 아이콘 id
		var groupMap: [UUID: UUID] = [:]
		var iconMap: [UUID: [String: String]] = [:]

		for var incoming in backup.groups {
			guard let gi = groups.firstIndex(where: { $0.id == incoming.id }) ?? groups.firstIndex(where: { $0.name == incoming.name }) else {
				groupMap[incoming.id] = incoming.id
				groups.append(incoming)
				report.groupsAdded += 1
				report.iconsAdded += incoming.icons.count
				continue
			}
			let byName = groups[gi].id != incoming.id
			groupMap[incoming.id] = groups[gi].id
			var map: [String: String] = [:]
			var icons = groups[gi].icons
			for icon in incoming.icons {
				var icon = icon
				let idx = icons.firstIndex(where: { $0.id == icon.id })
					?? (byName ? icons.firstIndex(where: { $0.name == icon.name }) : nil)
				if let idx {
					map[icon.id] = icons[idx].id
					icon.id = icons[idx].id
					if icons[idx] != icon { icons[idx] = icon; report.iconsUpdated += 1 }
				} else {
					map[icon.id] = icon.id
					icons.append(icon)
					report.iconsAdded += 1
				}
			}
			iconMap[groups[gi].id] = map
			incoming.id = groups[gi].id
			incoming.categories = union(groups[gi].categories, incoming.categories)
			incoming.icons = icons
			if groups[gi] != incoming { groups[gi] = incoming; report.groupsUpdated += 1 }
		}

		for var incoming in backup.fonts {
			// 그룹·아이콘 id 를 이 앱 것으로 바꾼다
			incoming.glyphs = incoming.glyphs.map { g in
				var g = g
				g.groupID = groupMap[g.groupID] ?? g.groupID
				g.iconID = iconMap[g.groupID]?[g.iconID] ?? g.iconID
				return g
			}
			guard let fi = fonts.firstIndex(where: { $0.id == incoming.id }) ?? fonts.firstIndex(where: { $0.name == incoming.name }) else {
				fonts.append(incoming)
				report.fontsAdded += 1
				report.glyphsAdded += incoming.glyphs.count
				report.codeConflicts += conflicts(incoming)
				continue
			}
			let old = fonts[fi]
			var glyphs = old.glyphs
			for g in incoming.glyphs {
				var g = g
				if let idx = glyphs.firstIndex(where: { $0.id == g.id })
					?? glyphs.firstIndex(where: { $0.groupID == g.groupID && $0.iconID == g.iconID }) {
					g.id = glyphs[idx].id
					if glyphs[idx] != g { glyphs[idx] = g; report.glyphsUpdated += 1 }
				} else {
					glyphs.append(g)
					report.glyphsAdded += 1
				}
			}
			incoming.id = old.id
			incoming.sections = union(old.sections, incoming.sections)
			incoming.glyphs = glyphs
			// 내려받은 횟수는 줄어들지 않게 큰 쪽을 쓴다
			incoming.downloads = max(old.downloads, incoming.downloads)
			if old != incoming { fonts[fi] = incoming; report.fontsUpdated += 1 }
			report.codeConflicts += conflicts(incoming)
		}
		return report
	}

	/// 기존 순서를 지키고 새 이름을 뒤에 붙인다
	private func union(_ a: [String], _ b: [String]) -> [String] {
		a + b.filter { !a.contains($0) }
	}

	private func conflicts(_ font: FontDoc) -> Int {
		Dictionary(grouping: font.glyphs, by: \.code).values.filter { $0.count > 1 }.reduce(0) { $0 + $1.count }
	}
}

/// 파일 메뉴의 내보내기·불러오기
@MainActor
enum BackupMenu {
	static func exportAll(_ store: Store) {
		let panel = NSSavePanel()
		panel.allowedContentTypes = [.json]
		let day = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
		panel.nameFieldStringValue = "iFont-\(day).json"
		panel.message = "모든 폰트(\(store.fonts.count)개)와 아이콘그룹(\(store.groups.count)개)을 JSON 파일 하나로 내보냅니다."
		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			try Backup.encode(store).write(to: url, options: .atomic)
			alert("내보냈습니다", "폰트 \(store.fonts.count)개, 아이콘그룹 \(store.groups.count)개\n\(url.path)", reveal: url)
		} catch {
			alert("내보내지 못했습니다", error.localizedDescription)
		}
	}

	static func importAll(_ store: Store) {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.json]
		panel.message = "iFont 에서 내보낸 JSON 을 고르세요. 기존 것과 병합합니다 (같은 것은 덮어쓰고, 파일에 없는 기존 것은 지우지 않습니다)."
		panel.prompt = "불러오기"
		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			let backup = try Backup.decode(Data(contentsOf: url))
			let report = store.merge(backup)
			alert("불러왔습니다", report.text)
		} catch {
			alert("불러오지 못했습니다", "iFont 에서 내보낸 파일이 아니거나 읽을 수 없습니다.\n\(error.localizedDescription)")
		}
	}

	private static func alert(_ title: String, _ text: String, reveal: URL? = nil) {
		let a = NSAlert()
		a.messageText = title
		a.informativeText = text
		a.addButton(withTitle: "확인")
		if reveal != nil { a.addButton(withTitle: "Finder 에서 보기") }
		if a.runModal() == .alertSecondButtonReturn, let reveal {
			NSWorkspace.shared.activateFileViewerSelecting([reveal])
		}
	}
}
