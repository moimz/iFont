import AppKit
import SwiftUI

/// 아이콘 칸 아래에 무엇을 보여 줄지
enum LabelMode: String {
	case name, code
}

/// 도구 막대의 "CSS 이름 / 유니코드" 전환
struct LabelModePicker: View {
	@AppStorage("labelMode") private var mode: LabelMode = .name

	var body: some View {
		Picker("표시", selection: $mode) {
			Image(systemName: "tag").help("아이콘명 보기").tag(LabelMode.name)
			Image(systemName: "number").help("유니코드 보기").tag(LabelMode.code)
		}
		.pickerStyle(.segmented)
		.fixedSize()
	}
}

/// 도구 막대의 "칸·여백 보기" 켜고 끄기
struct EmBoxToggle: View {
	@AppStorage("showEmBox") private var showBox = false

	var body: some View {
		Toggle(isOn: $showBox) {
			Label("칸·여백 보기", systemImage: "square.dashed")
		}
		.toggleStyle(.button)
		.help(showBox ? "칸·여백 숨기기" : "24px 칸과 2px 여백선 보기")
	}
}

/// 아이콘 칸 하나. 마우스를 올리면 오른쪽 위에 복사 버튼이 나온다.
struct IconCell: View {
	static let size: CGFloat = 134
	/// 칸 안 아이콘 크기
	/// 24px 의 2배. 칸·여백 보기에서 1px 이 2pt 로 또렷하게 보인다
	static let glyph: CGFloat = 48

	var shape: CGPath
	var width: Double
	var em: Double = 1000
	/// 칸 아래 글자 (CSS 이름 또는 \e102)
	var label: String
	/// 복사할 값. nil 이면 복사 버튼을 숨긴다
	var copyValue: String?
	var selected = false
	var monospaced = false
	/// 마우스를 올렸을 때 보여 줄 설명 (키워드 등). nil 이면 label
	var tooltip: String? = nil
	/// 복사 버튼을 누르면 할 일 (있으면 copyValue 대신. 예: 선 굵기 적용 SVG 복사)
	var copyAction: (() -> Void)? = nil
	var copyHelp: String? = nil

	@State private var hovering = false
	@State private var copied = false

	var body: some View {
		// 아이콘은 칸 가운데, 글자는 아이콘 아래 끝과 칸 아래 끝의 가운데.
		// 정확히 가운데에 두면 아래 글자 때문에 처져 보여서 아이콘을 조금 올린다.
		let glyph = Self.glyph
		let glyphY = Self.size / 2 - 7
		ZStack {
			GlyphView(shape: shape, width: width, em: em)
				.frame(width: glyph, height: glyph)
				.foregroundStyle(selected ? Color.white : Color.primary)
				.position(x: Self.size / 2, y: glyphY)
			Text(label)
				.font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
				.lineLimit(1)
				.truncationMode(.middle)
				.foregroundStyle(selected ? Color.white.opacity(0.95) : Color.secondary)
				.frame(width: Self.size - 12)
				.position(x: Self.size / 2, y: (glyphY + glyph / 2 + Self.size) / 2)
		}
		.frame(width: Self.size, height: Self.size)
		.background(selected ? Color.accentColor : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 10))
		.overlay(alignment: .topTrailing) {
			if copyValue != nil || copyAction != nil, hovering || copied {
				Button {
					if let copyAction { copyAction() } else if let copyValue {
						NSPasteboard.general.clearContents()
						NSPasteboard.general.setString(copyValue, forType: .string)
					}
					copied = true
					Task {
						try? await Task.sleep(for: .seconds(1.2))
						copied = false
					}
				} label: {
					Image(systemName: copied ? "checkmark" : "doc.on.doc")
						.font(.system(size: 11, weight: .semibold))
						.frame(width: 22, height: 22)
						.background(.regularMaterial, in: .circle)
				}
				.buttonStyle(.plain)
				.help(copyHelp ?? "\(copyValue ?? "") 복사")
				.padding(5)
			}
		}
		.contentShape(.rect)
		.onHover { hovering = $0 }
		.help(tooltip ?? label)
	}
}
