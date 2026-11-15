import CoreGraphics
import Foundation

/// 아이콘을 24px 칸 규칙(채우기는 모양 바깥, 선은 선 중심이 2–22px 안)에 맞춘다.
/// 아이콘 세트가 일부러 정한 크기·위치(작은 dot, 한쪽에 둔 signal·user-plus 등)는 지키고, 넘친 것만 고친다. 비율은 늘 그대로.
/// - 크기: 20px 를 넘으면 20px 로 줄인다. 작은 아이콘은 키우지 않는다 (일부러 작은 것과 구분할 수 없어서)
/// - 위치: 줄였거나 2–22px 밖으로 나가 있으면 가운데로. 안에 있으면 그대로
/// - 선 굵기: 2px
/// 눈에 보이는 크기 보정(원은 조금 크게 등)이나 픽셀 맞춤은 하지 않는다
enum IconFit {
	/// 선 굵기 (px)
	static let strokeWidth = 2.0
	/// 넘으면 안 되는 크기 (px)
	static let limit = 20.0
	/// 이만큼(px)은 넘쳐도 봐준다 (곡선 계산 오차)
	static let tolerance = 0.2

	struct Result {
		var icon: Icon
		/// 맞추기 전·후 크기 (px, 폭×높이: 채우기는 모양 바깥, 선은 선 중심)
		var before: CGSize
		var after: CGSize
		/// 0.1px 넘게 바뀌었는지
		var changed: Bool
	}

	static func fit(_ icon: Icon) -> Result {
		let u = unitsPer24px

		// 선 아이콘은 선 중심(+채우기 부분), 채우기 아이콘은 모양 바깥으로 잰다
		let parts: [CGPath] = (icon.hasFill ? [SVGPath.cgPath(icon.path)] : []) + (icon.strokes ?? []).map { SVGPath.cgPath($0.d) }
		let b = parts.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
		guard !b.isNull, max(b.width, b.height) > 0 else {
			return Result(icon: icon, before: .zero, after: .zero, changed: false)
		}
		let long = max(b.width, b.height)
		let k: CGFloat = long > (limit + tolerance) * u ? limit * u / long : 1
		// 줄였거나 2–22px 밖으로 나가 있으면 칸 가운데로, 아니면 제자리
		let lo = (2 - tolerance) * u, hi = (22 + tolerance) * u
		let out = b.minX < lo || b.maxX > hi || b.minY < lo || b.maxY > hi
		let center = k != 1 || out ? CGPoint(x: 500, y: 500) : CGPoint(x: b.midX, y: b.midY)
		var t = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: k, y: k).translatedBy(x: -b.midX, y: -b.midY)

		var result = icon
		if icon.hasFill { result.path = SVGPath.cgPath(icon.path).copy(using: &t).map(PathWriter.string) ?? icon.path }
		if let strokes = icon.strokes {
			result.strokes = strokes.map { s in
				var s = s
				s.d = SVGPath.cgPath(s.d).copy(using: &t).map(PathWriter.string) ?? s.d
				s.width = strokeWidth * u
				return s
			}
		}
		result.width = 1000

		let before = CGSize(width: b.width / u, height: b.height / u)
		let after = CGSize(width: b.width * k / u, height: b.height * k / u)
		let moved = abs(center.x - b.midX) > 0.1 * u || abs(center.y - b.midY) > 0.1 * u
		let resized = k != 1
		let widthChanged = abs(icon.width - 1000) > 0.5
			|| (icon.strokes ?? []).contains { abs($0.width - strokeWidth * u) > 0.1 * u }
		return Result(icon: result, before: before, after: after, changed: moved || resized || widthChanged)
	}
}
