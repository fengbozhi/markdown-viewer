#!/bin/zsh
# Markdown Viewer 一键构建脚本
# 用法: ./build.sh
set -e
cd "$(dirname "$0")"

APP="Markdown Viewer.app"
rm -rf "$APP/Contents/MacOS/MarkdownViewer"

# 编译(单文件 SwiftUI 应用,需 -parse-as-library 支持 @main)
swiftc -O -parse-as-library \
  -o "$APP/Contents/MacOS/MarkdownViewer" \
  src/MarkdownViewerApp.swift \
  -framework SwiftUI -framework AppKit -framework WebKit

# 复制渲染引擎资源
cp src/marked.min.js src/highlight.min.js src/mermaid.min.js \
   src/atom-one-dark.min.css \
   src/github-markdown-light.css src/github-markdown-dark.css \
   "$APP/Contents/Resources/"

# 临时签名(本机运行)
codesign --force -s - "$APP"

echo "构建完成: $APP"
open "$APP"
