#!/bin/bash
# 打包：Windows/Linux = UPX 壳模板 + 追加 pck + 手写 trailer；Android = 官方 apk 模板。
# 用法：pack_all.sh [windows|linux|android|all]（预设需先由 make_presets.py 生成）
# trailer 格式 = 对齐补零 + u64(pck 含补零长度) + u32(0x43504447)，与官方 p_embed 分支一致；
# Godot 4.7 的 embed 走 PE/ELF "pck" 节，UPX 会毁掉它，故 embed=false 后手工追加。
set -e
cd "$(dirname "$0")/../.."
PACK_ROOT="${PACK_ROOT:-/d/tool or code environment}"
PYTHON="${PYTHON:-$PACK_ROOT/python/python.exe}"
GODOT_BIN="${GODOT_BIN:-/d/GameEngine/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
WHAT="${1:-all}"
mkdir -p export/windows export/linux export/android

if [[ "$WHAT" == "windows" || "$WHAT" == "all" ]]; then
	rm -f export/windows/MVL.exe export/windows/MVL.pck
	"$GODOT_BIN" --headless --path . --export-release "Windows Desktop" export/windows/MVL.exe
fi
if [[ "$WHAT" == "linux" || "$WHAT" == "all" ]]; then
	rm -f export/linux/MVL.x86_64 export/linux/MVL.pck
	"$GODOT_BIN" --headless --path . --export-release "Linux" export/linux/MVL.x86_64
fi
if [[ "$WHAT" == "android" || "$WHAT" == "all" ]]; then
	rm -f export/android/MVL.apk
	"$GODOT_BIN" --headless --path . --export-release "Android" export/android/MVL.apk
fi

"$PYTHON" - <<'EOF'
import os, struct
pairs = [("export/windows/MVL.exe", "export/windows/MVL.pck"),
         ("export/linux/MVL.x86_64", "export/linux/MVL.pck")]
for exe, pck in pairs:
    if not os.path.exists(pck):
        continue
    data = open(pck, "rb").read()
    pad = (len(data) + 12) % 8
    with open(exe, "ab") as f:
        f.write(data + b"\0" * pad + struct.pack("<Q", len(data) + pad) + struct.pack("<I", 0x43504447))
    os.remove(pck)
    print("single-file:", exe, os.path.getsize(exe), "bytes")
if os.path.exists("export/android/MVL.apk"):
    print("apk:", os.path.getsize("export/android/MVL.apk"), "bytes")
EOF