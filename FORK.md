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
- 本 fork **不修改 `shell/custom-packages.sh`**,故 24.10.x 及更早固件**不含**这些个人定制。这是有意为之:按约定,Aurora 主题与 PassWall 相关软件包只保留在 25.12.x。

### 内容(取消注释后并入的包)
```bash
# Aurora 极光主题及配置
CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-theme-aurora luci-app-aurora-config luci-i18n-aurora-config-zh-cn"
# PassWall 相关(内核 + 中文语言包)
CUSTOM_PACKAGES="$CUSTOM_PACKAGES xray-core sing-box hysteria luci-i18n-passwall-zh-cn"
```

### 关于 PassWall 语义的两点说明(重要)
- 清单请求的是 `luci-i18n-passwall-zh-cn`(中文语言包),**未**单独列 `luci-app-passwall` 本体。PassWall 本体会通过 luci 语言包对主应用的依赖被拉入。"清单请求" 与 "最终固件确实包含" 需以实际构建为准,见第 6 节。
- 上游最新版已把该可选行的包集调整为 `geoview xray-core sing-box hysteria luci-i18n-passwall-zh-cn`(新增 `geoview`)。本 fork **沿用已验证可用的包集(不含 geoview)**,并且**不改用 PassWall2**——这是刻意的最小定制。若今后确需 `geoview` 或 PassWall2,请单独评估后手动调整,不要默认跟随上游。

## 3. 日常同步上游流程(Git 原生)

约定:更新只进 `master`,再把 `master` 合并进 `custom`,个人定制永远不回流 `master`。

```bash
# 1) 拉取上游最新
git fetch upstream master

# 2) master 对齐上游(master 是纯镜像,直接快进/重置到上游)
git checkout master
git merge --ff-only upstream/master   # 若上游快进失败,说明 master 被误改,应排查而非强推
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
- `master` 与上游保持纯镜像,正常应是快进;不要用 `--force` 把定制带上 master。
- `custom` 采用普通 `merge` 而非 `rebase`,避免对已共享分支重写历史、需强制推送。
- 必要时按第 6 节重新触发一次构建验证。

## 4. 从 `custom` 构建 25.12.x 固件

1. 打开本 fork 的 **Actions** 页。
2. 选择工作流 **"Build 25.12.x Rockchip"**(文件 `build-rockchip-25.12.x.yml`)。
3. 点 **Run workflow**,并在 **Branch** 下拉中选择 **`custom`**(关键:选 custom 才会带上本 fork 定制)。
4. 参数:
   - `profile`:如 `friendlyarm_nanopi-r3s`、`friendlyarm_nanopi-r4s`(R3S/R4S 均受支持,列表见工作流内 options)。
   - `luci_version`:按需选 25.12.x。
   - 其余(大小、docker、pppoe、管理 IP)按需。
5. 构建成功后固件自动上传为 Release 资产。

## 5. 发布(Release)注意事项

- 该工作流用 `softprops/action-gh-release` 发布到**硬编码的固定标签** `Autobuild`(Release 名 `ImmortWrt-Rockchip`),上传 `bin/targets/rockchip/armv8/*.img.gz`。
- 因为是固定标签,**从 `master` 或 `custom` 触发都会更新同一个 `Autobuild` Release**。为避免"纯净未定制固件覆盖定制固件",**只在 `custom` 上触发构建**;不要从 `master` 触发 rockchip 构建。
- 触发新构建会更新该 Release 的正文与同名资产。既有 `Autobuild` Release 当前保存着 2026-05-17 构建的 r3s/r4s 固件;重新构建将覆盖这些内容,请知悉后再操作。
- 工作流的发布机制沿用上游设计,本 fork **不修改**上游工作流。

## 6. 本次规范化:完成状态与验证证据

**已完成并已验证:**
- 审计:fork 原领先上游 4 提交(2 个上游同步合并 + 2 个个人定制)、落后 35 提交;个人定制净 diff 仅为 `shell/apk-custom-packages.sh` 两行。
- 备份(见第 7 节)已在改写历史前推送并验证。
- `master` 已对齐上游最新:`origin/master == upstream/master`(ahead/behind 0/0,tree 完全一致)。
- `custom` 相对 `master`:**参与构建的改动**仅为 `shell/apk-custom-packages.sh` 两行定制(+一行说明注释);另有本维护文档 `FORK.md`,它**不参与构建**。`shell/custom-packages.sh` 未被改动(24.10.x 不受影响)。
- 静态检查工作流:仅 `workflow_dispatch` 触发、`actions/checkout@v6` 不带 `ref`(即在所选分支触发即使用所选分支的脚本与清单)、执行 `rockchip/build25.sh`、`permissions: contents: write`(足够发布 Release)。
- 运行时清单解析自检(非破坏性):
  ```bash
  bash -c 'CUSTOM_PACKAGES=""; source shell/apk-custom-packages.sh; echo "$CUSTOM_PACKAGES"'
  # 输出包含: luci-theme-aurora luci-app-aurora-config luci-i18n-aurora-config-zh-cn \
  #          xray-core sing-box hysteria luci-i18n-passwall-zh-cn
  ```
  证明定制在清单侧被正确拼接、无重复。

**尚未验证(与实际构建的区别):**
- 未执行一次全新的端到端固件实构建:本机无 docker;且经 GitHub Actions 实跑会覆盖既有 `Autobuild` Release 资产(受本任务约束不得为验证而覆盖重要产物)。故"定制包能否在实机构建中被成功解析安装"目前依据:
  1) 既有 `Autobuild` Release 于 2026-05-17 以同一定制态成功构建出 r3s/r4s 固件(历史证据);
  2) 上述静态与运行时检查。
- 结论:**静态检查通过,端到端实构建未在本轮执行。** 若需最终确认,请由维护者在 `custom` 上按第 4 节触发一次构建(并接受会更新该 Release)。

## 7. 备份与恢复

- 规范化前的原 fork `master` 历史(含两个个人提交与两次同步合并)已备份于:
  - 分支 `backup/master-pre-normalize-20261021`
  - 附注标签 `backup/master-pre-normalize-20261021`
  - 二者均指向原始提交 `990b069`,已推送至 `origin`。
- 恢复方式(如需回到规范化前状态):
  ```bash
  git fetch origin
  git push --force-with-lease=master:$(git rev-parse origin/master) \
      origin backup/master-pre-normalize-20261021:master
  ```
