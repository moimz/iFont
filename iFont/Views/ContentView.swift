import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
	/// 모든 폰트·아이콘그룹에서 찾기
	case search
	case font(UUID)
	case group(UUID)
}

struct ContentView: View {
	@Environment(Store.self) private var store
	@State private var selection: SidebarItem?
	@State private var importingConfig = false
	@State private var message: (title: String, text: String)?

	var body: some View {
		NavigationSplitView {
			SidebarView(selection: $selection)
				.navigationSplitViewColumnWidth(min: 200, ideal: 230)
				.toolbar {
					ToolbarItem {
						Menu {
							Button("폰트 추가") { selection = .font(store.addFont().id) }
							Button("아이콘그룹 추가") { selection = .group(store.addGroup().id) }
							Divider()
							Button("Fontello 설정으로 폰트 가져오기…") { importingConfig = true }
						} label: {
							Label("추가", systemImage: "plus")
						}
						.menuIndicator(.hidden)
						.help("폰트 또는 아이콘그룹 추가")
					}
				}
		} detail: {
			switch selection {
			case .font(let id):
				if let index = store.fonts.firstIndex(where: { $0.id == id }) {
					FontEditorView(font: Bindable(store).fonts[index], selection: $selection)
						.id(id)
				}
			case .group(let id):
				if let index = store.groups.firstIndex(where: { $0.id == id }) {
					IconGroupView(group: Bindable(store).groups[index], selection: $selection)
						.id(id)
				}
			case .search:
				GlobalSearchView(selection: $selection)
			case nil:
				EmptyStateView(selection: $selection)
			}
		}
		.onChange(of: store.fonts.count, initial: true) {
			#if DEBUG
			// 개발용: IFONT_SHOW=<그룹 이름> 이면 그 그룹을 열고 시작
			if selection == nil, let name = ProcessInfo.processInfo.environment["IFONT_SHOW"],
			   let g = store.groups.first(where: { $0.name == name }) { selection = .group(g.id) }
			#endif
			if selection == nil, let first = store.fonts.first { selection = .font(first.id) }
		}
		.fileImporter(isPresented: $importingConfig, allowedContentTypes: [.json]) { result in
			guard case .success(let url) = result else { return }
			let access = url.startAccessingSecurityScopedResource()
			defer { if access { url.stopAccessingSecurityScopedResource() } }
			do {
				let (font, report) = try store.importFontello(url)
				selection = .font(font.id)
				message = ("\(report.fontName) 폰트를 가져왔습니다", ImportReportText.text(report))
			} catch {
				message = ("가져오지 못했습니다", error.localizedDescription)
			}
		}
		.alert(message?.title ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
			Button("확인") {}
		} message: {
			Text(message?.text ?? "")
		}
	}
}

/// 아무것도 고르지 않았을 때 (처음 실행 포함)
struct EmptyStateView: View {
	@Environment(Store.self) private var store
	@Binding var selection: SidebarItem?

	var body: some View {
		ContentUnavailableView {
			Label(store.groups.isEmpty ? "아이콘그룹이 없습니다" : "폰트를 고르세요", systemImage: "textformat.abc")
		} description: {
			Text(store.groups.isEmpty
			     ? "먼저 아이콘그룹을 만들고 SVG 나 폰트 파일로 아이콘을 넣으세요."
			     : "왼쪽에서 폰트를 고르거나 새 폰트를 추가하세요.")
		} actions: {
			HStack {
				Button("아이콘그룹 추가") { selection = .group(store.addGroup().id) }
				Button("폰트 추가") { selection = .font(store.addFont().id) }
					.buttonStyle(.borderedProminent)
			}
		}
	}
}
