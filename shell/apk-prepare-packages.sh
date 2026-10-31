#!/bin/sh

BASE_DIR="extra-packages"
TEMP_DIR="$BASE_DIR/temp-unpack"
TARGET_DIR="packages"

# 清理旧的目录
rm -rf "$TEMP_DIR" "$TARGET_DIR"
mkdir -p "$TEMP_DIR" "$TARGET_DIR"

# 解压 .run 文件
for run_file in "$BASE_DIR"/*.run; do
    [ -e "$run_file" ] || continue
    echo "🧩 解压 $run_file -> $TEMP_DIR"
    sh "$run_file" --target "$TEMP_DIR" --noexec
done

# 1. 收集 run 解压出的 .apk 文件
find "$TEMP_DIR" -type f -name "*.apk" -exec cp -v {} "$TARGET_DIR"/ \;

# 2. 收集 extra-packages/*/ 下的 .apk 文件（只查一级子目录）

find "$BASE_DIR" -mindepth 2 -maxdepth 2 -type f -name "*.apk" ! -path "$TEMP_DIR/*" \
  -exec echo "👉 Found:" {} \; \
  -exec cp -v {} "$TARGET_DIR"/ \;

# 3. 固定版本的第三方 APK(仓库 run/ 目录之外,直接按上游正式发布下载)
#
# luci-app-singbox-admin 只在上游 Releases 发布,未进入任何 feed。ImageBuilder
# 会把 packages/ 下的 *.apk 重新生成 packages.adb 再解析安装,因此:
#   - 文件名必须符合 <name>-<version>.apk(上游发布名带下划线与 _all 后缀,需改名);
#   - 版本固定在此处,不跟随 latest,避免构建结果漂移。
SINGBOX_ADMIN_VER="4.1.1-r1"
SINGBOX_ADMIN_SHA256="2fc67133c95c93978c1920e57548f52ad40c10423610220d79f34af9fc174410"
SINGBOX_ADMIN_URL="https://github.com/yukiinagato/luci-app-singbox-admin/releases/download/v4.1.1/luci-app-singbox-admin_4.1.1-r1_all.apk"
SINGBOX_ADMIN_FILE="$TARGET_DIR/luci-app-singbox-admin-$SINGBOX_ADMIN_VER.apk"

echo "⬇️  下载 luci-app-singbox-admin $SINGBOX_ADMIN_VER"
if ! wget -q -O "$SINGBOX_ADMIN_FILE" "$SINGBOX_ADMIN_URL"; then
  echo "❌ 下载失败:$SINGBOX_ADMIN_URL" >&2
  rm -f "$SINGBOX_ADMIN_FILE"
  exit 1
fi
if ! echo "$SINGBOX_ADMIN_SHA256  $SINGBOX_ADMIN_FILE" | sha256sum -c - >/dev/null 2>&1; then
  echo "❌ SHA-256 校验失败:$SINGBOX_ADMIN_FILE" >&2
  rm -f "$SINGBOX_ADMIN_FILE"
  exit 1
fi
echo "✅ luci-app-singbox-admin $SINGBOX_ADMIN_VER 已放入 $TARGET_DIR/"

echo "✅ 所有 .apk 文件已整理至 $TARGET_DIR/"
