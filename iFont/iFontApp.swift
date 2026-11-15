import SwiftUI

@main
struct iFontApp: App {
	@State private var store: Store = {
		let s = Store()
		s.load()
		// 다른 기기에서 iCloud 로 바뀐 파일이 오면 다시 읽는다
		CloudWatcher.shared.start { s.reloadIfChangedOutside() }
		return s
	}()

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(store)
				.frame(minWidth: 1000, minHeight: 640)
				.onAppear(perform: debugSetup)
				.onChange(of: store.groups) { store.save() }
				.onChange(of: store.fonts) { store.save() }
				// 앱으로 돌아올 때 앱 밖에서 고친 파일이 있으면 다시 읽는다
				.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
					store.reloadIfChangedOutside()
				}
		}
		.windowToolbarStyle(.unified)
		.commands {
			CommandGroup(after: .newItem) {
				// 앱 밖에서 폰트·그룹 파일을 고쳤을 때 다시 읽는다
				Button("모두 다시 읽기") { _ = store.reloadAll() }
					.keyboardShortcut("r")
			}
			CommandGroup(replacing: .importExport) {
				Button("불러오기…") { BackupMenu.importAll(store) }
					.keyboardShortcut("o", modifiers: [.command, .shift])
				Button("내보내기…") { BackupMenu.exportAll(store) }
					.keyboardShortcut("e", modifiers: [.command, .shift])
			}
		}
	}

	/// 개발용 환경변수
	/// - IFONT_GROUP="그룹이름=경로[|경로…]" : 같은 이름 그룹이 없으면 만들고 SVG·폰트 파일·폴더를 넣는다 (여러 그룹은 ; 로 구분)
	/// - IFONT_IMPORT=config.json 경로 : 같은 이름 폰트가 없으면 Fontello 설정으로 폰트를 가져온다
	private func debugSetup() {
		#if DEBUG
		let env = ProcessInfo.processInfo.environment
		for spec in (env["IFONT_GROUP"] ?? "").split(separator: ";") {
			let parts = spec.split(separator: "=", maxSplits: 1).map(String.init)
			guard parts.count == 2, !store.groups.contains(where: { $0.name == parts[0] }) else { continue }
			var group = store.addGroup()
			group.name = parts[0]
			let result = IconImport.load(parts[1].split(separator: "|").map { URL(fileURLWithPath: String($0)) })
			group.icons = result.icons
			if let i = store.groups.firstIndex(where: { $0.id == group.id }) { store.groups[i] = group }
			print("[iFont] 그룹 \(group.name): \(result.summary)")
		}
		if let path = env["IFONT_IMPORT"] {
			let url = URL(fileURLWithPath: path)
			let name = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["name"] as? String
			if !store.fonts.contains(where: { $0.name == name }), let (_, report) = try? store.importFontello(url) {
				print("[iFont] \(ImportReportText.text(report))")
			}
		}
		#endif
	}
}
