// CardGamesWebView.swift — pwa/cardgames(トランプゲーム)の`index.html`をそのまま
// WKWebViewで表示する。外部fetchなしの完全自己完結HTMLなので、ネイティブ移植せず
// バンドルしたコピーをオフラインで開くだけで動く。ソースは
// `pwa/cardgames/index.html`からの手動コピー — 同期は自動ではないので、Web版を
// 変更したらこのコピーにも反映するか検討すること(CLAUDE.md参照)。

import SwiftUI
@preconcurrency import WebKit

struct CardGamesWebView: UIViewRepresentable {
    /// `CardGameEntry.id`(shinkei/speed/daifugo/poker/bj。ババ抜き・7並べ・
    /// 21は2026-09-09にユーザー指示で削除した)。
    /// ホーム画面を経由せず、そのゲームのセットアップ画面へ直行させる
    /// (2026-09-09、ユーザー指示「トランプの各ゲームをトップページにおいて」)。
    let gameID: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        // ホームリンクを隠す処理と、該当ゲームのセットアップ画面(goSetup()。
        // index.html内で定義された関数で、ホーム画面のアイコンをタップしたときと
        // 同じ処理)へ直行させる処理を1本のスクリプトにまとめてある。
        // DOMContentLoadedの時点でgoSetup()は定義済みのはずだが、万一のタイミング
        // ずれに備えて見つかるまで最大1秒(50ms×20回)リトライする
        // (2026-09-09、ユーザー報告「トランプゲームをクリックしても始まらない」)。
        let source = """
        document.addEventListener('DOMContentLoaded', function() {
          var l = document.querySelector('.home-link');
          if (l) l.style.display = 'none';
          var attempts = 20;
          function tryOpen() {
            if (typeof goSetup === 'function') {
              goSetup('\(gameID)');
            } else if (attempts > 0) {
              attempts -= 1;
              setTimeout(tryOpen, 50);
            }
          }
          tryOpen();
        });
        """
        let openGameScript = WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        let controller = WKUserContentController()
        controller.addUserScript(openGameScript)
        let config = WKWebViewConfiguration()
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        // 見た目上は完全に静かに失敗しうる箇所(2026-09-09、ユーザー報告
        // 「トランプゲームが出てこない」で発覚): index.htmlがバンドルに
        // 見つからない場合、以前はここで何もせず終わり、WKWebViewが永久に
        // 空白のまま(エラーも出ない)になっていた。原因が分かるよう、
        // 見つからないときは理由をそのままHTMLとして表示する。
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(Self.errorHTML(message: "トランプゲームの index.html がアプリ内に見つかりませんでした(バンドルへの同梱に失敗している可能性があります)。"), baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func errorHTML(message: String) -> String {
        """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        body{margin:0;padding:24px;background:#0b3d24;color:#eaf5ec;
             font-family:-apple-system,sans-serif;font-size:15px;line-height:1.6;}
        h1{font-size:17px;color:#f2c14e;}
        </style></head>
        <body><h1>トランプゲームを読み込めませんでした</h1><p>\(message)</p></body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            webView.loadHTMLString(CardGamesWebView.errorHTML(message: error.localizedDescription), baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.loadHTMLString(CardGamesWebView.errorHTML(message: error.localizedDescription), baseURL: nil)
        }
    }
}
