const fs = require("fs");
const { JSDOM } = require("jsdom");

const html = fs.readFileSync("/tmp/mdv_test.html", "utf8");
const dom = new JSDOM(html, { runScripts: "outside-only", pretendToBeVisual: true });
const { window } = dom;

const R = "/Users/fengbozhi/WorkBuddy/2026-09-27-07-27-09/MarkdownViewer/src/Resources/";
// 按 HTML 中相同顺序注入库(marked/highlight/mermaid/katex)与内联管线
for (const f of ["marked.min.js", "highlight.min.js", "mermaid.min.js", "katex.min.js"]) {
  try { window.eval(fs.readFileSync(R + f, "utf8")); } catch (e) { console.log("lib load warn:", f, e.message); }
}
// 提取内联脚本执行
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
window.eval(scripts[scripts.length - 1]);

setTimeout(() => {
  const doc = window.document;
  // 注意:不能用 body.textContent(script 标签源码也会被计入),只取渲染容器
  const bodyText = doc.getElementById("content").textContent;
  const codeText = doc.querySelector("pre code")?.textContent || "";
  const styleText = doc.querySelector("style")?.textContent || "";
  const checks = [
    ["KaTeX 行内公式渲染", doc.querySelectorAll(".katex").length >= 2],
    ["KaTeX 块级公式", doc.querySelectorAll(".katex-display").length >= 1],
    ["TOC 目录生成", !!doc.querySelector(".mdv-toc")],
    ["TOC 锚点链接", !!doc.querySelector('.mdv-toc a[href="#mdv-h-0"]')],
    ["标题锚点 id", !!doc.getElementById("mdv-h-0")],
    ["高亮 ==...==", !!doc.querySelector("mark.mdv-hl")],
    ["下标 H~2~O", [...doc.querySelectorAll("sub")].some(e => e.textContent === "2")],
    ["上标 x^2^", [...doc.querySelectorAll("sup")].some(e => e.textContent === "2")],
    ["删除线保留", !!doc.querySelector("del")],
    ["脚注区生成", !!doc.querySelector("section.footnotes")],
    ["脚注引用链接", !!doc.querySelector('.footnote-ref a[href="#mdv-fn-1"]')],
    ["代码复制按钮", !!doc.querySelector(".code-copy-btn")],
    ["语言标签", [...doc.querySelectorAll(".code-lang")].some(e => e.textContent === "swift")],
    ["代码行号", !!doc.querySelector(".code-line")],
    ["代码块内 $x$ 未渲染为公式", codeText.includes("$x$")],
    ["代码块内 :smile: 未转换", codeText.includes(":smile:")],
    ["MDV 搜索接口存在", typeof window.MDV?.search === "function"],
    // v3 新功能
    ["Callout 渲染", doc.querySelectorAll(".mdv-callout").length >= 2],
    ["Callout 标题与颜色", [...doc.querySelectorAll(".mdv-callout-title")].some(e => e.textContent.includes("Warning") && e.style.color.length > 0)],
    ["Callout 无残留 blockquote 标记", !bodyText.includes("[!NOTE]")],
    ["Emoji 短代码转换", bodyText.includes("😄") && bodyText.includes("🚀") && bodyText.includes("❤️")],
    ["Front Matter 属性面板", !!doc.querySelector(".mdv-frontmatter")],
    ["Front Matter 键值", [...doc.querySelectorAll(".mdv-fm-key")].some(e => e.textContent === "title") && [...doc.querySelectorAll(".mdv-fm-val")].some(e => e.textContent === "测试文档")],
    ["Front Matter 数组展开", [...doc.querySelectorAll(".mdv-fm-val")].some(e => e.textContent === "markdown, 测试")],
    ["Front Matter 原文不显示", !bodyText.includes("draft: false")],
    ["任务复选框渲染", doc.querySelectorAll('input[type="checkbox"]').length === 2],
    ["任务复选框可点击(disabled 移除)", [...doc.querySelectorAll('input[type="checkbox"]')].every(cb => !cb.disabled)],
    ["已完成任务勾选状态", [...doc.querySelectorAll('input[type="checkbox"]')].some(cb => cb.checked)],
    // 样式/交互优化(标题锚点 / 平滑滚动 / 打印分页 / 宽表格)
    ["标题 hover 锚点存在", !!doc.querySelector("h1 .mdv-anchor")],
    ["锚点链接指向标题 id", doc.querySelector("h1 .mdv-anchor")?.getAttribute("href") === "#mdv-h-0"],
    ["锚点不污染标题文本(¶ 由 CSS 生成)", !doc.querySelector("h1")?.textContent.includes("¶")],
    ["TOC 文本不含锚点符号", ![...doc.querySelectorAll(".mdv-toc a")].some(a => a.textContent.includes("¶"))],
    ["CSS:平滑滚动", styleText.includes("scroll-behavior: smooth")],
    ["CSS:减弱动态效果降级", styleText.includes("prefers-reduced-motion")],
    ["CSS:打印分页保护", styleText.includes("@media print") && styleText.includes("break-inside: avoid")],
    ["CSS:宽表格横向滚动", styleText.includes("overflow-x: auto")],
    ["CSS:代码块选中色", styleText.includes("::selection")],
    // 可读性回归:未知语言代码块(cmd)不应黑对黑
    ["未知语言 cmd 代码块存在", !!doc.querySelector("pre code.language-cmd")],
    ["未知语言高亮失败时补 .hljs 类", doc.querySelector("pre code.language-cmd")?.classList.contains("hljs")],
    ["CSS:代码块基础色不依赖 .hljs", /\.markdown-body pre code\s*\{[^}]*color:\s*#abb2bf/.test(styleText)],
    ["CSS:Callout 深色模式配色", html.includes("#4493f8") && html.includes("MDV_DARK ? dark : light")],
  ];
  let fail = 0;
  for (const [name, ok] of checks) { console.log((ok ? "PASS" : "FAIL") + "  " + name); if (!ok) fail++; }
  // 搜索功能实测
  const hits = window.MDV.search("测试");
  console.log((hits > 0 ? "PASS" : "FAIL") + "  文档内查找(命中 " + hits + " 处)");
  if (hits === 0) fail++;
  process.exit(fail ? 1 : 0);
}, 1500);
