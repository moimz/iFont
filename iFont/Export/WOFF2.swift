import Compression
import Foundation

/// TrueType 표들을 WOFF2 로 묶는다. glyf·loca 는 변환하지 않고(null transform) 그대로 brotli 로 압축한다.
enum WOFF2Writer {
	/// WOFF2 가 미리 정해 둔 표 이름 번호
	private static let knownTags = [
		"cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post", "cvt ", "fpgm", "glyf", "loca", "prep", "CFF ", "VORG", "EBDT",
		"EBLC", "gasp", "hdmx", "kern", "LTSH", "PCLT", "VDMX", "vhea", "vmtx", "BASE", "GDEF", "GPOS", "GSUB", "EBSC", "JSTF", "MATH",
		"CBDT", "CBLC", "COLR", "CPAL", "SVG ", "sbix", "acnt", "avar", "bdat", "bloc", "bsln", "cvar", "fdsc", "feat", "fmtx", "fvar",
		"gvar", "hsty", "just", "lcar", "mort", "morx", "opbd", "prop", "trak", "Zapf", "Silf", "Glat", "Gloc", "Feat", "Sill",
	]

	enum Failure: Error, LocalizedError {
		case compress
		var errorDescription: String? { "woff2 압축에 실패했습니다." }
	}

	static func font(_ tables: [(tag: String, data: Data)]) throws -> Data {
		// glyf 바로 뒤에 loca 가 오게 놓는다
		var ordered = tables.sorted { $0.tag < $1.tag }
		if let l = ordered.firstIndex(where: { $0.tag == "loca" }), let g = ordered.firstIndex(where: { $0.tag == "glyf" }) {
			let loca = ordered.remove(at: l)
			ordered.insert(loca, at: ordered.firstIndex(where: { $0.tag == "glyf" }).map { $0 + 1 } ?? g + 1)
		}
		var directory = ByteWriter()
		var stream = Data()
		for t in ordered {
			let known = knownTags.firstIndex(of: t.tag)
			// glyf·loca 는 변환 번호 3 이 '변환 안 함', 나머지는 0 이 '변환 안 함'
			let transform = (t.tag == "glyf" || t.tag == "loca") ? 3 : 0
			directory.u8((known ?? 63) | transform << 6)
			if known == nil { directory.tag(t.tag) }
			base128(&directory, UInt32(t.data.count))
			stream += t.data
		}
		let compressed = try brotli(stream)
		let sfntSize = 12 + 16 * tables.count + tables.reduce(0) { $0 + ($1.data.count + 3) / 4 * 4 }

		var body = directory.data + compressed
		while body.count % 4 != 0 { body.append(0) }
		var out = ByteWriter()
		out.tag("wOF2")
		out.u32(0x0001_0000)
		out.u32(UInt32(48 + body.count))
		out.u16(tables.count)
		out.u16(0)
		out.u32(UInt32(sfntSize))
		out.u32(UInt32(compressed.count))
		out.u16(1); out.u16(0)
		for _ in 0..<5 { out.u32(0) }   // 메타데이터·개인 데이터 없음
		return out.data + body
	}

	/// UIntBase128: 7비트씩, 앞 바이트들은 최상위 비트 1
	private static func base128(_ w: inout ByteWriter, _ v: UInt32) {
		var bytes: [UInt8] = [UInt8(v & 0x7F)]
		var rest = v >> 7
		while rest > 0 { bytes.insert(UInt8(rest & 0x7F) | 0x80, at: 0); rest >>= 7 }
		w.data.append(contentsOf: bytes)
	}

	private static func brotli(_ data: Data) throws -> Data {
		let capacity = data.count + 1024
		var dst = [UInt8](repeating: 0, count: capacity)
		let n = data.withUnsafeBytes { src in
			compression_encode_buffer(&dst, capacity, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_BROTLI)
		}
		guard n > 0 else { throw Failure.compress }
		return Data(dst.prefix(n))
	}
}
