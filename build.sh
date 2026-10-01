#!/bin/zsh
# Markdown Viewer 一键构建脚本
# 用法: ./build.sh          构建并启动(构建前自动跑单元测试,失败则中止)
#       ./build.sh --skip-tests   跳过测试直接构建
set -e
cd "$(dirname "$0")"

APP="Markdown Viewer.app"

# 1) 单元测试:编辑器核心逻辑(纯函数,不依赖 AppKit)
if [[ "$1" != "--skip-tests" ]]; then
  echo "==> 运行单元测试..."
  swiftc -O -o /tmp/mdv_editor_tests \
    tests/main.swift \
    src/Editing/EditorCommands.swift src/Editing/MarkdownHighlighter.swift src/Editing/TaskToggle.swift \
    src/Models/FuzzyMatch.swift src/Models/DocStats.swift \
    -framework Foundation
  /tmp/mdv_editor_tests > /tmp/mdv_tests.log 2>&1 || { cat /tmp/mdv_tests.log; echo "测试失败,构建中止"; exit 1; }
  grep -c "^PASS" /tmp/mdv_tests.log | xargs echo "   通过用例数:"
fi

# 2) 编译(多文件 SwiftUI 应用,需 -parse-as-library 支持 @main)
echo "==> 编译..."
rm -rf "$APP/Contents/MacOS/MarkdownViewer"
swiftc -O -parse-as-library \
  -o "$APP/Contents/MacOS/MarkdownViewer" \
  $(find src -name "*.swift" | sort) \
  -framework SwiftUI -framework AppKit -framework WebKit

# 3) 复制渲染引擎资源(marked/highlight/mermaid/KaTeX + 样式 + 字体)
cp src/Resources/*.js src/Resources/*.css "$APP/Contents/Resources/"
rm -rf "$APP/Contents/Resources/fonts"
cp -r src/Resources/fonts "$APP/Contents/Resources/fonts"

# 4) 临时签名(本机运行)
codesign --force -s - "$APP"

echo "构建完成: $APP"
open "$APP"
