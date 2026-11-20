import SwiftUI
import AppKit

/// iFont 정보 창 (메뉴 iFont > iFont에 관하여). iSQL 의 정보 창과 같은 모양 (사용자 2026-11-20).
/// macOS 기본 정보 창은 글 영역이 창 가로를 꽉 채워 여백·둥근 상자를 줄 수 없어서 직접 만든다. 상자는 글 길이에 맞춘다 (스크롤 없음)
struct AboutView: View {
	static let windowID = "about"

	private var version: String {
		let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
		let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
		return "버전 \(v) (\(b))"
	}

	var body: some View {
		VStack(spacing: 0) {
			Image(nsImage: NSApp.applicationIconImage)
				.resizable()
				.frame(width: 96, height: 96)
				.padding(.top, 8)
			Text("iFont").font(.title2.bold()).padding(.top, 10)
			Text(version).font(.callout).foregroundStyle(.secondary).padding(.top, 4)
			Text("SVG 아이콘으로 아이콘 웹폰트(woff2 · css)를 만듭니다").font(.callout).foregroundStyle(.secondary).padding(.top, 2)

			VStack(alignment: .leading, spacing: 12) {
				section("기본 아이콘그룹") {
					item("Lucide (ISC)", "선 아이콘 2,052개")
					item("Tabler Icons (MIT)", "선 아이콘 5,491개")
					Text("앱에 들어 있어 고칠 수 없고 iCloud 로 동기화하지 않습니다. 이 아이콘으로 만든 폰트를 배포할 때는 각 세트의 라이선스 문구를 함께 넣으세요.")
						.foregroundStyle(.tertiary)
				}
				section("오픈소스") {
					item("Sparkle (MIT)", "자동 업데이트")
				}
				section("직접 넣는 아이콘") {
					Text("아이콘그룹에 넣는 SVG·폰트의 라이선스와 상표(로고)는 각 원본을 따릅니다.")
				}
				Button("라이선스 전문 보기…", action: openLicenses)
					.buttonStyle(.link)
			}
			.font(.caption)
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, alignment: .leading)
			.fixedSize(horizontal: false, vertical: true)
			.padding(14)
			.background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
			.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
			.clipShape(RoundedRectangle(cornerRadius: 10))
			.padding(.top, 18)

			Link("github.com/moimz/iFont", destination: URL(string: "https://github.com/moimz/iFont")!)
				.font(.caption)
				.padding(.top, 12)
		}
		.padding(.horizontal, 20)
		.padding(.bottom, 20)
		.frame(width: 360)
	}

	/// 번들의 Licenses.txt (Lucide · Tabler · Sparkle 라이선스 원문)를 텍스트 편집기로 연다
	private func openLicenses() {
		guard let url = Bundle.main.url(forResource: "Licenses", withExtension: "txt") else { return }
		NSWorkspace.shared.open(url)
	}

	private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title).fontWeight(.semibold).foregroundStyle(.primary.opacity(0.75))
			content()
		}
		.fixedSize(horizontal: false, vertical: true)
	}

	private func item(_ name: String, _ what: String) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Text("·")
			Text(name) + Text(" — " + what).foregroundStyle(.tertiary)
		}
	}
}

/// 메뉴 iFont > iFont에 관하여 (기본 정보 창 대신 AboutView)
struct AboutMenuButton: View {
	@Environment(\.openWindow) private var openWindow
	var body: some View {
		Button("iFont에 관하여") { openWindow(id: AboutView.windowID) }
	}
}
