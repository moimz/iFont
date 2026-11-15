import Foundation

/// 아이콘 폰트 CSS 에서 "글자 코드 → 클래스 이름"을 읽는다.
/// 예: `.xi-home:before { content: "\e600"; }` → E600: "home", 접두어 "xi-" (모두에 붙은 접두어는 떼서 따로 돌려준다)
enum CSSNames {
	struct Result {
		var names: [UInt32: String] = [:]
		var prefix: String?
	}

	static func load(_ url: URL) -> Result {
		guard let css = try? String(contentsOf: url, encoding: .utf8) else { return Result() }
		return parse(css)
	}

	static func parse(_ css: String) -> Result {
		// 주석 제거
		let text = css.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
		let block = try! NSRegularExpression(pattern: #"([^{}]+)\{[^{}]*?content\s*:\s*["']\\([0-9a-fA-F]{2,6})["']"#)
		let cls = try! NSRegularExpression(pattern: #"\.([A-Za-z_][A-Za-z0-9_-]*)\s*:{1,2}before"#)

		var pairs: [(UInt32, String)] = []
		let ns = text as NSString
		for m in block.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
			guard let code = UInt32(ns.substring(with: m.range(at: 2)), radix: 16) else { continue }
			let selectors = ns.substring(with: m.range(at: 1)) as NSString
			// 같은 코드에 별칭이 여러 개면 처음 것만 쓴다
			if let first = cls.firstMatch(in: selectors as String, range: NSRange(location: 0, length: selectors.length)) {
				pairs.append((code, selectors.substring(with: first.range(at: 1))))
			}
		}
		guard !pairs.isEmpty else { return Result() }

		// 90% 이상이 같은 "xx-" 접두어를 쓰면 뗀다 (폰트 쪽에 따로 접두어가 있으므로)
		var prefixCount: [String: Int] = [:]
		for (_, name) in pairs {
			if let dash = name.firstIndex(of: "-") { prefixCount[String(name[...dash]), default: 0] += 1 }
		}
		let prefix = prefixCount.max { $0.value < $1.value }.flatMap { Double($0.value) >= Double(pairs.count) * 0.9 ? $0.key : nil }

		var out: [UInt32: String] = [:]
		for (code, name) in pairs where out[code] == nil {
			var n = name
			if let prefix, n.hasPrefix(prefix), n.count > prefix.count { n.removeFirst(prefix.count) }
			out[code] = n
		}
		return Result(names: out, prefix: prefix)
	}
}
