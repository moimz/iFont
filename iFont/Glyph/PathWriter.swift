import CoreGraphics
import Foundation

/// CGPath 를 SVG path 문자열로 바꾼다. 좌표는 소수 한 자리까지 남긴다.
enum PathWriter {
	static func string(_ path: CGPath) -> String {
		var out = ""
		func n(_ v: CGFloat) -> String {
			let r = (v * 10).rounded() / 10
			if r == r.rounded() { return String(Int(r)) }
			return String(format: "%.1f", r)
		}
		func p(_ pt: CGPoint) -> String { n(pt.x) + " " + n(pt.y) }
		path.applyWithBlock { element in
			let e = element.pointee
			switch e.type {
			case .moveToPoint: out += "M" + p(e.points[0])
			case .addLineToPoint: out += "L" + p(e.points[0])
			case .addQuadCurveToPoint: out += "Q" + p(e.points[0]) + " " + p(e.points[1])
			case .addCurveToPoint: out += "C" + p(e.points[0]) + " " + p(e.points[1]) + " " + p(e.points[2])
			case .closeSubpath: out += "Z"
			@unknown default: break
			}
		}
		return out
	}
}
