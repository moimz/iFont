import SwiftUI

/// 아이콘 모양 하나를 칸 안에 맞춰 그린다.
/// 크기는 폭 width, 높이 unitsPerEm 의 글자 칸 기준으로 맞춰서 아이콘끼리 크기가 같게 보인다.
/// - 보통: 실제 모양의 가운데를 칸 가운데에 둔다 (폰트마다 기준선 위치가 달라 칸 기준이면 위아래로 쏠린다)
/// - 칸 보기(showBox): 글자 칸을 그대로 놓아 여백이 정확히 보이게 한다
struct GlyphShape: Shape {
	var shape: CGPath
	var width: Double
	var em: Double = 1000
	var fitBox = false

	func path(in rect: CGRect) -> Path {
		guard let t = Self.transform(shape: shape, width: width, em: em, fitBox: fitBox, in: rect),
		      let p = shape.copy(using: [t]) else { return Path() }
		return Path(p)
	}

	/// 칸 좌표(폭 width, 높이 em) → 화면 좌표 변환. 칸 보기일 때는 칸을 화면 가운데에 그대로 둔다
	static func transform(shape: CGPath, width: Double, em: Double, fitBox: Bool, in rect: CGRect) -> CGAffineTransform? {
		let box = CGSize(width: max(width, 1), height: em)
		let bounds = shape.boundingBoxOfPath
		guard !bounds.isNull, !bounds.isEmpty else { return nil }
		if fitBox {
			let scale = min(rect.width / box.width, rect.height / box.height)
			return CGAffineTransform(translationX: rect.midX - box.width / 2 * scale, y: rect.midY - box.height / 2 * scale)
				.scaledBy(x: scale, y: scale)
		}
		// 모양이 글자 칸보다 크면 모양 기준으로 줄인다
		let scale = min(rect.width / max(box.width, bounds.width), rect.height / max(box.height, bounds.height))
		return CGAffineTransform(translationX: rect.midX - bounds.midX * scale, y: rect.midY - bounds.midY * scale)
			.scaledBy(x: scale, y: scale)
	}
}

private extension CGPath {
	func copy(using transforms: [CGAffineTransform]) -> CGPath? {
		var t = transforms[0]
		return copy(using: &t)
	}
}

struct GlyphView: View {
	var shape: CGPath
	var width: Double
	var em: Double = 1000
	/// 아이콘만 돌릴 각도 (애니메이션). 칸·여백 표시는 그대로 둔다
	var rotation: Angle = .zero
	/// 도구 막대 설정과 상관없이 칸·여백을 보여 준다 (여백 맞추기 비교용)
	var alwaysBox = false
	/// 칸·여백 보기 (도구 막대에서 켜고 끈다)
	@AppStorage("showEmBox") private var showBox = false

	init(shape: CGPath, width: Double, em: Double = 1000, rotation: Angle = .zero, alwaysBox: Bool = false) {
		self.shape = shape
		self.width = width
		self.em = em
		self.rotation = rotation
		self.alwaysBox = alwaysBox
	}

	init(path: String, width: Double, em: Double = 1000) {
		self.init(shape: SVGPath.cgPath(path), width: width, em: em)
	}

	var body: some View {
		ZStack {
			if showBox || alwaysBox {
				GeometryReader { geo in
					let rect = CGRect(origin: .zero, size: geo.size)
					let box = CGSize(width: max(width, 1), height: em)
					let scale = min(rect.width / box.width, rect.height / box.height)
					let w = box.width * scale, h = box.height * scale
					let x = rect.midX - w / 2, y = rect.midY - h / 2
					// 24px 기준 1px = 칸 높이의 1/24
					let unit = h / 24
					ZStack(alignment: .topLeading) {
						Rectangle()
							.fill(Color.accentColor.opacity(0.18))
							.frame(width: w, height: h)
							.offset(x: x, y: y)
						// 1px 한계선: 선 바깥이 넘으면 안 되는 곳 (선 중심 2px 에 2px 선이면 여기까지 닿는다)
						Rectangle()
							.strokeBorder(Color.red.opacity(0.45), lineWidth: 0.5)
							.frame(width: w - unit * 2, height: h - unit * 2)
							.offset(x: x + unit, y: y + unit)
						// 2px 선: 선 중심이 넘으면 안 되는 곳. 보통 아이콘(선 중심 3px)은 선 바깥이 여기에 닿는다
						Rectangle()
							.strokeBorder(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
							.frame(width: w - unit * 4, height: h - unit * 4)
							.offset(x: x + unit * 2, y: y + unit * 2)
					}
				}
			}
			GlyphShape(shape: shape, width: width, em: em, fitBox: showBox || alwaysBox)
				.fill(style: FillStyle(eoFill: false))
				.rotationEffect(rotation)
		}
	}
}
