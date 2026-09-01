import SwiftUI
import WebKit

struct HelpView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        if let url = Bundle.main.url(forResource: "help", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct HelpWindow: View {
    var body: some View {
        HelpView()
            .frame(minWidth: 900, idealWidth: 1100, minHeight: 600, idealHeight: 800)
    }
}
