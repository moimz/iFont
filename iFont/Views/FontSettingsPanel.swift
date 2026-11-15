import SwiftUI

/// 오른쪽 사이드 패널: 기본(이름·선 굵기·버전·크기), CSS(접두어·주석), 요약, 사용 예, 맨 아래 폰트 다운로드 버튼
struct FontSettingsPanel: View {
	@Binding var font: FontDoc
	var onExport: () -> Void = {}

	var body: some View {
		Form {
			Section("기본") {
				TextField("폰트 이름", text: $font.name)
				WeightPicker(weight: $font.weight)
				// 큰 버전만 고치고, 뒤의 아이콘 수.다음 내려받기 횟수는 회색으로
				SuffixField(suffix: ".\(font.glyphs.count).\(font.downloads + 1)") {
					TextField("버전", value: $font.version, format: .number.grouping(.never))
				}
				TextField("em 크기", value: $font.unitsPerEm, format: .number.grouping(.never))
				TextField("Ascent", value: $font.ascent, format: .number.grouping(.never))
				LabeledContent("Descent", value: "\(font.descent)")
			}
			Section("CSS") {
				TextField("접두어", text: $font.prefix)
				TextEditor(text: $font.cssHeader)
					.font(.system(.caption, design: .monospaced))
					.frame(minHeight: 70)
				// 폴더만 적으면 파일 이름(폰트 이름.css)은 내보낼 때 붙는다
				SuffixField(suffix: "/" + FontExport.fileName(font) + ".css") {
					TextField("@file", text: $font.cssFile, prompt: Text("/app/resources/fonts"))
				}
				TextField("@author", text: $font.cssAuthor)
				TextField("@license", text: $font.cssLicense)
			}
			Section("요약") {
				LabeledContent("아이콘", value: "\(font.glyphs.count)개")
				if let lo = font.glyphs.map(\.code).min(), let hi = font.glyphs.map(\.code).max() {
					LabeledContent("코드 범위", value: "\(lo.hex) – \(hi.hex)")
				}
				let dupCodes = duplicates(font.glyphs.map(\.code)).count
				let dupNames = duplicates(font.glyphs.map(\.name)).count
				if dupCodes + dupNames > 0 {
					Label("겹치는 코드 \(dupCodes) · 이름 \(dupNames)", systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(.orange)
				}
			}
			Section("사용 예") {
				let name = font.glyphs.first?.name ?? "home"
				Text("<i class=\"\(FontExport.baseClass(font)) \(font.prefix)\(name)\"></i>")
					.font(.system(.caption, design: .monospaced))
					.textSelection(.enabled)
			}
		}
		.formStyle(.grouped)
		.safeAreaInset(edge: .bottom) {
			PanelButton(title: "폰트 다운로드", systemImage: "arrow.down.circle", action: onExport)
				.disabled(font.glyphs.isEmpty)
		}
	}
}

func duplicates<T: Hashable>(_ values: [T]) -> Set<T> {
	var seen = Set<T>(), dup = Set<T>()
	for v in values where !seen.insert(v).inserted { dup.insert(v) }
	return dup
}

