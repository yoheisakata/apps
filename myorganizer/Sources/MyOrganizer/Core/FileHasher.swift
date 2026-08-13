import Foundation
import CryptoKit

/// 重複ファイル判定用のMD5（セキュリティ用途ではなく同一性チェックのみ）。
enum FileHasher {
    static func md5(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = Insecure.MD5()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
