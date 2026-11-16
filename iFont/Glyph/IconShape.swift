import CoreGraphics
import Foundation

/// 그룹 설정(형태·선 굵기)을 적용한 아이콘의 실제 모양.
/// 원본은 그대로 두고, 보여 줄 때·폰트를 만들 때 이 모양을 쓴다.
enum IconShape {
	private static let cache = NSCache<NSNumber, CGPath>()

	/// 그룹 설정을 적용한 최종 채우기 모양
	static func path(_ icon: Icon, in group: IconGroup) -> CGPath {
		var h = Hasher()
		h.combine(icon.path); h.combine(icon.strokes); h.combine(icon.baseWeight)
		h.combine(group.style); h.combine(group.weight); h.combine(group.baseWeight)
		let key = NSNumber(value: h.finalize())
		if let hit = cache.object(forKey: key) { return hit }

		let result: CGPath
		if icon.hasStrokes {
			// 선 그룹: 설정한 굵기로 선을 그어 외곽선으로 만든다
			let width = group.style == .stroke ? group.weight.map { $0 * unitsPer24px } : nil
			result = outline(icon, width: width)
		} else {
			// 채우기 원본은 굵기를 바꾸지 않는다 (폰트에서도 굵기 설정이 적용되지 않는다)
			result = SVGPath.cgPath(icon.path)
		}
		cache.setObject(result, forKey: key)
		return result
	}

	/// 굵기 설정을 적용하지 않은 원래 모양 (원본 매칭용)
	static func original(_ icon: Icon) -> CGPath {
		icon.hasStrokes ? outline(icon, width: nil) : SVGPath.cgPath(icon.path)
	}

	/// 폰트에 넣는 모양: 그룹 굵기 설정(미리보기용)은 무시하고 원본 굵기 그대로. 선은 외곽선으로 바꾼다
	static func fontPathString(_ icon: Icon) -> String {
		icon.hasStrokes ? PathWriter.string(outline(icon, width: nil)) : icon.path
	}

	/// 폰트 선 굵기·크기 배율을 적용한 폰트 아이콘 모양. 선 그룹 원본만 그 굵기로 선을 긋고, 채우기 원본은 그대로 둔다.
	/// 배율은 선 중심을 em 가운데 기준으로 키운 뒤 선을 그어서 선 굵기는 바뀌지 않는다.
	/// weight 가 nil 이고 배율이 1 이면 nil (폰트에 복사해 둔 원본 굵기 모양을 쓴다)
	static func fontPath(_ icon: Icon, in group: IconGroup, weight: Double?, scale: Double = 1) -> CGPath? {
		guard weight != nil || scale != 1, group.style == .stroke, icon.hasStrokes else { return nil }
		var h = Hasher()
		h.combine("font"); h.combine(icon.path); h.combine(icon.strokes); h.combine(weight); h.combine(scale)
		let key = NSNumber(value: h.finalize())
		if let hit = cache.object(forKey: key) { return hit }
		let result = outline(icon, width: weight.map { $0 * unitsPer24px }, transform: scaling(scale, width: icon.width))
		cache.setObject(result, forKey: key)
		return result
	}

	/// em 가운데(가로 폭/2, 세로 500) 기준으로 키우는 변환
	static func scaling(_ scale: Double, width: Double) -> CGAffineTransform {
		guard scale != 1 else { return .identity }
		let cx = width / 2, cy = 500.0
		return CGAffineTransform(translationX: cx, y: cy).scaledBy(x: scale, y: scale).translatedBy(x: -cx, y: -cy)
	}

	/// 이미 외곽선인 모양(채우기 원본, 폰트에 복사해 둔 모양)을 배율만큼 키운다
	static func scaled(_ path: CGPath, scale: Double, width: Double) -> CGPath {
		guard scale != 1 else { return path }
		var t = scaling(scale, width: width)
		return path.copy(using: &t) ?? path
	}

	static func pathString(_ icon: Icon, in group: IconGroup) -> String {
		PathWriter.string(path(icon, in: group))
	}

	/// 채우기 부분 + 선들을 외곽선으로 바꿔 합친다. width 가 nil 이면 선마다 원래 굵기.
	/// 그린 방향(시계/반시계)이 서로 달라도 안쪽이 지워지지 않게 도형 합집합으로 합친다
	/// transform 은 선을 긋기 전에 선 중심(과 채우기 부분)에 적용한다
	static func outline(_ icon: Icon, width: Double?, transform: CGAffineTransform = .identity) -> CGPath {
		var t = transform
		func moved(_ p: CGPath) -> CGPath { t.isIdentity ? p : (p.copy(using: &t) ?? p) }
		var result: CGPath? = icon.hasFill ? moved(SVGPath.cgPath(icon.path)).normalized(using: .winding) : nil
		for part in icon.strokes ?? [] {
			let w = width ?? part.width
			guard w > 0 else { continue }
			let o = moved(SVGPath.cgPath(part.d)).copy(strokingWithWidth: w, lineCap: cap(part.cap), lineJoin: join(part.join), miterLimit: 4)
				.normalized(using: .winding)
			result = result.map { $0.union(o, using: .winding) } ?? o
		}
		return result ?? CGMutablePath()
	}

	/// 외곽선을 d 만큼 바깥(+)·안쪽(-)으로 옮긴다
	static func offset(_ path: CGPath, by d: Double) -> CGPath {
		guard abs(d) > 0.01, !path.isEmpty else { return path }
		let band = path.copy(strokingWithWidth: abs(d) * 2, lineCap: .round, lineJoin: .round, miterLimit: 4)
		let base = path.normalized(using: .winding)
		return d < 0 ? base.subtracting(band, using: .winding) : base.union(band, using: .winding)
	}

	/// 선으로 그린 듯한 모양의 굵기 추정 (높이 1000 기준). 가는 선이면 면적 ≈ 굵기 × 둘레 / 2
	static func thickness(_ path: CGPath) -> Double? {
		let len = perimeter(path)
		guard len > 0 else { return nil }
		return 2 * area(path) / len
	}

	/// 그룹 아이콘들의 원래 굵기 (24px 기준 px, 가운데값)
	static func measureBase(_ icons: [Icon]) -> Double? {
		let sample = icons.filter { $0.baseWeight == nil && $0.hasFill }
		let step = max(1, sample.count / 150)
		var values: [Double] = []
		for i in stride(from: 0, to: sample.count, by: step) {
			if let t = thickness(SVGPath.cgPath(sample[i].path)) { values.append(t / unitsPer24px) }
		}
		guard !values.isEmpty else { return nil }
		values.sort()
		return (values[values.count / 2] * 100).rounded() / 100
	}

	// MARK: - 내부

	private static func cap(_ s: String) -> CGLineCap {
		switch s { case "round": .round; case "square": .square; default: .butt }
	}

	private static func join(_ s: String) -> CGLineJoin {
		switch s { case "round": .round; case "bevel": .bevel; default: .miter }
	}

	private static func area(_ p: CGPath) -> Double {
		let s = 400
		let box = CGRect(x: -100, y: -100, width: 1300, height: 1300)
		var px = [UInt8](repeating: 0, count: s * s)
		px.withUnsafeMutableBytes { raw in
			guard let ctx = CGContext(data: raw.baseAddress, width: s, height: s, bitsPerComponent: 8, bytesPerRow: s,
			                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
			ctx.scaleBy(x: CGFloat(s) / box.width, y: CGFloat(s) / box.height)
			ctx.translateBy(x: -box.minX, y: -box.minY)
			ctx.addPath(p)
			ctx.setFillColor(gray: 1, alpha: 1)
			ctx.fillPath()
		}
		let filled = px.reduce(0) { $0 + ($1 > 127 ? 1 : 0) }
		return Double(filled) * Double(box.width * box.height) / Double(s * s)
	}

	/// 곡선은 몇 조각으로 나눠 길이를 잰다
	private static func perimeter(_ p: CGPath) -> Double {
		var len = 0.0, last = CGPoint.zero, start = CGPoint.zero
		func to(_ q: CGPoint) { len += hypot(q.x - last.x, q.y - last.y); last = q }
		p.applyWithBlock { e in
			let el = e.pointee
			switch el.type {
			case .moveToPoint: last = el.points[0]; start = last
			case .addLineToPoint: to(el.points[0])
			case .addQuadCurveToPoint:
				let p0 = last, c = el.points[0], p1 = el.points[1]
				for i in 1...8 {
					let t = CGFloat(i) / 8, u = 1 - t
					to(CGPoint(x: u * u * p0.x + 2 * u * t * c.x + t * t * p1.x, y: u * u * p0.y + 2 * u * t * c.y + t * t * p1.y))
				}
			case .addCurveToPoint:
				let p0 = last, c1 = el.points[0], c2 = el.points[1], p1 = el.points[2]
				for i in 1...8 {
					let t = CGFloat(i) / 8, u = 1 - t
					let x = u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p1.x
					let y = u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p1.y
					to(CGPoint(x: x, y: y))
				}
			case .closeSubpath: to(start)
			@unknown default: break
			}
		}
		return len
	}
}

// MARK: - 그룹 규칙

extension IconGroup {
	/// 가져온 아이콘을 그룹 형태에 맞춰 넣는다.
	/// 선 그룹: 선이 없는 채우기 아이콘은 거부. 채우기 그룹: 선 아이콘은 원래 굵기로 채우기로 바꾸고 그 굵기를 기억한다.
	mutating func add(_ result: inout IconImport.Result) {
		var accepted: [Icon] = []
		for var icon in result.icons {
			// SVG 파일은 넣을 때 여백 맞추기 (선 SVG 는 채우기로 바꾸기 전에 선 규칙으로 맞춘다)
			if autoFit, result.svgIDs.contains(icon.id) {
				let fit = IconFit.fit(icon)
				if fit.changed { icon = fit.icon; result.fitted += 1 }
			}
			switch style {
			case .stroke:
				if icon.hasStrokes { accepted.append(icon) } else { result.rejected.append(icon.name) }
			case .fill:
				if icon.hasStrokes {
					let widths = (icon.strokes ?? []).map(\.width)
					icon.baseWeight = widths.reduce(0, +) / Double(widths.count) / unitsPer24px
					icon.path = PathWriter.string(IconShape.outline(icon, width: nil))
					icon.strokes = nil
					result.converted += 1
				}
				accepted.append(icon)
			}
		}
		// CSS 이름은 원래 코드가 있는 아이콘에만 붙인다 (자동으로 붙일 코드에 잘못 붙지 않게 먼저 한다)
		result.applyNames(to: &icons)
		result.applyNames(to: &accepted)
		// 코드가 없는 아이콘(SVG 파일 등)은 E600 부터, 그룹에서 이미 쓴 코드 다음 빈 자리를 붙인다
		var used = Set(icons.compactMap(\.code) + accepted.compactMap(\.code))
		var next: UInt32 = max(0xE600, (used.filter { (0xE000...0xF8FF).contains($0) }.max() ?? 0xE5FF) + 1)
		for i in accepted.indices where accepted[i].code == nil {
			while used.contains(next) { next += 1 }
			if next > 0xF8FF { next = 0xE000; while used.contains(next) { next += 1 } }
			accepted[i].code = next
			used.insert(next)
			result.autoCoded += 1
		}
		result.icons = accepted
		icons += accepted
		if style == .fill { baseWeight = IconShape.measureBase(icons) }
	}

	/// 선 그룹 → 채우기 그룹. 모든 선을 원래 굵기로 외곽선으로 바꾼다 (되돌릴 수 없다)
	mutating func convertToFill() {
		guard style == .stroke else { return }
		for i in icons.indices where icons[i].hasStrokes {
			let widths = (icons[i].strokes ?? []).map(\.width)
			icons[i].baseWeight = widths.reduce(0, +) / Double(widths.count) / unitsPer24px
			icons[i].path = PathWriter.string(IconShape.outline(icons[i], width: nil))
			icons[i].strokes = nil
		}
		style = .fill
		weight = nil   // 채우기 그룹은 굵기 설정이 없다
		baseWeight = IconShape.measureBase(icons)
	}

	/// 채우기 아이콘이 하나도 없을 때만 선 그룹으로 바꿀 수 있다
	var canBecomeStroke: Bool { icons.allSatisfy(\.hasStrokes) }
}
