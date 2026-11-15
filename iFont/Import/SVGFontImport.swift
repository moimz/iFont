import CoreGraphics
import Foundation

/// SVG 폰트(<font><glyph d="…"/></font>, IcoMoon·Fontello 등이 만드는 형식)에서 글리프를 아이콘으로 꺼낸다.
/// 글리프 좌표는 y 위 방향이므로 em 을 1000 으로 맞추고 ascent 를 0 으로 하는 y 아래 방향으로 바꾼다.
enum SVGFontImport {
	/// SVG 파일이 폰트 형식인지 (앞부분에 <font 가 있는지)
	static func isFont(_ data: Data) -> Bool {
		guard let head = String(data: data.prefix(64 * 1024), encoding: .utf8) else { return false }
		return head.contains("<font") && head.contains("<glyph")
	}

	static func load(_ data: Data) -> [Icon] {
		let reader = Reader()
		let parser = XMLParser(data: data)
		parser.delegate = reader
		parser.parse()

		let scale = 1000 / reader.unitsPerEm
		var t = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: reader.ascent * scale)
		var icons: [Icon] = []
		for g in reader.glyphs where !g.d.isEmpty {
			let source = SVGPath.cgPath(g.d)
			guard !source.isEmpty, let flipped = source.copy(using: &t) else { continue }
			icons.append(Icon(id: makeUID(), name: g.name, path: PathWriter.string(flipped),
			                  width: ((g.advance ?? reader.defaultAdvance) * scale * 10).rounded() / 10, code: g.code))
		}
		return icons
	}

	private struct RawGlyph {
		var name: String
		var code: UInt32?
		var d: String
		var advance: Double?
	}

	private final class Reader: NSObject, XMLParserDelegate {
		var unitsPerEm: Double = 1000
		var ascent: Double = 800
		var defaultAdvance: Double = 1000
		var glyphs: [RawGlyph] = []
		private var hasAscent = false

		func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
			switch name {
			case "font":
				if let v = a["horiz-adv-x"].flatMap(Double.init) { defaultAdvance = v }
			case "font-face":
				if let v = a["units-per-em"].flatMap(Double.init) { unitsPerEm = v }
				if let v = a["ascent"].flatMap(Double.init) { ascent = v; hasAscent = true }
				if !hasAscent, let d = a["descent"].flatMap(Double.init) { ascent = unitsPerEm + d }
			case "glyph":
				guard let d = a["d"], !d.isEmpty else { return }
				let unicode = a["unicode"] ?? ""
				let scalars = Array(unicode.unicodeScalars)
				// 공백·제어문자 글리프는 건너뛴다
				if scalars.count == 1, scalars[0].value <= 0x20 { return }
				// "check-square, check-box" 처럼 별칭이 쉼표로 붙어 있으면 첫 이름만 쓴다
				var glyphName = (a["glyph-name"] ?? "").split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
				if glyphName.isEmpty || glyphName.hasPrefix("uni") || glyphName.hasPrefix("glyph") {
					glyphName = scalars.count == 1 ? String(format: "u%04X", scalars[0].value) : "glyph\(glyphs.count + 1)"
				}
				glyphs.append(RawGlyph(name: glyphName, code: scalars.count == 1 ? scalars[0].value : nil, d: d, advance: a["horiz-adv-x"].flatMap(Double.init)))
			default:
				break
			}
		}
	}
}
