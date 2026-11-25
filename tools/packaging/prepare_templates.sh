#!/bin/bash
# 准备 UPX 壳模板：windows = 自编译裁剪模板 + rcedit 图标 + UPX；linux = 官方模板 + UPX。
# 用法：prepare_templates.sh [windows|linux|all]
# Godot 4.7 的 embed 走 PE/ELF "pck" 节，UPX 会毁掉它 —— 所以壳模板配 embed=false + 追加 trailer（见 pack_all.sh）。
set -e
cd "$(dirname "$0")/../.."
PACK_ROOT="${PACK_ROOT:-/d/tool or code environment}"
PYTHON="${PYTHON:-$PACK_ROOT/python/python.exe}"
UPX_BIN="${UPX_BIN:-$PACK_ROOT/upx-5.3.0-win64/upx.exe}"
RCEDIT_BIN="${RCEDIT_BIN:-$PACK_ROOT/rcedit-x64.exe}"
TEMPLATES_DIR="${TEMPLATES_DIR:-$PACK_ROOT/godot-export-templates/4.7.2.stable}"
GODOT_SRC="${GODOT_SRC:-$PACK_ROOT/godot-src/godot-4.7.2-stable}"
WHAT="${1:-all}"

if [[ "$WHAT" == "windows" || "$WHAT" == "all" ]]; then
	bash "$(dirname "$0")/build_template.sh"
	T="$GODOT_SRC/bin/godot.windows.template_release.x86_64"
	cp "$T.exe" "$T.upx.exe"
	mkdir -p build
	"$PYTHON" -c "
from PIL import Image
Image.open('icon.png').convert('RGBA').save('build/mvl.ico', sizes=[(256,256),(64,64),(48,48),(32,32),(16,16)])
"
	"$RCEDIT_BIN" "$T.upx.exe" --set-icon "build/mvl.ico" \
		--set-file-version "1.0.0" --set-product-version "1.0.0" \
		--set-version-string "ProductName" "MVL" \
		--set-version-string "FileDescription" "Mindustry Visual Logic Editor"
	"$UPX_BIN" --best --lzma "$T.upx.exe"
fi

if [[ "$WHAT" == "linux" || "$WHAT" == "all" ]]; then
	cp "$TEMPLATES_DIR/linux_release.x86_64" "$TEMPLATES_DIR/linux_release.x86_64.upx"
	# tpz 解压不保留 unix 执行位，UPX 要求输入可执行
	chmod +x "$TEMPLATES_DIR/linux_release.x86_64.upx"
	"$UPX_BIN" --best --lzma "$TEMPLATES_DIR/linux_release.x86_64.upx"
fi