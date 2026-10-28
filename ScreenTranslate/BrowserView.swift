import SwiftUI
import WebKit

/// A web browser that translates pages in place, in the page itself, as you scroll. Inside the
/// app iOS allows this; Safari pages from other apps can only be translated by screenshot.
struct BrowserView: View {
    @StateObject private var browser = PageTranslator()
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    private static let quickLinks: [(String, String)] = [
        ("Yahoo! Auctions", "https://auctions.yahoo.co.jp"),
        ("Mercari", "https://jp.mercari.com"),
        ("Amazon Japan", "https://www.amazon.co.jp"),
        ("Rakuten", "https://www.rakuten.co.jp"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search or enter a website", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($addressFocused)
                    .onSubmit { browser.open(address) }
                if browser.isTranslating {
                    ProgressView()
                }
            }
            .padding(8)

            ZStack {
                WebView(webView: browser.webView)
                if browser.currentURL == nil {
                    List {
                        Section("Open") {
                            ForEach(Self.quickLinks, id: \.1) { link in
                                Button(link.0) { browser.open(link.1) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Browser")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { browser.webView.goBack() } label: { Image(systemName: "chevron.backward") }
                    .disabled(!browser.canGoBack)
                Button { browser.webView.goForward() } label: { Image(systemName: "chevron.forward") }
                    .disabled(!browser.canGoForward)
                Spacer()
                Button(browser.showsOriginal ? "Show translation" : "Show original") {
                    browser.showsOriginal.toggle()
                }
                Spacer()
                Button { browser.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .onChange(of: browser.currentURL) { _, url in
            if !addressFocused { address = url?.absoluteString ?? "" }
        }
    }
}

/// Owns the web view and swaps foreign text in the page for translations. A script in the page
/// sends the text near the visible area (again after scrolling or when the page adds content);
/// translations go back and replace it, keeping the original to switch back to.
@MainActor
final class PageTranslator: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    @Published var isTranslating = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?
    @Published var showsOriginal = false {
        didSet { webView.evaluateJavaScript("window.__stShowOriginal(\(showsOriginal)); 0", completionHandler: nil) }
    }

    private var pending = 0

    override init() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        controller.add(WeakHandler(self), name: "screenTranslate")
        webView.navigationDelegate = self
    }

    /// Opens a web address, or searches for anything else.
    func open(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let url: URL?
        if text.contains("."), !text.contains(" ") {
            url = URL(string: text.hasPrefix("http") ? text : "https://\(text)")
        } else {
            var components = URLComponents(string: "https://www.google.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: text)]
            url = components?.url
        }
        if let url { webView.load(URLRequest(url: url)) }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let items = message.body as? [[String: Any]] else { return }
        let texts = items.compactMap { item -> (Int, String)? in
            guard let id = item["id"] as? Int, let text = item["text"] as? String else { return nil }
            return (id, text)
        }
        guard !texts.isEmpty else { return }
        pending += 1
        isTranslating = true
        Task {
            let translations = await TextTranslator.translate(texts.map(\.1))
            let results = texts.compactMap { id, text in translations[text].map { ["id": id, "text": $0] as [String: Any] } }
            if let data = try? JSONSerialization.data(withJSONObject: results), let json = String(data: data, encoding: .utf8) {
                webView.evaluateJavaScript("window.__stApply(\(json)); 0", completionHandler: nil)
            }
            pending -= 1
            isTranslating = pending > 0
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigation()
        if showsOriginal { showsOriginal = false }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateNavigation()
    }

    private func updateNavigation() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url
    }

    /// Collects text near the screen in batches, and puts translations in place.
    private static let script = """
    (function () {
      if (window.__stReady) return;
      window.__stReady = true;
      var nodes = [], seen = new WeakSet(), showOriginal = false, timer = null;
      var skip = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEXTAREA: 1, INPUT: 1, CODE: 1, PRE: 1 };
      function nearScreen(node) {
        var element = node.parentElement;
        if (!element) return false;
        var rect = element.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) return false;
        var h = window.innerHeight;
        return rect.bottom > -h && rect.top < 2 * h;
      }
      function collect() {
        timer = null;
        if (!document.body) return;
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        var batch = [], node;
        while ((node = walker.nextNode()) && batch.length < 150) {
          if (seen.has(node)) continue;
          var text = node.nodeValue.trim();
          if (text.length < 1 || !/\\p{L}/u.test(text)) continue;
          var parent = node.parentElement;
          if (!parent || skip[parent.tagName] || parent.isContentEditable) continue;
          if (!nearScreen(node)) continue;
          seen.add(node);
          nodes.push({ node: node, original: node.nodeValue, translation: null });
          batch.push({ id: nodes.length - 1, text: text });
        }
        if (batch.length) {
          window.webkit.messageHandlers.screenTranslate.postMessage(batch);
          if (batch.length === 150) schedule(50);
        }
      }
      function schedule(delay) {
        if (!timer) timer = setTimeout(collect, delay);
      }
      window.__stApply = function (results) {
        results.forEach(function (r) {
          var entry = nodes[r.id];
          if (!entry) return;
          var lead = entry.original.match(/^\\s*/)[0], trail = entry.original.match(/\\s*$/)[0];
          entry.translation = lead + r.text + trail;
          if (!showOriginal) entry.node.nodeValue = entry.translation;
        });
      };
      window.__stShowOriginal = function (show) {
        showOriginal = show;
        nodes.forEach(function (entry) {
          if (entry.translation) entry.node.nodeValue = show ? entry.original : entry.translation;
        });
      };
      window.addEventListener('scroll', function () { schedule(250); }, { passive: true });
      new MutationObserver(function () { schedule(400); }).observe(document.documentElement, { childList: true, subtree: true });
      schedule(0);
    })();
    """
}

/// WKUserContentController keeps its handlers alive; this keeps it from keeping the page alive.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

private struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
