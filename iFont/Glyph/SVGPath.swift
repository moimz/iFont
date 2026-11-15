import CoreGraphics
import Foundation

/// SVG path 문자열을 CGPath 로 바꾼다. (M L H V C S Q T A Z, 대소문자 모두)
enum SVGPath {
	private static let cache = NSCache<NSString, CGPath>()

	static func cgPath(_ d: String) -> CGPath {
		if let hit = cache.object(forKey: d as NSString) { return hit }
		let path = parse(d)
		cache.setObject(path, forKey: d as NSString)
		return path
	}

	// MARK: - 토큰

	private enum Token { case command(Character), number(Double) }

	private static func tokenize(_ d: String) -> [Token] {
		var tokens: [Token] = []
		let chars = Array(d.utf8)
		var i = 0
		// 호(A/a)의 큰 호·방향 플래그는 "016" 처럼 붙여 쓸 수 있어서, 인자 순서를 세어 플래그 자리는 한 글자만 읽는다
		var inArc = false
		var argIndex = 0
		while i < chars.count {
			let c = chars[i]
			if (c >= 65 && c <= 90) || (c >= 97 && c <= 122), c != 101, c != 69 {
				tokens.append(.command(Character(UnicodeScalar(c))))
				inArc = c == 65 || c == 97
				argIndex = 0
				i += 1
			} else if inArc, argIndex % 7 == 3 || argIndex % 7 == 4, c == 48 || c == 49 {
				tokens.append(.number(c == 49 ? 1 : 0))
				argIndex += 1
				i += 1
			} else if c == 45 || c == 43 || c == 46 || (c >= 48 && c <= 57) {
				// 숫자: 부호, 정수부, 소수부(점은 하나만), 지수
				let start = i
				if c == 45 || c == 43 { i += 1 }
				var dot = false
				while i < chars.count {
					let ch = chars[i]
					if ch >= 48 && ch <= 57 { i += 1 }
					else if ch == 46 && !dot { dot = true; i += 1 }
					else { break }
				}
				if i < chars.count, chars[i] == 101 || chars[i] == 69 {
					var j = i + 1
					if j < chars.count, chars[j] == 45 || chars[j] == 43 { j += 1 }
					if j < chars.count, chars[j] >= 48 && chars[j] <= 57 {
						i = j
						while i < chars.count, chars[i] >= 48 && chars[i] <= 57 { i += 1 }
					}
				}
				let s = String(decoding: chars[start..<i], as: UTF8.self)
				tokens.append(.number(Double(s) ?? 0))
				argIndex += 1
			} else {
				i += 1
			}
		}
		return tokens
	}

	// MARK: - 해석

	private static func parse(_ d: String) -> CGPath {
		let tokens = tokenize(d)
		let path = CGMutablePath()
		var i = 0
		var cmd: Character = "M"
		var cur = CGPoint.zero
		var start = CGPoint.zero
		var lastCtrl: CGPoint?  // S/T 반사용
		var lastCmd: Character = " "

		func num() -> Double? {
			guard i < tokens.count, case .number(let v) = tokens[i] else { return nil }
			i += 1
			return v
		}
		func flag() -> Bool? {
			// 호의 플래그는 "11" 처럼 붙어 나올 수 있다
			guard let v = num() else { return nil }
			return v != 0
		}

		while i < tokens.count {
			if case .command(let c) = tokens[i] {
				cmd = c
				i += 1
				if c == "Z" || c == "z" {
					path.closeSubpath()
					cur = start
					lastCtrl = nil
					lastCmd = "Z"
					continue
				}
			} else if cmd == "Z" || cmd == "z" {
				i += 1
				continue
			}
			let rel = cmd.isLowercase
			let base = rel ? cur : .zero
			let upper = Character(cmd.uppercased())

			switch upper {
			case "M":
				guard let x = num(), let y = num() else { i += 1; continue }
				cur = CGPoint(x: base.x + x, y: base.y + y)
				path.move(to: cur)
				start = cur
				cmd = rel ? "l" : "L"  // 이어지는 좌표는 L
				lastCtrl = nil
			case "L":
				guard let x = num(), let y = num() else { i += 1; continue }
				cur = CGPoint(x: base.x + x, y: base.y + y)
				path.addLine(to: cur)
				lastCtrl = nil
			case "H":
				guard let x = num() else { i += 1; continue }
				cur.x = (rel ? cur.x : 0) + x
				path.addLine(to: cur)
				lastCtrl = nil
			case "V":
				guard let y = num() else { i += 1; continue }
				cur.y = (rel ? cur.y : 0) + y
				path.addLine(to: cur)
				lastCtrl = nil
			case "C":
				guard let x1 = num(), let y1 = num(), let x2 = num(), let y2 = num(), let x = num(), let y = num() else { i += 1; continue }
				let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
				cur = CGPoint(x: base.x + x, y: base.y + y)
				path.addCurve(to: cur, control1: CGPoint(x: base.x + x1, y: base.y + y1), control2: c2)
				lastCtrl = c2
			case "S":
				guard let x2 = num(), let y2 = num(), let x = num(), let y = num() else { i += 1; continue }
				let c1 = (lastCmd == "C" || lastCmd == "S") ? reflect(lastCtrl, cur) : cur
				let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
				cur = CGPoint(x: base.x + x, y: base.y + y)
				path.addCurve(to: cur, control1: c1, control2: c2)
				lastCtrl = c2
			case "Q":
				guard let x1 = num(), let y1 = num(), let x = num(), let y = num() else { i += 1; continue }
				let c = CGPoint(x: base.x + x1, y: base.y + y1)
				cur = CGPoint(x: base.x + x, y: base.y + y)
				path.addQuadCurve(to: cur, control: c)
				lastCtrl = c
			case "T":
				guard let x = num(), let y = num() else { i += 1; continue }
				let c = (lastCmd == "Q" || lastCmd == "T") ? reflect(lastCtrl, cur) : cur
				cur = CGPoint(x: base.x + x, y: base.y + y)
				path.addQuadCurve(to: cur, control: c)
				lastCtrl = c
			case "A":
				guard let rx = num(), let ry = num(), let rot = num(), let large = flag(), let sweep = flag(), let x = num(), let y = num() else { i += 1; continue }
				let end = CGPoint(x: base.x + x, y: base.y + y)
				addArc(path, from: cur, to: end, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
				cur = end
				lastCtrl = nil
			default:
				i += 1
				continue
			}
			lastCmd = upper
		}
		return path
	}

	private static func reflect(_ p: CGPoint?, _ about: CGPoint) -> CGPoint {
		guard let p else { return about }
		return CGPoint(x: 2 * about.x - p.x, y: 2 * about.y - p.y)
	}

	/// SVG 호(끝점 표기)를 3차 곡선 조각들로 바꿔 붙인다. (SVG 명세 F.6 의 중심점 변환)
	private static func addArc(_ path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rxIn: Double, ry ryIn: Double, rotation: Double, large: Bool, sweep: Bool) {
		if p0 == p1 { return }
		var rx = abs(rxIn), ry = abs(ryIn)
		if rx == 0 || ry == 0 { path.addLine(to: p1); return }

		let phi = rotation * .pi / 180
		let cosP = cos(phi), sinP = sin(phi)
		let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
		let x1p = cosP * dx + sinP * dy
		let y1p = -sinP * dx + cosP * dy

		let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
		if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }

		let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
		let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
		var coef = den == 0 ? 0 : sqrt(max(0, num / den))
		if large == sweep { coef = -coef }
		let cxp = coef * rx * y1p / ry
		let cyp = -coef * ry * x1p / rx
		let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
		let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2

		func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
			let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
			return a
		}
		let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
		var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
		if !sweep && delta > 0 { delta -= 2 * .pi }
		if sweep && delta < 0 { delta += 2 * .pi }

		let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
		let step = delta / Double(segments)
		let k = 4.0 / 3.0 * tan(step / 4)
		var t = theta1
		func point(_ a: Double) -> CGPoint {
			let x = rx * cos(a), y = ry * sin(a)
			return CGPoint(x: cosP * x - sinP * y + cx, y: sinP * x + cosP * y + cy)
		}
		func deriv(_ a: Double) -> CGPoint {
			let x = -rx * sin(a), y = ry * cos(a)
			return CGPoint(x: cosP * x - sinP * y, y: sinP * x + cosP * y)
		}
		for s in 0..<segments {
			let t2 = t + step
			let a = point(t), b = (s == segments - 1) ? p1 : point(t2)
			let da = deriv(t), db = deriv(t2)
			path.addCurve(to: b,
			              control1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
			              control2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y))
			t = t2
		}
	}
}
