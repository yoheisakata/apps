import Foundation

/// パスの半分圧縮つきUnion-Find。`DupPhotosViewModel`(重複写真のdHashクラスタリング)と
/// `VideoDupFinder`(動画重複のフレームハッシュクラスタリング)の両方で使う共通実装。
struct UnionFind {
    private var parent: [Int]
    init(_ n: Int) { parent = Array(0..<n) }
    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var cur = x
        while parent[cur] != root {
            let next = parent[cur]
            parent[cur] = root
            cur = next
        }
        return root
    }
    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        if ra != rb { parent[ra] = rb }
    }
}
