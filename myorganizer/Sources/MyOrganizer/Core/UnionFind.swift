import Foundation

/// パスの半分圧縮つきUnion-Find。`VideoDupFinder`(動画重複のフレームハッシュクラスタリング)で使う。
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
