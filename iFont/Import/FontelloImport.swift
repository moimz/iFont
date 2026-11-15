import Foundation

/// Fontello config.json 을 폰트 하나로 가져온다.
/// selected 인 아이콘만 원래 이름·코드·순서·모양 그대로 넣고, 등록된 아이콘그룹에서 모양이 같은 원본을 찾아 연결한다.
/// 폰트 아이콘은 반드시 원본이 있어야 하므로, 못 찾은 아이콘은 폰트 이름의 새 채우기 그룹을 만들어 원본으로 넣는다.
enum FontelloImport {
	private struct Config: Decodable {
		var name: String?
		var css_prefix_text: String?
		var hinting: Bool?
		var units_per_em: Int?
		var ascent: Int?
		var glyphs: [Glyph]
	}

	private struct Glyph: Decodable {
		var css: String
		var code: UInt32
		var selected: Bool?
		var svg: SVG?
	}

	private struct SVG: Decodable {
		var path: String
		var width: Double
	}

	struct Report {
		var fontName: String
		var total = 0
		var matched = 0
		/// 원본을 찾았고 크기·위치까지 같은 수
		var samePlacement = 0
		var unmatched: [String] = []
		/// 못 찾은 아이콘을 넣은 새 그룹 이름
		var newGroupName: String?
		/// 모양 정보가 없어(Fontello 기본 세트) 빠진 수
		var noShape = 0
	}

	static func load(_ url: URL, groups: [IconGroup]) throws -> (FontDoc, IconGroup?, Report) {
		let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
		let name = config.name?.isEmpty == false ? config.name! : url.deletingPathExtension().lastPathComponent
		var font = FontDoc(name: name)
		if let v = config.css_prefix_text { font.prefix = v }
		if let v = config.hinting { font.hinting = v }
		if let v = config.units_per_em { font.unitsPerEm = v }
		if let v = config.ascent { font.ascent = v }

		var report = Report(fontName: name)
		let candidates = ShapeMatch.candidates(groups)
		var newGroup = IconGroup(name: name)
		newGroup.prefix = font.prefix
		for g in config.glyphs where g.selected == true {
			report.total += 1
			guard let svg = g.svg else { report.noShape += 1; continue }
			if let found = ShapeMatch.best(path: svg.path, width: svg.width, name: g.css, in: candidates) {
				font.glyphs.append(FontGlyph(id: makeUID(), groupID: found.groupID, iconID: found.icon.id, name: g.css, code: g.code, path: svg.path, width: svg.width))
				report.matched += 1
				if found.samePlacement { report.samePlacement += 1 }
			} else {
				let icon = Icon(id: makeUID(), name: g.css, path: svg.path, width: svg.width, code: g.code)
				newGroup.icons.append(icon)
				font.glyphs.append(FontGlyph(id: makeUID(), groupID: newGroup.id, iconID: icon.id, name: g.css, code: g.code, path: svg.path, width: svg.width))
				report.unmatched.append(g.css)
			}
		}
		if newGroup.icons.isEmpty { return (font, nil, report) }
		report.newGroupName = newGroup.name
		return (font, newGroup, report)
	}
}
