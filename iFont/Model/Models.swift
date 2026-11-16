import Foundation

/// 선(stroke) 하나: 중심선과 굵기. 좌표·굵기는 path 와 같은 높이 1000 기준.
struct StrokePart: Codable, Hashable {
	var d: String
	var width: Double
	/// butt / round / square
	var cap: String = "butt"
	/// miter / round / bevel
	var join: String = "miter"
}

/// 아이콘그룹에 들어 있는 아이콘 원본 하나.
struct Icon: Identifiable, Codable, Hashable {
	/// 아이콘 고유값 (32자리 16진수)
	var id: String
	var name: String
	/// 채우기 모양 SVG path (y 아래 방향, 높이 1000 기준). 선 아이콘이면 비어 있을 수 있다
	var path: String
	var width: Double
	/// 폰트·SVG 폰트에서 가져온 경우 원래 글자 코드 (CSS 이름을 붙일 때 쓴다)
	var code: UInt32? = nil
	/// 선 그룹 아이콘의 선들 (원본 그대로 보관하고 보여 줄 때·폰트 만들 때 외곽선으로 바꾼다)
	var strokes: [StrokePart]? = nil
	/// 채우기 그룹에서 이 아이콘만의 원래 선 굵기 (24px 기준 px). 선 SVG 를 채우기로 바꿔 넣은 경우에 기록한다
	var baseWeight: Double? = nil
	/// 그룹 안 분류 이름. nil 이면 분류 없음
	var category: String? = nil
	/// 검색용 키워드 (예: bell → notification, alarm). 이름과 다른 말로도 찾을 수 있게 한다
	var tags: [String]? = nil

	var hasStrokes: Bool { !(strokes ?? []).isEmpty }
	var hasFill: Bool { !path.isEmpty }

	/// 검색어에 맞는지: 이름(접두어 포함), 키워드, \e600 코드
	func matches(_ query: String, prefix: String = "") -> Bool {
		let q = query.trimmingCharacters(in: .whitespaces).lowercased()
		if q.isEmpty { return true }
		if (prefix + name).lowercased().contains(q) { return true }
		if let code, code.cssEscape.contains(q) || code.hex.lowercased() == q { return true }
		return (tags ?? []).contains { $0.lowercased().contains(q) }
	}

	/// 이름이 없는 글리프에 붙인 임시 이름 (uE600) 에서 코드를 읽는다
	static func codeFromPlaceholder(_ name: String) -> UInt32? {
		guard name.count >= 5, name.count <= 7, name.first == "u" else { return nil }
		return UInt32(name.dropFirst(), radix: 16)
	}
}

/// 아이콘그룹의 형태
enum IconStyle: String, Codable, Hashable {
	/// 채우기: 모든 아이콘을 외곽선으로 보관. 선 SVG 는 들어올 때 채우기로 바뀐다
	case fill
	/// 선: 선 정보를 그대로 보관. 채우기 SVG·폰트 파일은 받지 않는다
	case stroke
}

/// 아이콘 원본 모음. iCloud 에 동기화된다.
struct IconGroup: Identifiable, Codable, Hashable {
	var id: UUID = UUID()
	var name: String
	/// CSS 클래스 접두어 (예: xi-). 이름 보기·복사와 이 그룹으로 만든 폰트에 쓴다
	var prefix: String = ""
	var style: IconStyle = .fill
	/// 선 굵기 설정 (24px 기준 px). nil 이면 원본 굵기 그대로
	var weight: Double? = nil
	/// 채우기 그룹 아이콘의 원래 선 굵기 (24px 기준 px, 아이콘들을 재서 정한다)
	var baseWeight: Double? = nil
	/// 그룹 안 분류 이름들 (보여 주는 순서)
	var categories: [String] = []
	/// SVG 파일을 넣을 때 여백을 24px 칸 규칙에 맞춘다 (IconFit)
	var autoFit: Bool = false
	var icons: [Icon] = []
}

extension IconGroup {
	// 예전 파일에 없는 항목은 기본값으로 읽는다
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decode(UUID.self, forKey: .id)
		name = try c.decode(String.self, forKey: .name)
		prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
		style = try c.decodeIfPresent(IconStyle.self, forKey: .style) ?? .fill
		weight = try c.decodeIfPresent(Double.self, forKey: .weight)
		baseWeight = try c.decodeIfPresent(Double.self, forKey: .baseWeight)
		categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
		autoFit = try c.decodeIfPresent(Bool.self, forKey: .autoFit) ?? false
		icons = try c.decode([Icon].self, forKey: .icons)
	}
}

extension IconGroup {
	/// 분류별로 묶은 아이콘. 분류가 하나도 없으면 이름 없는 한 묶음, 분류 없는 아이콘은 맨 뒤 nil 묶음
	func sections(_ icons: [Icon]) -> [(category: String?, icons: [Icon])] {
		guard !categories.isEmpty else { return [(nil, icons)] }
		var byCategory: [String: [Icon]] = [:]
		var none: [Icon] = []
		let known = Set(categories)
		for icon in icons {
			if let c = icon.category, known.contains(c) { byCategory[c, default: []].append(icon) } else { none.append(icon) }
		}
		var out = categories.map { (category: Optional($0), icons: byCategory[$0] ?? []) }
		if !none.isEmpty { out.append((nil, none)) }
		return out
	}

	mutating func setCategory(_ category: String?, for ids: Set<String>) {
		if let category, !categories.contains(category) { categories.append(category) }
		for i in icons.indices where ids.contains(icons[i].id) { icons[i].category = category }
	}

	mutating func renameCategory(_ old: String, to new: String) {
		let new = new.trimmingCharacters(in: .whitespaces)
		guard !new.isEmpty, old != new, let i = categories.firstIndex(of: old) else { return }
		if categories.contains(new) { categories.remove(at: i) } else { categories[i] = new }
		for j in icons.indices where icons[j].category == old { icons[j].category = new }
	}

	/// 분류를 지우면 그 아이콘들은 분류 없음으로 간다
	mutating func deleteCategory(_ name: String) {
		categories.removeAll { $0 == name }
		for i in icons.indices where icons[i].category == name { icons[i].category = nil }
	}

	mutating func moveCategory(_ name: String, by offset: Int) {
		guard let i = categories.firstIndex(of: name) else { return }
		let j = min(max(i + offset, 0), categories.count - 1)
		categories.swapAt(i, j)
	}
}

/// 24px 기준 1px 를 높이 1000 좌표로 바꾼 값
let unitsPer24px: Double = 1000.0 / 24

/// 폰트에 들어간 아이콘 하나. 폰트 아이콘은 반드시 아이콘그룹의 원본을 가리킨다
/// (SVG 는 아이콘그룹에만 올리고, 원본을 지우면 폰트에서도 빠진다).
/// 모양은 원본에서 복사해 두어 폰트 파일만으로도 그대로 복원된다.
struct FontGlyph: Identifiable, Codable, Hashable {
	var id: String
	/// 원본 아이콘그룹과 그 안의 아이콘
	var groupID: UUID
	var iconID: String
	var name: String
	var code: UInt32
	var path: String
	var width: Double
	/// 폰트 안 그룹 이름. nil 이면 그룹 없음
	var section: String? = nil
	/// 무한 반복 애니메이션 (예: 로딩 아이콘 회전). CSS 에 애니메이션 코드가 함께 들어간다
	var animation: GlyphAnimation? = nil
}

/// 아이콘 애니메이션. CSS 의 animation 값과 같은 뜻
enum GlyphAnimation: String, Codable, Hashable, CaseIterable {
	/// 2초에 한 바퀴 부드럽게 회전 (linear)
	case spin
	/// 1초에 한 바퀴, 8단계로 끊어서 회전 (steps(8))
	case pulse

	var title: String {
		switch self {
		case .spin: "회전"
		case .pulse: "8단계 회전"
		}
	}

	/// 한 바퀴 시간 (초)
	var duration: Double {
		switch self {
		case .spin: 2
		case .pulse: 1
		}
	}

	/// CSS animation-timing-function
	var timing: String {
		switch self {
		case .spin: "linear"
		case .pulse: "steps(8)"
		}
	}

	/// 시각 t(초)에서의 회전 각도 (도)
	func angle(at t: Double) -> Double {
		let phase = t.truncatingRemainder(dividingBy: duration) / duration
		switch self {
		case .spin: return phase * 360
		case .pulse: return (phase * 8).rounded(.down) * 45
		}
	}
}

/// 폰트 하나와 그 설정.
struct FontDoc: Identifiable, Codable, Hashable {
	var id: UUID = UUID()
	var name: String
	var prefix: String = "icon-"
	var unitsPerEm: Int = 1000
	var ascent: Int = 850
	var hinting: Bool = true
	/// 선 굵기 (24px 기준 px). nil 이면 원본 굵기. 선 그룹 원본 아이콘에만 적용하고 채우기 원본은 그대로 둔다
	var weight: Double? = nil
	/// 크기 배율. 내보낼 때 글리프를 em 가운데 기준으로 키운다(선 굵기는 그대로). 원본 아이콘은 바뀌지 않는다
	var scale: Double = 1
	/// 큰 버전. CSS 의 @version 은 "큰 버전.아이콘 수.내려받은 횟수" (예: 5.245.1)
	var version: Int = 1
	/// 폰트를 내려받은 횟수. 내려받을 때마다 1씩 늘어 버전 끝자리가 된다 (폰트 파일에 같이 저장되어 같이 동기화된다)
	var downloads: Int = 0
	/// CSS 파일 맨 위 주석에 넣을 글 (줄마다 " * " 가 붙는다). @version·@modified 는 내보낼 때 붙인다
	var cssHeader: String = ""
	/// CSS 주석의 @file(폴더만, 파일 이름은 내보낼 때 붙인다) · @author · @license (비우면 그 줄을 쓰지 않는다)
	var cssFile: String = ""
	var cssAuthor: String = ""
	var cssLicense: String = ""
	/// 마지막으로 내보낸 폴더
	var exportFolder: String? = nil
	/// 폰트 안 그룹 이름들 (보여 주는 순서)
	var sections: [String] = []
	var glyphs: [FontGlyph] = []

	var descent: Int { unitsPerEm - ascent }

	init(name: String) { self.name = name }

	// 예전 파일에 없는 항목은 기본값으로 읽는다
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decode(UUID.self, forKey: .id)
		name = try c.decode(String.self, forKey: .name)
		prefix = try c.decode(String.self, forKey: .prefix)
		unitsPerEm = try c.decode(Int.self, forKey: .unitsPerEm)
		ascent = try c.decode(Int.self, forKey: .ascent)
		hinting = try c.decode(Bool.self, forKey: .hinting)
		weight = try c.decodeIfPresent(Double.self, forKey: .weight)
		scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1
		version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
		downloads = try c.decodeIfPresent(Int.self, forKey: .downloads) ?? 0
		cssHeader = try c.decodeIfPresent(String.self, forKey: .cssHeader) ?? ""
		if let file = try c.decodeIfPresent(String.self, forKey: .cssFile) {
			cssFile = file
			cssAuthor = try c.decodeIfPresent(String.self, forKey: .cssAuthor) ?? ""
			cssLicense = try c.decodeIfPresent(String.self, forKey: .cssLicense) ?? ""
		} else {
			// 예전에는 주석 전체를 한 글로 받았다 → @file·@author·@license 줄을 칸으로 나눈다
			var rest: [String] = []
			for line in cssHeader.components(separatedBy: "\n") {
				let t = line.trimmingCharacters(in: .whitespaces)
				if t.hasPrefix("@file ") { cssFile = String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
				else if t.hasPrefix("@author ") { cssAuthor = String(t.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
				else if t.hasPrefix("@license ") { cssLicense = String(t.dropFirst(9)).trimmingCharacters(in: .whitespaces) }
				else { rest.append(line) }
			}
			cssHeader = rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
		}
		// @file 은 폴더만 둔다 (예전에 파일 이름까지 적었으면 뗀다)
		if cssFile.lowercased().hasSuffix(".css") { cssFile = (cssFile as NSString).deletingLastPathComponent }
		exportFolder = try c.decodeIfPresent(String.self, forKey: .exportFolder)
		sections = try c.decodeIfPresent([String].self, forKey: .sections) ?? []
		glyphs = try c.decode([FontGlyph].self, forKey: .glyphs)
	}

	/// 그룹별로 묶은 아이콘. 그룹이 하나도 없으면 이름 없는 한 묶음, 그룹 없는 아이콘은 맨 뒤 nil 묶음
	func grouped(_ glyphs: [FontGlyph]) -> [(section: String?, glyphs: [FontGlyph])] {
		guard !sections.isEmpty else { return [(nil, glyphs)] }
		var by: [String: [FontGlyph]] = [:]
		var none: [FontGlyph] = []
		let known = Set(sections)
		for g in glyphs {
			if let s = g.section, known.contains(s) { by[s, default: []].append(g) } else { none.append(g) }
		}
		var out = sections.map { (section: Optional($0), glyphs: by[$0] ?? []) }
		out.append((nil, none))
		return out
	}

	@discardableResult
	mutating func addSection(_ base: String = "새 그룹") -> String {
		var name = base, n = 2
		while sections.contains(name) { name = "\(base) \(n)"; n += 1 }
		sections.append(name)
		return name
	}

	mutating func renameSection(_ old: String, to new: String) {
		let new = new.trimmingCharacters(in: .whitespaces)
		guard !new.isEmpty, old != new, let i = sections.firstIndex(of: old) else { return }
		if sections.contains(new) { sections.remove(at: i) } else { sections[i] = new }
		for j in glyphs.indices where glyphs[j].section == old { glyphs[j].section = new }
	}

	/// 그룹을 지우면 그 아이콘들은 그룹 없음으로 간다
	mutating func deleteSection(_ name: String) {
		sections.removeAll { $0 == name }
		for i in glyphs.indices where glyphs[i].section == name { glyphs[i].section = nil }
	}

	mutating func moveSection(_ name: String, by offset: Int) {
		guard let i = sections.firstIndex(of: name) else { return }
		sections.swapAt(i, min(max(i + offset, 0), sections.count - 1))
	}

	/// name 그룹을 target 그룹 자리로 옮긴다 (끌어다 놓기). 아래로 끌면 target 뒤, 위로 끌면 target 앞
	mutating func moveSection(_ name: String, onto target: String) {
		guard name != target, let from = sections.firstIndex(of: name), let to = sections.firstIndex(of: target) else { return }
		sections.remove(at: from)
		let t = sections.firstIndex(of: target)!
		sections.insert(name, at: from < to ? t + 1 : t)
	}

	/// CSS·폰트에 쓰는 순서: 그룹 순서대로, 그룹 안에서는 놓인 순서대로, 그룹 없는 아이콘은 맨 뒤
	var orderedGlyphs: [FontGlyph] { grouped(glyphs).flatMap(\.glyphs) }

	/// 아이콘들을 target 아이콘 앞에 끼워 넣고 그 그룹으로 옮긴다.
	/// target 이 nil 이면 그 그룹의 맨 뒤로 간다. 옮기는 아이콘들끼리의 순서는 지금 순서를 지킨다.
	mutating func place(_ ids: [String], before target: String?, in section: String?) {
		let moving = Set(ids)
		guard !moving.isEmpty, target.map({ !moving.contains($0) }) ?? true else { return }
		var picked = glyphs.filter { moving.contains($0.id) }
		for i in picked.indices { picked[i].section = section }
		glyphs.removeAll { moving.contains($0.id) }
		let known = Set(sections)
		func inSection(_ g: FontGlyph) -> Bool {
			let s = g.section.flatMap { known.contains($0) ? $0 : nil }
			return s == section
		}
		let at: Int
		if let target, let i = glyphs.firstIndex(where: { $0.id == target }) {
			at = i
		} else if let last = glyphs.lastIndex(where: inSection) {
			at = last + 1
		} else {
			at = glyphs.count
		}
		glyphs.insert(contentsOf: picked, at: at)
	}

	/// 그룹 안 아이콘들 (지금 순서). section 이 nil 이면 그룹 없음
	func glyphs(in section: String?) -> [FontGlyph] {
		grouped(glyphs).first { $0.section == section }?.glyphs ?? []
	}

	/// 그룹을 start 부터 1씩 늘려 다시 매기면 다른 그룹 아이콘과 겹치는 코드들
	func renumberConflicts(_ section: String?, from start: UInt32) -> [UInt32] {
		let mine = glyphs(in: section)
		let ids = Set(mine.map(\.id))
		let others = Set(glyphs.filter { !ids.contains($0.id) }.map(\.code))
		return (0..<UInt32(mine.count)).map { start + $0 }.filter(others.contains)
	}

	/// 그룹 안 아이콘에 지금 순서대로 start 부터 1씩 늘려 코드를 붙인다
	mutating func renumber(_ section: String?, from start: UInt32) {
		var code = start
		for g in glyphs(in: section) {
			if let i = glyphs.firstIndex(where: { $0.id == g.id }) { glyphs[i].code = code; code += 1 }
		}
	}

	/// 아이콘들을 그룹으로 옮긴다 (nil 이면 그룹 없음)
	mutating func move(_ ids: Set<String>, to section: String?) {
		for i in glyphs.indices where ids.contains(glyphs[i].id) { glyphs[i].section = section }
	}

	/// 다음에 쓸 빈 코드 (사용자 영역 E000~F8FF 안에서)
	func nextCode() -> UInt32 {
		let used = Set(glyphs.map(\.code))
		var code: UInt32 = (glyphs.map(\.code).max() ?? 0xE000 - 1) + 1
		if code < 0xE000 || code > 0xF8FF { code = 0xE000 }
		while used.contains(code) { code += 1 }
		return code
	}
}

extension UInt32 {
	var hex: String { String(format: "%04X", self) }
	/// CSS content 에 바로 쓰는 형태 (예: \e102)
	var cssEscape: String { "\\" + String(self, radix: 16) }
}

func makeUID() -> String {
	UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
}
