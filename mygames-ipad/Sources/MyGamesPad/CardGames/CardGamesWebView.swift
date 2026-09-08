// CardGamesWebView.swift — pwa/cardgames(トランプゲーム)の`index.html`をそのまま
// WKWebViewで表示する。外部fetchなしの完全自己完結HTMLなので、ネイティブ移植せず
// バンドルしたコピーをオフラインで開くだけで動く。ソースは
// `pwa/cardgames/index.html`からの手動コピー — 同期は自動ではないので、Web版を
// 変更したらこのコピーにも反映するか検討すること(CLAUDE.md参照)。

import SwiftUI
@preconcurrency import WebKit

struct CardGamesWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let userScript = WKUserScript(
            source: "document.addEventListener('DOMContentLoaded', function() { var l = document.querySelector('.home-link'); if (l) l.style.display = 'none'; });",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        let controller = WKUserContentController()
        controller.addUserScript(userScript)
        let config = WKWebViewConfiguration()
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.scrollView.bounces = false

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
