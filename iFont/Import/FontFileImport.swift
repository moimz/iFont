import CoreGraphics
import CoreText
import Foundation

/// TTF·OTF·WOFF·WOFF2 폰트 파일에서 글리프를 아이콘으로 꺼낸다.
/// 좌표는 em 을 1000 으로 맞추고, 위쪽 기준선(ascent)을 0 으로 하는 y 아래 방향으로 바꾼다.
enum FontFileImport {
	enum Failure: LocalizedError {
		case unreadable
		var errorDescription: String? { "폰트 파일을 읽을 수 없습니다." }
	}

	static func load(_ url: URL) throws -> [Icon] {
		guard let data = try? Data(contentsOf: url),
		      let descs = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
		      let desc = descs.first else { throw Failure.unreadable }

		let probe = CTFontCreateWithFontDescriptor(desc, 12, nil)
		let upm = CGFloat(CTFontGetUnitsPerEm(probe))
		// 글자 크기를 em 단위와 같게 잡으면 경로 좌표가 폰트 단위 그대로 나온다
		let font = CTFontCreateWithFontDescriptor(desc, upm, nil)
		let cgFont = CTFontCopyGraphicsFont(font, nil)
		let ascent = CTFontGetAscent(font)
		let scale = 1000 / upm

		var icons: [Icon] = []
		var seenGlyphs = Set<CGGlyph>()
		for code in codepoints(CTFontCopyCharacterSet(font)) {
			var utf16 = Array(String(UnicodeScalar(code)!).utf16)
			var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
			guard CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count), let glyph = glyphs.first, glyph != 0 else { continue }
			guard seenGlyphs.insert(glyph).inserted else { continue }
			guard let outline = CTFontCreatePathForGlyph(font, glyph, nil), !outline.isEmpty else { continue }

			var advance = CGSize.zero
			var g = glyph
			CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &advance, 1)

			// y 위 방향(기준선 0) → y 아래 방향(ascent 가 0)
			var t = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: ascent * scale)
			guard let flipped = outline.copy(using: &t) else { continue }

			// 별칭이 쉼표로 붙어 있으면 첫 이름만 쓴다
			var name = ((cgFont.name(for: glyph) as String?) ?? "").split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
			if name.isEmpty || name.hasPrefix("uni") || name.hasPrefix("glyph") { name = String(format: "u%04X", code) }
			icons.append(Icon(id: makeUID(), name: name, path: PathWriter.string(flipped), width: (advance.width * scale * 10).rounded() / 10, code: code))
		}
		return icons
	}

	/// 폰트 문자 집합의 코드포인트 (공백·제어문자 제외)
	private static func codepoints(_ set: CFCharacterSet) -> [UInt32] {
		let cs = set as CharacterSet
		var out: [UInt32] = []
		for plane: UInt8 in 0...16 where cs.hasMember(inPlane: plane) {
			let base = UInt32(plane) << 16
			for low: UInt32 in 0...0xFFFF {
				let code = base | low
				guard code > 0x20, !(0xD800...0xDFFF).contains(code), let scalar = UnicodeScalar(code) else { continue }
				if cs.contains(scalar) { out.append(code) }
			}
		}
		return out
	}
}
