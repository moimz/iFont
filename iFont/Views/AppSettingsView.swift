import SwiftUI

/// iFont 앱 설정 (⌘,): 지금은 업데이트 칸만
struct AppSettingsView: View {
	private var version: String {
		let info = Bundle.main.infoDictionary
		let v = info?["CFBundleShortVersionString"] as? String ?? "?"
		let b = info?["CFBundleVersion"] as? String ?? "?"
		return "\(v) (\(b))"
	}

	var body: some View {
		Form {
			UpdateSection(version: version)
		}
		.formStyle(.grouped)
		.frame(width: 440)
		.fixedSize(horizontal: false, vertical: true)
	}
}

/// 앱 설정 > 업데이트: 버전 · 업데이트 확인 · 자동 확인 켜고 끄기 (Ai/devid/자동업데이트.md, iSQL 과 같은 칸)
private struct UpdateSection: View {
	let version: String
	@Bindable private var updater = Updater.shared

	var body: some View {
		Section {
			LabeledContent("버전") {
				HStack(spacing: 8) {
					Text(version).foregroundStyle(.secondary).monospacedDigit()
					Button("업데이트 확인…") { updater.checkForUpdates() }.disabled(!updater.canCheck)
				}
			}
			Toggle("자동으로 업데이트 확인", isOn: $updater.automaticallyChecks)
		} header: {
			Text("업데이트")
		} footer: {
			Text("하루에 한 번 새 버전이 있는지 확인하고, 있으면 설치할지 묻습니다.").foregroundStyle(.tertiary)
		}
	}
}

/// 메뉴 iFont > 업데이트 확인… (확인 중에는 흐리게)
struct UpdateMenuButton: View {
	private var updater = Updater.shared
	var body: some View {
		Button("업데이트 확인…") { updater.checkForUpdates() }
			.disabled(!updater.canCheck)
	}
}
