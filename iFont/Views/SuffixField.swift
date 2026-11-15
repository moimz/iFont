import AppKit
import SwiftUI

/// 설정 줄 입력칸 오른쪽에 고칠 수 없는 회색 글자를 붙인다 (예: 5 + ".339.3", 1.6 + "px", /app/fonts + "/moimz.css").
/// 다른 줄과 똑같은 입력칸을 그대로 쓰고, 칸 끝을 뒷글자 폭만큼 당긴 뒤 그 자리에 글자 기준선을 맞춰 그린다
struct SuffixField<Field: View>: View {
	var suffix: String
	@ViewBuilder var field: Field

	var body: some View {
		let w = suffix.isEmpty ? 0 : Self.width(suffix)
		field
			.padding(.trailing, w)
			.overlay(alignment: Alignment(horizontal: .trailing, vertical: .lastTextBaseline)) {
				Text(suffix)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.fixedSize()
					.allowsHitTesting(false)
			}
	}

	/// 설정 화면 본문 글꼴(시스템 13pt)로 잰 폭
	static func width(_ s: String) -> CGFloat {
		ceil((s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width)
	}
}
