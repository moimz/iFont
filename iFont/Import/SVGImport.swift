import CoreGraphics
import Foundation

/// SVG 파일 하나를 아이콘 하나로 바꾼다.
/// 채우기 도형은 path 에, 선(stroke) 도형은 중심선과 굵기 그대로 strokes 에 담는다.
/// 결과 좌표는 viewBox 높이를 1000 으로 맞춘 y 아래 방향이다.
enum SVGImport {
	enum Failure: LocalizedError {
		case unreadable, empty
		var errorDescription: String? {
			switch self {
			case .unreadable: "SVG 파일을 읽을 수 없습니다."
			case .empty: "그릴 도형이 없습니다."
			}
		}
	}

	static func load(_ url: URL) throws -> Icon {
		guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
		let reader = Reader()
		let parser = XMLParser(data: data)
		parser.delegate = reader
		guard parser.parse(), let box = reader.viewBox else { throw Failure.unreadable }
		if reader.fill.isEmpty && reader.strokes.isEmpty { throw Failure.empty }

		let scale = 1000 / box.height
		var t = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -box.minX, y: -box.minY)
		let fill = reader.fill.isEmpty ? "" : (reader.fill.copy(using: &t).map(PathWriter.string) ?? "")
		let strokes = reader.strokes.compactMap { s -> StrokePart? in
			guard let p = s.path.copy(using: &t) else { return nil }
			return StrokePart(d: PathWriter.string(p), width: (s.width * scale * 100).rounded() / 100, cap: s.cap, join: s.join)
		}
		return Icon(id: makeUID(), name: url.deletingPathExtension().lastPathComponent, path: fill,
		            width: (box.width * scale * 10).rounded() / 10, strokes: strokes.isEmpty ? nil : strokes)
	}

	// MARK: - XML 읽기

	private struct Style {
		var transform = CGAffineTransform.identity
		var fillNone = false
		var stroke = false
		var strokeWidth: CGFloat = 1
		var cap = "butt"
		var join = "miter"
		var hidden = false
	}

	private struct RawStroke {
		var path: CGPath
		var width: CGFloat
		var cap: String
		var join: String
	}

	private final class Reader: NSObject, XMLParserDelegate {
		var viewBox: CGRect?
		let fill = CGMutablePath()
		var strokes: [RawStroke] = []
		private var stack: [Style] = [Style()]

		func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
			var st = stack.last!
			if let s = a["transform"] { st.transform = Self.transform(s).concatenating(st.transform) }
			let css = Self.style(a)
			if let f = css["fill"] { st.fillNone = f == "none" || f == "transparent" }
			if let s = css["stroke"] { st.stroke = !(s == "none" || s == "transparent") }
			if let w = css["stroke-width"].flatMap(Self.length) { st.strokeWidth = w }
			if let c = css["stroke-linecap"] { st.cap = c }
			if let j = css["stroke-linejoin"] { st.join = j }
			st.hidden = st.hidden || ["defs", "clipPath", "mask", "symbol", "title", "desc", "metadata", "pattern", "linearGradient", "radialGradient"].contains(name)
				|| css["display"] == "none"
			stack.append(st)

			if name == "svg", viewBox == nil {
				if let vb = a["viewBox"]?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap({ Double($0) }), vb.count == 4 {
					viewBox = CGRect(x: vb[0], y: vb[1], width: vb[2], height: vb[3])
				} else if let w = a["width"].flatMap(Self.length), let h = a["height"].flatMap(Self.length) {
					viewBox = CGRect(x: 0, y: 0, width: w, height: h)
				}
				return
			}
			if st.hidden { return }

			var canFill = true
			let shape: CGPath?
			switch name {
			case "path":
				shape = a["d"].map { SVGPath.cgPath($0) }
			case "rect":
				let x = num(a["x"]), y = num(a["y"]), w = num(a["width"]), h = num(a["height"])
				var rx = a["rx"].map { num($0) }, ry = a["ry"].map { num($0) }
				rx = rx ?? ry; ry = ry ?? rx
				shape = w > 0 && h > 0
					? CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: min(rx ?? 0, w / 2), cornerHeight: min(ry ?? 0, h / 2), transform: nil)
					: nil
			case "circle":
				let r = num(a["r"])
				shape = r > 0 ? CGPath(ellipseIn: CGRect(x: num(a["cx"]) - r, y: num(a["cy"]) - r, width: r * 2, height: r * 2), transform: nil) : nil
			case "ellipse":
				let rx = num(a["rx"]), ry = num(a["ry"])
				shape = rx > 0 && ry > 0 ? CGPath(ellipseIn: CGRect(x: num(a["cx"]) - rx, y: num(a["cy"]) - ry, width: rx * 2, height: ry * 2), transform: nil) : nil
			case "polygon":
				shape = a["points"].map { SVGPath.cgPath("M" + $0 + "Z") }
			case "polyline":
				shape = a["points"].map { SVGPath.cgPath("M" + $0) }
			case "line":
				canFill = false
				let p = CGMutablePath()
				p.move(to: CGPoint(x: num(a["x1"]), y: num(a["y1"])))
				p.addLine(to: CGPoint(x: num(a["x2"]), y: num(a["y2"])))
				shape = p
			default:
				shape = nil
			}
			guard let shape else { return }
			if canFill && !st.fillNone { fill.addPath(shape, transform: st.transform) }
			if st.stroke {
				var t = st.transform
				// 변환에 들어 있는 확대 비율만큼 굵기도 바뀐다
				let factor = sqrt(abs(t.a * t.d - t.b * t.c))
				if let p = shape.copy(using: &t) {
					strokes.append(RawStroke(path: p, width: st.strokeWidth * factor, cap: st.cap, join: st.join))
				}
			}
		}

		func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
			if stack.count > 1 { stack.removeLast() }
		}

		private func num(_ s: String?) -> CGFloat { s.flatMap(Self.length) ?? 0 }

		static func length(_ s: String) -> CGFloat? {
			let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "px", with: "")
			return Double(t).map { CGFloat($0) }
		}

		static func style(_ a: [String: String]) -> [String: String] {
			var out: [String: String] = [:]
			for key in ["fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "display"] {
				if let v = a[key] { out[key] = v.trimmingCharacters(in: .whitespaces) }
			}
			for part in (a["style"] ?? "").split(separator: ";") {
				let kv = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
				if kv.count == 2 { out[kv[0]] = kv[1] }
			}
			return out
		}

		/// transform 속성 해석: matrix translate scale rotate skewX skewY
		static func transform(_ s: String) -> CGAffineTransform {
			var result = CGAffineTransform.identity
			var rest = Substring(s.replacingOccurrences(of: ",", with: " "))
			while let open = rest.firstIndex(of: "("), let close = rest.firstIndex(of: ")") {
				let name = rest[..<open].trimmingCharacters(in: .whitespaces)
				let v = rest[rest.index(after: open)..<close].split(separator: " ").compactMap { Double($0) }.map { CGFloat($0) }
				var t = CGAffineTransform.identity
				switch name {
				case "matrix" where v.count == 6: t = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
				case "translate" where !v.isEmpty: t = CGAffineTransform(translationX: v[0], y: v.count > 1 ? v[1] : 0)
				case "scale" where !v.isEmpty: t = CGAffineTransform(scaleX: v[0], y: v.count > 1 ? v[1] : v[0])
				case "rotate" where !v.isEmpty:
					let r = v[0] * .pi / 180
					t = v.count == 3
						? CGAffineTransform(translationX: v[1], y: v[2]).rotated(by: r).translatedBy(x: -v[1], y: -v[2])
						: CGAffineTransform(rotationAngle: r)
				case "skewX" where !v.isEmpty: t = CGAffineTransform(a: 1, b: 0, c: tan(v[0] * .pi / 180), d: 1, tx: 0, ty: 0)
				case "skewY" where !v.isEmpty: t = CGAffineTransform(a: 1, b: tan(v[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
				default: break
				}
				// 앞에 쓴 변환이 바깥쪽: 점에는 뒤의 것부터 적용된다
				result = t.concatenating(result)
				rest = rest[rest.index(after: close)...]
			}
			return result
		}
	}
}
