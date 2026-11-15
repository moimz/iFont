import CoreGraphics
import Foundation

/// 아이콘 모양 비교. 위치·크기를 맞춘 뒤 작은 흑백 그림으로 그려서 겹치는 비율(IoU)로 본다.
/// 같은 원본이라도 Fontello 가 크기·위치를 바꾸거나 좌표를 반올림하므로 문자열 비교로는 못 찾는다.
enum ShapeMatch {
	static let side = 48
	private static let words = side * side / 64

	struct Mask {
		var bits: [UInt64]
		var count: Int
		/// 외곽 상자의 가로/세로 비
		var aspect: Double
		var bounds: CGRect
	}

	static func mask(_ d: String) -> Mask? { mask(SVGPath.cgPath(d)) }

	static func mask(_ cg: CGPath) -> Mask? {
		let box = cg.boundingBoxOfPath
		guard box.width > 0, box.height > 0 else { return nil }
		let inner = CGFloat(side - 2)
		let s = inner / max(box.width, box.height)
		let ox = 1 + (inner - box.width * s) / 2
		let oy = 1 + (inner - box.height * s) / 2

		var pixels = [UInt8](repeating: 0, count: side * side)
		let ok: Bool = pixels.withUnsafeMutableBytes { raw in
			guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
			                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
			ctx.translateBy(x: ox, y: oy)
			ctx.scaleBy(x: s, y: s)
			ctx.translateBy(x: -box.minX, y: -box.minY)
			ctx.addPath(cg)
			ctx.setFillColor(gray: 1, alpha: 1)
			ctx.fillPath()
			return true
		}
		guard ok else { return nil }
		var bits = [UInt64](repeating: 0, count: words)
		var count = 0
		for i in 0..<pixels.count where pixels[i] > 127 {
			bits[i >> 6] |= 1 << UInt64(i & 63)
			count += 1
		}
		guard count > 0 else { return nil }
		return Mask(bits: bits, count: count, aspect: box.width / box.height, bounds: box)
	}

	private static let sameCache = NSCache<NSString, NSNumber>()

	/// 두 모양이 눈으로 보기에 같은지: 크기·위치가 거의 같고(1000 기준 12 이내) 겹치는 비율이 높으면 같다.
	/// 좌표 표기만 다른 같은 모양(원본에서 다시 넣은 경우)을 "바뀜"으로 보지 않으려고 쓴다
	static func sameShape(_ a: String, _ b: String) -> Bool {
		if a == b { return true }
		let key = "\(a.hashValue)|\(b.hashValue)" as NSString
		if let hit = sameCache.object(forKey: key) { return hit.boolValue }
		var same = false
		if let ma = mask(a), let mb = mask(b) {
			let p = ma.bounds, q = mb.bounds
			let placed = abs(p.minX - q.minX) <= 12 && abs(p.minY - q.minY) <= 12 && abs(p.width - q.width) <= 12 && abs(p.height - q.height) <= 12
			same = placed && iou(ma, mb) >= 0.85
		}
		sameCache.setObject(NSNumber(value: same), forKey: key)
		return same
	}

	static func iou(_ a: Mask, _ b: Mask) -> Double {
		var inter = 0
		for i in 0..<words { inter += (a.bits[i] & b.bits[i]).nonzeroBitCount }
		return Double(inter) / Double(a.count + b.count - inter)
	}

	struct Candidate {
		var groupID: UUID
		var icon: Icon
		var mask: Mask
	}

	struct Found {
		var groupID: UUID
		var icon: Icon
		var score: Double
		/// 원본을 그대로 쓰면 크기·위치까지 같은지 (1000 기준 10 이내)
		var samePlacement: Bool
	}

	static func candidates(_ groups: [IconGroup]) -> [Candidate] {
		groups.flatMap { g in g.icons.compactMap { icon in mask(IconShape.original(icon)).map { Candidate(groupID: g.id, icon: icon, mask: $0) } } }
	}

	/// 가장 비슷한 원본을 찾는다. 비슷한 것이 없으면 nil
	static func best(path: String, width: Double, name: String, in candidates: [Candidate], threshold: Double = 0.9) -> Found? {
		guard let m = mask(path) else { return nil }
		var best: (Candidate, Double)?
		for c in candidates where abs(c.mask.aspect - m.aspect) / max(m.aspect, 0.01) < 0.08 {
			var score = iou(m, c.mask)
			// 이름까지 같으면 거의 확실하다. 가는 선 위주 아이콘은 작은 그림 비교 점수가 낮게 나와서(0.85 안팎) 넉넉히 더한다
			if c.icon.name == name { score += 0.1 }
			if score > (best?.1 ?? 0) { best = (c, score) }
		}
		guard let (c, score) = best, score >= threshold else { return nil }
		let a = m.bounds, b = c.mask.bounds
		let same = abs(a.minX - b.minX) <= 10 && abs(a.minY - b.minY) <= 10 && abs(a.width - b.width) <= 10 && abs(a.height - b.height) <= 10 && abs(width - c.icon.width) <= 10
		return Found(groupID: c.groupID, icon: c.icon, score: min(score, 1), samePlacement: same)
	}
}
