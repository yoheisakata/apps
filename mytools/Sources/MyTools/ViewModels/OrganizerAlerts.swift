import AppKit

/// 写真整理・動画整理で共通の「整理先に年フォルダを指定している」警告ダイアログ。
/// `MediaOrganizer.looksLikeYearFolder`がtrueのとき、実行前にこれを出して処理をブロックする。
@MainActor
func showYearFolderAlert(destName: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "整理先に年フォルダを指定しています"
    alert.informativeText = """
        整理先の末尾が「\(destName)」で、年フォルダのように見えます。

        このツールは整理先の下に年/月/日フォルダを自動作成するため、年フォルダそのものを指定すると二重ネスト（\(destName)/\(destName)/...）になり、既存ファイルとの重複判定も正しく働きません。

        年フォルダを含まない親フォルダを指定してから、もう一度実行してください。
        """
    alert.addButton(withTitle: "OK")
    alert.runModal()
}
