# MyTube Pad

iPad用のミニ動画プレイヤー。**OneDriveの共有リンクだけ**を再生できる、mytube(Mac版)の
OneDrive機能だけを抜き出した縮小版アプリです。ローカルフォルダ・YouTubeプレイリストには
対応していません。

## 使い方

1. 右上の「+」からOneDriveの共有リンク(「リンクを知っている全員が閲覧可能」設定のフォルダ)
   に名前を付けて登録します。
2. 左のリストからリンクを選ぶと、フォルダ内の動画がグリッドで表示されます。
3. タップすると全画面で再生されます(右上の✕で閉じます)。
4. 再生できない場合は、グリッド画面を下に引っぱって再読み込みしてください
   (OneDriveの動画URLは1時間程度で失効するため)。

登録したリンクは端末に保存され、次回起動時も一覧に残ります。

## インストール(無料Apple IDでの7日間運用)

Apple Developer Programに入っていない場合、無料のApple IDでもXcodeから実機にインストール
できますが、**7日ごとに再インストールが必要**です。

1. `mytube-ipad`フォルダをMacで開き、ターミナルで以下を実行してXcodeプロジェクトを生成します
   (初回、および`project.yml`を変更した後は毎回必要):
   ```bash
   xcodegen generate
   open MyTubePad.xcodeproj
   ```
2. XcodeでSigning & Capabilities → Teamに自分のApple ID(Personal Team)を選択します。
3. iPadをUSBでMacに接続し、実行先(destination)にそのiPadを選んで▶を押すとインストール
   されます。
4. 7日経つと起動できなくなるので、同じ手順で再インストールしてください。

## 制約

- OneDriveの非公式内部API(`api-badgerp.svc.ms`)を使っています。Microsoftが予告なく
  仕様変更・遮断する可能性があります。
- 動画のURL(`@content.downloadUrl`)は1時間程度で失効します。再生できなくなったら
  グリッドを引っぱって再読み込みしてください。
- サムネイル画像は表示しません(タイトル・フォルダ名・ファイルサイズのみ)。
