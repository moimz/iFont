import CoreGraphics
import Foundation

/// 폰트를 내보낸다: <이름>.woff2, <이름>.svg(SVG 폰트), <이름>.css, <이름>.html(미리보기)
enum FontExport {
	struct Glyph {
		var glyph: FontGlyph
		/// 폰트 선 굵기를 적용한 모양 (화면 좌표: 높이 1000, y 아래 방향)
		var shape: CGPath
	}

	/// CSS @version 값: 큰 버전.아이콘 수.내려받은 횟수
	static func version(_ font: FontDoc) -> String { "\(font.version).\(font.glyphs.count).\(font.downloads)" }

	/// 폰트에 넣을 모양들 (CSS 순서). 선 그룹 원본은 폰트 선 굵기로, 그 밖에는 폰트에 복사해 둔 모양으로
	static func glyphs(_ font: FontDoc, store: Store) -> [Glyph] {
		font.orderedGlyphs.map { g in
			if let group = store.group(g.groupID), let icon = store.icon(of: g),
			   let p = IconShape.fontPath(icon, in: group, weight: font.weight) {
				return Glyph(glyph: g, shape: p)
			}
			return Glyph(glyph: g, shape: SVGPath.cgPath(g.path))
		}
	}

	/// 폴더에 네 파일을 쓴다. 쓴 파일 목록을 돌려준다
	@discardableResult
	static func write(_ font: FontDoc, store: Store, to folder: URL, date: Date = Date()) throws -> [URL] {
		let items = glyphs(font, store: store)
		let base = fileName(font)
		let ver = version(font)
		let outlines = items.map {
			OutlineGlyph.make(name: $0.glyph.name, code: $0.glyph.code, path: $0.shape, width: $0.glyph.width, unitsPerEm: font.unitsPerEm, ascent: font.ascent)
		}
		let tables = TrueTypeWriter.tables(outlines, info: .init(family: font.name, version: ver, unitsPerEm: font.unitsPerEm, ascent: font.ascent, descent: font.descent))
		let files: [(String, Data)] = [
			(base + ".woff2", try WOFF2Writer.font(tables)),
			(base + ".svg", Data(svgFont(font, items: items).utf8)),
			(base + ".css", Data(css(font, date: date).utf8)),
			(base + ".html", Data(html(font).utf8)),
		]
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		return try files.map { name, data in
			let url = folder.appendingPathComponent(name)
			try data.write(to: url, options: .atomic)
			return url
		}
	}

	/// 파일 이름: 폰트 이름에서 파일에 못 쓰는 글자를 뺀 것
	static func fileName(_ font: FontDoc) -> String {
		let s = font.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined().trimmingCharacters(in: .whitespaces)
		return s.isEmpty ? "font" : s
	}

	/// CSS 기본 클래스: 접두어에서 끝의 - 를 뺀 것 (mi- → mi)
	static func baseClass(_ font: FontDoc) -> String {
		var p = font.prefix
		while p.hasSuffix("-") || p.hasSuffix("_") { p.removeLast() }
		return p.isEmpty ? "icon" : p
	}

	// MARK: - SVG 폰트

	static func svgFont(_ font: FontDoc, items: [Glyph]) -> String {
		let k = Double(font.unitsPerEm) / 1000
		var flip = CGAffineTransform(a: k, b: 0, c: 0, d: -k, tx: 0, ty: Double(font.ascent))
		var out = """
		<?xml version="1.0" standalone="no"?>
		<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
		<svg xmlns="http://www.w3.org/2000/svg">
		<metadata>\(xml(font.name)) \(version(font)) · iFont</metadata>
		<defs>
		<font id="\(xml(font.name))" horiz-adv-x="\(font.unitsPerEm)">
		<font-face font-family="\(xml(font.name))" font-weight="400" font-stretch="normal" units-per-em="\(font.unitsPerEm)" ascent="\(font.ascent)" descent="-\(font.descent)" />
		<missing-glyph horiz-adv-x="\(font.unitsPerEm)" />

		"""
		for item in items {
			let d = item.shape.copy(using: &flip).map(PathWriter.string) ?? ""
			out += "<glyph glyph-name=\"\(xml(item.glyph.name))\" unicode=\"&#x\(String(item.glyph.code, radix: 16));\" d=\"\(d)\" horiz-adv-x=\"\(Int((item.glyph.width * k).rounded()))\" />\n"
		}
		out += "</font>\n</defs>\n</svg>\n"
		return out
	}

	private static func xml(_ s: String) -> String {
		s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
			.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
	}

	// MARK: - CSS

	static func css(_ font: FontDoc, date: Date = Date()) -> String {
		let ver = version(font)
		let base = baseClass(font)
		let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
		var out = "/**\n"
		// 주석 글 → 빈 줄 → @file · @author · @license (비운 것은 뺀다) → @version · @modified
		let header = font.cssHeader.trimmingCharacters(in: .whitespacesAndNewlines)
		let comment = header.isEmpty ? "\(font.name) 아이콘 폰트" : header
		for line in comment.components(separatedBy: "\n") {
			let t = line.trimmingCharacters(in: .whitespaces)
			out += t.isEmpty ? " *\n" : " * \(t)\n"
		}
		out += " *\n"
		let folder = font.cssFile.trimmingCharacters(in: .whitespaces)
		let file = folder.isEmpty ? "" : (folder.hasSuffix("/") ? folder : folder + "/") + fileName(font) + ".css"
		for (tag, value) in [("@file", file), ("@author", font.cssAuthor), ("@license", font.cssLicense)] {
			let v = value.trimmingCharacters(in: .whitespaces)
			if !v.isEmpty { out += " * \(tag) \(v)\n" }
		}
		out += " * @version \(ver)\n"
		out += " * @modified \(c.year!). \(c.month!). \(c.day!).\n"
		out += " */\n"
		out += """
		@font-face {
		    font-family: '\(font.name)';
		    font-weight: normal;
		    font-style: normal;
		    src: url('./\(fileName(font)).woff2?v=\(ver)') format('woff2');
		    font-display: block;
		}

		.\(base) {
		    display: inline-block;
		    font-style: normal;
		    font-family: \(cssFamily(font.name));
		    text-rendering: auto;
		    -webkit-font-smoothing: antialiased;
		    -moz-osx-font-smoothing: grayscale;
		}

		"""
		// 애니메이션이 있는 아이콘: 이름이 같은 keyframes 로 무한 반복
		for g in font.orderedGlyphs {
			guard let a = g.animation else { continue }
			let name = font.prefix + g.name
			let frames = """
			    0% {
			        -webkit-transform: rotate(0deg);
			        transform: rotate(0deg);
			    }
			    100% {
			        -webkit-transform: rotate(359deg);
			        transform: rotate(359deg);
			    }
			"""
			out += """
			.\(name) {
			    -webkit-animation: \(name) \(seconds(a.duration)) infinite \(a.timing);
			    animation: \(name) \(seconds(a.duration)) infinite \(a.timing);
			}
			@-webkit-keyframes \(name) {
			\(frames)
			}
			@keyframes \(name) {
			\(frames)
			}

			"""
		}
		if font.glyphs.contains(where: { $0.animation != nil }) { out += "\n" }
		for g in font.orderedGlyphs {
			out += """
			.\(font.prefix + g.name)::before {
			    content: '\(g.code.cssEscape)';
			}

			"""
		}
		return out.trimmingCharacters(in: .newlines) + "\n"
	}

	/// 이름에 글자·숫자·- 만 있으면 따옴표 없이 (moimz), 아니면 따옴표로
	private static func cssFamily(_ name: String) -> String {
		name.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0)) || $0 == "-") } ? name : "'\(name)'"
	}

	private static func seconds(_ v: Double) -> String {
		v == v.rounded() ? "\(Int(v))s" : "\(v)s"
	}

	// MARK: - 미리보기 HTML

	static func html(_ font: FontDoc) -> String {
		let base = baseClass(font)
		var sections = ""
		for part in font.grouped(font.glyphs) where !part.glyphs.isEmpty {
			let title = part.section ?? (font.sections.isEmpty ? "" : "그룹 없음")
			if !title.isEmpty { sections += "<h2>\(xml(title)) <small>\(part.glyphs.count)</small></h2>\n" }
			sections += "<div class=\"grid\">\n"
			for g in part.glyphs {
				let cls = font.prefix + g.name
				let anim = g.animation.map { " <span class=\"anim\">\($0.title)</span>" } ?? ""
				sections += "<button class=\"cell\" data-copy=\"\(xml(cls))\" title=\"누르면 클래스 이름 복사\"><i class=\"\(base) \(xml(cls))\"></i><code>\(g.code.cssEscape.replacingOccurrences(of: "\\", with: "&#92;"))</code><span class=\"name\">\(xml(cls))\(anim)</span></button>\n"
			}
			sections += "</div>\n"
		}
		return """
		<!doctype html>
		<html lang="ko">
		<head>
		<meta charset="utf-8">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<title>\(xml(font.name)) \(version(font))</title>
		<link rel="stylesheet" href="./\(fileName(font)).css">
		<style>
		:root { color-scheme: light dark; --bg: #fff; --fg: #1d1d1f; --sub: #86868b; --cell: #f5f5f7; --line: #e5e5ea; --accent: #0071e3; }
		@media (prefers-color-scheme: dark) { :root { --bg: #1c1c1e; --fg: #f5f5f7; --sub: #98989d; --cell: #2c2c2e; --line: #3a3a3c; --accent: #0a84ff; } }
		* { box-sizing: border-box; }
		body { margin: 0; padding: 24px 16px 48px; background: var(--bg); color: var(--fg); font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif; }
		header { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; margin-bottom: 8px; }
		h1 { font-size: 22px; margin: 0; }
		h1 small, h2 small { color: var(--sub); font-weight: normal; font-size: 13px; }
		input, select { font: inherit; padding: 6px 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--cell); color: var(--fg); }
		input { flex: 1; min-width: 180px; max-width: 320px; }
		.usage { color: var(--sub); font-size: 12px; margin: 0 0 8px; }
		.usage code { font-size: 12px; }
		h2 { font-size: 15px; margin: 28px 0 10px; }
		.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 8px; }
		.cell { display: flex; flex-direction: column; align-items: center; gap: 6px; padding: 14px 6px 10px; border: 0; border-radius: 10px; background: var(--cell); color: var(--fg); cursor: pointer; font: inherit; min-width: 0; }
		.cell:hover { outline: 2px solid var(--accent); }
		.cell i { font-size: var(--size, 32px); line-height: 1; }
		.cell code { font-size: 11px; color: var(--sub); }
		.cell .name { font-size: 11px; max-width: 100%; overflow-wrap: anywhere; text-align: center; }
		.cell .anim { color: var(--accent); }
		.cell.copied { outline: 2px solid var(--accent); }
		.hidden { display: none; }
		</style>
		</head>
		<body>
		<header>
		<h1>\(xml(font.name)) <small>\(version(font)) · 아이콘 \(font.glyphs.count)개</small></h1>
		<input id="q" type="search" placeholder="이름 또는 코드 검색" autofocus>
		<select id="size"><option value="24px">24px</option><option value="32px" selected>32px</option><option value="48px">48px</option></select>
		</header>
		<p class="usage">사용: <code>&lt;i class="\(base) \(xml(font.prefix))이름"&gt;&lt;/i&gt;</code> · 칸을 누르면 클래스 이름이 복사됩니다.</p>
		\(sections)
		<script>
		const q = document.getElementById('q');
		q.addEventListener('input', () => {
		  const v = q.value.trim().toLowerCase();
		  document.querySelectorAll('.cell').forEach(c => c.classList.toggle('hidden', v !== '' && !c.textContent.toLowerCase().includes(v)));
		  document.querySelectorAll('.grid').forEach(g => {
		    const h = g.previousElementSibling;
		    const any = g.querySelector('.cell:not(.hidden)');
		    g.classList.toggle('hidden', !any);
		    if (h && h.tagName === 'H2') h.classList.toggle('hidden', !any);
		  });
		});
		document.getElementById('size').addEventListener('change', e => document.body.style.setProperty('--size', e.target.value));
		document.querySelectorAll('.cell').forEach(c => c.addEventListener('click', () => {
		  try { navigator.clipboard.writeText(c.dataset.copy); } catch (e) {}
		  c.classList.add('copied'); setTimeout(() => c.classList.remove('copied'), 800);
		}));
		</script>
		</body>
		</html>

		"""
	}
}
