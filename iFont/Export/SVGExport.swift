import AppKit
import UniformTypeIdentifiers

/// 아이콘을 24×24 SVG 로 내려받는다. 하나면 .svg, 여러 개면 .zip
/// 선 아이콘은 선(stroke) 그대로, 굵기 설정을 적용해서 쓴다. 채우기 아이콘은 채우기 모양 그대로
enum SVGExport {
	struct Item {
		var name: String
		var svg: String
	}

	/// 아이콘 하나의 SVG. weight 는 24px 기준 px, nil 이면 선마다 원래 굵기
	static func svg(_ icon: Icon, weight: Double?) -> String {
		let w = max(icon.width, 1)
		var body = ""
		if icon.hasFill { body += "  <path d=\"\(icon.path)\" fill=\"currentColor\"/>\n" }
		for part in icon.strokes ?? [] {
			let sw = weight.map { $0 * unitsPer24px } ?? part.width
			body += "  <path d=\"\(part.d)\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"\(num(sw))\" stroke-linecap=\"\(part.cap)\" stroke-linejoin=\"\(part.join)\"/>\n"
		}
		return svg(width: w, body: body)
	}

	/// 채우기 모양 하나의 SVG (폰트에 복사해 둔 모양 등)
	static func svg(path: String, width: Double) -> String {
		svg(width: max(width, 1), body: "  <path d=\"\(path)\" fill=\"currentColor\"/>\n")
	}

	private static func svg(width: Double, body: String) -> String {
		let px = num(width / 1000 * 24)
		return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(px)\" height=\"24\" viewBox=\"0 0 \(num(width)) 1000\">\n\(body)</svg>\n"
	}

	private static func num(_ v: Double) -> String {
		let r = (v * 100).rounded() / 100
		return r == r.rounded() ? String(Int(r)) : String(r)
	}

	/// SVG 를 클립보드에 넣는다. 글자로도, SVG 그림(public.svg-image)으로도 붙여 넣을 수 있게 (여러 개면 빈 줄로 이어 글자로만)
	@MainActor
	static func copy(_ svgs: [String]) {
		guard !svgs.isEmpty else { return }
		let pb = NSPasteboard.general
		pb.clearContents()
		pb.setString(svgs.joined(separator: "\n"), forType: .string)
		if svgs.count == 1 { pb.setData(Data(svgs[0].utf8), forType: NSPasteboard.PasteboardType("public.svg-image")) }
	}

	/// ⌘C 용: 글자 + (하나면) SVG 그림
	static func providers(_ svgs: [String]) -> [NSItemProvider] {
		guard !svgs.isEmpty else { return [] }
		let p = NSItemProvider(object: svgs.joined(separator: "\n") as NSString)
		if svgs.count == 1 {
			let data = Data(svgs[0].utf8)
			p.registerDataRepresentation(forTypeIdentifier: "public.svg-image", visibility: .all) { done in done(data, nil); return nil }
		}
		return [p]
	}

	/// 저장 창을 띄워 내려받는다. zipName 은 여러 개일 때 압축 파일 이름(확장자 빼고)
	@MainActor
	static func save(_ items: [Item], zipName: String) {
		guard !items.isEmpty else { return }
		let panel = NSSavePanel()
		panel.canCreateDirectories = true
		if items.count == 1 {
			panel.allowedContentTypes = [.svg]
			panel.nameFieldStringValue = safe(items[0].name) + ".svg"
		} else {
			panel.allowedContentTypes = [.zip]
			panel.nameFieldStringValue = safe(zipName) + ".zip"
			panel.message = "SVG \(items.count)개를 압축 파일 하나로 내려받습니다."
		}
		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			if items.count == 1 {
				try Data(items[0].svg.utf8).write(to: url, options: .atomic)
			} else {
				try zip(items, folderName: url.deletingPathExtension().lastPathComponent, to: url)
			}
			NSWorkspace.shared.activateFileViewerSelecting([url])
		} catch {
			let a = NSAlert()
			a.messageText = "내려받지 못했습니다"
			a.informativeText = error.localizedDescription
			a.runModal()
		}
	}

	/// 임시 폴더에 SVG 들을 쓰고 ditto 로 압축한다 (안쪽 폴더 없이 SVG 만: 한글 폴더 이름이 윈도우에서 깨지지 않게). 이름이 겹치면 -2, -3 을 붙인다
	static func zip(_ items: [Item], folderName: String, to url: URL) throws {
		let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		let dir = tmp.appendingPathComponent(safe(folderName))
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: tmp) }
		var used = Set<String>()
		for item in items {
			var name = safe(item.name), n = 2
			while used.contains(name.lowercased()) { name = safe(item.name) + "-\(n)"; n += 1 }
			used.insert(name.lowercased())
			try Data(item.svg.utf8).write(to: dir.appendingPathComponent(name + ".svg"))
		}
		try? FileManager.default.removeItem(at: url)
		let p = Process()
		p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
		p.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noacl", dir.path, url.path]
		try p.run()
		p.waitUntilExit()
		guard p.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
	}

	private static func safe(_ s: String) -> String {
		let bad = CharacterSet(charactersIn: "/:\\")
		let r = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
		return r.isEmpty ? "icon" : r
	}
}
