#!/bin/bash
# 裁剪版 Windows release 导出模板：纯 2D UI 应用用不到的引擎模块全关。
# 保留：GDScript、GLES3(GL Compatibility)、freetype/text_server_adv(中文排版)、
#       mbedtls(公告窗 https)、bcdec(压缩纹理软解兜底)、webp(无损 ctex 解包)、wasapi。
# 环境可覆写：PACK_ROOT / GODOT_SRC / PYTHON（CI 与本地共用）。
set -e
PACK_ROOT="${PACK_ROOT:-/d/tool or code environment}"
GODOT_SRC="${GODOT_SRC:-$PACK_ROOT/godot-src/godot-4.7.2-stable}"
PYTHON="${PYTHON:-$PACK_ROOT/python/python.exe}"
export PATH="$PACK_ROOT/mingw64/bin:$PATH"
cd "$GODOT_SRC"

"$PYTHON" -m SCons platform=windows target=template_release arch=x86_64 use_mingw=yes \
	optimize=speed debug_symbols=no -j"$(nproc)" \
	vulkan=no d3d12=no accesskit=no sdl=no \
	disable_3d=yes disable_physics_2d=yes disable_physics_3d=yes \
	disable_navigation_2d=yes disable_navigation_3d=yes \
	module_godot_physics_2d_enabled=no module_godot_physics_3d_enabled=no \
	module_jolt_physics_enabled=no \
	module_navigation_2d_enabled=no module_navigation_3d_enabled=no \
	module_glslang_enabled=no \
	module_openxr_enabled=no module_mobile_vr_enabled=no module_webxr_enabled=no \
	module_camera_enabled=no module_interact_enabled=no \
	module_gridmap_enabled=no module_csg_enabled=no module_meshoptimizer_enabled=no \
	module_gltf_enabled=no module_fbx_enabled=no module_tinyexr_enabled=no \
	module_basis_universal_enabled=no module_cvtt_enabled=no module_betsy_enabled=no \
	module_astcenc_enabled=no module_etcpak_enabled=no \
	module_mp3_enabled=no module_theora_enabled=no module_vorbis_enabled=no \
	module_interactive_music_enabled=no \
	module_websocket_enabled=no module_webrtc_enabled=no \
	module_enet_enabled=no module_multiplayer_enabled=no module_upnp_enabled=no \
	module_jsonrpc_enabled=no module_objectdb_profiler_enabled=no \
	module_vhacd_enabled=no module_xatlas_unwrap_enabled=no module_raycast_enabled=no \
	module_lightmapper_rd_enabled=no \
	module_svg_enabled=no \
	module_bmp_enabled=no module_jpg_enabled=no module_tga_enabled=no \
	module_dds_enabled=no module_ktx_enabled=no module_hdr_enabled=no \
	module_noise_enabled=no module_visual_shader_enabled=no \
	module_zip_enabled=no \
	module_text_server_fb_enabled=no module_mono_enabled=no \
	"$@"