import Foundation

/// 아이콘그룹에 넣을 파일들(SVG, 폰트 파일, 폴더)을 아이콘으로 바꾼다.
enum IconImport {
	static let fontExtensions: Set<String> = ["ttf", "otf", "woff", "woff2"]

	struct Result {
		var icons: [Icon] = []
		/// 함께 고른 CSS 파일에서 읽은 글자 코드 → 이름
		var cssNames: [UInt32: String] = [:]
		/// CSS 클래스에 공통으로 붙어 있던 접두어 (예: xi-)
		var cssPrefix: String?
		/// CSS 이름을 붙인 아이콘 수 (apply 후 채워짐)
		var renamed = 0
		var failed: [String] = []
		/// 그룹 형태가 맞지 않아 넣지 않은 아이콘 (선 그룹에 채우기 아이콘)
		var rejected: [String] = []
		/// 채우기 그룹에 넣으면서 채우기로 바꾼 선 아이콘 수
		var converted = 0
		/// 코드가 없어 자동으로 코드를 붙인 아이콘 수
		var autoCoded = 0
		/// SVG 파일 하나로 들어온 아이콘 (여백 맞추기 대상. 폰트에서 온 아이콘은 폰트 여백을 그대로 둔다)
		var svgIDs: Set<String> = []
		/// 넣으면서 여백을 맞춘 아이콘 수
		var fitted = 0

		var summary: String {
			var s = "아이콘 \(icons.count)개를 추가했습니다."
			if !cssNames.isEmpty { s += "\nCSS 에서 읽은 이름 \(cssNames.count)개 중 \(renamed)개를 아이콘에 붙였습니다." }
			if !failed.isEmpty { s += "\n가져오지 못한 파일 \(failed.count)개: " + failed.prefix(5).joined(separator: ", ") + (failed.count > 5 ? " 외" : "") }
			if autoCoded > 0 { s += "\n코드가 없는 아이콘 \(autoCoded)개에 코드를 자동으로 붙였습니다." }
			if fitted > 0 { s += "\n아이콘 \(fitted)개는 여백을 24px 칸 규칙에 맞춰 넣었습니다." }
			if converted > 0 { s += "\n선으로 된 아이콘 \(converted)개는 채우기로 바꿔 넣었습니다." }
			if !rejected.isEmpty { s += "\n선 그룹이라 채우기 아이콘 \(rejected.count)개는 넣지 않았습니다: " + rejected.prefix(5).joined(separator: ", ") + (rejected.count > 5 ? " 외" : "") }
			return s
		}
	}

	static func load(_ urls: [URL]) -> Result {
		var result = Result()
		for url in urls {
			let access = url.startAccessingSecurityScopedResource()
			defer { if access { url.stopAccessingSecurityScopedResource() } }
			add(url, to: &result)
		}
		return result
	}

	private static func add(_ url: URL, to result: inout Result) {
		var isDir: ObjCBool = false
		FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
		if isDir.boolValue {
			let items = (FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
			let files = items.filter { ["svg", "css"].contains($0.pathExtension.lowercased()) || fontExtensions.contains($0.pathExtension.lowercased()) }
				.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
			for file in files { add(file, to: &result) }
			return
		}
		let ext = url.pathExtension.lowercased()
		if ext == "css" {
			let css = CSSNames.load(url)
			if css.names.isEmpty { result.failed.append(url.lastPathComponent) }
			result.cssNames.merge(css.names) { a, _ in a }
			if result.cssPrefix == nil { result.cssPrefix = css.prefix }
			return
		}
		do {
			if ext == "svg", let data = try? Data(contentsOf: url), SVGFontImport.isFont(data) {
				let icons = SVGFontImport.load(data)
				if icons.isEmpty { result.failed.append(url.lastPathComponent) }
				result.icons += icons
			} else if ext == "svg" {
				let icon = try SVGImport.load(url)
				result.svgIDs.insert(icon.id)
				result.icons.append(icon)
			} else if fontExtensions.contains(ext) {
				result.icons += try FontFileImport.load(url)
			}
		} catch {
			result.failed.append(url.lastPathComponent)
		}
	}
}

extension IconImport.Result {
	/// CSS 에서 읽은 이름을 같은 글자 코드를 가진 아이콘에 붙인다 (그룹 안의 기존 아이콘 포함)
	mutating func applyNames(to icons: inout [Icon]) {
		guard !cssNames.isEmpty else { return }
		for i in icons.indices {
			// 코드 없이 저장된 예전 아이콘은 uE600 같은 이름에서 코드를 알아낸다
			if icons[i].code == nil { icons[i].code = Icon.codeFromPlaceholder(icons[i].name) }
			if let code = icons[i].code, let name = cssNames[code], icons[i].name != name {
				icons[i].name = name
				renamed += 1
			}
		}
	}
}

enum ImportReportText {
	static func text(_ r: FontelloImport.Report) -> String {
		var s = "\(r.total)개 중 \(r.matched)개의 원본을 아이콘그룹에서 찾았습니다"
		s += r.matched > 0 ? " (크기·위치까지 같은 것 \(r.samePlacement)개)." : "."
		if !r.unmatched.isEmpty {
			s += "\n못 찾은 \(r.unmatched.count)개는 새 아이콘그룹 \"\(r.newGroupName ?? r.fontName)\"에 원본으로 넣었습니다: " + r.unmatched.prefix(8).joined(separator: ", ") + (r.unmatched.count > 8 ? " 외" : "")
		}
		if r.noShape > 0 { s += "\n모양 정보가 없는 Fontello 기본 세트 아이콘 \(r.noShape)개는 빠졌습니다." }
		return s
	}
}
