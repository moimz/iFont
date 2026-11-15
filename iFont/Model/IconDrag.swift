import Foundation

/// 아이콘그룹에서 폰트로 끌어다 놓을 때 주고받는 값. "ifont-icons:<그룹 id>:<아이콘 id,…>"
enum IconDrag {
	private static let head = "ifont-icons:"

	static func encode(groupID: UUID, iconIDs: [String]) -> String {
		head + groupID.uuidString + ":" + iconIDs.joined(separator: ",")
	}

	static func decode(_ s: String) -> (groupID: UUID, iconIDs: [String])? {
		guard s.hasPrefix(head) else { return nil }
		let parts = s.dropFirst(head.count).split(separator: ":", maxSplits: 1)
		guard parts.count == 2, let id = UUID(uuidString: String(parts[0])) else { return nil }
		return (id, parts[1].split(separator: ",").map(String.init))
	}
}

/// 칸 클릭으로 고르기 (Finder 처럼)
/// - 그냥 클릭: 그것만 (이미 그것만 골랐으면 해제)
/// - ⌘ 클릭: 넣었다 뺐다
/// - ⇧ 클릭: 마지막으로 누른 칸부터 여기까지 (⌘ 도 누르면 지금 고른 것에 더한다)
enum ClickSelect {
	static func click(_ id: String, order: [String], selected: inout Set<String>, anchor: inout String?, command: Bool, shift: Bool) {
		if shift, let a = anchor, let from = order.firstIndex(of: a), let to = order.firstIndex(of: id) {
			let range = Set(order[min(from, to)...max(from, to)])
			selected = command ? selected.union(range) : range
			return   // 기준 칸은 그대로 둬서 ⇧ 로 범위를 다시 고를 수 있게
		}
		if command {
			if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
		} else {
			selected = selected == [id] ? [] : [id]
		}
		anchor = id
	}
}
