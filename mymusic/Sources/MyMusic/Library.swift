import Foundation

/// サイドバーで選んでいる場所。ここで選んだ範囲がそのまま曲リスト = 再生キューになる。
enum LibrarySelection: Hashable {
    /// ライブラリ全体。
    case all
    /// OneDrive 以外(YouTube / Suno / 直リンク等、1リンク=1曲で追加したもの)。
    case links
    /// OneDrive 共有リンクの中の1フォルダ。`folderPath` が空なら共有フォルダのルート。
    /// mytube と同じく**選んだフォルダの配下もすべて含む**(祖先を選べば全部聴ける)。
    case oneDriveFolder(shareURL: String, folderPath: [String])

    func matches(_ track: Track) -> Bool {
        switch self {
        case .all:
            return true
        case .links:
            return track.oneDrive == nil
        case .oneDriveFolder(let shareURL, let folderPath):
            guard let ref = track.oneDrive, ref.shareURL == shareURL else { return false }
            return track.folderPath.starts(with: folderPath)
        }
    }
}

/// 1つの OneDrive 共有リンク(サイドバーのルート行1本ぶん)。
struct OneDriveLibrarySource: Identifiable, Equatable {
    var id: String { shareURL }
    let shareURL: String
    let name: String
    let trackCount: Int
}

/// サイドバーのフォルダツリー1ノード。子を持つ参照型(mytube の `FolderTreeNode` と同じ設計)。
final class LibraryNode: Identifiable {
    /// 共有リンク + フォルダパスで一意になる ID(展開状態の記憶キーにも使う)。
    let id: String
    let name: String
    let shareURL: String
    let folderPath: [String]
    var children: [LibraryNode] = []

    init(name: String, shareURL: String, folderPath: [String]) {
        self.id = "\(shareURL)#\(folderPath.joined(separator: "/"))"
        self.name = name
        self.shareURL = shareURL
        self.folderPath = folderPath
    }

    var selection: LibrarySelection { .oneDriveFolder(shareURL: shareURL, folderPath: folderPath) }
}

enum LibraryTree {
    /// 1つの共有リンクに属する曲から、フォルダ階層のツリー(ルートノード1本)を組み立てる。
    /// ノードは `Track.folderPath` だけから作るので、曲が1つも入っていない空フォルダは出ない。
    static func build(source: OneDriveLibrarySource, tracks: [Track]) -> LibraryNode {
        let root = LibraryNode(name: source.name, shareURL: source.shareURL, folderPath: [])
        var nodesByPath: [String: LibraryNode] = ["": root]

        for track in tracks where track.oneDrive?.shareURL == source.shareURL {
            var path: [String] = []
            var parent = root
            for component in track.folderPath {
                path.append(component)
                let key = path.joined(separator: "/")
                if let existing = nodesByPath[key] {
                    parent = existing
                } else {
                    let node = LibraryNode(name: component, shareURL: source.shareURL, folderPath: path)
                    nodesByPath[key] = node
                    parent.children.append(node)
                    parent = node
                }
            }
        }
        sortRecursively(root)
        return root
    }

    private static func sortRecursively(_ node: LibraryNode) {
        node.children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for child in node.children { sortRecursively(child) }
    }
}
