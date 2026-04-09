import Foundation

struct MarkdownHTMLRenderer {
    func render(markdown: String, sourceURL: URL?) -> String {
        let markdownBase64 = Data(markdown.utf8).base64EncodedString()
        let baseHref = sourceURL?
            .deletingLastPathComponent()
            .absoluteString
            .htmlAttributeEscaped ?? ""

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <base href="\(baseHref)">
          <style>
            :root {
              color-scheme: dark;
              --line: rgba(255,255,255,0.08);
              --text: #f2f1f5;
              --muted: #b8bcc8;
              --accent: #f49a70;
              --cyan: #8ac5ff;
              --code: #11131c;
            }
            * { box-sizing: border-box; }
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
              color: var(--text);
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              -webkit-user-select: text;
              user-select: text;
            }
            body {
              padding: 18px 20px 28px;
              line-height: 1.65;
              font-size: 14px;
              word-wrap: break-word;
            }
            a { color: var(--cyan); text-decoration: none; }
            h1, h2, h3, h4, h5, h6 {
              color: var(--text);
              line-height: 1.2;
              margin: 0 0 14px;
              font-weight: 700;
            }
            h1 { font-size: 28px; }
            h2 { font-size: 22px; margin-top: 30px; }
            h3 { font-size: 18px; margin-top: 24px; }
            p, ul, ol, blockquote, pre, table {
              margin: 0 0 16px;
            }
            ul, ol { padding-left: 22px; }
            li + li { margin-top: 6px; }
            blockquote {
              margin-left: 0;
              padding: 12px 16px;
              border-left: 3px solid var(--accent);
              background: rgba(244,154,112,0.08);
              color: var(--muted);
              border-radius: 0 12px 12px 0;
            }
            code {
              font-family: "SF Mono", "JetBrains Mono", Menlo, monospace;
              font-size: 12px;
            }
            :not(pre) > code {
              padding: 2px 6px;
              border-radius: 8px;
              background: rgba(255,255,255,0.08);
            }
            pre {
              overflow: auto;
              padding: 14px 16px;
              border-radius: 16px;
              background: var(--code);
              border: 1px solid var(--line);
            }
            pre code {
              display: block;
              white-space: pre;
              color: var(--text);
            }
            .code-block {
              position: relative;
              margin: 0 0 16px;
            }
            .code-block pre {
              margin: 0;
              padding-top: 42px;
            }
            .code-copy {
              position: absolute;
              top: 10px;
              right: 10px;
              border: 1px solid var(--line);
              background: rgba(255,255,255,0.08);
              color: var(--text);
              border-radius: 999px;
              padding: 6px 10px;
              font-size: 11px;
              font-weight: 600;
              cursor: pointer;
            }
            .code-copy:hover {
              background: rgba(244,154,112,0.18);
              border-color: rgba(244,154,112,0.35);
            }
            table {
              width: 100%;
              border-collapse: collapse;
              border-radius: 12px;
              overflow: hidden;
              border: 1px solid var(--line);
            }
            th, td {
              padding: 10px 12px;
              border-bottom: 1px solid var(--line);
              text-align: left;
            }
            th {
              color: var(--muted);
              background: rgba(255,255,255,0.04);
            }
            hr {
              border: none;
              height: 1px;
              background: var(--line);
              margin: 22px 0;
            }
            img {
              max-width: 100%;
              border-radius: 14px;
              border: 1px solid var(--line);
            }
            .mermaid {
              display: flex;
              justify-content: center;
              margin: 20px 0;
              padding: 16px;
              border-radius: 16px;
              background: var(--code);
              border: 1px solid var(--line);
            }
          </style>
          <script>\(Self.markedScript)</script>
          <script>\(Self.mermaidScript)</script>
        </head>
        <body>
          <article id="content"></article>
          <script>
            const markdownBase64 = "\(markdownBase64)";
            const bytes = Uint8Array.from(atob(markdownBase64), c => c.charCodeAt(0));
            const markdown = new TextDecoder().decode(bytes);
            const content = document.getElementById("content");

            function reportHeight() {
              const height = Math.max(
                document.documentElement.scrollHeight,
                document.body.scrollHeight,
                content.scrollHeight
              );

              if (window.webkit?.messageHandlers?.contentHeight) {
                window.webkit.messageHandlers.contentHeight.postMessage(height);
              }
            }

            function replaceMermaidBlocks() {
              const selectors = [
                "pre code.language-mermaid",
                "pre code.lang-mermaid",
                "pre code.mermaid"
              ];
              const codeBlocks = document.querySelectorAll(selectors.join(","));

              codeBlocks.forEach((block, index) => {
                const container = document.createElement("div");
                container.className = "mermaid";
                container.id = `mermaid-${index}`;
                container.textContent = block.textContent;
                block.closest("pre").replaceWith(container);
              });
            }

            function decorateCodeBlocks() {
              const codeBlocks = document.querySelectorAll("pre");

              codeBlocks.forEach((pre) => {
                if (pre.parentElement?.classList.contains("code-block")) {
                  return;
                }

                const wrapper = document.createElement("div");
                wrapper.className = "code-block";

                const button = document.createElement("button");
                button.className = "code-copy";
                button.type = "button";
                button.textContent = "Copy";
                button.addEventListener("click", () => {
                  const code = pre.innerText;
                  if (window.webkit?.messageHandlers?.copyCodeBlock) {
                    window.webkit.messageHandlers.copyCodeBlock.postMessage(code);
                  }
                  button.textContent = "Copied";
                  window.setTimeout(() => {
                    button.textContent = "Copy";
                  }, 1400);
                });

                pre.parentNode.insertBefore(wrapper, pre);
                wrapper.appendChild(button);
                wrapper.appendChild(pre);
              });
            }

            async function renderMarkdown() {
              marked.setOptions({
                gfm: true,
                breaks: false,
                mangle: false,
                headerIds: true
              });

              content.innerHTML = marked.parse(markdown);
              replaceMermaidBlocks();
              decorateCodeBlocks();

              if (window.mermaid) {
                mermaid.initialize({
                  startOnLoad: false,
                  theme: "dark",
                  securityLevel: "loose"
                });

                try {
                  await mermaid.run({ querySelector: ".mermaid" });
                } catch (error) {
                  console.error("Mermaid render failed", error);
                }
              }

              reportHeight();
              window.requestAnimationFrame(reportHeight);
              window.setTimeout(reportHeight, 120);
            }

            window.addEventListener("load", renderMarkdown);
            document.addEventListener("DOMContentLoaded", reportHeight);
          </script>
        </body>
        </html>
        """
    }

    private static let markedScript = loadScript(named: "marked.min")
    private static let mermaidScript = loadScript(named: "mermaid.min")

    private static func loadScript(named name: String) -> String {
        guard
            let url = Bundle.module.url(forResource: name, withExtension: "js"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return ""
        }

        return contents.replacingOccurrences(of: "</script", with: "<\\/script")
    }
}

private extension String {
    var htmlAttributeEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
