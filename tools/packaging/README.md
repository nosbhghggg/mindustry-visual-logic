# 打包工作流

三平台单文件产物：Windows exe / Linux x86_64 / Android apk（arm64-v8a）。
CI 见 [.github/workflows/package.yml](../../.github/workflows/package.yml)：`workflow_dispatch` 手动触发，或打 `v*` tag 自动跑；产物在 Actions artifacts。

## 管线

1. `build_template.sh` — 自编译裁剪版 Windows release 模板（MinGW + SCons，关 3D/物理/导航/Vulkan/D3D12/无用导入器；
   保留 GDScript、GLES3、freetype+text_server_adv、mbedtls、bcdec、**webp**（无损 ctex 解包是运行时依赖，关了纹理全加载失败））
2. `prepare_templates.sh [windows|linux|all]` — Windows：裁剪模板 + rcedit 图标 + UPX；Linux：官方模板 + UPX
3. `make_presets.py` — 生成 gitignored 的 `export_presets.cfg`（换机/CI 必跑）
4. `pack_all.sh [windows|linux|android|all]` — 导出 + 单文件化

**单文件化的阴招**：Godot 4.7 的 embed_pck 写 PE/ELF 里名为 `pck` 的节，UPX 会毁掉它。
所以 embed=false 导出 exe+pck，把 pck 追加到 exe 尾再手写 12 字节 trailer
（对齐补零 + u64 长度 + u32 magic 0x43504447）——运行时第三兜底认文件尾 magic，与官方 embed 写法逐字一致。

## 本地跑

环境默认在 `D:\tool or code environment`（mingw64 / godot-src / python / upx / rcedit / 官方模板），
可用 `PACK_ROOT` `GODOT_BIN` `PYTHON` `UPX_BIN` `RCEDIT_BIN` `TEMPLATES_DIR` `GODOT_SRC` 覆写：

```bash
bash tools/packaging/prepare_templates.sh all
python tools/packaging/make_presets.py \
  --win-template "$PACK_ROOT/godot-src/godot-4.7.2-stable/bin/godot.windows.template_release.x86_64.upx.exe" \
  --linux-template "$PACK_ROOT/godot-export-templates/4.7.2.stable/linux_release.x86_64.upx" \
  --keystore "$APPDATA/Godot/keystores/mvl-release.keystore" --keystore-user mvl --keystore-pass mvlrelease
bash tools/packaging/pack_all.sh all
```

## 注意

- **Android 签名**：本地 release keystore 在 `AppData/Roaming/Godot/keystores/mvl-release.keystore`，更新 APK 必须同一把；
  CI 每次生成临时自签证书，CI 包与本地包不能互相覆盖安装。
- Linux 产物经 artifact 下载后执行位会丢，目标机上 `chmod +x`。
- UPX 壳可能触发杀软启发式误报；Windows 无壳备份可临时把预设 `custom_template/release` 指回未压壳模板重导。
- Android 走非 Gradle 路线（预built apk 模板），JDK 只跑 keytool/apksigner；改 Gradle 路线需 JDK ≤ 23。