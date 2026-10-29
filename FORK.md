# Fork 维护与上游同步指南

本文件是 **本 fork(choicky/ImmortalWrt-ImageBuilder)专属的维护说明**,不参与上游内容,仅存在于 `custom` 分支。上游的用户文档(README.md / PACKAGES.md / SUPPORT.md / info.md)保持其原有职责,不在此重复。

## 1. 分支模型

- **`master` —— 纯上游同步分支。** 内容与上游 `wukongdaily/ImmortalWrt-ImageBuilder` 的 `master` 完全一致,**不承载任何个人定制**。它只用于跟踪上游,便于低冲突同步。日常构建固件请使用 `custom`,不要用 `master`。
- **`custom` —— 个人定制分支。** 从 `master` 派生,仅叠加下述 25.12.x 软件包定制。构建定制固件、发布产物都在此分支进行。

上游与本 fork 的默认分支均为 `master`。

## 2. 个人定制(仅 25.12.x)

### 位置
定制只涉及四处,且都只存在于 `custom` 分支:

1. **`shell/apk-custom-packages.sh`** —— 取消 Aurora 主题行、PassWall 行的注释(原有定制),并新增 WireGuard / ZeroTier / luci-app-singbox-admin 三行。
2. **`shell/apk-prepare-packages.sh`** —— 在原有"收集 .run 解包出的 .apk"之后追加一段:按固定版本下载 `luci-app-singbox-admin` 的 APK 到 `packages/`,改名成 `<name>-<version>.apk` 并校验 SHA-256。只影响 APK 收集,不参与其它包的解析。
3. **`files/lib/upgrade/keep.d/wg-site`** —— 新增文件,只声明三条 sysupgrade 保留路径。它不含任何密钥内容、不含设备运行配置,可安全入库。
4. **`files/etc/uci-defaults/99-custom.sh`** —— 上游的首次启动脚本(经工作流 `-v …/files` 挂载进镜像),本 fork 只改其中的 WAN 与 LAN 初始化判断,见「首次启动脚本(99-custom.sh)的网络初始化」。

### 生效范围:为什么只有 25.12.x
- 25.12.x 使用 APK 包管理,其构建脚本 `*/build25.sh` 会 `source shell/apk-custom-packages.sh`(rockchip、x86-64、mediatek-filogic、sunxi-cortexa53 的 build25 均是),清单里的 `CUSTOM_PACKAGES` 随后被并入 `make image ... PACKAGES=...`。
- 24.10.x 及更早版本使用 opkg,其 `*/build24.sh` / `build23.sh` `source shell/custom-packages.sh`(不是 apk 清单)。
- `shell/apk-prepare-packages.sh` 只被这四个 `build25.sh` 调用(与 apk 清单同一生效范围),24.10.x 及更早用的是 opkg 侧的 `shell/prepare-packages.sh`,不受影响。
- `files/lib/upgrade/keep.d/wg-site` 走 `FILES=` 覆盖层,同样只对 25.12.x 生效;它对未安装这些路径的设备是空操作(见「升级保留」)。
- `files/etc/uci-defaults/99-custom.sh` 是**所有目标共用**的上游脚本(24.10.x、25.12.x、ophub/dev-board 等工作流都把它挂进镜像),因此本次 WAN 初始化的修复不限于 25.12.x;它只改变判断条件,不改写入的取值。
- 本 fork **不修改 `shell/custom-packages.sh`**,故 24.10.x 及更早固件**不包含本 fork 新增的个人定制**(此项仅说明本 fork 定制不外溢,不对上游默认包含哪些软件包作断言)。这是有意为之:按约定,Aurora 主题与 PassWall 相关软件包只保留在 25.12.x。

### 内容(取消注释后并入的包)
```bash
# Aurora 极光主题及配置
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-aurora luci-app-aurora-config luci-i18n-aurora-config-zh-cn"
# PassWall 相关(内核 + 中文语言包)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES xray-core sing-box hysteria luci-i18n-passwall-zh-cn"
# R3S/R4S 原生 WireGuard 中转节点与 ZeroTier 备用路由
CUSTOM_PACKAGES="$CUSTOM_PACKAGES kmod-wireguard wireguard-tools zerotier luci-app-zerotier"
# sing-box Web 管理面板(第三方固定版本 APK,由 apk-prepare-packages.sh 投放到 packages/)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-singbox-admin"
```

### 升级保留(sysupgrade)

目标:保留配置升级后,R3S/R4S 的 WireGuard 中转、ZeroTier 备用路由与 sing-box 面板设置能自行恢复,不依赖任何恢复脚本或常驻服务。

**软件包必须内置。** `sysupgrade` 会整体替换 rootfs,已安装但不在新镜像中的包会消失。因此下列包必须出现在 `CUSTOM_PACKAGES` 里:
- `kmod-wireguard` + `wireguard-tools`:后者自带 `/lib/netifd/proto/wireguard.uc`(25.12 起 netifd 的 wireguard proto 处理器是 ucode 实现,不再是 `.sh`),并依赖 `kmod-wireguard`。缺任一项,`wg_site` 在升级后无法创建。
- `zerotier` + `luci-app-zerotier`:ZeroTier 备用路由的运行前提。
- `luci-app-singbox-admin`:面板本体(投放方式见下一节)。

**keep.d 的语义(决定什么必须显式列)。** `sysupgrade` 默认(`-c`)只备份两类文件:①`/lib/upgrade/keep.d/*` 与 `/etc/sysupgrade.conf` 中列出的路径(目录会展开成其中的文件与软链);②APK 登记的 `/etc` 受保护文件(conffiles;24.10 及更早由 opkg 的 conffiles 承担)。**`base-files` 自带的 `keep.d/base-files-essential` 并不包含 `/etc/config/`**,该目录是靠 conffiles 机制保留的,不要把它记成 keep.d 的功劳。

因此下列内容无需在本仓库重复声明:

| 路径 | 由谁保留 |
| --- | --- |
| `/etc/config/network`(含 `wg_site` 的 `private_key`、两条 /25 与一条 /24 的 `config route`、转发) | netifd conffile |
| `/etc/config/zerotier`(含 `global.secret`) | zerotier conffile |
| `/etc/config/firewall`、`/etc/nftables.d/` | firewall4 conffile / 自带 keep.d |
| `/etc/config/singbox` | **不自动保留**,由本仓库 `keep.d` 补(见下) |
| `/etc/sing-box/`(config.json、nftables.sh、backups/) | **不自动保留**,由本仓库 `keep.d` 补:sing-box 包没有 `keep.d`,`config.json` 用 `INSTALL_DATA` 安装、不是 conffile |

**ZeroTier 身份不需要额外保留。** `/var/lib/zerotier-one` 是运行时目录(`/var` 指向 tmpfs):`/etc/init.d/zerotier` 每次 start/stop 都 `rm -rf` 后重建(配置了 `config_path` 时重建为指向它的软链),节点身份实际取自 `/etc/config/zerotier` 的 `global.secret`,而该文件是 conffile。故 `keep.d` **不列** `/var/lib/zerotier-one`——列了也只能备份到一个随即被删除的软链。若曾把 `config_path` 改到 `/etc` 之外(例如 `/root/zerotier`),那次升级前必须按下面的检查清单把它补进 `/etc/sysupgrade.conf`。

**需要 keep.d 补的三条。** `files/lib/upgrade/keep.d/wg-site` 只列这三项,原因都是"不属于任何软件包的 conffiles":

| 路径 | 为什么默认不会备份 |
| --- | --- |
| `/etc/wg-site.key` | 用户自建的私钥备份副本;私钥权威副本仍在 `/etc/config/network` 的 `private_key`,由 conffile 保留 |
| `/etc/config/singbox` | `luci-app-singbox-admin` 的 APK 由上游 `apk mkpkg` 直接生成,没有 conffiles 元数据 |
| `/etc/sing-box/` | sing-box 包不带 `keep.d`,`config.json` 不是 conffile;面板的 config 备份与 `nftables.sh` 也在此目录 |

**首次升级前必须自查(关键)。** 新固件里的 `keep.d` 只对"以后"的升级生效;从当前设备升到本固件那一次,用的是**旧固件自己的** `keep.d` 与 `/etc/sysupgrade.conf`——旧固件不认识 `/etc/wg-site.key`。所以升级前先在 R3S/R4S 上执行:

```sh
sysupgrade -l | grep -E '^/etc/(config/(network|zerotier|firewall|singbox)|sing-box/|wg-site\.key)'
```

期望至少看到 `/etc/config/network` 与(装了 ZeroTier 时)`/etc/config/zerotier`。旧固件通常看不到 `/etc/wg-site.key` 与 `/etc/sing-box/`——它们默认不在任何清单里,按需要补。`/etc/config/singbox` 单独判断:**文件存在但没出现在 `sysupgrade -l` 的清单里,就在首次升级前把它加进 `/etc/sysupgrade.conf`;已经列入备份、或该文件根本不存在,则不需要任何操作**(面板还没装过时不要凭空添加这一行)。

```sh
echo /etc/wg-site.key  >> /etc/sysupgrade.conf   # WireGuard 私钥备份副本
echo /etc/sing-box/    >> /etc/sysupgrade.conf   # sing-box 的 config.json / nftables.sh
# 仅当面板设置已存在、但还没进备份清单时才补:
if [ -f /etc/config/singbox ] && ! sysupgrade -l | grep -qx /etc/config/singbox; then
  echo /etc/config/singbox >> /etc/sysupgrade.conf
fi
sysupgrade -l | grep -E 'wg-site\.key|sing-box/|config/singbox'  # 复查
```

缺其他路径(例如自定义的 ZeroTier `config_path`)同样追加到 `/etc/sysupgrade.conf`,复查通过后再升级。从本固件之后再升级,这些路径已由镜像内的 `keep.d` 自动覆盖,不必重复添加。

**边界。** 以上只保证"保留配置升级"路径;刷写时不勾选保留配置(或 `sysupgrade -n`)则一切按新装处理。该 `keep.d` 文件位于 `files/`,会随本仓库所有 25.12.x 目标进入镜像;对不含该路径的设备,`sysupgrade` 的 `find` 会忽略不存在的条目,无副作用。

### 首次启动脚本(99-custom.sh)的网络初始化

`files/etc/uci-defaults/99-custom.sh` 由 OpenWrt 的 uci-defaults 机制在首次启动时执行并自删。**sysupgrade 保留配置升级后,新镜像里这份脚本会再跑一次**,而此时 `/etc/config/network` 已经是还原回来的用户配置。原逻辑在多网口分支里无条件改写 WAN 与 LAN,于是升级后 PPPoE 被重置成 DHCP、LAN 地址/掩码/br-lan 端口被改回首次安装的值。

修复只替换了这两处判断,写入的取值保持原样:

| 对象 | 判定为"已有用户配置" | 已有配置时 | 仍是固件默认(首次安装) |
| --- | --- | --- | --- |
| WAN | `network.wan.username` 非空,或 `network.wan.proto` 存在且不是 `dhcp`/`none` | 跳过 WAN/WAN6 的 `device`/`proto` 改写与 PPPoE 凭据写入 | 写 `wan.proto=dhcp`、`wan6.proto=dhcpv6`;`enable_pppoe=yes` 时再改 PPPoE 并写账号密码 |
| LAN | `network.lan.ipaddr` 非空且不是 `192.168.1.1`,或 `network.lan.proto` 存在且不是 `static` | 跳过 br-lan 端口、`lan.proto`/`netmask`/`ipaddr` 的改写 | 沿用原流程:改 br-lan 端口、`lan.proto=static`、掩码,地址取 `custom_router_ip.txt` 或 `192.168.100.1` |

**为什么不只看段是否存在:** 镜像自带的 `/etc/config/network` 本来就有默认 WAN(dhcp、无凭据)和默认 LAN(static、192.168.1.1/24),首次安装时它们必然存在;拿"存在"当"已配置"的证据会连带关掉首次安装的初始化。判断因此落在"值是否已偏离固件默认"上。LAN 的默认地址取自 ImmortalWrt 各目标共用的 192.168.1.1/24。

**边界:** ①`enable_pppoe=yes` 的固件上,若设备 WAN 被人为改成无凭据的 DHCP,升级后仍会写回 PPPoE;②LAN 被人为设成 192.168.1.1 时,升级后仍会按首次安装路径改写;③固件默认 LAN 地址不是 192.168.1.1 的目标,首次安装会被判为"已配置"而跳过 LAN 初始化(不影响访问,只是不再套用 `custom_router_ip`)。这三种情况在 UCI 值上与"首次安装"无法区分。默认构建(`enable_pppoe=no`)不受 ①。WAN/LAN 之外的段落(防火墙、ttyd、dropbear、docker 等)均未改动。

### luci-app-singbox-admin(第三方 APK:来源、版本、投放)

- **为什么用上游制品。** 本 fork 的 `choicky/luci-app-singbox-admin` 没有 tag、Release,也没有 Actions 制品(2026-10-29 核实),不存在"choicky 仓库可用的稳定 APK";插件源码未做任何修改,直接取上游正式发布。
- **来源与版本。** `yukiinagato/luci-app-singbox-admin` 的 v4.1.1 Release,`luci-app-singbox-admin_4.1.1-r1_all.apk`(29 674 B,SHA-256 `2fc67133c95c93978c1920e57548f52ad40c10423610220d79f34af9fc174410`,arch `noarch`)。URL 与 SHA-256 固定写在 `shell/apk-prepare-packages.sh`,不跟随 `latest`。
- **文件名必须改。** ImageBuilder 用 `apk mkndx` 为 `packages/*.apk` 建索引,安装时按 `<name>-<version>.apk` 找文件;把上游的 `…_4.1.1-r1_all.apk` 原名放进去会报 `package mentioned in index not found`。脚本因此落盘为 `luci-app-singbox-admin-4.1.1-r1.apk`。
- **依赖可满足。** APK 声明依赖 `luci-base`、`sing-box`、`nftables`;`sing-box` 已在本清单的 PassWall 行内,`nftables` 由 ImmortalWrt 默认镜像(firewall4)提供。
- **签名。** 上游制品未签名。ImageBuilder 建索引时用 `--allow-untrusted` 接收外部 APK,再用本地构建密钥重签 `packages.adb`;安装时校验的是该索引及其中的哈希,因此未签名包可以装入(已用 apk-tools 3.0.8 按同一参数组合实测通过)。
- **不覆盖现有 sing-box 配置。** 包内只有 `/etc/config/singbox`(面板自身设置)与 `/usr/libexec/singbox-*`、LuCI 静态资源等,不含 `/etc/sing-box/`;sing-box 的 `config.json` 完全不碰。
- **不自动启用防火墙规则。** `/usr/share/singbox-admin/nftables.sh.example` 只是示例;`/etc/init.d/singbox-firewall` 安装时不建 `/etc/rc.d` 软链,`/etc/config/singbox` 的 `fw_boot` 默认为 `0`;且构建期 `apk add` 带 `--no-scripts`,`postinst` 不会执行。
- **升级保留。** 该 APK 由上游 `apk mkpkg` 直接生成,没有 conffiles 元数据,构建期不会产生 `conffiles_static`;因此 `/etc/config/singbox` 由本仓库的 `keep.d` 显式声明保留。它自己的 `postinst` 会在构建期被 `--no-scripts` 跳过,不会改动构建环境。

### 依赖语义(附一手核验证据,核验于 2026-10-21)
- **PassWall 本体会被装入。** 清单只请求 `luci-i18n-passwall-zh-cn`(中文语言包),未显式列 `luci-app-passwall` 本体;经一手证据核实本体会随依赖被拉入:
  - ImmortalWrt `luci` feed 的打包模板 `luci.mk` 会为每种语言生成 `luci-i18n-<pkg>-<lang>` 子包并设 `DEPENDS:=$(PKG_NAME)`,故 `luci-i18n-passwall-zh-cn` 依赖 `luci-app-passwall`;`make image PACKAGES=…` 按 apk 依赖解析,请求 i18n 即拉入本体。
  - 25.12.x 构建经 `build25.sh` 从 `wukongdaily/apk` 解包:PassWall run(26.6.2)实际捆绑了 `luci-app-passwall`、`luci-i18n-passwall-zh-cn`、`xray-core`、`sing-box`、`hysteria`、`geoview` 及 chinadns-ng / dns2socks / tcping / v2ray-geoip / v2ray-geosite 等 apk,统一收集进本地 `packages/` 供解析安装。
  - 证据边界:上述依据来自打包规则(`luci.mk` 源码)与捆绑包清单(一手)。`.apk` 是 `ADBd` 容器,本轮用 apk-tools 3.0.8 解析了 `luci-app-singbox-admin` 的元数据,但 passwall run 内的各个 apk 未逐一做二进制级 `depend` 复核。
- **`geoview` 定性。** `geoview` 是 `luci-app-passwall` 的构建期 `select`(`INCLUDE_Geoview` 在 aarch64 默认 `y`),其 apk 已随 run 捆绑于 `packages/`,会作为本体的传递依赖被自动解析。故清单**无需显式列出 `geoview`**;列出与自动解析结果等价,显式列出反而与传递解析重复。上游把 `geoview` 写进该行只是显式化。**最终固件仍会包含 geoview**(经本体依赖)。本定制**不改用 PassWall2**。
- **Aurora 无缺失本体。** `aurora/` 捆绑的正是清单所请求的 `luci-theme-aurora`、`luci-app-aurora-config`、`luci-i18n-aurora-config-zh-cn` 三项。

## 3. 日常同步上游流程(Git 原生)

约定:更新只进 `master`,再把 `master` 合并进 `custom`,个人定制永远不回流 `master`。

```bash
# 1) 拉取上游最新
git fetch upstream master

# 2) master 对齐上游(master 是纯镜像,直接快进到上游)
git checkout master
git merge --ff-only upstream/master   # 若快进失败,说明 master 被误改,应排查而非强推
git push origin master

# 3) 把更新后的 master 整合进 custom(优先普通 merge)
git checkout custom
git merge master
#   若 shell/apk-custom-packages.sh 冲突:在 custom 上解决,保留本 fork 定制块的语义,
#   不要把定制反向合进 master。

# 4) 检查定制仍然有效(见第 6 节的 source 解析自检)
git push origin custom
```

说明:
- `master` 与上游保持纯镜像,正常应是快进;不要用 `--force` 把定制带上 `master`。
- `custom` 采用普通 `merge` 而非 `rebase`,避免对已共享分支重写历史、需强制推送。
- 必要时按第 6 节重新触发一次构建验证。

## 4. 从 `custom` 构建 25.12.x 固件

1. 打开本 fork 的 **Actions** 页。
2. 选择工作流 **"Build 25.12.x Rockchip"**(文件 `build-rockchip-25.12.x.yml`)。
3. 点 **Run workflow**,并在 **Branch** 下拉中选择 **`custom`**(关键:选 custom 才会带上本 fork 定制;该工作流仅 `workflow_dispatch` 触发,`actions/checkout` 不带 `ref`,即用所选分支的脚本与清单)。
4. 参数:
   - `profile`:如 `friendlyarm_nanopi-r3s`、`friendlyarm_nanopi-r4s`(R3S/R4S 均受支持,完整列表见工作流内 options)。
   - `luci_version`:按需选 25.12.x(上游当前提供 25.12.0 / 25.12.1 / 25.12.2)。
   - 其余(软件包大小、docker、pppoe、管理 IP)按需。
5. 构建成功后固件自动上传为 Release 资产。

## 5. 发布(Release)注意事项

- 该工作流用 `softprops/action-gh-release` 发布到**硬编码的固定标签** `Autobuild`(Release 名 `ImmortWrt-Rockchip`),上传 `bin/targets/rockchip/armv8/*.img.gz`。
- 因为是固定标签,**从 `master` 或 `custom` 触发都会更新同一个 `Autobuild` Release**。为避免"纯净未定制固件覆盖定制固件",**只在 `custom` 上触发构建**;不要从 `master` 触发 rockchip 构建。
- 触发新构建会更新该 Release 的正文与同名资产。既有 `Autobuild` Release 当前保存着 2026-05-17 构建的 r3s/r4s 固件;重新构建将覆盖这些内容,请知悉后再操作。
- **Docker 开关的实际生效路径**:`build25.sh` 依据 `INCLUDE_DOCKER` 环境变量加入 `luci-i18n-dockerman-zh-cn`;而工作流中 `echo '… docker' >> shell/custom-packages.sh` 一步针对的是 opkg 清单(25.12.x 的 `build25.sh` 并不读取它),对 25.12.x 而言是无副作用的遗留步骤。此为**上游既有行为**,与本 fork 定制无关,本轮不修改。
- 工作流的发布机制沿用上游设计,本 fork **不修改**上游工作流。

## 6. 完成状态与验证证据(核验时间 2026-10-29)

> 下列 SHA、领先/落后数量与 Release 资产均为**本次核验时点**的状态;后续同步上游后,请以 `git`/`gh` 实测为准,勿将其当作当前实时值。

**A. 分支规范化 —— 已完成**
- `master` 纯上游:`origin/master == upstream/master == c2744d7`(ahead/behind **0/0**,tree 完全一致)。此 SHA 稳定,不受本轮收尾影响。
- `custom` 从规范化后的 `master` 派生,`master` 是其**祖先**;其内容 = `master` + `shell/apk-custom-packages.sh` 的定制行 + `shell/apk-prepare-packages.sh` 的固定版本 APK 投放 + `files/lib/upgrade/keep.d/wg-site` + `files/etc/uci-defaults/99-custom.sh` 的网络初始化判断 + 本 `FORK.md` 维护文档。`custom` 的**头条 SHA 与领先提交数会随文档提交而推进**,请以 `git rev-parse custom`、`git rev-list --left-right --count master...custom` 实测为准,本文不硬编码,以免收尾后再漂移。
- 历史备份见第 7 节,已在任何历史改写之前推送并验证,备份分支/标签均指向 `990b069`(稳定)。

**B. 代码 / Git 状态 —— 已独立核验(通过)**
- `custom` 相对 `master`:**参与构建的改动**为 `shell/apk-custom-packages.sh`(Aurora / PassWall / WireGuard / ZeroTier / sing-box 面板定制行及说明注释)、`shell/apk-prepare-packages.sh`(固定版本 APK 下载 + SHA-256 校验)、`files/lib/upgrade/keep.d/wg-site`(sysupgrade 保留清单,不含密钥或设备配置)与 `files/etc/uci-defaults/99-custom.sh`(仅 WAN/LAN 初始化判断);另有本维护文档 `FORK.md`(**不参与构建**)。
- `shell/custom-packages.sh` 未被改动 → 24.10.x 及更早不包含本 fork 新增的个人定制。
- 语法检查(`bash -n` / `sh -n`):`apk-custom-packages.sh`、`custom-packages.sh`、`rockchip/build25.sh`、`apk-prepare-packages.sh` 均通过。
- 运行时解析(非破坏性):
  ```bash
  bash -c 'CUSTOM_PACKAGES=""; source shell/apk-custom-packages.sh; echo "$CUSTOM_PACKAGES"'
  # 得到:luci-theme-aurora luci-app-aurora-config luci-i18n-aurora-config-zh-cn \
  #      xray-core sing-box hysteria luci-i18n-passwall-zh-cn \
  #      luci-app-singbox-admin kmod-wireguard wireguard-tools zerotier luci-app-zerotier
  #      (无重复项)
  ```
- 调用链:25.12.x 工作流 → 挂载并执行 `rockchip/build25.sh` → `source shell/apk-custom-packages.sh` → `sh shell/apk-prepare-packages.sh`(把第三方 APK 放进 `packages/`)→ `make image PACKAGES=…`(ImageBuilder 重新生成 `packages.adb` 后解析安装)。

**C. 软件包依赖 —— 已一手核实(见第 2 节)**
- 已核实 `luci-i18n-passwall-zh-cn` 经 `luci.mk` 依赖并拉入 `luci-app-passwall` 本体;PassWall run 26.6.2 捆绑本体与全部相关 apk;`geoview` 为本体的传递依赖,会自动包含,无需显式列出。
- `luci-app-singbox-admin` 的 APK 元数据已用 apk-tools 3.0.8 实测读出:name/version `4.1.1-r1`、arch `noarch`、depends `luci-base nftables sing-box`;并在临时 root 中完成 `mkndx` + `apk add` 实装,文件落点与 `/etc/config/singbox` 内容符合预期(见第 2 节)。
- `wireguard-tools` 的 proto 处理器路径已按 ImmortalWrt `package/network/utils/wireguard-tools/Makefile` 核实为 `/lib/netifd/proto/wireguard.uc`;ZeroTier 身份的保存方式按 `packages/net/zerotier` 的 init 脚本与 Makefile 的 conffiles 核实。

**D. 静态检查通过,端到端实构建未执行**
- 未在本轮执行全新的固件实构建:经 GitHub Actions 实跑会覆盖既有 `Autobuild` Release 资产(受约束不得为验证而覆盖重要产物),也不在本任务的验证范围内。
- 已做的替代验证:podman 中 apk-tools 3.0.8 复现 ImageBuilder 的 `mkndx --allow-untrusted` + 本地密钥签名索引 + 不带 `--allow-untrusted` 的安装路径,确认未签名第三方 APK 可装入;脚本 `bash -n` / `sh -n` 通过。
- `99-custom.sh` 用容器 + 伪 `uci`(记录每条 `uci` 调用、KV 存状态)跑了最小场景,只替换了 `/sys/class/net` 路径、其余脚本原样:
  - WAN:首次安装(默认 dhcp)仍写 dhcp/dhcpv6;首次安装 + `enable_pppoe=yes` 仍写 PPPoE;保留配置升级(pppoe + 账号密码)对 WAN 无任何 `uci set`。
  - LAN:首次安装(`192.168.1.1`/static)仍写 `lan.proto=static`、掩码与 `custom_router_ip`;保留配置升级(`192.168.100.1`)对 LAN 无任何 `uci set`,状态前后一致。
- 历史参考(**非当前版本验收**):`Autobuild` Release 于 2026-05-17 曾以定制态构建出 r3s/r4s 固件(资产当时仍在)。这不代表当前 `25.12.2` 及最新依赖的端到端结果。
- 结论:**代码/Git 核验、依赖一手核实、APK 投放机制实测、静态与运行时检查均已通过;端到端实机构建本轮未执行。**

**E. 待维护者确认 / 执行**
- 首次从现行固件升级前,按第 2 节「首次升级前必须自查」执行 `sysupgrade -l`,必要时补 `/etc/sysupgrade.conf`。
- 如需最终确认定制在实机构建中被正确包含:在 `custom` 分支按第 4 节触发一次 "Build 25.12.x Rockchip"(profile 选 r3s 或 r4s),并**接受该操作会更新 `Autobuild` Release**。构建产物应含 PassWall、Aurora、WireGuard、ZeroTier 与 `luci-app-singbox-admin`;若清单某项在最新 feed 中解析失败,再据错误信息做最小调整。

## 7. 备份与恢复

- 规范化前的原 fork `master` 历史(含两个个人提交与两次同步合并)已备份于 `origin`,均指向原始提交 `990b069`:
  - 分支 `refs/heads/backup/master-pre-normalize-20261021`
  - 附注标签 `refs/tags/backup/master-pre-normalize-20261021`
  - 二者**同名**,引用时请使用**完整 refspec**(`refs/heads/…` 或 `refs/tags/…`)以避免歧义;下方恢复命令已用 `refs/heads/…`。
- 恢复方式(如需回到规范化前状态;`--force-with-lease` 的预期值取当前 `origin/master`):
  ```bash
  git fetch origin
  git push --force-with-lease=master:$(git rev-parse origin/master) \
      origin refs/heads/backup/master-pre-normalize-20261021:master
  ```
