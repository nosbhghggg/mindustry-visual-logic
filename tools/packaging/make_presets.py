#!/usr/bin/env python3
"""生成 export_presets.cfg（gitignored，换机/CI 都要重配）。三预设：Windows / Linux / Android。"""
import argparse

p = argparse.ArgumentParser()
p.add_argument("--win-template", default="")
p.add_argument("--linux-template", default="")
p.add_argument("--keystore", default="")
p.add_argument("--keystore-user", default="")
p.add_argument("--keystore-pass", default="")
p.add_argument("--out", default="export_presets.cfg")
a = p.parse_args()
# ConfigFile 把反斜杠当转义：路径统一正斜杠
for k in ("win_template", "linux_template", "keystore"):
    setattr(a, k, getattr(a, k).replace("\\", "/"))

HEAD = """name={name}
platform={platform}
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="docs/*,blocks/*"
exclude_filter="build/*,export/*,*icon_troll.png*"
export_path={path}
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2
"""

out = []
out.append("[preset.0]\n\n" + HEAD.format(name='"Windows Desktop"', platform='"Windows Desktop"', path='"export/windows/MVL.exe"') + f"""
[preset.0.options]

custom_template/debug=""
custom_template/release="{a.win_template}"
debug/export_console_wrapper=0
binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=false
application/icon="res://icon.png"
application/icon_interpolation=4
application/file_version=""
application/product_version=""
application/company_name=""
application/product_name="MVL"
application/file_description="Mindustry Visual Logic Editor"
application/copyright=""
application/trademarks=""
application/export_angle=0
application/export_d3d12=0
ssh_remote_deploy/enabled=false
""")
out.append("[preset.1]\n\n" + HEAD.format(name='"Linux"', platform='"Linux"', path='"export/linux/MVL.x86_64"') + f"""
[preset.1.options]

custom_template/debug=""
custom_template/release="{a.linux_template}"
binary_format/embed_pck=false
binary_format/architecture="x86_64"
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
ssh_remote_deploy/enabled=false
""")
out.append("[preset.2]\n\n" + HEAD.format(name='"Android"', platform='"Android"', path='"export/android/MVL.apk"') + f"""
[preset.2.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
keystore/release="{a.keystore}"
keystore/release_user="{a.keystore_user}"
keystore/release_password="{a.keystore_pass}"
architectures/arm64-v8a=true
architectures/armeabi-v7a=false
architectures/x86=false
architectures/x86_64=false
version/code=1
version/name="1.0"
package/unique_name="org.mvl.editor"
package/name="MVL"
package/signed=true
permissions/internet=true
""")
open(a.out, "w", encoding="utf-8", newline="\n").write("\n".join(out))
print("presets written:", a.out)