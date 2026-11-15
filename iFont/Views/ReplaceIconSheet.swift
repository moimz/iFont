import SwiftUI

/// 폰트 아이콘 하나의 모양을 다른 아이콘으로 바꾸는 시트.
/// 왼쪽에서 아이콘그룹을 고르고 오른쪽에서 아이콘을 고른다. 폰트 아이콘은 언제나 아이콘그룹의 원본을 쓴다
/// (새 SVG 는 아이콘그룹에 먼저 넣는다).
/// 이름·코드·폰트 안 그룹은 그대로 두고 모양만 바꾼다.
struct ReplaceIconSheet: View {
	@Environment(Store.self) private var store
	@Environment(\.dismiss) private var dismiss
	var font: FontDoc
	var glyph: FontGlyph

	@State private var groupID: UUID?
	@State private var chosen: String?
	@State private var search = ""

	private let columns = [GridItem(.adaptive(minimum: 96, maximum: 96), spacing: 6)]

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()
			HStack(spacing: 0) {
				List(selection: $groupID) {
					ForEach(store.groups) { g in
						HStack {
							Text(g.name)
							Spacer()
							Text("\(g.icons.count)").foregroundStyle(.secondary).monospacedDigit()
						}
						.tag(g.id)
					}
				}
				.listStyle(.sidebar)
				.frame(width: 200)
				Divider()
				iconGrid
			}
			Divider()
			footer
		}
		.frame(width: 960, height: 640)
		.onAppear {
			// 지금 원본의 그룹·아이콘을 먼저 보여 준다
			groupID = glyph.groupID
		}
		.onChange(of: groupID) { chosen = nil }
	}

	private var group: IconGroup? { store.group(groupID) }

	private var header: some View {
		HStack(spacing: 16) {
			// 지금 모양 → 고른 모양
			preview(SVGPath.cgPath(glyph.path), width: glyph.width, caption: "지금")
			Image(systemName: "arrow.right").foregroundStyle(.secondary)
			if let group, let id = chosen, let icon = group.icons.first(where: { $0.id == id }) {
				preview(IconShape.path(icon, in: group), width: icon.width, caption: group.prefix + icon.name)
			} else {
				preview(nil, width: 1000, caption: "고르세요")
			}
			VStack(alignment: .leading, spacing: 2) {
				Text("아이콘 대치").font(.headline)
				Text("\(font.prefix + glyph.name)  \(glyph.code.cssEscape) — 이름·코드는 그대로 두고 모양만 바꿉니다.")
					.font(.callout).foregroundStyle(.secondary)
			}
			Spacer()
			TextField("이름, 키워드, \\e600 검색", text: $search)
				.textFieldStyle(.roundedBorder)
				.frame(width: 220)
		}
		.padding(16)
	}

	private func preview(_ shape: CGPath?, width: Double, caption: String) -> some View {
		VStack(spacing: 4) {
			Group {
				if let shape {
					GlyphView(shape: shape, width: width, em: Double(font.unitsPerEm))
				} else {
					Image(systemName: "questionmark").foregroundStyle(.tertiary)
				}
			}
			.frame(width: 40, height: 40)
			.padding(8)
			.background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
			Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 110)
		}
	}

	@ViewBuilder
	private var iconGrid: some View {
		if let group {
			let icons = group.icons.filter { $0.matches(search, prefix: group.prefix) }
			ScrollViewReader { proxy in
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
						ForEach(group.sections(icons), id: \.category) { section in
							Section {
								LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
									ForEach(section.icons) { icon in
										cell(icon, in: group)
											.id(icon.id)
									}
								}
								.padding(.horizontal, 12)
								.padding(.vertical, 6)
							} header: {
								if !group.categories.isEmpty {
									Text(section.category ?? "분류 없음")
										.font(.subheadline.weight(.semibold))
										.foregroundStyle(.secondary)
										.frame(maxWidth: .infinity, alignment: .leading)
										.padding(.horizontal, 12).padding(.vertical, 6)
										.background(.bar)
								}
							}
						}
					}
					.padding(.bottom, 12)
				}
				.onAppear {
					// 지금 원본이 있는 그룹이면 그 아이콘으로 스크롤
					if group.id == glyph.groupID, case let iid = glyph.iconID {
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(iid, anchor: .center) }
					}
				}
			}
			.id(group.id)
		} else {
			ContentUnavailableView("아이콘그룹을 고르세요", systemImage: "square.grid.3x3")
		}
	}

	private func cell(_ icon: Icon, in group: IconGroup) -> some View {
		let isChosen = chosen == icon.id
		let isCurrent = group.id == glyph.groupID && icon.id == glyph.iconID
		return VStack(spacing: 6) {
			GlyphView(shape: IconShape.path(icon, in: group), width: icon.width)
				.frame(width: 32, height: 32)
				.foregroundStyle(isChosen ? Color.white : Color.primary)
			Text(group.prefix + icon.name)
				.font(.system(size: 10))
				.lineLimit(1).truncationMode(.middle)
				.foregroundStyle(isChosen ? Color.white.opacity(0.9) : Color.secondary)
		}
		.padding(6)
		.frame(width: 96, height: 80)
		.background(isChosen ? Color.accentColor : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
		.overlay {
			// 지금 쓰고 있는 원본은 테두리로 표시
			if isCurrent { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2) }
		}
		.contentShape(.rect)
		.onTapGesture(count: 2) { apply(icon.id) }
		.onTapGesture { chosen = icon.id }
		.help((group.prefix + icon.name) + ((icon.tags ?? []).isEmpty ? "" : "\n키워드: " + (icon.tags ?? []).joined(separator: ", ")))
	}

	private var footer: some View {
		HStack {
			Text("아이콘을 두 번 누르면 바로 대치합니다.").font(.caption).foregroundStyle(.secondary)
			Spacer()
			Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
			Button("대치") { if let chosen { apply(chosen) } }
				.keyboardShortcut(.defaultAction)
				.disabled(chosen == nil)
		}
		.padding(16)
	}

	private func apply(_ iconID: String) {
		guard let groupID else { return }
		store.replace(glyph.id, in: font.id, with: iconID, from: groupID)
		dismiss()
	}
}
