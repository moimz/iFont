import Foundation

/// 폰트·아이콘그룹 파일을 둘 곳.
/// iCloud 를 쓸 수 있으면 iCloud Drive 의 앱 전용 폴더(iCloud.com.moimz.iFont/Data, Finder 에는 안 보임), 아니면 이 맥 Application Support/iFont.
/// 처음 iCloud 로 갈 때 이 맥 파일을 한 번 올리고(같은 것은 최근 것), 이 맥 폴더는 백업으로 그대로 둔다.
final class StorageLocation: @unchecked Sendable {
	static let containerID = "iCloud.com.moimz.iFont"
	static let shared = StorageLocation()
	static let kinds = ["Fonts", "IconGroups"]

	let url: URL
	let isCloud: Bool

	static let local: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		.appendingPathComponent("iFont", isDirectory: true)

	private init() {
		let fm = FileManager.default
		var cloud: URL?
		if fm.ubiquityIdentityToken != nil, let c = fm.url(forUbiquityContainerIdentifier: Self.containerID) {
			cloud = c.appendingPathComponent("Data", isDirectory: true)
		} else {
			// 서명 없는 명령줄 도구도 같은 파일을 쓰게: 앱이 한 번 만든 iCloud 폴더가 있으면 그곳
			let fixed = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/iCloud~com~moimz~iFont/Data", isDirectory: true)
			if fm.fileExists(atPath: fixed.path) { cloud = fixed }
		}
		url = cloud ?? Self.local
		isCloud = cloud != nil
		for sub in Self.kinds {
			try? fm.createDirectory(at: url.appendingPathComponent(sub), withIntermediateDirectories: true)
		}
		if isCloud { migrateLocal() }
	}

	/// 이 맥 파일을 iCloud 로 한 번 올린다. 이미 있는 것은 수정 시각이 더 최근일 때만 덮어쓴다
	private func migrateLocal() {
		let fm = FileManager.default
		let marker = Self.local.appendingPathComponent("moved-to-icloud")
		guard !fm.fileExists(atPath: marker.path) else { return }
		var copied = 0
		for kind in Self.kinds {
			let src = Self.local.appendingPathComponent(kind)
			for file in (try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where file.pathExtension == "json" {
				let dst = url.appendingPathComponent(kind).appendingPathComponent(file.lastPathComponent)
				let placeholder = dst.deletingLastPathComponent().appendingPathComponent("." + dst.lastPathComponent + ".icloud")
				if fm.fileExists(atPath: placeholder.path) { continue }   // iCloud 에 이미 있음 (아직 안 받은 것)
				if fm.fileExists(atPath: dst.path), modified(dst) >= modified(file) { continue }
				if let data = try? Data(contentsOf: file) { Self.write(data, to: dst); copied += 1 }
			}
		}
		try? "이 폴더의 파일을 \(Date()) 에 iCloud 로 옮겼습니다 (\(copied)개). 지금부터 iFont 는 iCloud 쪽을 씁니다. 이 폴더는 백업입니다.\n"
			.write(to: marker, atomically: true, encoding: .utf8)
	}

	private func modified(_ u: URL) -> Date {
		(try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
	}

	/// 아직 내려받지 않은 파일(.이름.json.icloud)의 id. 다시 읽을 때 사라진 것으로 보지 않는다
	func placeholderIDs(_ kind: String) -> Set<UUID> {
		guard isCloud else { return [] }
		let names = (try? FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent(kind).path)) ?? []
		return Set(names.compactMap { n in
			guard n.hasPrefix("."), n.hasSuffix(".json.icloud") else { return nil }
			return UUID(uuidString: String(n.dropFirst().dropLast(".json.icloud".count)))
		})
	}

	/// 아직 내려받지 않은 파일을 모두 받기 시작한다
	func downloadAll() {
		guard isCloud else { return }
		for kind in Self.kinds {
			for id in placeholderIDs(kind) {
				try? FileManager.default.startDownloadingUbiquitousItem(at: url.appendingPathComponent(kind).appendingPathComponent(id.uuidString + ".json"))
			}
		}
	}

	/// iCloud 가 함께 쓰는 파일이라 조율해서 쓴다
	static func write(_ data: Data, to target: URL) {
		var error: NSError?
		NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &error) { u in
			try? data.write(to: u, options: .atomic)
		}
	}

	static func remove(_ target: URL) {
		var error: NSError?
		NSFileCoordinator().coordinate(writingItemAt: target, options: .forDeleting, error: &error) { u in
			try? FileManager.default.removeItem(at: u)
		}
	}
}

/// 다른 기기에서 바뀐 iCloud 파일을 지켜본다: 안 받은 파일은 받고, 충돌은 최근 것으로 정리하고, 바뀌면 알려 준다
final class CloudWatcher: NSObject, @unchecked Sendable {
	static let shared = CloudWatcher()
	private let query = NSMetadataQuery()
	private var onChange: (() -> Void)?
	private var pending: DispatchWorkItem?

	func start(onChange: @escaping () -> Void) {
		guard StorageLocation.shared.isCloud, FileManager.default.ubiquityIdentityToken != nil else { return }
		self.onChange = onChange
		query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
		query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
		NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .NSMetadataQueryDidFinishGathering, object: query)
		NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .NSMetadataQueryDidUpdate, object: query)
		query.start()
	}

	@objc private func changed() {
		query.disableUpdates()
		for i in 0..<query.resultCount {
			guard let item = query.result(at: i) as? NSMetadataItem, let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
			let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
			if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
				try? FileManager.default.startDownloadingUbiquitousItem(at: url)
			}
			if (item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool) == true {
				Self.resolveConflicts(url)
			}
		}
		query.enableUpdates()
		// 여러 파일이 한꺼번에 오면 한 번만 다시 읽는다
		pending?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.onChange?() }
		pending = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
	}

	/// 두 기기에서 같은 파일을 고쳤으면 가장 최근에 고친 것을 남긴다
	static func resolveConflicts(_ url: URL) {
		guard let others = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !others.isEmpty,
		      let current = NSFileVersion.currentVersionOfItem(at: url) else { return }
		let newest = (others + [current]).max { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }!
		if newest != current { _ = try? newest.replaceItem(at: url) }
		for v in others { v.isResolved = true }
		try? NSFileVersion.removeOtherVersionsOfItem(at: url)
	}
}
