import SwiftUI

/// 고른 아이콘의 여백을 24px 칸 규칙에 맞추기 전·후를 나란히 보여 주고, 체크한 것만 바꾼다
struct FitIconsSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(Store.self) private var store
	@Binding var group: IconGroup
	var ids: Set<String>

	@State private var items: [Item] = []
	@State private var checked: Set<String> = []
	@State private var loading = true

	struct Item: Identifiable {
		var id: String { before.id }
		var before: Icon
		var fit: IconFit.Result
	}

	private let columns = [GridItem(.adaptive(minimum: 230, maximum: 260), spacing: 10)]

	var body: some View {
		VStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 4) {
				Text("여백 맞추기").font(.headline)
				Text("넘친 것만 고칩니다. \(items.contains { $0.before.hasStrokes } ? "선 중심이" : "모양이") 2–22px(20px)를 넘으면 비율 그대로 20px 로 줄여 가운데에 놓고, 칸 밖으로 나가 있으면 가운데로 옮깁니다\(items.contains { $0.before.hasStrokes } ? ". 선 굵기는 2px 로 맞춥니다" : ""). 작은 아이콘은 일부러 작게 그린 것일 수 있어 키우지 않습니다.")
					.font(.callout).foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding()

			Divider()
			if loading {
				ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if items.isEmpty {
				ContentUnavailableView("바꿀 아이콘이 없습니다", systemImage: "checkmark.circle", description: Text("고른 아이콘이 모두 이미 규칙에 맞습니다."))
			} else {
				ScrollView {
					LazyVGrid(columns: columns, spacing: 10) {
						ForEach(items) { item in card(item) }
					}
					.padding()
				}
			}
			Divider()

			HStack {
				let same = ids.count - items.count
				Text(loading ? "" : "바뀌는 아이콘 \(items.count)개" + (same > 0 ? " · 이미 맞는 아이콘 \(same)개" : ""))
					.foregroundStyle(.secondary)
				if !items.isEmpty {
					Button(checked.count == items.count ? "모두 빼기" : "모두 고르기") {
						checked = checked.count == items.count ? [] : Set(items.map(\.id))
					}
					.buttonStyle(.link)
				}
				Spacer()
				Button("취소", role: .cancel) { dismiss() }
					.keyboardShortcut(.cancelAction)
				Button("\(checked.count)개 바꾸기") { apply() }
					.keyboardShortcut(.defaultAction)
					.disabled(checked.isEmpty)
			}
			.padding()
			if usedInFonts > 0 {
				Text("이 중 \(usedInFonts)개는 폰트에서 쓰고 있습니다. 폰트 아이콘은 그대로이므로, 폰트 화면에서 직접 바꿔 넣으세요.")
					.font(.caption).foregroundStyle(.orange)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding([.horizontal, .bottom])
			}
		}
		.frame(minWidth: 620, idealWidth: 820, minHeight: 480, idealHeight: 640)
		.task {
			let icons = group.icons.filter { ids.contains($0.id) }
			let result = await Task.detached { icons.map { Item(before: $0, fit: IconFit.fit($0)) }.filter(\.fit.changed) }.value
			items = result
			checked = Set(result.map(\.id))
			loading = false
		}
	}

	private var usedInFonts: Int {
		let used = Set(store.fonts.flatMap { $0.glyphs.filter { $0.groupID == group.id }.map(\.iconID) })
		return checked.filter(used.contains).count
	}

	private func card(_ item: Item) -> some View {
		let on = checked.contains(item.id)
		return VStack(spacing: 6) {
			HStack(spacing: 6) {
				preview(item.before, label: "전")
				Image(systemName: "arrow.right").foregroundStyle(.secondary)
				preview(item.fit.icon, label: "후")
			}
			HStack(spacing: 4) {
				Image(systemName: on ? "checkmark.circle.fill" : "circle")
					.foregroundStyle(on ? Color.accentColor : .secondary)
				Text(group.prefix + item.before.name).lineLimit(1).truncationMode(.middle)
			}
			.font(.callout)
			Text("\(size(item.fit.before)) → \(size(item.fit.after))")
				.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
		}
		.padding(10)
		.frame(maxWidth: .infinity)
		.background(on ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 10))
		.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1.5))
		.contentShape(.rect)
		.onTapGesture {
			if on { checked.remove(item.id) } else { checked.insert(item.id) }
		}
	}

	private func preview(_ icon: Icon, label: String) -> some View {
		VStack(spacing: 2) {
			GlyphView(shape: IconShape.original(icon), width: icon.width, alwaysBox: true)
				.frame(width: 84, height: 84)
			Text(label).font(.caption2).foregroundStyle(.secondary)
		}
	}

	private func size(_ s: CGSize) -> String {
		let f = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
		return "\(Double(s.width).formatted(f))×\(Double(s.height).formatted(f))px"
	}

	private func apply() {
		let fitted = Dictionary(uniqueKeysWithValues: items.filter { checked.contains($0.id) }.map { ($0.id, $0.fit.icon) })
		for i in group.icons.indices {
			if let icon = fitted[group.icons[i].id] { group.icons[i] = icon }
		}
		dismiss()
	}
}
