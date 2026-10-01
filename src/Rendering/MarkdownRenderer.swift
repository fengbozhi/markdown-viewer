import Foundation

/// Markdown 渲染器(内置 marked.js + highlight.js + mermaid.js + KaTeX,离线可用)
enum MarkdownRenderer {

    // MARK: 资源加载

    static let markedJS: String = loadResource("marked.min", "js") ?? ""
    static let hljsJS: String = loadResource("highlight.min", "js") ?? ""
    static let mermaidJS: String = loadResource("mermaid.min", "js") ?? ""
    static let katexJS: String = loadResource("katex.min", "js") ?? ""
    static let githubCSS: String = loadResource("github-markdown-light", "css") ?? ""
    static let githubDarkCSS: String = loadResource("github-markdown-dark", "css") ?? ""
    static let hljsCSS: String = loadResource("atom-one-dark.min", "css") ?? ""

    /// KaTeX 样式,字体路径改写为 local:// 指向 bundle 内字体
    static let katexCSS: String = {
        guard let css = loadResource("katex.min", "css") else { return "" }
        guard let fontsURL = Bundle.main.resourceURL?.appendingPathComponent("fonts"),
              let enc = fontsURL.path.addingPercentEncoding(
                  withAllowedCharacters: CharacterSet(charactersIn: "/")
                      .union(.alphanumerics)
                      .union(CharacterSet(charactersIn: "-._~!$&'()*+,;=:@"))) else { return css }
        return css.replacingOccurrences(of: "fonts/",
                                        with: LocalFileSchemeHandler.scheme + "://" + enc + "/")
    }()

    static func loadResource(_ name: String, _ ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let str = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return str
    }

    // MARK: 文件读取

    /// 读取文件(解码失败时也不会返回 nil)
    static func readFile(_ url: URL) -> String {
        if let data = try? Data(contentsOf: url) {
            return TextNormalizer.normalizeNewlines(String(decoding: data, as: UTF8.self))
        }
        return "*(无法读取文件)*"
    }

    /// 提取文档标题:第一个 `# 一级标题`
    static func extractTitle(from markdown: String) -> String {
        let normalized = TextNormalizer.normalizeNewlines(markdown)
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") && t.count > 2 {
                return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    // MARK: 资源路径改写

    /// 把 Markdown 中相对路径的图片/资源改写为 local:// 绝对路径
    static func absolutizeResources(in markdown: String, baseDir: URL) -> String {
        func convert(_ rawPath: String) -> String? {
            let p = rawPath.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { return nil }
            let lower = p.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://")
                || lower.hasPrefix("data:") || lower.hasPrefix("local:")
                || lower.hasPrefix("file:") || p.hasPrefix("#") {
                return nil
            }
            let absPath: String
            if p.hasPrefix("/") {
                absPath = URL(fileURLWithPath: p).standardizedFileURL.path
            } else {
                absPath = baseDir.appendingPathComponent(p).standardizedFileURL.path
            }
            guard let enc = absPath.addingPercentEncoding(
                withAllowedCharacters: CharacterSet(charactersIn: "/")
                    .union(.alphanumerics)
                    .union(CharacterSet(charactersIn: "-._~!$&'()*+,;=:@"))) else { return nil }
            return LocalFileSchemeHandler.scheme + "://" + enc
        }

        var result = markdown

        // 通用替换:按匹配逐个回调转换
        func replacing(_ regex: NSRegularExpression, in text: String, _ transform: (NSTextCheckingResult, NSString) -> String) -> String {
            let ns = text as NSString
            var out = ""
            var lastEnd = 0
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.range.location != NSNotFound else { return }
                out += ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
                out += transform(m, ns)
                lastEnd = m.range.location + m.range.length
            }
            out += ns.substring(from: lastEnd)
            return out
        }

        // 处理 Markdown 图片语法 ![alt](path "title") 与链接中的 <path> 形式
        if let regex = try? NSRegularExpression(pattern: "(!\\[[^\\]\\n]*\\]\\(\\s*)([^)\\s]+)([^)\\n]*\\))") {
            result = replacing(regex, in: result) { m, ns in
                if let abs = convert(ns.substring(with: m.range(at: 2))) {
                    return ns.substring(with: m.range(at: 1)) + abs + ns.substring(with: m.range(at: 3))
                }
                return ns.substring(with: m.range)
            }
        }
        // 处理内联 HTML <img src="..."> / <video src="...">
        if let regex = try? NSRegularExpression(pattern: "(<(?:img|video|source|audio)\\b[^>]*?\\bsrc\\s*=\\s*[\"'])([^\"']+)([\"'])") {
            result = replacing(regex, in: result) { m, ns in
                if let abs = convert(ns.substring(with: m.range(at: 2))) {
                    return ns.substring(with: m.range(at: 1)) + abs + ns.substring(with: m.range(at: 3))
                }
                return ns.substring(with: m.range)
            }
        }
        return result
    }

    // MARK: HTML 生成

    static func html(forFile url: URL, dark: Bool = false) -> String {
        let markdown = readFile(url)
        let processed = absolutizeResources(in: markdown, baseDir: url.deletingLastPathComponent())
        let html = buildHTML(markdown: processed, dark: dark)
        // 调试:设置环境变量 MDV_DUMP_HTML 时把生成的 HTML 写到 /tmp 供测试
        if ProcessInfo.processInfo.environment["MDV_DUMP_HTML"] != nil {
            try? html.write(toFile: "/tmp/mdv_dump.html", atomically: true, encoding: .utf8)
        }
        return html
    }

    /// 导出独立 HTML:把 local:// 引用的图片与字体全部内嵌为 base64,可脱离 App 分发
    static func standaloneHTML(forFile url: URL, dark: Bool = false) -> String {
        embedLocalResources(in: html(forFile: url, dark: dark))
    }

    /// 把 HTML 中 local:// 引用的资源(图片/字体)替换为 base64 data URI
    static func embedLocalResources(in html: String) -> String {
        // 匹配 src="local://..." 与 CSS url(local://...)
        guard let regex = try? NSRegularExpression(
            pattern: "(?:src=\"|url\\()local://([^\\)\"]+)") else { return html }

        let ns = html as NSString
        var out = ""
        var lastEnd = 0
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.range.location != NSNotFound else { return }
            out += ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
            let full = ns.substring(with: m.range)
            let encPath = ns.substring(with: m.range(at: 1))
            if let path = encPath.removingPercentEncoding,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                let mime = LocalFileSchemeHandler.mime(forExtension: URL(fileURLWithPath: path).pathExtension.lowercased())
                let dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
                out += full.hasPrefix("src=") ? "src=\"\(dataURI)" : "url(\(dataURI)"
            } else {
                out += full
            }
            lastEnd = m.range.location + m.range.length
        }
        out += ns.substring(from: lastEnd)
        return out
    }

    static func buildHTML(markdown: String, dark: Bool = false) -> String {
        // JSON 编码后嵌入 JS 字符串字面量,转义 </ 防止提前闭合 script
        let rawLiteral: String
        if let data = try? JSONEncoder().encode(markdown),
           let s = String(data: data, encoding: .utf8) {
            rawLiteral = s
        } else {
            rawLiteral = "\"\""
        }
        let mdLiteral = rawLiteral
            .replacingOccurrences(of: "</", with: "<\\/")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")

        let contentCSS = dark ? githubDarkCSS : githubCSS
        let bodyBg = dark ? "#0d1117" : "#ffffff"
        let markHit = dark ? "rgba(187, 128, 9, 0.45)" : "#ffe58f"
        let markCur = dark ? "rgba(249, 168, 37, 0.9)" : "#ffab40"
        let hlBg = dark ? "rgba(187, 128, 9, 0.4)" : "#fff3a3"
        let carbonBg = "#282c34"
        let carbonHeader = "#21252b"
        let copyBtnColor = "#8b949e"
        let copyBtnHover = "#e6edf3"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        \(contentCSS)
        \(hljsCSS)
        \(katexCSS)
        html, body { margin: 0; padding: 0; background: \(bodyBg); }
        .markdown-body {
          box-sizing: border-box;
          min-width: 200px;
          max-width: 1200px;
          margin: 0 auto;
          padding: 36px 44px;
          font-family: -apple-system, "PingFang SC", "Hiragino Sans GB", "Helvetica Neue", sans-serif;
        }
        .markdown-body img {
          background-color: transparent;
          cursor: zoom-in;
          -webkit-user-drag: none;
        }
        .markdown-body pre {
          position: relative;
          background: \(carbonBg);
          border-radius: 12px;
          padding: 0;
          margin: 16px 0;
          box-shadow: 0 8px 24px rgba(0,0,0,0.18);
          overflow: hidden;
        }
        .markdown-body pre .code-window-header {
          display: flex;
          align-items: center;
          gap: 8px;
          height: 32px;
          padding: 0 14px;
          background: \(carbonHeader);
          border-bottom: 1px solid rgba(255,255,255,0.06);
          -webkit-user-select: none;
          user-select: none;
        }
        .markdown-body pre .code-window-header .dot {
          width: 10px;
          height: 10px;
          border-radius: 50%;
          flex-shrink: 0;
        }
        .markdown-body pre .code-window-header .dot:nth-child(1) { background: #ff5f56; }
        .markdown-body pre .code-window-header .dot:nth-child(2) { background: #ffbd2e; }
        .markdown-body pre .code-window-header .dot:nth-child(3) { background: #27c93f; }
        .markdown-body pre .code-lang {
          margin-left: 6px;
          font-size: 11px;
          color: #7d8590;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }
        .markdown-body pre .code-copy-btn {
          margin-left: auto;
          border: none;
          background: transparent;
          color: \(copyBtnColor);
          font-size: 11px;
          cursor: pointer;
          padding: 2px 8px;
          border-radius: 4px;
          font-family: -apple-system, "PingFang SC", sans-serif;
        }
        .markdown-body pre .code-copy-btn:hover { color: \(copyBtnHover); background: rgba(255,255,255,0.08); }
        .markdown-body pre code.hljs {
          display: block;
          background: \(carbonBg) !important;
          padding: 12px 16px 16px 0;
          margin: 0;
          font-family: "SF Mono", "JetBrains Mono", "Fira Code", "Menlo", "Monaco", monospace;
          font-size: 13px;
          line-height: 1.6;
          overflow-x: auto;
        }
        .markdown-body pre code .code-line {
          display: block;
          padding-left: 3.2em;
          position: relative;
        }
        .markdown-body pre code .code-line::before {
          content: attr(data-line);
          position: absolute;
          left: 0;
          width: 2.2em;
          text-align: right;
          color: #4b5263;
          -webkit-user-select: none;
          user-select: none;
        }
        .mermaid-chart {
          display: flex;
          justify-content: center;
          margin: 16px 0;
          overflow-x: auto;
        }
        .mermaid-chart svg { max-width: 100%; height: auto; }
        mark.mdv-hit { background: \(markHit); color: inherit; border-radius: 2px; }
        mark.mdv-current { background: \(markCur); color: inherit; border-radius: 2px; }
        mark.mdv-hl { background: \(hlBg); color: inherit; border-radius: 3px; padding: 0 1px; }
        .mdv-toc {
          border: 1px solid var(--color-border-default, rgba(128,128,128,0.2));
          border-radius: 10px;
          padding: 14px 18px;
          margin: 16px 0;
          background: var(--color-canvas-subtle, rgba(128,128,128,0.05));
        }
        .mdv-toc-title { font-weight: 600; margin-bottom: 6px; font-size: 0.95em; }
        .mdv-toc ul { list-style: none; margin: 0; padding: 0; }
        .mdv-toc li { margin: 2px 0; line-height: 1.5; }
        .mdv-toc li a { text-decoration: none; }
        .mdv-toc .mdv-toc-l1 { padding-left: 0; font-weight: 600; }
        .mdv-toc .mdv-toc-l2 { padding-left: 18px; }
        .mdv-toc .mdv-toc-l3 { padding-left: 36px; font-size: 0.92em; }
        .mdv-toc .mdv-toc-l4, .mdv-toc .mdv-toc-l5, .mdv-toc .mdv-toc-l6 { padding-left: 54px; font-size: 0.88em; }
        .footnotes { font-size: 0.86em; color: var(--color-fg-muted, #666); }
        .footnotes hr { margin: 24px 0 12px; }
        .footnotes ol { padding-left: 20px; }
        .footnotes li { margin: 3px 0; }
        .footnote-ref a { text-decoration: none; }
        .footnote-backref { text-decoration: none; margin-left: 4px; opacity: 0.7; }
        .katex-display { margin: 16px 0; overflow-x: auto; overflow-y: hidden; }
        /* GitHub/Obsidian 风格 Callout 提示框 */
        .mdv-callout {
          border: 1px solid var(--color-border-default, rgba(128,128,128,0.25));
          border-left: 4px solid #888;
          border-radius: 8px;
          padding: 10px 14px;
          margin: 16px 0;
          background: var(--color-canvas-subtle, rgba(128,128,128,0.05));
        }
        .mdv-callout > p { margin: 6px 0; }
        .mdv-callout-title { font-weight: 600; font-size: 0.95em; }
        /* YAML Front Matter 属性面板(Obsidian Properties 风格) */
        .mdv-frontmatter {
          border: 1px solid var(--color-border-default, rgba(128,128,128,0.25));
          border-radius: 10px;
          margin: 0 0 24px;
          font-size: 0.9em;
          overflow: hidden;
        }
        .mdv-fm-head {
          padding: 8px 14px;
          font-weight: 600;
          background: var(--color-canvas-subtle, rgba(128,128,128,0.08));
          border-bottom: 1px solid var(--color-border-default, rgba(128,128,128,0.2));
        }
        .mdv-fm-row {
          display: flex;
          padding: 6px 14px;
          border-top: 1px solid var(--color-border-muted, rgba(128,128,128,0.12));
        }
        .mdv-fm-key { width: 130px; flex-shrink: 0; color: var(--color-fg-muted, #666); font-weight: 500; }
        .mdv-fm-val { word-break: break-word; }
        /* 任务列表复选框(可点击) */
        .markdown-body input[type="checkbox"] {
          cursor: pointer;
          width: 15px;
          height: 15px;
          margin: 0 6px 0 0;
          vertical-align: -2px;
        }
        .mdv-transform {
          display: inline-flex;
          align-items: center;
          gap: 10px;
          background: var(--color-neutral-muted, rgba(128,128,128,0.08));
          border: 1px solid var(--color-border-default, rgba(128,128,128,0.15));
          border-radius: 8px;
          padding: 6px 10px;
          margin: 2px 0;
          vertical-align: middle;
          line-height: 1.3;
        }
        .mdv-transform-side {
          display: flex;
          flex-direction: column;
          align-items: center;
          min-width: 0;
          max-width: 160px;
        }
        .mdv-transform-icon { font-size: 1.1em; line-height: 1; margin-bottom: 2px; }
        .mdv-transform-name {
          font-size: 0.9em;
          font-weight: 500;
          color: var(--color-fg-default, inherit);
          max-width: 100%;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .mdv-transform-url {
          font-size: 0.75em;
          color: var(--color-fg-muted, #888);
          max-width: 100%;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .mdv-transform-arrow {
          color: var(--color-fg-muted, #999);
          font-weight: bold;
          font-size: 1.1em;
          padding: 0 2px;
          flex-shrink: 0;
        }
        /* 取消 GitHub 默认的 pre 内边距与背景,交由自定义 Carbon 样式接管 */
        .markdown-body pre,
        .markdown-body pre > code {
          background: \(carbonBg) !important;
        }
        .markdown-body pre code.hljs {
          background: \(carbonBg) !important;
        }
        /* 行内代码保持浅色胶囊样式(不适用于代码块) */
        .markdown-body :not(pre) > code {
          background: \(dark ? "rgba(110,118,129,0.4)" : "rgba(175,184,193,0.2)");
          color: \(dark ? "#e6edf3" : "#1f2328");
          border-radius: 6px;
          padding: 0.2em 0.4em;
          font-family: "SF Mono", "Menlo", "Monaco", monospace;
          font-size: 0.88em;
        }
        </style>
        </head>
        <body>
        <div class="markdown-body" id="content"></div>
        <script>\(markedJS)</script>
        <script>\(hljsJS)</script>
        <script>\(mermaidJS)</script>
        <script>\(katexJS)</script>
        <script>
        var MDV_DARK = \(dark);
        var HEADING_SELECTOR = ".markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6";
        var MATH_TOKEN_RE = /@@MDVMATH(\\d+)@@/g;

        try {
          var MD = \(mdLiteral);
          // 0) 提取 YAML Front Matter(渲染为属性面板)
          var fm = extractFrontMatter(MD);
          MD = fm.md;
          // 1) 提取脚注定义 [^id]: 文本
          var footnoteDefs = extractFootnoteDefs(MD);
          MD = footnoteDefs.md;
          // 2) 保护数学公式(跳过代码围栏),防止 marked 误解析公式内符号
          var mathProtected = protectMath(MD);
          MD = mathProtected.md;
          var mathStore = mathProtected.store;
          // 3) Markdown 解析
          // 自定义 del 分词器:单 ~ 不再解析为删除线(留给 ~下标~ 语法),双 ~~ 仍为删除线
          if (marked.use) {
            marked.use({
              tokenizer: {
                del: function (src) {
                  var m2 = src.match(/^~~(?=\\S)([\\s\\S]*?[^\\s~])~~(?!~)/);
                  if (m2) {
                    return { type: "del", raw: m2[0], text: m2[1], tokens: this.lexer.inlineTokens(m2[1]) };
                  }
                  if (/^~(?!~)/.test(src)) {
                    return { type: "text", raw: "~", text: "~" };
                  }
                }
              }
            });
          }
          var contentEl = document.getElementById("content");
          contentEl.innerHTML = marked.parse(MD, { gfm: true, breaks: false });
          // 4) 修复 marked.js 对中文紧接 ** 的加粗/斜体解析失败(如 **生成提示词：**根据)
          fixCJKEmphasis(contentEl);
          // 5) 还原并渲染数学公式(KaTeX)
          restoreMath(contentEl, mathStore);
          // 6) 标题加锚点 id + 渲染 [TOC] 目录
          assignHeadingIds();
          renderTOC();
          // 7) 渲染脚注引用与脚注区
          renderFootnotes(contentEl, footnoteDefs.defs);
          // 8) 扩展语法:==高亮== / ~下标~ / ^上标^
          renderInlineExtras(contentEl);
          // 9) GitHub/Obsidian 风格 Callout(> [!NOTE] / [!TIP] / [!WARNING] ...)
          renderCallouts(contentEl);
          // 10) Emoji 短代码(:smile: → 😄)
          renderEmojis(contentEl);
          // 11) 任务列表复选框:可点击,点击后回写源文件
          enableTaskCheckboxes();
          // 12) Front Matter 属性面板(置于文档顶部)
          renderFrontMatter(contentEl, fm.data);
          // 13) 代码高亮(跳过 mermaid)
          if (window.hljs) {
            hljs.configure({ ignoreUnescapedHTML: true });
            document.querySelectorAll("pre code").forEach(function (el) {
              if (el.className.indexOf("language-mermaid") === -1) {
                try { hljs.highlightElement(el); } catch (e) {}
              }
            });
          }
          // 14) 美化图片转换说明: ![原图名](本地路径) -> ![VL模型描述](MinIO URL)
          applyImageTransforms(contentEl);
          // 15) Carbon 风格代码块:窗口按钮 + 语言标签 + 复制按钮 + 行号
          styleCodeBlocks();
          // 16) Mermaid 流程图渲染:把 ```mermaid 代码块转换为图表
          if (window.mermaid) {
            mermaid.initialize({
              startOnLoad: false,
              theme: MDV_DARK ? "dark" : "default",
              securityLevel: "loose",
              fontFamily: '-apple-system, "PingFang SC", "Hiragino Sans GB", sans-serif'
            });
            var mmdBlocks = document.querySelectorAll("pre code.language-mermaid");
            (async function () {
              var seq = 0;
              for (var el of mmdBlocks) {
                var pre = el.closest("pre");
                if (!pre) { continue; }
                try {
                  var result = await mermaid.render("mmd-svg-" + Date.now() + "-" + (seq++), el.textContent);
                  var chart = document.createElement("div");
                  chart.className = "mermaid-chart";
                  chart.innerHTML = result.svg;
                  pre.replaceWith(chart);
                } catch (err) {
                  // 渲染失败时保留原始代码块
                  console.warn("mermaid render failed:", err);
                }
              }
            })();
          }
        } catch (e) {
          document.getElementById("content").textContent = "渲染出错: " + e.message;
        }

        // ---- 脚注:提取定义(行首 [^id]: 文本),返回剥离定义后的 Markdown ----
        function extractFootnoteDefs(md) {
          var defs = {};
          var out = md.replace(/^\\[\\^([^\\]\\n]+)\\]:[^\\S\\n]*(.*)$/gm, function (_, id, text) {
            defs[id.trim()] = text;
            return "";
          });
          return { md: out, defs: defs };
        }

        // ---- 数学公式保护:跳过代码围栏,把 $...$ / $$...$$ 替换为占位符 ----
        function protectMath(md) {
          var store = [];
          var out = [];
          var inFence = false;
          var buf = [];
          function flush() {
            if (!buf.length) return;
            var seg = buf.join("\\n");
            seg = seg.replace(/\\$\\$([\\s\\S]+?)\\$\\$/g, function (m) {
              store.push({ tex: m.slice(2, -2), display: true });
              return "@@MDVMATH" + (store.length - 1) + "@@";
            });
            // 行内公式:Pandoc 规则($ 后不跟空格,闭 $ 前不是空格且后不跟数字,避免误判价格)
            seg = seg.replace(/(?<![\\\\$])\\$(?!\\s)((?:[^$\\n\\\\]|\\\\.)*?)(?<!\\s)\\$(?!\\d)/g, function (m, tex) {
              store.push({ tex: tex, display: false });
              return "@@MDVMATH" + (store.length - 1) + "@@";
            });
            out.push(seg);
            buf = [];
          }
          var lines = md.split("\\n");
          for (var i = 0; i < lines.length; i++) {
            if (/^\\s*(```|~~~)/.test(lines[i])) {
              flush();
              out.push(lines[i]);
              inFence = !inFence;
              continue;
            }
            if (inFence) out.push(lines[i]); else buf.push(lines[i]);
          }
          flush();
          return { md: out.join("\\n"), store: store };
        }

        // ---- 还原并渲染数学公式 ----
        function restoreMath(root, store) {
          if (!store.length) return;
          // 正文中的占位符 → KaTeX 渲染
          var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
              var el = node.parentElement;
              if (!el || el.closest("pre, code, script, style")) return NodeFilter.FILTER_REJECT;
              MATH_TOKEN_RE.lastIndex = 0;
              return MATH_TOKEN_RE.test(node.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
          });
          var nodes = [];
          while (walker.nextNode()) nodes.push(walker.currentNode);
          nodes.forEach(function (node) {
            MATH_TOKEN_RE.lastIndex = 0;
            var frag = document.createDocumentFragment();
            var text = node.nodeValue, last = 0, m;
            while ((m = MATH_TOKEN_RE.exec(text)) !== null) {
              var item = store[parseInt(m[1], 10)];
              frag.appendChild(document.createTextNode(text.slice(last, m.index)));
              if (item && window.katex) {
                var span = document.createElement("span");
                try { katex.render(item.tex, span, { displayMode: item.display, throwOnError: false }); }
                catch (e) { span.textContent = item.display ? "$$" + item.tex + "$$" : "$" + item.tex + "$"; }
                frag.appendChild(span);
              } else if (item) {
                frag.appendChild(document.createTextNode(item.display ? "$$" + item.tex + "$$" : "$" + item.tex + "$"));
              }
              last = m.index + m[0].length;
            }
            frag.appendChild(document.createTextNode(text.slice(last)));
            node.parentNode.replaceChild(frag, node);
          });
          // 代码块/行内代码里残留的占位符 → 还原为原始 $ 文本
          root.querySelectorAll("code").forEach(function (code) {
            if (code.textContent.indexOf("@@MDVMATH") === -1) return;
            var w2 = document.createTreeWalker(code, NodeFilter.SHOW_TEXT, null);
            var ns = [], n;
            while ((n = w2.nextNode())) ns.push(n);
            ns.forEach(function (node) {
              MATH_TOKEN_RE.lastIndex = 0;
              node.nodeValue = node.nodeValue.replace(MATH_TOKEN_RE, function (_, idx) {
                var item = store[parseInt(idx, 10)];
                if (!item) return "";
                return item.display ? "$$" + item.tex + "$$" : "$" + item.tex + "$";
              });
            });
          });
        }

        // ---- 标题锚点 id(与 Swift 端大纲提取顺序一致) ----
        function assignHeadingIds() {
          document.querySelectorAll(HEADING_SELECTOR).forEach(function (h, i) {
            h.id = "mdv-h-" + i;
          });
        }

        // ---- [TOC] 目录渲染 ----
        function renderTOC() {
          var hs = document.querySelectorAll(HEADING_SELECTOR);
          if (!hs.length) return;
          function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
          document.querySelectorAll(".markdown-body p").forEach(function (p) {
            if (p.textContent.trim() !== "[TOC]") return;
            var html = '<div class="mdv-toc-title">目录</div><ul>';
            hs.forEach(function (h) {
              var lvl = parseInt(h.tagName.substring(1), 10);
              html += '<li class="mdv-toc-l' + lvl + '"><a href="#' + h.id + '">' + esc(h.textContent) + "</a></li>";
            });
            html += "</ul>";
            var nav = document.createElement("nav");
            nav.className = "mdv-toc";
            nav.innerHTML = html;
            p.replaceWith(nav);
          });
        }

        // ---- 脚注渲染 ----
        function renderFootnotes(root, defs) {
          var refPattern = /\\[\\^([^\\]\\n]+)\\]/g;
          var order = [];   // 按出现顺序编号
          var indexOf = {};
          var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
              var el = node.parentElement;
              if (!el || el.closest("pre, code, script, style")) return NodeFilter.FILTER_REJECT;
              refPattern.lastIndex = 0;
              return refPattern.test(node.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
          });
          var nodes = [];
          while (walker.nextNode()) nodes.push(walker.currentNode);
          nodes.forEach(function (node) {
            refPattern.lastIndex = 0;
            var frag = document.createDocumentFragment();
            var text = node.nodeValue, last = 0, m;
            while ((m = refPattern.exec(text)) !== null) {
              var id = m[1].trim();
              if (!(id in defs)) continue;   // 无定义的引用保持原文
              if (!(id in indexOf)) { indexOf[id] = order.length + 1; order.push(id); }
              var num = indexOf[id];
              frag.appendChild(document.createTextNode(text.slice(last, m.index)));
              var sup = document.createElement("sup");
              sup.className = "footnote-ref";
              sup.innerHTML = '<a href="#mdv-fn-' + num + '" id="mdv-fnref-' + num + '">[' + num + "]</a>";
              frag.appendChild(sup);
              last = m.index + m[0].length;
            }
            frag.appendChild(document.createTextNode(text.slice(last)));
            node.parentNode.replaceChild(frag, node);
          });
          if (!order.length) return;
          function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
          var html = "<hr><ol>";
          order.forEach(function (id) {
            var num = indexOf[id];
            html += '<li id="mdv-fn-' + num + '">' + esc(defs[id]) +
                    ' <a class="footnote-backref" href="#mdv-fnref-' + num + '">↩</a></li>';
          });
          html += "</ol>";
          var section = document.createElement("section");
          section.className = "footnotes";
          section.innerHTML = html;
          root.appendChild(section);
        }

        // ---- 扩展语法:==高亮== / ~下标~ / ^上标^ ----
        function renderInlineExtras(root) {
          var hlPattern = /==([^=\\n]+)==/g;
          var subPattern = /(?<!~)~([^\\s~][^\\s~\\n]*?)~(?!~)/g;
          var supPattern = /(?<!\\^)\\^([^\\s^][^\\s^\\n]*?)\\^(?!\\^)/g;
          function anyMatch(text) {
            hlPattern.lastIndex = 0; subPattern.lastIndex = 0; supPattern.lastIndex = 0;
            return hlPattern.test(text) || subPattern.test(text) || supPattern.test(text);
          }
          function transform(text) {
            hlPattern.lastIndex = 0; subPattern.lastIndex = 0; supPattern.lastIndex = 0;
            return text
              .replace(hlPattern, '<mark class="mdv-hl">$1</mark>')
              .replace(subPattern, "<sub>$1</sub>")
              .replace(supPattern, "<sup>$1</sup>");
          }
          var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
              var el = node.parentElement;
              if (!el || el.closest("pre, code, script, style, .katex, mark.mdv-hl")) return NodeFilter.FILTER_REJECT;
              return anyMatch(node.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
          });
          var nodes = [];
          while (walker.nextNode()) nodes.push(walker.currentNode);
          nodes.forEach(function (node) {
            var html = transform(node.nodeValue);
            if (html === node.nodeValue) return;
            var span = document.createElement("span");
            span.innerHTML = html;
            node.parentNode.replaceChild(span, node);
          });
        }

        // 修复中文边界导致的强调符解析失败(**加粗*斜体*)
        function fixCJKEmphasis(root) {
          var strongPattern = /(?<!\\*)\\*\\*([^\\*]+?)\\*\\*(?!\\*)/g;
          var emPattern = /(?<!\\*)\\*([^\\*\\n]+?)\\*(?!\\*)/g;
          function replaceInNode(text) {
            var changed = false;
            strongPattern.lastIndex = 0;
            emPattern.lastIndex = 0;
            var hasStrong = strongPattern.test(text);
            var hasEm = emPattern.test(text);
            if (!hasStrong && !hasEm) return null;
            var html = text
              .replace(strongPattern, "<strong>$1</strong>")
              .replace(emPattern, "<em>$1</em>");
            return html;
          }
          var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function(node) {
              var el = node.parentElement;
              if (!el || el.closest("code, pre, strong, em, .katex")) return NodeFilter.FILTER_REJECT;
              strongPattern.lastIndex = 0;
              emPattern.lastIndex = 0;
              return (strongPattern.test(node.nodeValue) || emPattern.test(node.nodeValue)) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
          });
          var nodes = [];
          while (walker.nextNode()) nodes.push(walker.currentNode);
          nodes.forEach(function(node) {
            var html = replaceInNode(node.nodeValue);
            if (!html) return;
            var span = document.createElement("span");
            span.innerHTML = html;
            node.parentNode.replaceChild(span, node);
          });
        }

        // Carbon 风格代码块:窗口按钮 + 语言标签 + 复制按钮 + 行号
        function styleCodeBlocks() {
          document.querySelectorAll("pre").forEach(function (pre) {
            if (pre.querySelector(".code-window-header")) return;
            if (pre.querySelector(".mermaid-chart")) return;
            var code = pre.querySelector("code");
            if (!code) return;
            // 复制用的原始代码文本(高亮不影响 textContent)
            var rawText = code.textContent || "";
            // 语言标签
            var lang = "";
            var m = (code.className || "").match(/language-([a-zA-Z0-9#+_-]+)/);
            if (m) lang = m[1];
            // 顶部窗口按钮 + 语言 + 复制
            var header = document.createElement("div");
            header.className = "code-window-header";
            header.innerHTML = '<span class="dot"></span><span class="dot"></span><span class="dot"></span>' +
              (lang ? '<span class="code-lang"></span>' : "") +
              '<button class="code-copy-btn" type="button">复制</button>';
            if (lang) header.querySelector(".code-lang").textContent = lang;
            var btn = header.querySelector(".code-copy-btn");
            btn.addEventListener("click", function () { copyText(btn, rawText); });
            pre.insertBefore(header, pre.firstChild);
            // 行号
            var text = code.innerHTML;
            var lines = text.split("\\n");
            var numbered = lines.map(function (line, idx) {
              return '<span class="code-line" data-line="' + (idx + 1) + '">' + (line || " ") + '</span>';
            }).join("\\n");
            code.innerHTML = numbered;
          });
        }
        // 复制到剪贴板(clipboard API 不可用时回退 execCommand)
        function copyText(btn, text) {
          function done() {
            btn.textContent = "已复制";
            setTimeout(function () { btn.textContent = "复制"; }, 1500);
          }
          function fallback() {
            var ta = document.createElement("textarea");
            ta.value = text;
            ta.style.position = "fixed";
            ta.style.opacity = "0";
            document.body.appendChild(ta);
            ta.select();
            try { document.execCommand("copy"); } catch (e) {}
            ta.remove();
            done();
          }
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(done, fallback);
          } else {
            fallback();
          }
        }

        // 美化图片转换说明: ![alt1](url1) -> ![alt2](url2)
        function applyImageTransforms(root) {
          var transformPattern = /!\\[([^\\]]*)\\]\\(([^)]+)\\)\\s*->\\s*!\\[([^\\]]*)\\]\\(([^)]+)\\)/g;
          function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
          function side(icon, alt, url) {
            return '<span class="mdv-transform-side">' +
              '<span class="mdv-transform-icon">' + icon + '</span>' +
              '<span class="mdv-transform-name" title="' + esc(alt) + '">' + esc(alt || "图片") + '</span>' +
              '<span class="mdv-transform-url" title="' + esc(url) + '">' + esc(url) + '</span>' +
              '</span>';
          }
          function makeCard(alt1, url1, alt2, url2) {
            return '<span class="mdv-transform">' +
              side("🖼", alt1, url1) +
              '<span class="mdv-transform-arrow">→</span>' +
              side("🖼", alt2, url2) +
              '</span>';
          }
          function replaceInText(text) {
            transformPattern.lastIndex = 0;
            if (!transformPattern.test(text)) return null;
            transformPattern.lastIndex = 0;
            return text.replace(transformPattern, function (_, alt1, url1, alt2, url2) {
              return makeCard(alt1, url1, alt2, url2);
            });
          }

          // 1) 处理行内代码中的转换说明(多行代码块<pre><code>保持原样)
          root.querySelectorAll("code").forEach(function (code) {
            if (code.closest("pre")) return;
            var html = replaceInText(code.textContent);
            if (!html) return;
            var wrapper = document.createElement("span");
            wrapper.innerHTML = html;
            code.parentNode.replaceChild(wrapper, code);
          });

          // 2) 处理普通文本节点
          var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function(node) {
              var el = node.parentElement;
              if (!el || el.closest("code, pre")) return NodeFilter.FILTER_REJECT;
              transformPattern.lastIndex = 0;
              return transformPattern.test(node.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
          });
          var nodes = [];
          while (walker.nextNode()) nodes.push(walker.currentNode);
          nodes.forEach(function(node) {
            var html = replaceInText(node.nodeValue);
            if (!html) return;
            var span = document.createElement("span");
            span.innerHTML = html;
            node.parentNode.replaceChild(span, node);
          });
        }

        // ---- YAML Front Matter:提取文档头部 ---...--- 元数据 ----
        function extractFrontMatter(md) {
          var m = md.match(/^---[^\\S\\n]*\\n([\\s\\S]*?)\\n---[^\\S\\n]*(?:\\n|$)/);
          if (!m) return { md: md, data: null };
          var lines = m[1].split("\\n");
          var rows = [];
          function stripQuote(s) { return s.replace(/^["']|["']$/g, ""); }
          for (var i = 0; i < lines.length; i++) {
            var km = lines[i].match(/^([^:\\n]+):[^\\S\\n]*(.*)$/);
            if (!km) continue;
            var key = km[1].trim();
            if (!key || key.charAt(0) === "-") continue;
            var val = stripQuote(km[2].trim());
            if (val === "") {
              // 数组形式:后续缩进的 - item 行
              var items = [];
              while (i + 1 < lines.length && /^\\s+-\\s+/.test(lines[i + 1])) {
                i++;
                items.push(stripQuote(lines[i].replace(/^\\s+-\\s+/, "").trim()));
              }
              rows.push([key, items.join(", ")]);
              continue;
            }
            // 行内数组 [a, b]
            var am = val.match(/^\\[(.*)\\]$/);
            if (am) {
              val = am[1].split(",").map(function (s) { return stripQuote(s.trim()); }).filter(Boolean).join(", ");
            }
            rows.push([key, val]);
          }
          return { md: md.slice(m[0].length), data: rows.length ? rows : null };
        }

        // ---- Front Matter 属性面板渲染 ----
        function renderFrontMatter(root, data) {
          if (!data || !data.length) return;
          function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
          var html = '<div class="mdv-fm-head">📋 属性</div>';
          data.forEach(function (kv) {
            html += '<div class="mdv-fm-row"><span class="mdv-fm-key">' + esc(kv[0]) +
                    '</span><span class="mdv-fm-val">' + esc(kv[1] || "—") + "</span></div>";
          });
          var el = document.createElement("div");
          el.className = "mdv-frontmatter";
          el.innerHTML = html;
          root.insertBefore(el, root.firstChild);
        }

        // ---- GitHub/Obsidian 风格 Callout(> [!TYPE]) ----
        // 注意:用函数包裹数据表,利用函数声明提升,保证 try 块中可调用(var 赋值不提升)
        function calloutDefs() { return {
          note: ["#0969da", "ℹ️", "Note"], info: ["#0969da", "ℹ️", "Info"], todo: ["#0969da", "☑️", "Todo"],
          tip: ["#1a7f37", "💡", "Tip"], success: ["#1a7f37", "✅", "Success"],
          check: ["#1a7f37", "✅", "Success"], done: ["#1a7f37", "✅", "Success"],
          important: ["#8250df", "❗", "Important"], example: ["#8250df", "📝", "Example"],
          warning: ["#9a6700", "⚠️", "Warning"], question: ["#9a6700", "❓", "Question"],
          help: ["#9a6700", "❓", "Question"], faq: ["#9a6700", "❓", "Question"],
          caution: ["#cf222e", "🔥", "Caution"], danger: ["#cf222e", "🔥", "Danger"],
          error: ["#cf222e", "🔥", "Error"], failure: ["#cf222e", "❌", "Failure"],
          fail: ["#cf222e", "❌", "Failure"], missing: ["#cf222e", "❌", "Missing"], bug: ["#cf222e", "🐛", "Bug"],
          quote: ["#57606a", "💬", "Quote"], cite: ["#57606a", "💬", "Quote"],
          abstract: ["#0e7490", "📄", "Abstract"], summary: ["#0e7490", "📄", "Abstract"]
        }; }
        function renderCallouts(root) {
          var CALLOUT_DEFS = calloutDefs();
          root.querySelectorAll("blockquote").forEach(function (bq) {
            var first = bq.querySelector("p");
            if (!first) return;
            var m = first.innerHTML.match(/^\\s*\\[!([A-Za-z]+)\\](<br\\s*\\/?>)?/);
            if (!m) return;
            var def = CALLOUT_DEFS[m[1].toLowerCase()];
            if (!def) return;
            first.innerHTML = first.innerHTML.slice(m[0].length);
            if (!first.innerHTML.trim()) first.remove();
            var box = document.createElement("div");
            box.className = "mdv-callout";
            box.style.borderLeftColor = def[0];
            var title = document.createElement("div");
            title.className = "mdv-callout-title";
            title.style.color = def[0];
            title.textContent = def[1] + " " + def[2];
            box.appendChild(title);
            while (bq.firstChild) box.appendChild(bq.firstChild);
            bq.parentNode.replaceChild(box, bq);
          });
        }

        // ---- Emoji 短代码(:smile: → 😄,GitHub/Obsidian 风格) ----
        function emojiMap() { return {
          "smile":"😄","smiley":"😃","grin":"😁","laughing":"😆","joy":"😂","rofl":"🤣",
          "wink":"😉","blush":"😊","yum":"😋","sunglasses":"😎","nerd_face":"🤓","thinking":"🤔",
          "neutral_face":"😐","expressionless":"😑","sleeping":"😴","mask":"😷","cry":"😢","sob":"😭",
          "angry":"😠","rage":"😡","scream":"😱","confused":"😕","upside_down_face":"🙃",
          "rolling_eyes":"🙄","zipper_mouth_face":"🤐","lying_face":"🤥","sweat_smile":"😅",
          "grimacing":"😬","hugs":"🤗","star_struck":"🤩","partying_face":"🥳",
          "heart":"❤️","orange_heart":"🧡","yellow_heart":"💛","green_heart":"💚","blue_heart":"💙",
          "purple_heart":"💜","black_heart":"🖤","broken_heart":"💔","sparkling_heart":"💖","two_hearts":"💕",
          "thumbsup":"👍","+1":"👍","thumbsdown":"👎","-1":"👎","ok_hand":"👌","clap":"👏",
          "raised_hands":"🙌","pray":"🙏","muscle":"💪","wave":"👋","point_up":"☝️","point_down":"👇",
          "point_left":"👈","point_right":"👉","v":"✌️","handshake":"🤝","writing_hand":"✍️",
          "eyes":"👀","eye":"👁️","brain":"🧠","speech_balloon":"💬","thought_balloon":"💭","zzz":"💤",
          "fire":"🔥","sparkles":"✨","star":"⭐","star2":"🌟","zap":"⚡","boom":"💥","dizzy":"💫",
          "sunny":"☀️","cloud":"☁️","rainbow":"🌈","snowflake":"❄️","umbrella":"☔","ocean":"🌊",
          "rocket":"🚀","airplane":"✈️","car":"🚗","taxi":"🚕","bus":"🚌","train":"🚆","ship":"🚢","anchor":"⚓",
          "tada":"🎉","confetti_ball":"🎊","balloon":"🎈","gift":"🎁","trophy":"🏆","medal":"🏅",
          "100":"💯","check":"✔️","white_check_mark":"✅","x":"❌","no_entry":"⛔","warning":"⚠️",
          "question":"❓","exclamation":"❗","bangbang":"‼️","bulb":"💡","mag":"🔍","mag_right":"🔎",
          "lock":"🔒","unlock":"🔓","key":"🔑","hammer":"🔨","wrench":"🔧","gear":"⚙️","link":"🔗",
          "paperclip":"📎","pushpin":"📌","scissors":"✂️","calendar":"📅","memo":"📝","pencil2":"✏️",
          "book":"📖","books":"📚","notebook":"📓","bookmark":"🔖","label":"🏷️",
          "computer":"💻","keyboard":"⌨️","iphone":"📱","email":"📧","inbox_tray":"📥","outbox_tray":"📤",
          "hourglass":"⌛","watch":"⌚","battery":"🔋","money_with_wings":"💸","gem":"💎",
          "house":"🏠","office":"🏢","hospital":"🏥","school":"🏫","church":"⛪",
          "bug":"🐛","robot":"🤖","ghost":"👻","alien":"👽","skull":"💀","poop":"💩",
          "cat":"🐱","dog":"🐶","mouse":"🐭","rabbit":"🐰","fox_face":"🦊","bear":"🐻","panda_face":"🐼",
          "tiger":"🐯","lion":"🦁","pig":"🐷","frog":"🐸","monkey":"🐵","chicken":"🐔","penguin":"🐧",
          "bird":"🐦","unicorn":"🦄","bee":"🐝","turtle":"🐢","snake":"🐍","octopus":"🐙","fish":"🐟","whale":"🐳",
          "apple":"🍎","banana":"🍌","grapes":"🍇","strawberry":"🍓","watermelon":"🍉","peach":"🍑",
          "cherries":"🍒","pineapple":"🍍","mango":"🥭","lemon":"🍋","avocado":"🥑","tomato":"🍅",
          "bread":"🍞","cheese":"🧀","egg":"🥚","hamburger":"🍔","pizza":"🍕","taco":"🌮","sushi":"🍣",
          "ramen":"🍜","rice":"🍚","ice_cream":"🍨","cake":"🍰","birthday":"🎂","chocolate_bar":"🍫","candy":"🍬",
          "coffee":"☕","tea":"🍵","beer":"🍺","beers":"🍻","wine_glass":"🍷","cocktail":"🍸","milk":"🥛",
          "soccer":"⚽","basketball":"🏀","football":"🏈","baseball":"⚾","tennis":"🎾","volleyball":"🏐",
          "dart":"🎯","video_game":"🎮","game_die":"🎲","chess_pawn":"♟️","guitar":"🎸","microphone":"🎤",
          "headphones":"🎧","art":"🎨","clapper":"🎬","camera":"📷","movie_camera":"🎥"
        }; }
        function renderEmojis(root) {
          var EMOJI_MAP = emojiMap();
          var re = /:([a-zA-Z0-9_+\\-]+):/g;
          function hasEmoji(text) {
            re.lastIndex = 0;
            var m;
            while ((m = re.exec(text)) !== null) { if (EMOJI_MAP[m[1]]) return true; }
            return false;
          }
          var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
              var el = node.parentElement;
              if (!el || el.closest("pre, code, script, style, .katex")) return NodeFilter.FILTER_REJECT;
              return hasEmoji(node.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
          });
          var nodes = [];
          while (walker.nextNode()) nodes.push(walker.currentNode);
          nodes.forEach(function (node) {
            re.lastIndex = 0;
            var text = node.nodeValue;
            var out = "", last = 0, m, changed = false;
            while ((m = re.exec(text)) !== null) {
              var e = EMOJI_MAP[m[1]];
              if (!e) continue;
              changed = true;
              out += text.slice(last, m.index) + e;
              last = m.index + m[0].length;
            }
            if (changed) node.nodeValue = out + text.slice(last);
          });
        }

        // ---- 任务列表复选框:可点击,点击事件上报原生回写源文件 ----
        function enableTaskCheckboxes() {
          document.querySelectorAll('input[type="checkbox"]').forEach(function (cb, idx) {
            cb.removeAttribute("disabled");
            cb.addEventListener("change", function () {
              var handlers = (window.webkit && window.webkit.messageHandlers) || {};
              if (handlers.taskToggle) {
                handlers.taskToggle.postMessage({ index: idx, checked: !!cb.checked });
              } else {
                cb.checked = !cb.checked;   // 无桥接环境(如导出 HTML)时还原状态
              }
            });
          });
        }

        // 双击图片 → 通知原生弹窗全屏显示
        document.addEventListener("dblclick", function (e) {
          var t = e.target;
          if (t && t.tagName === "IMG") {
            var src = t.getAttribute("src") || "";
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.imagePopup) {
              window.webkit.messageHandlers.imagePopup.postMessage(src);
            }
          }
        });

        // 文档内查找
        window.MDV = {
          clearHits: function () {
            document.querySelectorAll("mark.mdv-hit").forEach(function (m) {
              var parent = m.parentNode;
              if (!parent) return;
              while (m.firstChild) parent.insertBefore(m.firstChild, m);
              parent.removeChild(m);
              parent.normalize();
            });
          },
          search: function (text) {
            this.clearHits();
            if (!text) return 0;
            var root = document.getElementById("content");
            if (!root) return 0;
            var needle = text.toLowerCase();
            var matches = [];
            var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
            var node;
            while ((node = walker.nextNode())) {
              var p = node.parentElement;
              if (!p || p.closest("script,style,noscript")) continue;
              var hay = node.nodeValue.toLowerCase();
              if (hay.indexOf(needle) === -1) continue;
              var starts = [];
              var i = hay.indexOf(needle);
              while (i !== -1) { starts.push(i); i = hay.indexOf(needle, i + needle.length); }
              matches.push([node, starts]);
            }
            var total = 0;
            matches.forEach(function (pair) {
              var n = pair[0], starts = pair[1];
              for (var k = starts.length - 1; k >= 0; k--) {
                try {
                  var range = document.createRange();
                  range.setStart(n, starts[k]);
                  range.setEnd(n, starts[k] + needle.length);
                  var mark = document.createElement("mark");
                  mark.className = "mdv-hit";
                  range.surroundContents(mark);
                  total++;
                } catch (e) {}
              }
            });
            return total;
          },
          jumpTo: function (index) {
            var marks = document.querySelectorAll("mark.mdv-hit");
            if (!marks.length) return -1;
            var i = ((index % marks.length) + marks.length) % marks.length;
            marks.forEach(function (m) { m.classList.remove("mdv-current"); });
            var m = marks[i];
            m.classList.add("mdv-current");
            m.scrollIntoView({ behavior: "smooth", block: "center" });
            return i;
          }
        };

        // 阅读进度 + 当前章节上报(滚动同步大纲高亮)
        window.addEventListener("scroll", (function () {
          var last = 0;
          var lastHeading = -2;
          return function () {
            var now = Date.now();
            if (now - last < 100) return;
            last = now;
            var handlers = (window.webkit && window.webkit.messageHandlers) || {};
            var d = document.documentElement;
            var max = d.scrollHeight - d.clientHeight;
            var p = max > 0 ? d.scrollTop / max : 0;
            if (handlers.scrollProgress) {
              handlers.scrollProgress.postMessage(Math.round(Math.max(0, Math.min(1, p)) * 100));
            }
            if (handlers.activeHeading) {
              var hs = document.querySelectorAll(HEADING_SELECTOR);
              var idx = -1;
              for (var i = 0; i < hs.length; i++) {
                if (hs[i].getBoundingClientRect().top <= 80) idx = i; else break;
              }
              if (idx !== lastHeading) {
                lastHeading = idx;
                handlers.activeHeading.postMessage(idx);
              }
            }
          };
        })(), true);
        </script>
        </body>
        </html>
        """
    }
}
