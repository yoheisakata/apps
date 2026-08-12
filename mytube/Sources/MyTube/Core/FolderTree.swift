import Foundation

/// サイドバーのフォルダツリー(`Views/SidebarView.swift`の`FolderTreeRow`)1ノード分。
/// `LocalSource`/`RemoteSource`ごとに`FolderTree.build`でルートノードを1本作り、
/// `VideoItem.folderPath`を辿ってサブフォルダを再帰的に組み立てる(`photo-gallery`の
/// `PhotoStore.rebuildTree()`と同じ考え方)。
final class FolderTreeNode: Identifiable {
    let id: String
    let name: String
    let sourceID: String
    /// このノードのソースルートから見たパス(ルートノード自身は`[]`)。
    let folderPath: [String]
    var children: [FolderTreeNode] = []

    init(id: String, name: String, sourceID: String, folderPath: [String]) {
        self.id = id
        self.name = name
        self.sourceID = sourceID
        self.folderPath = folderPath
    }
}

enum FolderTree {
    static func build(sourceID: String, sourceName: String, videos: [VideoItem]) -> FolderTreeNode {
        let root = FolderTreeNode(id: sourceID, name: sourceName, sourceID: sourceID, folderPath: [])

        for video in videos {
            var node = root
            var pathSoFar: [String] = []
            for component in video.folderPath {
                pathSoFar.append(component)
                if let existing = node.children.first(where: { $0.name == component }) {
                    node = existing
                } else {
                    let child = FolderTreeNode(
                        id: "\(sourceID)|\(pathSoFar.joined(separator: "/"))",
                        name: component, sourceID: sourceID, folderPath: pathSoFar)
                    node.children.append(child)
                    node = child
                }
            }
        }

        sortChildren(root)
        return root
    }

    private static func sortChildren(_ node: FolderTreeNode) {
        node.children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        node.children.forEach(sortChildren)
    }
}
