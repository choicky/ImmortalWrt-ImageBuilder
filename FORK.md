# Fork 维护与上游同步指南

本文件是 **本 fork(choicky/ImmortalWrt-ImageBuilder)专属的维护说明**,不参与上游内容,仅存在于 `custom` 分支。上游的用户文档(README.md / PACKAGES.md / SUPPORT.md / info.md)保持其原有职责,不在此重复。

## 1. 分支模型

- **`master` —— 纯上游同步分支。** 内容与上游 `wukongdaily/ImmortalWrt-ImageBuilder` 的 `master` 完全一致,**不承载任何个人定制**。它只用于跟踪上游,便于低冲突同步。日常构建固件请使用 `custom`,不要用 `master`。
- **`custom` —— 个人定制分支。** 从 `master` 派生,仅叠加下述 25.12.x 软件包定制。构建定制固件、发布产物都在此分支进行。

上游与本 fork 的默认分支均为 `master`。

## 2. 个人定制(仅 25.12.x)

### 位置
定制只改一个文件:**`shell/apk-custom-packages.sh`**,取消其中两行的注释(Aurora 主题行、PassWall 行)。

### 生效范围:为什么只有 25.12.x
- 25.12.x 使用 APK 包管理,其构建脚本 `*/build25.sh` 会 `source shell/apk-custom-packages.sh`(rockchip、x86-64、mediatek-filogic、sunxi-cortexa53 的 build25 均是),清单里的 `CUSTOM_PACKAGES` 随后被并入 `make image ... PACKAGES=...`。
- 24.10.x 及更早版本使用 opkg,其 `*/build24.sh` / `build23.sh` `source shell/custom-packages.sh`(不是 apk 清单)。
- 本 fork **不修改 `shell/custom-packages.sh`**,故 24.10.x 及更早固件**不包含本 fork 新增的个人定制**(此项仅说明本 fork 定制不外溢,不对上游默认包含哪些软件包作断言)。这是有意为之:按约定,Aurora 主题与 PassWall 相关软件包只保留在 25.12.x。

### 内容(取消注释后并入的包)
```bash
# Aurora 极光主题及配置
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-aurora luci-app-aurora-config luci-i18n-aurora-config-zh-cn"
# PassWall 相关(内核 + 中文语言包)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES xray-core sing-box hysteria luci-i18n-passwall-zh-cn"
```

### 依赖语义(附一手核验证据,核验于 2026-10-21)
- **PassWall 本体会被装入。** 清单只请求 `luci-i18n-passwall-zh-cn`(中文语言包),未显式列 `luci-app-passwall` 本体;经一手证据核实本体会随依赖被拉入:
  - ImmortalWrt `luci` feed 的打包模板 `luci.mk` 会为每种语言生成 `luci-i18n-<pkg>-<lang>` 子包并设 `DEPENDS:=$(PKG_NAME)`,故 `luci-i18n-passwall-zh-cn` 依赖 `luci-app-passwall`;`make image PACKAGES=…` 按 apk 依赖解析,请求 i18n 即拉入本体。
  - 25.12.x 构建经 `build25.sh` 从 `wukongdaily/apk` 解包:PassWall run(26.6.2)实际捆绑了 `luci-app-passwall`、`luci-i18n-passwall-zh-cn`、`xray-core`、`sing-box`、`hysteria`、`geoview` 及 chinadns-ng / dns2socks / tcping / v2ray-geoip / v2ray-geosite 等 apk,统一收集进本地 `packages/` 供解析安装。
  - 证据边界:上述依据来自打包规则(`luci.mk` 源码)与捆绑包清单(一手);**本机未能解析预构建 `.apk` 的二进制 `.PKGINFO`**(`ADBd` 容器,本地无对应解析器)。因此单个预构建 apk 内 `depend` 字面串未做二进制级复核。
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
#   若 shell/apk-custom-packages.sh 冲突:在 custom 上解决,保留本 fork 的两行定制语义,
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

## 6. 完成状态与验证证据(核验时间 2026-10-21)

> 下列 SHA、领先/落后数量与 Release 资产均为**本次核验时点**的状态;后续同步上游后,请以 `git`/`gh` 实测为准,勿将其当作当前实时值。

**A. 分支规范化 —— 已完成**
- `master` 纯上游:`origin/master == upstream/master == c2744d7`(ahead/behind **0/0**,tree 完全一致)。
- `custom` 从规范化后的 `master` 派生,`master` 是其祖先(领先 **2**、落后 **0**);`custom` 时点头条 = `3328f0a`。
- 历史备份见第 7 节,已在任何历史改写之前推送并验证。

**B. 代码 / Git 状态 —— 已独立核验(通过)**
- `custom` 相对 `master`:**参与构建的改动**仅为 `shell/apk-custom-packages.sh`(两行定制 + 一行说明注释);另有本维护文档 `FORK.md`(**不参与构建**)。
- `shell/custom-packages.sh` 未被改动 → 24.10.x 及更早不包含本 fork 新增的个人定制。
- 语法检查(`bash -n` / `sh -n`):`apk-custom-packages.sh`、`custom-packages.sh`、`rockchip/build25.sh`、`apk-prepare-packages.sh` 均通过。
- 运行时解析(非破坏性):
  ```bash
  bash -c 'CUSTOM_PACKAGES=""; source shell/apk-custom-packages.sh; echo "$CUSTOM_PACKAGES"'
  # 得到:luci-theme-aurora luci-app-aurora-config luci-i18n-aurora-config-zh-cn \
  #      xray-core sing-box hysteria luci-i18n-passwall-zh-cn  (无重复项)
  ```
- 调用链:25.12.x 工作流 → 挂载并执行 `rockchip/build25.sh` → `source shell/apk-custom-packages.sh` → `make image PACKAGES=…`。

**C. 软件包依赖 —— 已一手核实(见第 2 节)**
- 已核实 `luci-i18n-passwall-zh-cn` 经 `luci.mk` 依赖并拉入 `luci-app-passwall` 本体;PassWall run 26.6.2 捆绑本体与全部相关 apk;`geoview` 为本体的传递依赖,会自动包含,无需显式列出。
- 未做(已如实标注):本机未解析预构建 `.apk` 的二进制 `.PKGINFO`(`ADBd` 容器无本地解析器)。

**D. 静态检查通过,端到端实构建未执行**
- 未在本轮执行全新的固件实构建:本机无 docker;且经 GitHub Actions 实跑会覆盖既有 `Autobuild` Release 资产(受约束不得为验证而覆盖重要产物)。
- 历史参考(**非当前版本验收**):`Autobuild` Release 于 2026-05-17 曾以定制态构建出 r3s/r4s 固件(资产当时仍在)。这不代表当前 `25.12.2` 及最新依赖的端到端结果。
- 结论:**分支规范化、代码/Git 核验、依赖一手核实、静态与运行时检查均已通过;端到端实机构建本轮未执行。**

**E. 待维护者确认 / 执行**
- 如需最终确认定制在实机构建中被正确包含:在 `custom` 分支按第 4 节触发一次 "Build 25.12.x Rockchip"(profile 选 r3s 或 r4s),并**接受该操作会更新 `Autobuild` Release**。构建产物应含 PassWall、Aurora;如清单某项在最新 feed 中解析失败,再据错误信息做最小调整。

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
