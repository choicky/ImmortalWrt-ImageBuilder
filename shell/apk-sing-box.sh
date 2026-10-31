#!/bin/sh
# ============= 官方最新稳定版 sing-box 集成(仅 imm 25.12.x,APK)=============
# 用法(必须在 ImageBuilder 根目录下执行,build25.sh 即满足):
#   sh shell/apk-sing-box.sh <APK架构> <packages目录> <files/etc/config目录>
# 例:sh shell/apk-sing-box.sh aarch64_generic /home/build/immortalwrt/packages /home/build/immortalwrt/files/etc/config
#
# 行为:
# 1) 经官方 SagerNet/sing-box releases/latest API 取最新稳定版(接口本身已排除
#    prerelease/draft,再用正则仅接受 vX.Y.Z 稳定标签),一次构建只解析一次版本;
# 2) 下载该版本对应架构的官方 OpenWrt APK 并校验 API 提供的 sha256 摘要,最终
#    以规范文件名 sing-box-<版本>-r<修订>.apk 存入 packages/(mkndx 按包元数据
#    推导索引文件名,文件名不符会在真实安装阶段 "package ... not found");
# 3) 在临时目录(软链 packages/ 全部 .apk)构建只读索引并从中读取"版本-修订"
#    (不假设修订号恒为 -r0);绝不改写 packages/packages.adb —— IB 默认
#    CONFIG_SIGNATURE_CHECK=y,make 构建时会用本地密钥重建签名索引,helper 写出
#    的未签名索引反而会被 apk 拒收(整包索引失效,连带 aurora/passwall 等本地
#    包 "no such package")。再以真实仓库组合(repositories 远程索引 + 临时索引)
#    预解析,确认裸名 sing-box 恰会选中该官方版本;
# 4) 向 files/etc/config 写入 sing-box uci 覆盖(enabled=0),保持与 feed 旧包一致的
#    服务默认不自启行为(官方包默认为 enabled=1);覆盖仅作用于新镜像首次发布,
#    设备既有配置在 sysupgrade 中按 conffile 正常保留,不受影响;
# 5) stdout 输出官方精确版本(如 1.14.4-r0),供调用方做构建后核验。
#    任何一步失败均以非零退出 —— 由调用方终止构建,杜绝静默回退到 feed 旧版本。
#    注意:官方版本经预解析以"裸名最高版本"生效,不经 make image PACKAGES 传入
#    name=version 钉定 —— IB Makefile 的 FormatPackages 存在评测粘连,钉定会
#    传染其后所有包(实测导致 libgcc1=1.14.4-r0 等连锁 unsatisfiable)。
set -e

SB_ARCH="$1"
PKG_DIR="$2"
FILES_CFG="$3"

err() {
    echo "apk-sing-box: $*" >&2
    exit 1
}

[ -n "$SB_ARCH" ] && [ -n "$PKG_DIR" ] || err "缺少参数: <APK架构> <packages目录> [files/etc/config目录]"
ROOT="$PWD"
PKG_DIR="$(cd "$PKG_DIR" 2>/dev/null && pwd)" || err "packages 目录不存在: $2"
APKB="$ROOT/staging_dir/host/bin/apk"
[ -x "$APKB" ] || err "未找到 ImageBuilder 自带 apk 工具: $APKB (请在 IB 根目录运行本脚本)"

JSON="$(mktemp)"
DBTMP="$(mktemp -d)"
TMPIDX=""
trap 'rm -f "$JSON"; rm -rf "$DBTMP" "$TMPIDX"' EXIT

# 1) 发现最新稳定版
API="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
curl -fsS --connect-timeout 15 --retry 3 -o "$JSON" "$API" || err "请求 GitHub API 失败: $API"
VER="$(sed -n 's/^[[:space:]]*"tag_name": "v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"[[:space:]]*,*[[:space:]]*$/\1/p' "$JSON" | head -n1)"
[ -n "$VER" ] || err "releases/latest 未解析出稳定版本标签(vX.Y.Z)"

# 2) 定位并下载本架构官方 APK,校验 sha256
ASSET="sing-box_${VER}_openwrt_${SB_ARCH}.apk"
META="$(awk -v want="$ASSET" '
    /^ *\{/ { name=""; url=""; dig="" }
    /"name": / { s=$0; sub(/.*"name": *"/, "", s); sub(/".*/, "", s); name=s }
    /"browser_download_url": / { s=$0; sub(/.*"browser_download_url": *"/, "", s); sub(/".*/, "", s); url=s }
    /"digest": / { s=$0; sub(/.*"digest": *"/, "", s); sub(/".*/, "", s); dig=s }
    /^ *\}/ { if (name == want && url != "") { print url; print dig; exit } }
' "$JSON")"
URL="$(printf '%s\n' "$META" | sed -n '1p')"
DIGEST="$(printf '%s\n' "$META" | sed -n '2p')"
[ -n "$URL" ] || err "官方 v$VER 发布不含 $ASSET(目标架构无官方包?)"
[ -n "$DIGEST" ] || err "官方资产 $ASSET 缺少 sha256 摘要元数据,拒绝跳过校验"

wget -q -T 30 -t 3 -O "$PKG_DIR/$ASSET" "$URL" || { rm -f "$PKG_DIR/$ASSET"; err "下载失败: $URL"; }
GOT="$(sha256sum "$PKG_DIR/$ASSET" | awk '{print $1}')"
[ "$GOT" = "${DIGEST#sha256:}" ] || { rm -f "$PKG_DIR/$ASSET"; err "sha256 校验不通过: $ASSET"; }

# 3) 临时目录只读索引:软链 packages/ 下全部 .apk,在临时目录生成索引;
#    绝不触碰 packages/packages.adb(签名索引必须由 make 用本地密钥重建,
#    未签名索引会被 CONFIG_SIGNATURE_CHECK=y 的 apk 整体拒收)。
TMPIDX="$(mktemp -d)" || err "无法创建临时索引目录"
for SB_APK in "$PKG_DIR"/*.apk; do
    ln -sf "$SB_APK" "$TMPIDX/" || err "创建临时索引软链失败"
done
( cd "$TMPIDX" && "$APKB" mkndx --allow-untrusted --output packages.adb *.apk ) >/dev/null 2>&1 \
    || err "临时索引构建失败"
"$APKB" --root "$DBTMP" --arch "$SB_ARCH" add --initdb >/dev/null 2>&1 \
    || "$APKB" --root "$DBTMP" --arch "$SB_ARCH" add --initdb --usermode >/dev/null 2>&1 \
    || err "初始化临时 apk 数据库失败"
# packages/ 可能同时存在其他来源的 sing-box(如 passwall run 捆绑旧版),
# policy 会列出多版本 —— 必须精确命中 "本次发布 vX.Y.Z-rN",而不是取任意首条。
FULLVER="$("$APKB" --root "$DBTMP" --arch "$SB_ARCH" --repository "$TMPIDX/packages.adb" --allow-untrusted --no-network policy sing-box 2>/dev/null \
    | awk -v want="$VER" 'index($0, "  " want "-r")==1 { gsub(/[: ]/, ""); print; exit }')"
[ -n "$FULLVER" ] || err "本地索引中未找到官方 sing-box $VER-rN(索引缺失或资产异常)"

# 3b) 以规范文件名落盘:apk mkndx 在索引中记录的是"由包元数据推导"的文件名
#     (sing-box-<版本>-r<修订>.apk),而官方资产名为下划线风格
#     (sing-box_<版本>_openwrt_<架构>.apk)。若保留原文件名,make 重建签名索引后,
#     真实安装阶段会报 "package mentioned in index not found" 并失败(已实测)。
if [ "$ASSET" != "sing-box-$FULLVER.apk" ]; then
    mv -f "$PKG_DIR/$ASSET" "$PKG_DIR/sing-box-$FULLVER.apk" || err "规范化 apk 文件名失败"
    ASSET="sing-box-$FULLVER.apk"
    ln -sf "$PKG_DIR/$ASSET" "$TMPIDX/" 2>/dev/null || true
fi

# 4) 预解析确认:按构建同款仓库组合(repositories 远程索引 + 临时本地索引),
#    裸名 sing-box 必须恰好解析到本次官方版本;否则(如更高版本混入)立即失败。
RESOLVED="$("$APKB" --root "$DBTMP" --arch "$SB_ARCH" \
    --repositories-file "$ROOT/repositories" \
    --repository "$TMPIDX/packages.adb" \
    --allow-untrusted --cache-dir "$ROOT/dl" --no-progress \
    add --simulate sing-box 2>/dev/null \
    | sed -n 's/^([^)]*) Installing sing-box (\([^)]*\))$/\1/p' | head -n1)"
[ -n "$RESOLVED" ] || err "预解析失败:apk add --simulate sing-box 无结果(仓库不可达或依赖无法满足)"
[ "$RESOLVED" = "$FULLVER" ] || err "sing-box 将解析到 $RESOLVED 而非官方 $FULLVER(存在更高混入版本或索引异常),已中止"

# 5) 覆盖默认 uci 配置:保持服务默认不自启(feed 行为)
if [ -n "$FILES_CFG" ]; then
    mkdir -p "$FILES_CFG"
    cat > "$FILES_CFG/sing-box" <<'EOF'
config sing-box 'main'
	option enabled '0'
	option conffile '/etc/sing-box/config.json'
	option workdir '/usr/share/sing-box'
	option log_stderr '1'
EOF
fi

# 6) 输出官方精确版本(供构建后核验)
printf '%s\n' "$FULLVER"
