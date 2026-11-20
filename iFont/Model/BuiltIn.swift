import Foundation

/// 앱에 기본으로 들어 있는 아이콘그룹 (Lucide · Tabler, 사용자 2026-11-20).
/// 앱 번들의 `<그룹 id>.json` 에서 읽고, 저장·iCloud 동기화·백업에서 뺀다. 화면에서는 자물쇠를 달고 고치지 못하게 한다.
/// id 는 iCloud 에 있던 그룹 그대로라, 그 원본을 쓰던 폰트 아이콘(moimz 의 Lucide 원본 등)이 계속 이어진다.
/// 라이선스 원문은 번들의 Licenses.txt (앱 정보 창에서 연다)
enum BuiltInGroups {
	static let lucide = UUID(uuidString: "49D15ECA-DDCB-499A-8B66-3CC1C0F3C4D9")!
	static let tabler = UUID(uuidString: "6ACB54AA-8CBE-4B12-B4F3-075B25103073")!
	/// 보여 주는 순서
	static let order = [lucide, tabler]
	static let ids = Set(order)

	/// 그룹마다 라이선스 (그룹 설정 패널에 보여 준다)
	static func license(_ id: UUID) -> String? {
		switch id {
		case lucide: "ISC License · lucide.dev"
		case tabler: "MIT License · tabler.io/icons"
		default: nil
		}
	}

	/// 기본 그룹들을 읽는다. folder 를 주면 그 폴더에서(앱 밖 도구용: 소스의 iFont/BuiltIn), 아니면 앱 번들에서
	static func load(from folder: URL? = nil) -> [IconGroup] {
		order.compactMap { id in
			let url = folder?.appendingPathComponent(id.uuidString + ".json")
				?? Bundle.main.url(forResource: id.uuidString, withExtension: "json")
			guard let url, let data = try? Data(contentsOf: url) else { return nil }
			return try? JSONDecoder().decode(IconGroup.self, from: data)
		}
	}
}

extension IconGroup {
	/// 앱에 기본으로 들어 있는 그룹 (고칠 수 없고 저장·동기화하지 않는다)
	var isBuiltIn: Bool { BuiltInGroups.ids.contains(id) }
}
