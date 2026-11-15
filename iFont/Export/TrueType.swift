import CoreGraphics
import Foundation

/// 폰트에 넣을 글자 하나 (폰트 단위, y 위 방향, 기준선 0)
struct OutlineGlyph {
	var name: String
	var code: UInt32
	var advance: Int
	/// 윤곽들. 점마다 (x, y, 곡선 위 점인지)
	var contours: [[(x: Int, y: Int, on: Bool)]]

	var points: [(x: Int, y: Int, on: Bool)] { contours.flatMap { $0 } }
	var bounds: (xMin: Int, yMin: Int, xMax: Int, yMax: Int) {
		let p = points
		guard !p.isEmpty else { return (0, 0, 0, 0) }
		return (p.map(\.x).min()!, p.map(\.y).min()!, p.map(\.x).max()!, p.map(\.y).max()!)
	}

	/// 화면 좌표(높이 1000, y 아래 방향, 위쪽 끝 0) 모양을 폰트 단위 TrueType 윤곽으로 바꾼다.
	/// 3차 곡선은 2차 곡선 여러 개로 나눠 근사한다 (오차 0.5 단위 이내)
	static func make(name: String, code: UInt32, path: CGPath, width: Double, unitsPerEm: Int, ascent: Int) -> OutlineGlyph {
		let k = Double(unitsPerEm) / 1000
		func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * k, y: Double(ascent) - p.y * k) }
		var contours: [[(x: Int, y: Int, on: Bool)]] = []
		var cur: [(x: Int, y: Int, on: Bool)] = []
		var last = CGPoint.zero
		func add(_ p: CGPoint, on: Bool) {
			let q = (x: Int(p.x.rounded()), y: Int(p.y.rounded()), on: on)
			// 같은 자리에 겹친 곡선 위 점은 하나로
			if let l = cur.last, l.x == q.x, l.y == q.y, l.on, on { return }
			cur.append(q)
		}
		func finish() {
			// 끝점이 시작점과 같으면 뺀다 (윤곽은 저절로 닫힌다)
			if cur.count > 1, let f = cur.first, let l = cur.last, f.on, l.on, f.x == l.x, f.y == l.y { cur.removeLast() }
			if cur.count >= 3 { contours.append(cur) }
			cur = []
		}
		func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, depth: Int) {
			// 3차 곡선을 2차 곡선 하나로 볼 때의 오차: √3/36 · |P3 − 3P2 + 3P1 − P0|
			let dx = p3.x - 3 * p2.x + 3 * p1.x - p0.x, dy = p3.y - 3 * p2.y + 3 * p1.y - p0.y
			let err = sqrt(3) / 36 * hypot(dx, dy)
			if err <= 0.5 || depth >= 8 {
				let c = CGPoint(x: (3 * (p1.x + p2.x) - p0.x - p3.x) / 4, y: (3 * (p1.y + p2.y) - p0.y - p3.y) / 4)
				add(c, on: false)
				add(p3, on: true)
				return
			}
			// 반으로 나눈다 (de Casteljau)
			func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
			let a = mid(p0, p1), b = mid(p1, p2), c = mid(p2, p3), d = mid(a, b), e = mid(b, c), m = mid(d, e)
			cubic(p0, a, d, m, depth: depth + 1)
			cubic(m, e, c, p3, depth: depth + 1)
		}
		var start = CGPoint.zero
		path.applyWithBlock { el in
			let e = el.pointee
			switch e.type {
			case .moveToPoint:
				finish()
				last = pt(e.points[0]); start = last
				add(last, on: true)
			case .addLineToPoint:
				last = pt(e.points[0]); add(last, on: true)
			case .addQuadCurveToPoint:
				add(pt(e.points[0]), on: false)
				last = pt(e.points[1]); add(last, on: true)
			case .addCurveToPoint:
				let p3 = pt(e.points[2])
				cubic(last, pt(e.points[0]), pt(e.points[1]), p3, depth: 0)
				last = p3
			case .closeSubpath:
				finish()
				last = start
			@unknown default: break
			}
		}
		finish()
		return OutlineGlyph(name: name, code: code, advance: Int((width * k).rounded()), contours: contours)
	}
}

/// 빅엔디언 바이트 쓰기
struct ByteWriter {
	var data = Data()
	mutating func u8(_ v: Int) { data.append(UInt8(truncatingIfNeeded: v)) }
	mutating func u16(_ v: Int) { u8(v >> 8); u8(v) }
	mutating func i16(_ v: Int) { u16(v & 0xFFFF) }
	mutating func u32(_ v: UInt32) { u16(Int(v >> 16)); u16(Int(v & 0xFFFF)) }
	mutating func i64(_ v: Int64) { u32(UInt32(truncatingIfNeeded: v >> 32)); u32(UInt32(truncatingIfNeeded: v)) }
	mutating func tag(_ s: String) { data.append(contentsOf: Array(s.utf8.prefix(4)) + Array(repeating: 0x20, count: max(0, 4 - s.utf8.count))) }
	mutating func pad4() { while data.count % 4 != 0 { u8(0) } }
}

/// TrueType(.ttf) 폰트 파일을 만든다. 힌팅 없이 윤곽만 넣는다.
enum TrueTypeWriter {
	struct Info {
		var family: String
		var version: String
		var unitsPerEm: Int
		var ascent: Int
		var descent: Int
	}

	/// 표 이름과 내용. woff2 를 만들 때도 쓴다
	static func tables(_ glyphs: [OutlineGlyph], info: Info) -> [(tag: String, data: Data)] {
		// 0번 글자는 .notdef (빈 모양)
		let all = [OutlineGlyph(name: ".notdef", code: 0, advance: info.unitsPerEm, contours: [])] + glyphs
		let boxes = all.map(\.bounds)
		let drawn = boxes.indices.filter { !all[$0].contours.isEmpty }
		let xMin = drawn.map { boxes[$0].xMin }.min() ?? 0, yMin = drawn.map { boxes[$0].yMin }.min() ?? 0
		let xMax = drawn.map { boxes[$0].xMax }.max() ?? 0, yMax = drawn.map { boxes[$0].yMax }.max() ?? 0

		// glyf · loca
		var glyf = ByteWriter()
		var offsets: [UInt32] = []
		for (i, g) in all.enumerated() {
			offsets.append(UInt32(glyf.data.count))
			guard !g.contours.isEmpty else { continue }
			let b = boxes[i]
			glyf.i16(g.contours.count)
			glyf.i16(b.xMin); glyf.i16(b.yMin); glyf.i16(b.xMax); glyf.i16(b.yMax)
			var end = -1
			for c in g.contours { end += c.count; glyf.u16(end) }
			glyf.u16(0)   // 명령 없음
			let pts = g.points
			// 플래그: 곡선 위 점(1) + x·y 가 1바이트로 들어가면 짧게(2·4, 부호는 0x10·0x20)
			var xs = ByteWriter(), ys = ByteWriter(), flags = ByteWriter()
			var px = 0, py = 0
			for p in pts {
				var f = p.on ? 1 : 0
				let dx = p.x - px, dy = p.y - py
				if dx == 0 { f |= 0x10 } else if abs(dx) < 256 { f |= 0x02 | (dx > 0 ? 0x10 : 0); xs.u8(abs(dx)) } else { xs.i16(dx) }
				if dy == 0 { f |= 0x20 } else if abs(dy) < 256 { f |= 0x04 | (dy > 0 ? 0x20 : 0); ys.u8(abs(dy)) } else { ys.i16(dy) }
				flags.u8(f)
				px = p.x; py = p.y
			}
			glyf.data += flags.data + xs.data + ys.data
			glyf.pad4()
		}
		offsets.append(UInt32(glyf.data.count))
		var loca = ByteWriter()
		for o in offsets { loca.u32(o) }

		// head
		let now = Int64(Date().timeIntervalSince1970) + 2_082_844_800   // 1904-01-01 기준 초
		var head = ByteWriter()
		head.u32(0x0001_0000)
		head.u32(fixed(info.version))
		head.u32(0)            // checkSumAdjustment: 파일을 다 만든 뒤 채운다
		head.u32(0x5F0F_3CF5)
		head.u16(0x000B)
		head.u16(info.unitsPerEm)
		head.i64(now); head.i64(now)
		head.i16(xMin); head.i16(yMin); head.i16(xMax); head.i16(yMax)
		head.u16(0)            // macStyle
		head.u16(8)            // lowestRecPPEM
		head.i16(2)            // fontDirectionHint
		head.i16(1)            // indexToLocFormat: 4바이트
		head.i16(0)

		// hhea
		let lsbs = all.indices.map { all[$0].contours.isEmpty ? 0 : boxes[$0].xMin }
		var hhea = ByteWriter()
		hhea.u32(0x0001_0000)
		hhea.i16(info.ascent); hhea.i16(-info.descent); hhea.i16(0)
		hhea.u16(all.map(\.advance).max() ?? 0)
		hhea.i16(drawn.map { boxes[$0].xMin }.min() ?? 0)
		hhea.i16(drawn.map { all[$0].advance - boxes[$0].xMax }.min() ?? 0)
		hhea.i16(drawn.map { boxes[$0].xMax }.max() ?? 0)
		hhea.i16(1); hhea.i16(0); hhea.i16(0)
		for _ in 0..<4 { hhea.i16(0) }
		hhea.i16(0)
		hhea.u16(all.count)

		// hmtx
		var hmtx = ByteWriter()
		for (i, g) in all.enumerated() { hmtx.u16(g.advance); hmtx.i16(lsbs[i]) }

		// maxp
		var maxp = ByteWriter()
		maxp.u32(0x0001_0000)
		maxp.u16(all.count)
		maxp.u16(all.map { $0.points.count }.max() ?? 0)
		maxp.u16(all.map { $0.contours.count }.max() ?? 0)
		maxp.u16(0); maxp.u16(0)
		maxp.u16(2)
		for _ in 0..<8 { maxp.u16(0) }

		// OS/2 (버전 4)
		let codes = glyphs.map(\.code)
		var os2 = ByteWriter()
		os2.u16(4)
		os2.i16(all.isEmpty ? 0 : all.map(\.advance).reduce(0, +) / all.count)
		os2.u16(400); os2.u16(5); os2.u16(0)
		let em = info.unitsPerEm
		os2.i16(em * 65 / 100); os2.i16(em * 70 / 100); os2.i16(0); os2.i16(em * 14 / 100)
		os2.i16(em * 65 / 100); os2.i16(em * 70 / 100); os2.i16(0); os2.i16(em * 48 / 100)
		os2.i16(em * 5 / 100); os2.i16(em * 25 / 100)
		os2.i16(0)
		for _ in 0..<10 { os2.u8(0) }                      // panose
		os2.u32(0); os2.u32(1 << 28); os2.u32(0); os2.u32(0)   // 유니코드 범위: 사용자 영역(PUA)
		os2.tag("iFnt")
		os2.u16(0x40)                                       // REGULAR
		os2.u16(Int(min(codes.min() ?? 0, 0xFFFF))); os2.u16(Int(min(codes.max() ?? 0, 0xFFFF)))
		os2.i16(info.ascent); os2.i16(-info.descent); os2.i16(0)
		os2.u16(max(info.ascent, yMax)); os2.u16(max(info.descent, -yMin))
		os2.u32(1); os2.u32(0)
		os2.i16(0); os2.i16(0)
		os2.u16(0); os2.u16(32); os2.u16(1)

		return [
			("OS/2", os2.data), ("cmap", cmap(glyphs)), ("glyf", glyf.data), ("loca", loca.data),
			("head", head.data), ("hhea", hhea.data), ("hmtx", hmtx.data), ("maxp", maxp.data),
			("name", name(info)), ("post", post(all)),
		]
	}

	/// 표들을 .ttf 한 파일로 묶는다
	static func font(_ tables: [(tag: String, data: Data)]) -> Data {
		let sorted = tables.sorted { $0.tag < $1.tag }
		let n = sorted.count
		var entrySelector = 0
		while (1 << (entrySelector + 1)) <= n { entrySelector += 1 }
		let searchRange = (1 << entrySelector) * 16
		var out = ByteWriter()
		out.u32(0x0001_0000)
		out.u16(n); out.u16(searchRange); out.u16(entrySelector); out.u16(n * 16 - searchRange)
		var offset = 12 + 16 * n
		var headOffset = 0
		for t in sorted {
			out.tag(t.tag); out.u32(checksum(t.data)); out.u32(UInt32(offset)); out.u32(UInt32(t.data.count))
			if t.tag == "head" { headOffset = offset }
			offset += (t.data.count + 3) / 4 * 4
		}
		for t in sorted { out.data += t.data; out.pad4() }
		// head.checkSumAdjustment = 0xB1B0AFBA − 파일 전체 체크섬
		let adjust = 0xB1B0_AFBA &- checksum(out.data)
		var d = out.data
		let a = headOffset + 8
		d[a] = UInt8(adjust >> 24); d[a + 1] = UInt8((adjust >> 16) & 0xFF); d[a + 2] = UInt8((adjust >> 8) & 0xFF); d[a + 3] = UInt8(adjust & 0xFF)
		return d
	}

	static func checksum(_ data: Data) -> UInt32 {
		var sum: UInt32 = 0
		let bytes = [UInt8](data) + Array(repeating: 0, count: (4 - data.count % 4) % 4)
		for i in stride(from: 0, to: bytes.count, by: 4) {
			sum &+= UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])
		}
		return sum
	}

	/// "5.238" → 16.16 고정소수
	private static func fixed(_ version: String) -> UInt32 {
		let parts = version.split(separator: ".").compactMap { Int($0) }
		let major = parts.first ?? 1, minor = parts.count > 1 ? parts[1] : 0
		return UInt32(major & 0xFFFF) << 16 | UInt32(min(minor, 0xFFFF))
	}

	/// 글자 코드 → 글자 번호. BMP 는 형식 4, BMP 밖이 있으면 형식 12 도 넣는다
	private static func cmap(_ glyphs: [OutlineGlyph]) -> Data {
		let pairs = glyphs.enumerated().map { (code: Int($1.code), gid: $0 + 1) }.sorted { $0.code < $1.code }
		// 코드와 글자 번호가 함께 1씩 느는 구간으로 묶는다
		var runs: [(start: Int, end: Int, gid: Int)] = []
		for p in pairs {
			if let l = runs.last, p.code == l.end + 1, p.gid == l.gid + (p.code - l.start) { runs[runs.count - 1].end = p.code } else { runs.append((p.code, p.code, p.gid)) }
		}
		let bmp = runs.filter { $0.end <= 0xFFFE }
		var f4 = ByteWriter()
		let segs = bmp.count + 1
		var es = 0
		while (1 << (es + 1)) <= segs { es += 1 }
		f4.u16(4); f4.u16(16 + segs * 8); f4.u16(0)
		f4.u16(segs * 2); f4.u16((1 << es) * 2); f4.u16(es); f4.u16(segs * 2 - (1 << es) * 2)
		for r in bmp { f4.u16(r.end) }; f4.u16(0xFFFF)
		f4.u16(0)
		for r in bmp { f4.u16(r.start) }; f4.u16(0xFFFF)
		for r in bmp { f4.u16((r.gid - r.start) & 0xFFFF) }; f4.u16(1)
		for _ in 0..<segs { f4.u16(0) }

		var subtables: [(platform: Int, encoding: Int, data: Data)] = [(0, 3, f4.data), (3, 1, f4.data)]
		if runs.contains(where: { $0.end > 0xFFFF }) {
			var f12 = ByteWriter()
			f12.u16(12); f12.u16(0); f12.u32(UInt32(16 + runs.count * 12)); f12.u32(0); f12.u32(UInt32(runs.count))
			for r in runs { f12.u32(UInt32(r.start)); f12.u32(UInt32(r.end)); f12.u32(UInt32(r.gid)) }
			subtables += [(0, 4, f12.data), (3, 10, f12.data)]
		}
		var out = ByteWriter()
		out.u16(0); out.u16(subtables.count)
		var offset = 4 + 8 * subtables.count
		for s in subtables { out.u16(s.platform); out.u16(s.encoding); out.u32(UInt32(offset)); offset += s.data.count }
		for s in subtables { out.data += s.data }
		return out.data
	}

	private static func name(_ info: Info) -> Data {
		let ps = String(info.family.unicodeScalars.filter { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0)) || $0 == "-") })
		let records: [(Int, String)] = [
			(1, info.family), (2, "Regular"), (3, "iFont:\(info.family):\(info.version)"),
			(4, info.family), (5, "Version \(info.version)"), (6, ps.isEmpty ? "iFont" : ps),
		]
		let strings = records.map { (id: $0.0, data: $0.1.data(using: .utf16BigEndian)!) }
		var out = ByteWriter()
		out.u16(0); out.u16(strings.count); out.u16(6 + 12 * strings.count)
		var offset = 0
		for s in strings {
			out.u16(3); out.u16(1); out.u16(0x409); out.u16(s.id); out.u16(s.data.count); out.u16(offset)
			offset += s.data.count
		}
		for s in strings { out.data += s.data }
		return out.data
	}

	/// post 2.0: 글자 이름을 넣어 둔다 (다시 가져올 때 이름이 살아 있게)
	private static func post(_ all: [OutlineGlyph]) -> Data {
		var out = ByteWriter()
		out.u32(0x0002_0000)
		out.u32(0)
		out.i16(-75); out.i16(50)
		out.u32(0); out.u32(0); out.u32(0); out.u32(0); out.u32(0)
		out.u16(all.count)
		var names = Data()
		var index = 258
		var used = Set<String>()
		for (i, g) in all.enumerated() {
			if i == 0 { out.u16(0); continue }   // .notdef 는 표준 이름 0번
			var n = String(g.name.unicodeScalars.filter { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0)) || $0 == "-" || $0 == "_" || $0 == ".") }.prefix(60))
			if n.isEmpty || used.contains(n) { n = String(format: "uni%04X", g.code) }
			used.insert(n)
			out.u16(index); index += 1
			names.append(UInt8(n.utf8.count)); names.append(contentsOf: Array(n.utf8))
		}
		out.data += names
		return out.data
	}
}
