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
    ["代码块内 $x$ 未渲染为公式", doc.querySelector("pre code") && doc.querySelector("pre code").textContent.includes("$x$")],
    ["MDV 搜索接口存在", typeof window.MDV?.search === "function"],
  ];
  let fail = 0;
  for (const [name, ok] of checks) { console.log((ok ? "PASS" : "FAIL") + "  " + name); if (!ok) fail++; }
  // 搜索功能实测
  const hits = window.MDV.search("测试");
  console.log((hits > 0 ? "PASS" : "FAIL") + "  文档内查找(命中 " + hits + " 处)");
  if (hits === 0) fail++;
  process.exit(fail ? 1 : 0);
}, 1500);
