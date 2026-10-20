# 工作日志 — ODIN 移植实施（016 之后的阶段 0/1/3）

> 用途：随时记录进展与下一步，**任何时刻中断都能照此恢复**。每完成一步就地更新本文件。
> 起始时间：2026-08-29 11:4x　分支：`main`　基线提交：`1838e73`

---

## 一、已锁定的决策（用户拍板，2026-08-29）

| # | 决策 | 选择 |
|---|---|---|
| 1 | 阶段 2（UTF-8） | **放弃 FAT32 中文，不做 nls_utf8**。不重编内核模块；以 exFAT / NTFS 为主力文件系统 |
| 2 | 自动挂载方案 | **systemd mount unit**（udev 打 `TAG+="systemd"`），**不装 udisks2** |
| 3 | 首刷策略 | **接受首刷期间没有 OTG**，安全版 `l0-safe` 作为 `default` |

## 二、安全红线（自定，不突破）

- **不对真机做任何刷写**（fastboot flash 一律不做）。
- 真机上的改动分两级：
  - **可逆**：`/etc`、`/usr/local/sbin`、`/etc/systemd` 下的用户态文件 —— 改前备份到 `*.odin-bak`，可随时回滚。
  - **不可逆**：替换 `/boot` 里的 DTB 或改 `extlinux.conf` 的 `default` 并重启 —— **必须先跟用户单独确认**。
- 真机当前是唯一的 SSH 生命线，任何可能导致重启后失联的操作都视为高风险。

## 三、当前基线状态（已实测核对）

产物 md5（与 reports/013 记录一致，8/28 批次之后无改动）：

```
dist/lk2nd.img              521d64fcb2ab4cf534bac1f9b8440712
dist/odin-debian.img        6b009587431b2d4e88bd6c4698a18bfd
odin-qemu/rootfs.img        2ab66f0800afa2e0c560dff7d36569fe
dist/odin-debian-sparse.img b7aea6cfe5f4a167f2a8796e8cade624
```

镜像内实测（挂载 `dist/odin-debian.img` 到容器 `/mnt/chk` 后核对）：

| 项 | 值 |
|---|---|
| `/boot` | `vmlinuz` 30468104、`initramfs.cpio.gz` 988089、`dtbs/qcom/msm8953-smartisan-odin.dtb` 44362（**仅此一个 dtb**） |
| `extlinux.conf` | 单 label `l0`；`fdtdir /boot/dtbs`；append 含 `console=ttyMSM0,115200n8 earlycon=msm_serial_dm,0x78af000 root=/dev/disk/by-label/pmOS_root rootwait rw` |
| 模块目录 | 仅 `6.19.0-postmarketos-qcom-msm8953`；`kernel/fs/nls/` 只有 `nls_ucs2_utils.ko` |
| `/etc/udev/rules.d/` | **空** |
| `/usr/local/sbin/` | `odin-firstboot-resize.sh`（013 已重写）、`odin-usb-gadget.sh`（8/22 旧版，待替换） |
| odin DTB 属性 | `dr_mode` 有、`usb-role-switch` 有、**`role-switch-default-mode` 无**（→ 默认 peripheral，UDC 恒在）；无 `chosen/framebuffer` 节点；含 `cont-splash@90001000` 保留内存；含 `fusb301`/`typec-controller@25`/`usb-c-connector`/`otg-vbus` |

构建环境：

- 容器 `odin-build`（debian:bookworm，OrbStack）**运行中**，`/work` = 宿主 `/Volumes/caseSensitiveBar`
- `/mnt/stage` = 真机 rootfs 可写基线；`/mnt/stage-qemu` = QEMU 基线；两者**与镜像同步**（无更新文件）
- 内核源码树 `/Volumes/caseSensitiveBar/linux-msm8953`：`.config`、`vmlinux`、`arch/arm64/boot/Image`、odin DTB、`Module.symvers` 齐全（Alpine gcc 13.2.1，8/21–8/22 构建）
- QEMU 台 `odin-qemu/`：`run.sh`（`-M virt -cpu cortex-a57 -smp 2 -m 1024`，ssh 2222 / telnet 2323，qemu-xhci + usb-storage）
  - **注意**：`odin-qemu/Image` 是 8/23 的**另一个内核**，与镜像内核不同源，只能验用户态

## 四、任务清单

| # | 任务 | 状态 |
|---|---|---|
| T5 | 阶段0：生成并编译 `msm8953-smartisan-odin-norolesw.dtb` | **已完成** |
| T6 | 阶段0：`extlinux.conf` 双 label，首刷 default = `l0-safe` | **已完成** |
| T7 | 阶段1：staging 安装 exfatprogs/ntfs-3g/dosfstools/btrfs-progs/xfsprogs/f2fs-tools | **已完成** |
| T8 | 阶段1：automount udev 规则 + `odin-mount-opts.sh` | **已完成** |
| T9 | QEMU 验证阶段0+1（启动 / 自动挂载 / 网络 / usb0 unmanaged） | 待开始（等镜像重建） |
| T10 | 阶段3：`odin-usb-role.sh` + udev 规则 + service/timer 看门狗 | **已完成** |
| T11 | QEMU 冒烟验证阶段3 | 待开始 |
| T12 | 重建镜像 + 全量校验 | 进行中 |
| T13 | 真机动态验证（仅可逆改动） | 待开始 |
| T14 | 更新 FLASH.md / README + 写 reports/017 + 提交 | 待开始 |

## 五、进度日志

（每步完成后追加）

- **2026-08-29 11:4x** — 建任务清单与本日志；完成镜像/环境基线核对（见 §三）。
- **11:50 T5 完成** — 安全版 DTB 落地。
  - 新增 `dts/msm8953-smartisan-odin-norolesw.dts`（`#include` 完整版后做 4 处删改：
    `dr_mode` → peripheral、删 `usb-role-switch`、删 `ports`、删 fusb301 的 `connector`）
  - 新增 `dts/build-dtb.sh`（可复现构建脚本，自动识别 dtc 1.6/1.7）
  - **标定**：用宿主 dtc 1.7.2 与容器 dtc 1.6.1 分别重编完整版 DTS，**两者都逐字节复现**
    既有 dtb（md5 `e0ecc4ad23d02bce50997bdb011aa993`，44362 B）→ 管线可信
  - 产物：`dts/msm8953-smartisan-odin.dtb` 44362 B（同上）、
    `dts/msm8953-smartisan-odin-norolesw.dtb` 43924 B（md5 `627f692d298d425b69ac4f81867c0436`，
    两个 dtc 版本结果一致）
  - 反编译自检：安全版 `usb-role-switch`=0、`usb-c-connector`=0、`dr_mode="peripheral"` ✅；
    仅 `otg-vbus` 稳压器保留（切回完整版时仍可用）
  - **踩坑**：dtc 要求属性写在 `/delete-node/` 之前，否则报
    `Properties must precede subnodes`；内核自带的 `scripts/dtc/dtc` 是 aarch64-musl
    二进制，macOS 宿主与 debian 容器都跑不了（exec format / 缺 musl loader）

- **12:00 T6 完成** — 双 label 引导。
  - **读 lk2nd 源码定案**（`lk2nd/boot/extlinux.c:394-434`）：`fdt` 与 `fdtdir`
    **互斥** —— label 里只要有 `fdtdir`，lk2nd 就用 `lk2nd,dtb-files` 拼
    `<dtbdir>/qcom/<name>.dtb` 并**覆盖** `fdt`。所以安全版 label 只写 `fdt`。
  - **重大结构发现**：镜像是**单一文件系统**（只有 `pmOS_root`），`/extlinux/` 与
    `/boot/` 都在根分区里，不是 pmOS 那种 pmOS_boot+pmOS_root 双分区。
    ⇒ **切 label 只需在系统里改 `/extlinux/extlinux.conf` 再重启**，不用挂 boot 分区。
  - 新增源 `dist/build/rootfs/extlinux/extlinux.conf`（default=l0-safe，l0 用 fdtdir、
    l0-safe 用 fdt），由 `apply-staging-fixes.sh` 部署。

- **12:05 T7 完成** — 两个 staging（`/mnt/stage`、`/mnt/stage-qemu`）都装了
  exfatprogs / ntfs-3g / dosfstools / btrfs-progs / xfsprogs / f2fs-tools。
  无新增 systemd 服务拓扑（只有静态的 `sys-fs-fuse-connections.mount`）。
  `user` 的 uid = 1000（挂载选项要对齐这个值）。

- **12:08 T8 完成** — 自动挂载。
  - **推翻了 015 §3.2 的一处假设**：实测 bookworm systemd 252 里，**PID 1 不读任何
    `SYSTEMD_MOUNT_*` 属性**，只有 `/usr/bin/systemd-mount` 读，且只认
    `SYSTEMD_MOUNT_WHERE` 与 `SYSTEMD_MOUNT_OPTIONS` 两个。
    ⇒ 光写 `TAG+="systemd"` 不会挂载任何东西，必须显式 `RUN+=/usr/bin/systemd-mount`。
  - 放弃 `--owner=`（systemd-mount 会对挂载点做 chown，vfat/exfat 上会失败），
    改为在挂载选项里给 `uid=/gid=/fmask/dmask`。
  - 新增源：`dist/build/rootfs/etc/udev/rules.d/99-odin-automount.rules`、
    `dist/build/rootfs/usr/local/sbin/odin-mount-opts.sh`。
  - `odin-mount-opts.sh` 逐 fstype 自检已过（vfat/exfat → uid,gid,fmask,dmask；
    ntfs3/ntfs → uid,gid,umask；POSIX → 仅 noatime）。

- **12:13 T10 完成** — USB 角色自动切换。
  - 新增源：`dist/build/rootfs/usr/local/sbin/odin-usb-role.sh`、
    `dist/build/rootfs/etc/udev/rules.d/99-odin-usb-role.rules`。
  - 脚本特性：flock 防重入、先空后名绑定 UDC、任何分支 exit 0、无 typec 且无 UDC
    时立即返回（避免 QEMU 空等 20s）、dnsmasq 按 pidfile 幂等。
  - **保留服务名 `odin-usb-gadget.service`**（不改名为 odin-usb-role），因为 QEMU
    镜像是按这个名字 mask 的；改为 `Type=oneshot + RemainAfterExit=yes`。
  - 看门狗命名 `odin-usb-gadget.timer`（同源名），只在服务未被 mask 的真机镜像启用。
  - 同步改了 `dist/build/setup-rootfs.sh` 的 gadget 段，改从 `dist/build/rootfs/`
    取源，避免将来从零重建时静默回退到旧逻辑。
  - **脚本部署注意**：`apply-staging-fixes.sh` 用 `cat >` 而非 `cp` 写 service/timer ——
    QEMU 镜像里它是 `/dev/null` 符号链接，写穿它正好保持 mask 生效。

- **12:41 QEMU 最终回归（第四次重建的镜像）** —— 全绿：
  - 4 个 USB 盘全部自动挂载（vfat/ntfs/ext4；exFAT 因 QEMU 内核不支持而挂不上）
  - **挂载选项生效**：sda = `noatime,uid=1000,gid=1000,fmask=0133,dmask=0022` ✅
    sdc(ntfs-3g) = `noatime` + `default_permissions,allow_other` ✅；sdd(ext4) = `noatime` ✅
  - **用户可写性验证通过**：sda、sdc 用 `user` 直接写成功，文件属主 1000:1000 ✅
  - `systemctl --failed` = 0 ✅
  - 两个 DTB 与双 label extlinux.conf 均正确落到镜像内 ✅

- **12:32 发现并修掉一个"刷了就起不来"的隐患（本次最重要的发现）**
  - 从 `dist/lk2nd.img` 里解出全部 31 条 QCDT 条目后比对发现：
    `msm8953-smartisan-odin` 的 board-id 是 `<0x0b 0x01>`，而
    `msm8953-xiaomi-markw` 是 `<0x1000b 0x01>`。
  - 查 `dev_tree.h:56-58`：`VARIANT_MASK=0xff` ⇒ 两者 **variant_id 都是 0x0b**，
    高位 `0x10` 只是 major。按 `dev_tree.c:448-500` 的匹配规则，变体相同即同时候选。
  - **修正一处误判**：真机 DT 里的 `<0x1000b 0x01>` **不是硬件 ID** —— 全树 grep 确认
    lk2nd **没有任何写 `qcom,board-id` 的代码**，那只是 markw 内核 DTB 自己的声明值。
    原厂 `evidence/stock_dtb_1.dtb` 明确写着 `qcom,board-id = <0x0b 0x01>`
    （model = "Qualcomm Technologies, Inc. MSM8953 ODIN"）⇒ **项目 DTS 写的是对的**。
  - 但风险仍在：若 lk2nd 判给 markw，原 `l0` 的 `fdtdir` 会去找镜像里没有的
    `msm8953-xiaomi-markw.dtb` ⇒ 启动失败。
  - **已修**：`l0` 与 `l0-safe` **全部改为显式 `fdt`**，不再用 `fdtdir`。
    选中 odin → 有屏 + 全功能；选中 markw → 无屏但能起、SSH 可用。
  - 附带确认：只有 lk2nd 选中 odin 条目才会替换 `smartisan,odin-panel` 占位
    compatible —— 这是屏幕点亮的唯一开关，只能真机判定。若实测无屏，下一步是
    精简 lk2nd（只留 odin 条目）强制命中。

- **12:47 真机安全验证（只读 + dry-run，SSH 全程未受影响）**
  - UDC = `7000000.usb` ✅；`/sys/class/typec` 不存在（pmOS 内核无 fusb301）✅
  - **`find /sys -name role` 为空** ⇒ 阶段 3 的"手动 `echo device > .../role` 强制切回"
    这条后门在当前内核上**不可用**（风险坐实，已写进 FLASH.md）
  - `odin-usb-role.sh --dry-run` 在真机上跑通：`device: [dry-run] udc=7000000.usb
    gadget-UDC='' dnsmasq_running=no; no action` —— 逻辑正确且**零副作用**
  - `odin-mount-opts.sh` 四种 fstype 自检通过
  - pmOS 侧对照：systemd 257 / udev 257 有 `systemd-mount`、`exfat.ko` 存在、
    `nls_utf8` 缺失（与项目内核一致）

- **12:47 T12 完成** — 最终产物（第 5 次重建，全部校验通过）：
  ```
  dist/lk2nd.img              521d64fcb2ab4cf534bac1f9b8440712   （未改动）
  dist/odin-debian.img        98482fdbdcd15e6f568c162fda3629ca
  dist/odin-debian-sparse.img 56a2cbca0075c7aac3d184b5f2a618e1   （check_sparse = IDENTICAL）
  odin-qemu/rootfs.img        c30ecee6a9ffb519cf5ac6f37fea1949
  ```
  注：上面 sparse 的 md5 是 12:47 那次；随后 12:47 又为 dry-run 重建过一次，
  以 `tools/check_sparse.py` 复跑为准（最近一次为 IDENTICAL）。

### 柒、真机刷入循环（用户授权选项二：无人值守执行）

**流程依据**：`reports/018`（状态机、命令、红线）。红线：**只刷 userdata，绝不刷 boot**。

**13:19 前置确认**
- 状态 A：pmOS 运行，`model = Xiaomi Redmi 4 Prime`，lk2nd `21.0-r0-postmarketos`
- `extlinux.conf` 真实位置 `/boot/extlinux/extlinux.conf`（`/boot` = `pmOS_boot` 子分区）
- 备份已在本地 `evidence/live-device-backup/`（boot 分区 64M / /boot 28M / GPT 前 8M / STATE.txt）

**13:20 步骤 ① A→B：改名引导配置 → 重启 → lk2nd 停 fastboot ✅**
- 只 `mv` 未删除：`extlinux.conf` → `extlinux.conf.DISABLED`，内容校验完整
- 两次踩坑：macOS 无 `timeout` 命令；`pm_do.exp` 执行的是手机上的 `/tmp/pmr.sh`，
  必须走 `sh /tmp/pmr.sh <本地脚本>` 才会先 scp 上传
- 重启后 ~60s：`fastboot devices` → **`<emmc-serial>  fastboot`** ✅
  **实测证实：lk2nd 启动失败确实会自动停在 fastboot**（与用户判断一致）

**13:22 fastboot 只读探测 —— 拿到高价值信息（已存档 `fastboot-getvar-all.txt`）**
```
lk2nd:version    : 21.0-r0-postmarketos
lk2nd:model      : Xiaomi Redmi 4 Prime (markw)      ← lk2nd 选中的是 markw 条目
lk2nd:compatible : xiaomi,markw
lk2nd:panel      : qcom,mdss_dsi_ft8716_1080p_video  ← ★ 面板名
unlocked         : yes
max-download-size: 0x1fe00000 (534 MB)
partition-size:userdata : 0x1bfabfbe00 (111.9 GiB)
```
- ★ **`lk2nd:panel` 有值 ⇒ 原厂 aboot 确实透传了面板名**，reports/010 §七 悬而未决的问题
  答案是"是"。且面板为 **FT8716**，正是补丁 0005 支持的型号。
- lk2nd 仍选中 markw（不是 odin）⇒ 我们的 `smartisan,odin-panel` 占位不会被替换 ⇒
  **预期无屏**，与 reports/017 的分析一致。
- 推论：硬件 target major = 0x10（故 markw 以 major 精确匹配胜出），
  即使换成我们的 lk2nd，markw 仍会赢 ⇒ **必须精简 lk2nd（去掉 markw）才能让 odin 命中**。

**13:24 步骤 ② 刷入 userdata ✅（EXIT=0，178 秒）**
```
Sending sparse 'userdata' 1/2 (522237 KB)  OKAY [ 13.021s]
Writing  'userdata'                        OKAY [ 14.222s]
Sending sparse 'userdata' 2/2 (122484 KB)  OKAY [  2.957s]
Writing  'userdata'                        OKAY [147.606s]
```

**13:27 步骤 ③ `fastboot reboot` → 至今（13:48）未出 SSH —— 状态 D，无响应**

诊断：
- `fastboot devices` 空（不在 fastboot）
- SSH 两个密码（user / cheng）均超时
- PC 侧 USB 网卡 en17 消失
- `ioreg`/`system_profiler` 上**完全没有手机**，只剩 Hub(`Xiaomi Type-C 5-in-1 Hub`) 与 RTL9210 硬盘盒
  ⇒ **手机不是直连，是接在 Type-C Hub 上**（新发现，之前没注意到）

分析（推测，待串口证实）：
- 与 ① 不同：这次 lk2nd **找到了** extlinux.conf 并成功跳转内核，
  所以"找不到配置→停 fastboot"这条救援路径**不再触发**
- 内核若 panic 或卡死，USB gadget 不会枚举 ⇒ PC 上完全看不到设备 ⇒ 与观察吻合
- 已排除扩容因素：无 64bit 特性下 895 个组、只需 6 个 reserved GDT（有 127），分钟级

**当前阻塞**：无串口输出，无法定位卡在哪一步；恢复需要人工长按电源键 + 音量键进 fastboot。

**下一步（等用户在场或授权）**
1. 长按电源 10–15s 强制关机 → 音量减+电源 进 fastboot
2. `fastboot boot` 试启动，或换 `l0`/`l0-safe`、或改用 markw DTB 试
3. 若都不行，用 pmbootstrap 重装 pmOS 回到已知可用状态

**19:08 用户已手工进 fastboot，并改为直连（不再走 Type-C Hub）**
- `fastboot devices` → `<emmc-serial>  fastboot` ✅
- USB 拓扑：`"USB Product Name" = "Android"` / Serial `<emmc-serial>`，Hub 已消失 ✅
- 结论：**当前处于状态 B**，可以按 018 手册继续

**19:10 精简 lk2nd 的可行性推导（源码级，不是猜测）**

`dev_tree.h:81-112` 的匹配位序（数字=bit 位，越大优先级越高）：
```
VARIANT_MINOR_BEST/EXACT      9/10
VARIANT_MAJOR_BEST/EXACT     11/12
SUBTYPE_DEFAULT_MATCH        25
SUBTYPE_EXACT_MATCH          26   ← 关键
VARIANT_MATCH                27
SOC_MATCH                    28
```
`dev_tree.c:599-608` 比较规则：先比 `dt_match_val`（位图整体当整数比），**相等时再比 major，major 大的赢**。

因为 `BIT(26) > BIT(25) + BIT(12)`，**带 SUBTYPE_EXACT 的条目必然压过只有 MAJOR_EXACT 的**。

遍历全部 31 条 QCDT 条目，`msm-id=0x125 & (variant & 0xff)=0x0b & subtype=0x01` 的**只有两个**：
- `msm8953-xiaomi-markw` (`<0x1000b 0x01>`，major=0x10 → SUBTYPE_EXACT + MAJOR_EXACT)
- `msm8953-smartisan-odin` (`<0x0b 0x01>`，major=0x00 → SUBTYPE_EXACT + MAJOR_BEST)

⇒ **删掉 markw 后，odin 成为唯一带 SUBTYPE_EXACT 的候选，稳赢。**
（对照：xiaomi-common 是 `<0x1000b 0x00>` → 只有 SUBTYPE_DEFAULT，注定输给 odin；
sdm450-xiaomi-rosy / sdm632-qrd-sku4 虽也是 0x0b/0x01 但 msm-id 分别是 0x152/0x15d，SOC 不匹配直接排除。）

**19:13 精简 lk2nd 构建成功**
- 改 `lk2nd/device/dts/msm8953/rules.mk`：整行移除 `msm8953-xiaomi-markw.dtb` 与
  `sdm450-xiaomi-rosy.dtb`，说明注释写在 **ADTBS 块之前**
- **踩坑**：Makefile 里**不能把注释插进 `\` 续行中间** —— 第一次改写把注释放进续行块，
  报 `rules.mk:28: recipe commences before first target`（注释行打断了续行链，
  后续以 tab 开头的行被当成 recipe）。改成块外注释后正常。原文件已备份为 `rules.mk.orig`
- 构建：`make TOOLCHAIN_PREFIX=arm-none-eabi- PROJECT=lk2nd-msm8953`（容器已装该工具链）
- 产物 `dist/lk2nd-nomarkw.img`：364560 B（原 366608，小 2 KB），md5 `b6e475252976e267bc8b6d7766f9c9f9`
  - **27 个 appended DTB**（原 29）
  - `strings | grep xiaomi-markw` → **0 处**（已清除）✅
  - `strings | grep smartisan-odin` → 2 处（保留）✅

**19:14 用 `fastboot boot` 从内存启动验证（未写分区，boot 分区仍是 pmOS 的 lk2nd）**
- 命令 `fastboot boot dist/lk2nd-nomarkw.img` 已下发
- 结果：**又是状态 D** —— 不在 fastboot、USB 上无手机、无 USB 网卡、SSH 全不通
- 用户观察：**背光亮着、黑屏**

**关键判断（重要）**
- 两次失败用的是**同一个 Debian 镜像**，lk2nd 分别是 pmOS 原版(21.0) 与 精简版 ⇒
  **问题不在 lk2nd，在 Debian 6.19 + odin DTB 这一侧**
- 背光亮说明手机有电、lk2nd/内核走到了点亮背光这一步（比上次的完全无响应进了一步）
- 无 USB 网卡 ⇒ 内核里 UDC 没起来（dwc3 未成功 probe）⇒ 与我们"安全版 DTB 是
  dr_mode=peripheral、UDC 应恒在"的预期不符
- **当前瓶颈：没有串口输出，无法定位内核卡在哪一步。** 继续盲试只会反复消耗按键。

**待验证的两个假设（等进 fastboot 后做对照测试）**
- H1 硬件其实更接近 markw（lk2nd 判 markw、board-id 0x1000b/01），odin DTB 不匹配
  ⇒ 对照：用 **Debian 内核 + markw DTB** 构造 boot.img 做 `fastboot boot`
- H2 odin 安全版 DTB 本身有问题（我删 ports/role-switch 的改动引入）
  ⇒ 对照：用 **Debian 内核 + odin 完整版 DTB**（未删改）做 `fastboot boot`

### 玖、★ 重大突破：Debian 系统已在真机跑起来，且 lk2nd 命中 odin

**19:14 `fastboot boot dist/lk2nd-nomarkw.img`（内存启动精简版 lk2nd）**
- 现象：USB 网卡枚举了（en20），但 PC 只拿到 169.254 自分配地址
- 分析：gadget 是 **initramfs 的 `usb_up()`** 配的（只配地址、**不开 dnsmasq**）
  ⇒ 系统当时还没走到 systemd 的 gadget 服务
- 用户手动给 PC 配固定 IP → **SSH 成功登录** ✅

**19:31 登录后核心诊断 —— 两个目标全部达成**
```
hostname  : odin                                ← 我们的镜像（不再是 pmOS 的 u2pro）
uname     : 6.19.0-postmarketos-qcom-msm8953
model     : Smartisan U2 Pro (ODIN)             ← 加载的是 odin DTB ✅
compat    : smartisan,odin qcom,msm8953
★ panel@0 : smartisan,odin-ft8716 smartisan,odin-panel
            ↑ lk2nd 把占位替换成真实面板 FT8716 ⇒ 精简 markw 生效，odin 命中 ✅
lk2nd,version : unknown-20260829                ← 本次构建的精简版（version 未注入）

UDC       : 7000000.usb ✅
usb0      : 172.16.42.1/24 ✅
gadget    : active ✅
扩容      : /dev/mmcblk0p57  111G  651M  105G  1%   ← 2GiB→111G 成功 ✅
failed    : 0 个 ✅
```
**结论：reports/018 的推导被实机证实 —— 删掉 markw 后 odin 成为唯一
SUBTYPE_EXACT_MATCH 候选，必然命中；面板识别链路（aboot 透传 → lk2nd 替换
占位 compatible）在真机上完整工作。**

**剩余问题：屏幕仍未点亮**
```
/sys/class/drm/ : 只有 version      ← 没有 card0
/dev/dri        : 不存在
/sys/class/backlight/ : 空
但驱动都绑定了：
  1a00000.display-subsystem → msm-mdss
  1a01000.display-controller → msm_mdp
  1a94000.dsi   → msm_dsi
  1a94400.phy   → msm_dsi_phy
  panel_ft8716  : 已加载但 0 users（没绑到设备）
/sys/bus/platform/devices/ 里只有 1a94000.dsi，**没有 panel 设备**
/sys/kernel/debug/devices_deferred : 空（没有设备 deferred）
dmesg: gcc-msm8953 sync_state() pending due to 1a00000.display-subsystem
```
→ 初步判断：**panel platform device 没有被创建**（panel@0 是 dsi 的子节点，
不是 simple-bus，不会自动变成 platform device），需要 msm_dsi 在 probe 时
自己解析子节点找 panel；而 panel 驱动是模块(=m)，加载时机可能晚于 msm_dsi probe。

**下一步待试（按风险从低到高）**
1. 重新触发 msm_dsi probe：`echo 1a94000.dsi > .../msm_dsi/unbind; echo ... > bind`
   （此时 panel_ft8716 已注册，重 probe 可能就接上了）—— **零风险，先试**
2. 装 kmod（modprobe 不存在）+ iputils-ping（用户已发现 ping 缺失）
3. 把面板驱动改为内建(=y)重编内核
4. 若都不行，考虑 panel 是否应改成通过 ports/endpoint 连接

**顺带发现的两个包缺失（待办）**
- `kmod` 未装 ⇒ `modprobe` 不存在 ⇒ 模块自动加载机制失效
- `iputils-ping` 未装 ⇒ `ping` 不可用

**★ 屏幕取得实质进展（ovp 改 29600 并重启后）**
```
/sys/class/backlight : backlight          ← 背光设备出现 ✅（WLED probe 不再报错）
/dev/dri             : by-path card0 renderD128   ← DRM card0 出现 ✅
/sys/class/drm       : card0 card0-DSI-1 renderD128
[drm] Initialized msm 1.13.0 ... minor 0
[drm] fb0: msmdrmfb frame buffer device   ← fb0 出现 ✅
panel compatible     : smartisan,odin-ft8716（写死生效，lk2nd 未覆盖）
```
**仍未点亮** —— 只剩最后一步：
```
ft8716 1a94000.dsi.0: Failed to initialize panel: -22
[drm:mdp5_irq_error_handler] *ERROR* errors: 04000000
```
即背光/DRM 框架都起来了，但面板驱动自身的初始化序列返回 -EINVAL，需查
`drivers/gpu/drm/panel/panel-ft8716.c` 的 probe（供电/时序/命令序列）。

### 拾、USB 网络自动分配 IP —— 根因已查明，修复已提交，但尚未部署成功

**两层原因（都是实机抓出来的，不是推测）**

第 1 层：dnsmasq 根本起不来
```
dnsmasq: cannot set --bind-interfaces and --bind-dynamic
```
/etc/dnsmasq.d/zz-gadget-exclude.conf 里有 `bind-dynamic`，与脚本命令行的
`--bind-interfaces` 互斥 ⇒ dnsmasq 读配置后直接退出（日志里 "dnsmasq started
(pid N)" 是假象，进程随即消失、pgrep 查不到）。
另外系统 dnsmasq 用 bind-dynamic 绑通配地址，占住 UDP 67。

第 2 层：地址池"没有可用地址"
```
DHCPDISCOVER(usb0) a6:df:c9:9c:b7:3e   no address available
租约文件: 66:ec:1e:92:ff:3f 172.16.42.2 <pc-hostname>
```
地址池当时只有 172.16.42.2 一个；手机每次重启 USB gadget 会**重新生成随机 MAC**，
PC 侧网卡 MAC 跟着变 ⇒ dnsmasq 当成全新客户端，而唯一地址被旧 MAC 的 12h 租约占住
⇒ PC 只能拿 169.254 自分配地址。
**这正是 postmarketOS 用 unudhcpd 的原因**（它不做租约管理，任何客户端都给固定 IP）。

**修复（已提交 fe2904d）**
1. 写死 NCM 的 host_addr/dev_addr（02:00:0d:1d:00:01 / …ba，基于序列号 <emmc-serial>）
2. 地址池扩到 172.16.42.2–172.16.42.10 兜底
3. gadget dnsmasq 加 `--conf-file=/dev/null`（不读系统配置）
4. apply-staging-fixes.sh 里 mask 系统 dnsmasq
5. 脚本加启动后校验：dnsmasq 没活下来就记日志 + 打自身日志

**⚠️ 部署尚未成功（当前卡点）**
- 失败的写法：`ssh ... 'echo user | sudo -S bash -s' <<'EOF'`
  —— `echo user |` 把 sudo 的 stdin 占用了，`bash -s` 读不到 heredoc ⇒ 命令没执行。
  （之前成功的那次是 `bash /tmp/install_dtbs.sh`，脚本在远端，**不是** `bash -s`）
- 一旦手机重启，PC 就拿不到 IP（旧脚本还在），于是 SSH 不通 ⇒ 无法部署 ⇒ 死锁。
- 本机现在 PC 侧是 169.254，IPv4/IPv6 都连不上手机。

**打破死锁：需要人工在 PC 上配一次 IP（最后一次）**
```sh
sudo ifconfig enXX alias 172.16.42.10 netmask 255.255.255.0     # enXX = 当前 USB 网卡
ssh user@172.16.42.1
```
连上后执行（注意用远端脚本文件，不要 `bash -s`）：
```sh
sshpass -p user ssh ... user@172.16.42.1 'cat > /tmp/rn.sh' < dist/build/rootfs/usr/local/sbin/odin-usb-role.sh
sshpass -p user ssh ... user@172.16.42.1 'echo user | sudo -S cp /tmp/rn.sh /usr/local/sbin/odin-usb-role.sh'
sshpass -p user ssh ... user@172.16.42.1 'echo user | sudo -S rm -f /var/lib/misc/dnsmasq.leases'
sshpass -p user ssh ... user@172.16.42.1 'echo user | sudo -S systemctl reboot'
```
重启后 gadget 用固定 MAC 重建，PC 应能**自动**拿到 172.16.42.2，此后无需再手工配置。

**其它待办**
- 手机尚无外网（无默认路由），wlan0 未起来 ⇒ 后续 apt 装包需先解决联网
- 离线 deb 已备好（90 个，35MB）在宿主机 `/Volumes/caseSensitiveBar/odin-offline-debs/`，
  用户指示暂不安装，留待后续
- `ping`、`modprobe` 等工具缺失（kmod / iputils-ping 未装）；
  登录 Shell 已确认是 GNU bash 5.2.15（非 busybox），/bin/sh -> dash，符合预期

### 捌、精简 lk2nd（已完成构建，已被实机验证命中 odin）

- **12:50 T14 完成** — FLASH.md 已更新（双 label、显式 fdt 的来由、外置存储矩阵、
  自愈看门狗、role 回退缺口）。README 已更新（§四刷机包与用户态组件、§五已验证内容、
  §六刷入步骤、§七已知限制、§八决策）。reports/017 实施报告已写。
- **13:16 仓库收尾完成** — 4 个提交：
  `8f43fac` 阶段0/1/3 落地 · `6a5aab8` 文档与报告 · `5fa186b` 镜像产物 · `9988689` 备份与操作手册
  `git status` 干净。

- **12:20 QEMU 首次回归（用第 1 批重建的镜像）** —— 三个重要发现：
  1. ✅ 4 个 USB 盘（vfat/exfat/ntfs/ext4 superfloppy）全部识别，
     `ID_BUS=usb` + `ID_FS_USAGE=filesystem` + `ID_FS_TYPE` 正确
  2. ❌ **superfloppy 没有 `ID_PART_ENTRY_NUMBER`** ⇒ 原规则的分区号限制会把
     "整盘一个文件系统、无分区表"的 U 盘全部排除。**已放宽规则**（去掉该条件）。
  3. ❌ `systemd-mount` 以普通 user 身份执行报
     `Interactive authentication required`（polkit）。udev 的 RUN 是 root，
     产品路径不受影响；测试脚本改用 `sudo -S` 复现。
  4. ❌ failed 单元 0 ✅；`odin-mount-opts.sh` 分流自检全过 ✅

- **12:21 两个内核层结论（拿源码/配置坐实，不靠推测）**：
  - **exFAT 不依赖 nls_utf8** —— `fs/exfat/super.c:38-41` iocharset=utf8 时
    `opts->utf8=1`，`:691-697` 走 `set_default_d_op(exfat_utf8_dentry_ops)`
    **根本不调用 `load_nls()`**，用内建 `utf16s_to_utf8s()`。
    ⇒ **"放弃 FAT32、靠 exFAT" 的决策成立，中文文件名开箱正常**。
    （这条修正了 015 §4.5 "exFAT 驱动内建 UTF-16 处理" 的含糊表述）
  - **镜像内核无法在 QEMU 里跑** —— `.config` 只有 `VIRTIO_BLK/NET/CONSOLE=y`，
    但 `VIRTIO_PCI`、`VIRTIO_MMIO` **均未设置** ⇒ virt 机器上没有块设备/网卡。
    印证 015 #12：QEMU **只能验用户态**，内核/硬件相关项必须真机验证。
  - 顺带核实：`CONFIG_EXFAT_FS=m`（**是模块不是内建**，修正 015 §4.5 的说法），
    镜像内 `kernel/fs/exfat/exfat.ko` 确实存在（594 KB，modules.dep 无依赖）；
    `CONFIG_NTFS3_FS=y` 内建（`modules.builtin` 里有 ntfs3）；`CONFIG_BLK_DEV_SD=y`。
    exfat 挂载时由内核 `request_module("fs-exfat")` 自动加载，无需额外处理。

### 拾壹、面板驱动正确性审查（用户要求：仔细核对移植是否正确）—— 结论：移植正确

做法：从仓库里原厂 DTB 的反编译 `evidence/stock.dts` 精确提取
`qcom,mdss_dsi_ft8716_1080p_video` 节点（行 11215–11280）的
`qcom,mdss-dsi-on-command`（1622 字节），按 qcom 命令格式
`dtype,last,vc,ack,wait,dlen_hi,dlen_lo,payload` 解码为 125 条命令，
与 `drivers/gpu/drm/panel/panel-ft8716.c` 的 `ft8716_panel_on()` 逐条比对 payload：

```
原厂 125 条  vs  驱动 123 条    不一致 = 2
[123] 原厂: 05 11 00  ← exit_sleep_mode
[124] 原厂: 05 29 00  ← set_display_on
```
差的这 2 条驱动用标准 DCS API（`mipi_dsi_dcs_exit_sleep_mode` / `set_display_on`），
语义等价；**前 123 条逐字节完全一致** ✅
（脚本：/tmp/extract2.py、/tmp/cmp_panel.py；原始数据：/tmp/panel_cmp/）

### 拾贰、IPv6 固定地址 —— 零配置兜底通道（已实机验证）

- 新增 `odin-usb6-addr.service`（已 enable）：开机后给 usb0 加固定链路本地地址
  **`fe80::1`**（保留内核自动生成那个，不覆盖）。sshd 默认监听 `[::]:22`。
- 实测：PC 只有 169.254 自分配地址时，`ssh user@fe80::1%enXX` **照样连得上** ✅
- 注意：ssh 必须带 `-o PreferredAuthentications=password -o PubkeyAuthentication=no`，
  否则 ssh 先试 publickey 卡住，sshpass 传入的密码不会被使用（踩过一次）。

### 拾叁、★ 死锁打破：PC 开机自动拿到 IP（已实机验证）

**死锁**：手机一重启 PC 就拿不到 IP ⇒ SSH 不通 ⇒ 无法部署修复 ⇒ 死循环。
**破局**：用拾贰的 IPv6 通道连进去完成部署。

**最终修复（在 fe2904d 基础上再补两处健壮性问题）**：
1. dnsmasq 在 usb0 刚 `addr add` 完就绑定 —— 地址还处于 tentative，导致 dnsmasq
   起来后**又退出**（表现：日志有 "dnsmasq started (pid N)"，但 pgrep 查不到进程）。
   修：启动前轮询等待 usb0 真的出现 172.16.42.1，最多 10s。
2. `dnsmasq_running()` 原先只判断 pidfile 里的 pid 是否存在 —— pid 被别的进程复用时
   会误判成"已在运行"从而永远不启动。修：额外校验 `/proc/<pid>/cmdline` 含 `--interface=usb0`。
3. `rm -f "$PIDFILE"` 改为无条件清理（原来 `-s` 判断，空 pidfile 会残留）。

**实机验证（重启后，PC 全程零配置）**：
```
en27 自动拿到 172.16.42.6
SSH(v4) 172.16.42.1 通，hostname=odin，uptime 1 分钟（刚重启）
dnsmasq pid 281 开机自启成功，监听 usb0，range 172.16.42.2–172.16.42.10
日志：bound UDC=7000000.usb → usb0=172.16.42.1/24 → dnsmasq started (pid 281)
```
⇒ **以后重启手机再也不用碰 PC 的网络设置。**
（PC 侧拿到 .4/.6 会变，但不影响使用——SSH 连的是手机侧固定的 172.16.42.1。）
（dnsmasq 日志时间戳显示 Apr 27 是手机系统时钟未同步，非故障。）

### 拾肆、⚠️ 更正：启用 GPU 是正确修复，但**没有解决面板 -EINVAL**

**更正此前判断**：上面那次"面板初始化成功"是**误判** —— 当时开着 `drm.debug`，
dmesg 环形缓冲被 vblank 日志刷爆，早期的 `Failed to initialize panel` 已被冲掉，
于是 grep 到"0 次失败"。**去掉 drm.debug 后干净日志显示：面板 -EINVAL 一直存在**，
与 GPU 无关（此前 GPU disabled 时同样失败）。

**启用 GPU 本身仍是对的**（markw 的 DTB 有完整 gpu 节点，odin.dts 漏了 ⇒ 已补，adreno 已绑定）。

**当前干净日志（去掉 drm.debug 后）**：
```
[27.330957] msm_mdp: bound 1a94000.dsi (ops dsi_ops)
[27.334418] adreno 1c00000.gpu: supply vdd not found, using dummy regulator
[27.338690] adreno 1c00000.gpu: supply vddcx not found, using dummy regulator
[27.351643] msm_mdp: bound 1c00000.gpu (ops a3xx_ops)
[27.403052] Direct firmware load for qcom/a530_pm4.fw failed with error -2   ← GPU 微码缺
[27.408603] [adreno_request_fw] *ERROR* failed to load a530_pm4.fw
[27.449170] ft8716 1a94000.dsi.0: Failed to initialize panel: -22            ← 仍未解决
[27.474164] [mdp5_irq_error_handler] *ERROR* errors: 04000000
[27.491132] fb0: sys_imageblit: framebuffer is not in virtual address space  ← 另一个问题

DSI enabled=enabled status=connected dpms=On；backlight=4095/4095；fbcon bind=1
GPU firmware 错误数=2（a530 微码缺）
```

**定位进度（判据逐个排除）**：
DSI 主机 `drivers/gpu/drm/msm/dsi/dsi_host.c:1710 dsi_host_transfer()`:
```c
if (!msg || !msm_host->power_on) return -EINVAL;   ← 静默，不打印
```
实机 grep 各判据结果（全部 0 次 ⇒ 失败来自上面这个静默分支，或另一个未打印的路径：
```
packet size is too big     : 0
cmd cannot fit into BLLP   : 0
Power on failed            : 0
failed to prepare host     : 0
create packet failed       : 0
cmd dma tx failed          : 0
```
注：`dsi_manager.c:244` 有注释 "Enable before preparing the panel, disable after unpreparing"，`dsi_mgr_bridge_power_on()` 末尾会 `msm_dsi_host_enable_irq()` 后才返回 ⇒ 理论上
`power_on` 在 panel prepare 时为 true，但实机时序显示 panel prepare(27.449) 在
host enable 之前(27.474 才出 error irq) ⇒ **bridge 链顺序仍需确认（谁先 pre_enable）。
`drm_panel_bridge` 在 msm 中的挂载点尚未找到（grep msm/ 无 `drm_panel_bridge`）。

**下一步（已明确）**
1. **重编 `panel_ft8716.ko` 加打印**，定位具体失败的第 N 条命令（驱动树已完整构建过，`make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- M=drivers/gpu/drm/panel modules）
2. 补 GPU 微码 `qcom/a530_pm4.fw` / `a530_pfp.fw`（Debian 无 firmware-misc-nonfree 候选，需从 pmOS 的 firmware-qcom-adreno-a530 或原厂 ROM 取
3. 查 `fb0: sys_imageblit: framebuffer is not in virtual address space（影响 fbcon 显示）
4. 若 bridge 顺序有问题，可尝试把初始化命令从 `prepare` 移到 `enable`

**教训（方法层面）**
- 用 `drm.debug` 抓日志前，先确认要抓的类别不会刷爆缓冲；否则早期错误被覆盖，会得到假结论（本次已踩两次：一次误判成功，一次误判 GPU 是根因）
- 任何"日志里没这个错误"的结论，都要先验证环形缓冲是否完整（`dmesg | head -3` 看最早记录的时间戳）
- `dd` 直接写 `/dev/fb0` 不一定刷到硬件（msm 的 fbdev 需要 damage 触发），不能作为"像素管道不通"的证据
- `default-brightness = <200>` 相对 `max 4095` 只有 5%，看起来像没开背光 ⇒ 已改 2048（50%）
- ssh 需带 `-o PreferredAuthentications=password -o PubkeyAuthentication=no`，否则 sshpass 的密码用不上
- zsh 里变量不做单词分割，`$SSHO` 会被当成单个参数 ⇒ 要么写完整选项，要么用脚本文件

### 拾伍、当前未解：面板初始化 -EINVAL（屏幕仍未亮）

### 拾肆、当前未解：面板初始化 -EINVAL（屏幕仍未亮）

```
ft8716 1a94000.dsi.0: Failed to initialize panel: -22
[drm:mdp5_irq_error_handler] *ERROR* errors: 04000000
msm_mdp 1a01000.display-controller: no GPU device was found
Unbalanced enable for IRQ 39   (WARNING，来自 wled_ovp_work 过压处理)
已修好的：/sys/class/backlight/backlight 出现；/dev/dri/{card0,renderD128}、fb0 出现
```

- 失败点：`ft8716_prepare()` → `variant->on()`。on() 里只有两个**有日志**的失败点
  （exit_sleep / display_on），但日志里没有这两条 ⇒ 是 123 条序列中某条被
  `dsi_dcs_write_seq` 宏**静默 return**（该宏不打印日志）⇒ 本质是 **DSI 主机拒收命令**。
- 已排除：供电没问题（`regulator_bulk_enable` vddio/vdd/lab/ibb 全部成功之后才失败）。

**高嫌疑：DTS 漏了启用 GPU**
- `msm8953.dtsi` 里 `gpu: gpu@1c00000` 默认 `status = "disabled"`；
  配套 `zap_shader_region: zap@81800000`、`gpu_zap_shader: zap-shader` 都在 dtsi 里。
- **odin.dts 里完全没有 `&gpu { status = "okay"; }`** ⇒ 实机 `GPU 设备不存在`、`/dev/kgsl*` 无。
- 对比 markw：DTB 里有完整 `gpu@1c00000` + zap-shader + `firmware-name = "qcom/msm8953/xiaomi/markw/a506_zap.mdt"`。
- 另：镜像里**没有任何 GPU 固件**，只装了 `firmware-atheros`。a506_zap.mdt 属 postmarketOS
  专有包（从原厂 ROM 提取），Debian 与容器里都没有 ⇒ 需从原厂 ROM 取（`refs/`、`Pro_user_V4.2.5/`）。

**下一步**
1. odin.dts 补 `&gpu { status = "okay"; }`（无需固件也能先验证 GPU 是否影响 DSI 命令）
2. 从原厂 ROM 找 a506_zap.mdt（`/firmware/image/`、`/vendor/firmware/`）
3. 若与 GPU 无关，继续查 DSI 主机拒收命令的原因（`MIPI_DSI_MODE_LPM` 标志 / host 时序）
4. 顺带：wled OVP 过压（ovp 现为 29600，备用更保守值 19600）引发的 `Unbalanced enable for IRQ 39`

### 待清理清单（最后统一做，中途不删）
- `/Volumes/caseSensitiveBar/.dtbbuild/`（DTB 标定临时目录，仓库外）
- 容器内 `/tmp/dtbbuild`、`/tmp/dtbcal`、`/tmp/asf.sh`
- 容器内 `/mnt/src`、`/mnt/src-qemu`（旧镜像只读挂载取证点，仍挂着 loop）
- 容器内 `/mnt/chk`（本次核查挂载点，仍挂着 `dist/odin-debian.img`）
- 宿主 `/tmp/odin-*.log`、`/tmp/odin-md5.txt`


### 拾陆、★ 成功：屏幕点亮 + DHCP 稳定（两个长期问题都解决）

**A. 屏幕不亮 —— 根因：面板初始化命令发得太早**

drivers/gpu/drm/msm/dsi/dsi_host.c:1710 dsi_host_transfer() 开头：
    if (!msg || !msm_host->power_on) return -EINVAL;     ← 静默，不打印任何日志

而 panel-ft8716.c 的 drm_panel_funcs 原来只有 prepare/unprepare/get_modes（**没有 enable**），
初始化 DCS 命令全在 prepare 发。实机时序证明 panel prepare 发生在 DSI 主机上电之前 ⇒ 每条命令
-EINVAL，所以日志里只有一句 "Failed to initialize panel: -22"，极具迷惑性。

关键时序（已去掉 drm.debug 的干净日志）：
    [27.822154] bound 1c00000.gpu (ops a3xx_ops)
    [27.879968] [adreno_request_fw] failed to load a530_pm4.fw
    [27.919011] FT8716 DBG: cmd[0] len=2 reg=0x00 ret=-22    ← 第一条就失败
    [27.945115] [mdp5_irq_error_handler] errors: 04000000      ← 之后主机才 enable

修复（已提交 patches/0008-drm-panel-ft8716-send-init-sequence-in-enable-not-prepare.patch）：
  - on() 移到新增的 ft8716_enable()；off() 移到 ft8716_disable()
  - prepare 只保留上电 + reset
  - 定位手段：临时给 dsi_dcs_write_seq 宏加打印（已 revert，实测 FT8716 DBG 残留 = 0）

**B. DHCP 不稳定 —— 双重根因**
1. **MAC 固定失效（我脚本的 bug）**：
   旧代码 `[ -f host_addr ] || echo $MAC > host_addr`，但 configfs 的 host_addr/dev_addr 文件
   **总是存在**（内核填随机值）⇒ 判断恒真 ⇒ 永远跳过写入 ⇒ 每次重启新 MAC。
   且绑定 UDC 后这两个属性不可写（Permission denied）。
   改为 usb0 出现后 `ip link set usb0 address`（实测生效：02:00:0d:1d:00:02）。

2. **地址池被旧租约占满**：每次新 MAC 一条 12h 租约，九个地址（.2~.10）耗尽 ⇒ 新客户端
   "no address available"。

修复（采纳用户思路：永远只连一台电脑，不按 MAC 区分）：
  - 地址池改为**单地址** 172.16.42.2~172.16.42.2（任何 MAC 都分到同一个 IP）
  - 每次重建 gadget 前 `rm -f /var/lib/misc/dnsmasq.leases`
  - 租约 12h → 1h

**C. 最终实机状态（存档：evidence/device-probe/STATE-DISPLAY-OK.txt）**
```
Failed to initialize panel = 0
DSI enabled=enabled status=connected dpms=On
backlight = 4095/4095
fb0 = 1080,1920   fbcon bind=1
GPU = adreno（a530 微码仍缺，不影响显示）
usb0 MAC = 02:00:0d:1d:00:02
usb0 IP  = 172.16.42.1/24
dhcp-range=172.16.42.2,172.16.42.2,1h
DHCPACK(usb0) 172.16.42.2 <pc-hostname>     ← PC 自动拿到固定 IP
cmdline: console=ttyMSM0,115200n8 ... console=tty0     ← 控制台上屏
/ = 111G，已用 916M
```

**D. 这轮用到的两个关键技巧（可复用）**
- **IPv6 链路本地兜底通道**：当 IPv4 DHCP 挂了，手机仍可用 `ssh user@fe80::<EUI64>%enXX` 连上。
  实际地址不是 fe80::1（我加的固定地址服务没生效），而是由 MAC 推导的 EUI-64：
  MAC 02:00:0d:1d:00:02 ⇒ fe80::67ff:fedb:feba。
  发现方法：`ping6 -c 2 ff02::1%<iface>` 看谁回应。
- **定位"静默失败"的通用手段**：给判据处的宏/函数临时加打印，重编**单个模块**（`make M=drivers/... modules`），
  scp 到设备覆盖 .ko + depmod，重启看日志；定位完 revert 重编干净版。

### 待办（下一轮）
1. GPU 微码固件 `qcom/a530_pm4.fw` / `a530_pfp.fw` 仍未装（Debian 无 firmware-misc-nonfree 候选，pmOS 的 firmware-qcom-adreno-a530 才有）
2. `fb0: sys_imageblit: framebuffer is not in virtual address space`（影响 fbcon 显示质量）
3. 修复 odin-usb6-addr.service（fe80::1 固定地址没生效，改用 EUI-64 发现即可，或修服务让它真的加上）
4. 待最终清理：仓库根目录的空文件 power_on（我的 shell 误操作产物）
5. 尚未刷入：dist/ 镜像未重刷到手机（当前手机系统是之前刷的 + 增量部署的模块与配置）；
   若要从零复现，需用 fastboot 重刷 dist/lk2nd.img + dist/odin-debian-sparse.img
6. 考虑把 dist/lk2nd.img 换成精简版（去掉 markw）：需要刷 boot 分区（有风险，需确认）


---

## 拾柒 [2026-08-29 22:30] 需求：整理成「从原生 Fastboot 从头刷入」的完整可复现流程

用户原话：「我们需要给它整理成能够从头刷入的脚本和镜像。从头刷入的意思是，从设备自带的
原生的 Fastboot 开始，刷入 LK2ND，然后再执行的一系列操作，到能够连接 SSH。成功使用这个
系统，这样一个完整的流程……先说说你准备怎么做？」

### 现状盘点（22:26 实测）
| 产物/资源 | 路径 | 状态 |
|---|---|---|
| 内核树 | `/Volumes/caseSensitiveBar/linux-msm8953`（分支 odin-wip） | 在，含 0001-0008 |
| 补丁 | `patches/0001..0008` | 齐（0008=面板 init 挪到 enable） |
| DTB | `dts/*.dtb` × 4 | 齐（含背光 2048/GPU 修复） |
| lk2nd 原版 | `dist/lk2nd.img` 366608 B + `lk2nd/bin/emmc_appsboot.mbn` | 已真机验证可启动 |
| lk2nd 精简版 | `dist/lk2nd-nomarkw.img` 364560 B（去掉 markw 条目） | **未经真机验证** |
| Debian 镜像 | `dist/odin-debian.img` 2GiB + `-sparse.img` 660MB | 8/29 12:46 批次，**不含** 0008/背光/DHCP 三项修复 |
| rootfs overlay | `dist/build/rootfs/`（6 个文件） | 含最新 odin-usb-role.sh（单地址池） |
| staging 修复 | `dist/build/apply-staging-fixes.sh` | 含 §4/§5/§6 |
| 镜像导出 | `tools/build-image.sh` | 含全量回读校验 |
| 构建容器 | docker `odin-build`（debian:bookworm，Up 27h） | 在 |
| 主机 fastboot | `/opt/homebrew/bin/fastboot` 36.0.0 | 在 |

### ⚠️ 关键判断
**现有 dist/ 镜像落后于真机**：手机现在跑的是「早期镜像 + 增量部署的 .ko / DTB / 脚本」，
而 `dist/odin-debian.img` 是 12:46 生成的，之后的三项关键修复（0008 面板、DTB 背光+GPU、
odin-usb-role.sh 单地址池）**都没烘焙进去**。直接拿它从头刷 ⇒ 必然黑屏 + DHCP 不稳。
⇒ 所以「从头刷入」的第一步不是刷机，而是 **先重跑一遍构建管线，产出一个与真机等价的镜像**。

### 计划（待用户确认后执行）

**A. 构建侧 —— `tools/build-all.sh`（一条命令重建全部产物）**
1. 校验内核树：确认 0001-0008 已 apply（`git -C linux-msm8953 log/diff`）
2. 重编 `panel-ft8716.ko`（容器内 `make ARCH=arm64 M=drivers/gpu/drm/panel modules`）
3. `dts/build-dtb.sh` → 4 个 DTB
4. 以**当前真机系统**为基线建 staging（SSH + rsync/tar 拉回，而非用旧的 /mnt/debian），
   再套 `apply-staging-fixes.sh` 打 overlay + 新 .ko + 新 DTB + extlinux.conf
5. `tools/build-image.sh` → `odin-debian.img` + `-sparse.img`，全量回读校验
6. 生成 `dist/MANIFEST.sha256`，记录每个产物的 md5/大小/来源

**B. 刷机侧 —— `flash/flash-all.sh`（原生 fastboot → SSH 可用，可重入）**
拆成带序号的阶段脚本，任何一步失败都能从那一步重跑：
```
00-precheck      本机 fastboot/镜像/md5 校验、SSH 可达性、备份提醒
10-backup        经 SSH 备份真机关键文件（/extlinux /usr/local/sbin /etc/udev
                 /lib/modules/.../panel-ft8716.ko /etc/systemd 自研单元）
20-fastboot      轮询等待设备进入原生 fastboot（引导用户按 音量减+电源）
30-flash-boot    fastboot flash boot <lk2nd>
40-flash-data    fastboot flash userdata odin-debian-sparse.img（失败回退 raw，带重试）
50-boot          fastboot reboot，等待 USB NCM 网卡出现
60-usbnet        等 PC 拿到 172.16.42.2（DHCP 优先，超时则静态兜底）
70-ssh           等 22 端口可达，SSH 登录
80-verify        跑 12 项验收（内核/面板/背光/DRM/usb0/dnsmasq/扩容/…）
90-handoff       提示切 l0 完整版、OTG、GPU 微码等后续项
```
配套：`flash/lib/common.sh`（日志/重试/超时/时间戳）、`flash/rescue.sh`（IPv6 EUI-64 /
initramfs telnet / 串口 三条兜底通道）、`flash/STATE.md`（状态机 A/B/C/D 与循环策略）。

**C. 需要用户拍板的两件事**
1. 首刷用哪个 lk2nd：原版（已验证，但可能命中 markw 条目 ⇒ 无屏）/ 精简版（强制命中 odin，
   理论上必亮屏，但从未刷入过真机）
2. 刷 userdata 会清空手机全部数据 —— 是否需要先做一次 userdata 全量备份

### 待办（延续）
（见上一节 1-6 项，另加：本轮新增的构建/刷机脚本）

---

## 拾捌 [2026-08-29 22:50] 全量备份 + 发布准备

### A. 真机全量备份（已完成）
产物在**手机上**：`/root/odin-backup/rootfs-full.tar`（953 MB，16392 条目，tar rc=0，
`DONE` 标记已落）。脚本 `flash/stages/10-backup.sh`，三个子命令：
- 无参数：在手机上打包（nohup 后台 + 每 5s 轮询大小，只用一条 stat，hub 繁忙也安全）
- `--status`：看进度
- `--fetch`：HTTP 拉回（`python3 -m http.server` 绑 172.16.42.1，`curl -C -` 断点续传）

**踩坑 1（重要）**：最初写成 `ssh 设备 tar -cf - / | gzip > 本机`，两次都在 ~14s/~110MB
处断，设备随后 30s 完全不响应 ping。分离测试证明**不是网络问题**——纯流量压测
400MB 用 20s 跑完（约 20MB/s）。是设备端 tar 边读边往外吐时 USB NCM 会 stall。
⇒ 大批量数据先在设备本地落盘，传输阶段只做顺序大文件拷贝。

**踩坑 2**：`/root` 是 0700，用 `odin_ssh`（user 身份）去 `tar -tf` 只得到空输出，
差点把一份完好的备份判成"截断"。⇒ 涉及 /root 一律用 `odin_sudo*`。
已把这条写进 `flash/lib/common.sh` 的注释。

**踩坑 3**：bash 在 C locale 下把紧跟在 `$VAR` 后面的中文字符当变量名的一部分
（`DEVICE_IP）——先确认` ⇒ `DEVICE_IP\uFFFD: unbound variable`）。
⇒ 所有脚本里变量一律写成 `${VAR}`。

### B. 关键事实修正：boot 分区里不是我们的 lk2nd
实测 `/dev/disk/by-partlabel/boot` 的 bootimg 头 `kernel_size=339260`，
既不是 `dist/lk2nd.img`(352980) 也不是 `lk2nd-nomarkw.img`(351316) ⇒
**boot 分区至今仍是 pmOS 原版 lk2nd 21.0**（当时只用 `fastboot boot` 内存启动验证过精简版）。
- 备份 `evidence/live-device-backup/boot-partition.img` 与实时分区**逐字节一致**（md5 相同）
  ⇒ 有可靠回滚路径。
- 屏幕之所以亮，靠的是 DTB 里写死 `compatible="smartisan,odin-ft8716"`，
  与 lk2nd 选中哪个条目无关。所以刷精简版 lk2nd 是"再加一道保险"，不是雪中送炭。

### C. 发布前的安全修复：SSH 主机密钥
`git grep "BEGIN ... PRIVATE KEY"` 在两个刷机镜像里命中 —— 镜像带着一把固定的
SSH 主机私钥，公开发布等于所有设备共用同一身份（可 MITM）。
- `tools/build-image.sh` §2 干净化：删除 `/etc/ssh/ssh_host_*`
- `dist/build/apply-staging-fixes.sh` §2b：新增 `odin-ssh-hostkeys.service`
  （`Before=ssh.service`，`ssh-keygen -A` 只补缺失的类型，尾部 `exit 0` 保证失败也不挡 SSH）
- 不能用 ssh.service 的 ExecStartPre drop-in：Debian 自带 `ExecStartPre=/usr/sbin/sshd -t`，
  而 drop-in 的 ExecStartPre 是**追加**在其后，无密钥时 `sshd -t` 直接退出，轮不到生成动作。

### D. extlinux.conf 与 DTB 对齐真机
真机验证可用的是 `*-ft8716*.dtb`（面板写死），仓库里却指向自动识别版，且 append 少了
`console=tty0`（控制台上屏开关）。已同步：
- `dist/build/rootfs/extlinux/extlinux.conf` 两个 label 都改指 ft8716 变体 + 补 `console=tty0`
- `apply-staging-fixes.sh` §4 改为部署**四个** DTB（主用 ft8716 对，自动识别对留作换屏退路）

### E. 准备公开仓库（进行中）
- 安装 `git-filter-repo` 2.47.0
- 审计结果：730 个二进制文件 / 5.18 GB 已入库，`.git` 达 4.7 GB
  （2GB 刷机镜像、660MB sparse、147MB 内核模块树、40MB busybox、2.2GB QEMU 测试盘、
  evidence 下解出来的整个 initramfs 树）
- 隐私扫描：无私钥/无 `/Users/xxx` 路径；有设备侧 MAC（由 eMMC 序列号派生）与
  PC 主机名（DHCP 日志里的 `<pc-hostname>`）
- `.gitignore` 已加上 `*.img/*.dtb/*.ko/*.mbn/*.tar*/*.cpio.gz/*.bin/*.elf` 等规则
- 计划：在 `/tmp` 的克隆副本上跑 filter-repo 清历史（**不动源仓库**），
  验证干净后再推 `git@github.com:idealisan/samrtisan-odin-debian.git`

---

## 拾玖 [2026-08-29 23:24] 公开仓库已推送

地址：https://github.com/idealisan/samrtisan-odin-debian （PUBLIC，仓库名沿用用户给的拼写）

### 结果
| 项 | 前 | 后 |
|---|---|---|
| `.git` | 4.7 GB | 772 KB |
| 跟踪文件 | 908（含 728 个二进制 / 5.18 GB） | 181（纯文本） |
| 提交 | 31 | 31（全部保留） |
| 最大文件 | 2 GB 刷机镜像 | 199 KB 内核 config |

### 清理手段（已固化为 `tools/prepare-public-repo.sh`）
```sh
tools/prepare-public-repo.sh /tmp/odin-clean ~/.config/odin-port/replacements.txt
```
1. 剔除全部二进制（file(1) 判定非 text 的）+ 剔除 >250KB 的 blob（清掉历史里误入库的 2GB 镜像）
2. 脱敏：`--replace-text`（文件内容）+ `--replace-message`（**提交信息**）
   —— 只做前者会漏：最初扫历史仍命中 3 处，全在 commit message 里
3. **源仓库完全不动**，输出是一个独立的、历史已重写的克隆

脱敏规则文件放在仓库**外面**（`~/.config/odin-port/replacements.txt`）：
规则里必然写着要替换的原串，一旦入库等于把想藏的东西又写回公开仓库。

### 脱敏掉的
- eMMC 序列号 `<emmc-serial>` → `<emmc-serial>`
- 由序列号派生的 gadget MAC `02:00:0d:1d:00:02/:b9` → `02:00:0d:1d:00:01/02`
  （`odin-usb-role.sh` 里原本写死的是本机派生值，已改为通用占位，可用环境变量覆盖）
- PC 主机名 → `<pc-hostname>`（DHCP 日志片段）

### 脚本本身踩的三个坑（macOS 自带 bash 3.2）
1. **bash 3.2 解析不了 `$( )` 里带 `;;` 的 case** —— macOS 默认 shell 就是 3.2，
   最小复现都报 `syntax error near unexpected token ';;'`。把判定抽成 `is_binary()` 函数解决。
2. `set -e` 下 `is_binary "$f" && printf ...` 遇到文本文件返回 1，作为 while 最后一条
   命令会把整个子 shell 带崩（脚本静默退出）。改用 if/then/fi。
3. 私钥自检命中了脚本自己那行 grep 模式 → 加 `grep -v` 过滤自引用。

### 待办
- **Release 资产尚未发布**：`dist/` 里的 Debian 镜像还是 8/29 12:46 批次，缺 0008/背光/GPU/
  DHCP 四项修复。等 `tools/build-all.sh` 重建出与真机等价的新镜像后，再一次性发布 v0.1，
  含 lk2nd 两个版本 + 4 个 DTB + 新镜像 + MANIFEST。现在发只会发布一个必然黑屏的镜像。

---

## 贰拾 [2026-08-30 00:06] GitHub Actions 构建流水线

### 触发条件（按用户要求）
只挂 `release: [prereleased, released]`。
**不要用 `published`** —— GitHub 发布 prerelease 时同时发 `published` 与 `prereleased`，
实测一次发布触发了两个 run（33261492532 / 33261492105）。prereleased 覆盖预发布、
released 覆盖正式版，两者不重叠。

### 五个 job
`dtb` / `lk2nd` / `kernel` / `rootfs(needs kernel+dtb)` / `publish(全部产物挂 Release)`

### ★ 关键更正：lk2nd 的上游不是 msm8953-mainline
我们的补丁路径是 `lk2nd/device/dts/msm8953/...`，而 msm8953-mainline/lk2nd 的设备树在
`dts/`、设备表在 `dts/rules.mk` —— 完全对不上。
真实上游是 **msm8916-mainline/lk2nd tag 19.0**（postmarketOS 用的就是这个版本，
设备上 `lk2nd:version : 21.0-r0-postmarketos` 即由此打包）。
- 构建目标：`make TOOLCHAIN_PREFIX=arm-none-eabi- PROJECT=lk2nd-msm8953`
- 产物：`build-lk2nd-msm8953/lk2nd.img`
- 本地源码在 `/Volumes/caseSensitiveBar/refs/lk2nd`（非 git 仓库，是从 pmaports 解出来的）

新增 `lk2nd/0004`：从 QCDT 设备表去掉 `msm8953-xiaomi-markw` 与 `sdm450-xiaomi-rosy`，
强制 lk2nd 命中 odin。这一步原先是手改 rules.mk 做的，CI 里无法复现，固化为补丁。

### 首轮 CI 三个 job 全败（rc1），根因
1. **dtb/kernel：`upload-pack: not our ref af739964a952`**
   钉的 SHA 是本地 `odin-wip` 的 HEAD —— 它已经含我们的 0007 补丁，不是上游提交。
   应钉上游基线 `05f7e89ab9731565d8a62e3b5d1ec206485eeb0b`（Linux 6.19，master）。
2. **lk2nd：`LK2ND_VER: 19.0` 在 YAML 里是浮点数**，GitHub 传进来成了 `19`，
   下载 URL 404 → `gzip: stdin: not in gzip format`。已加引号。
3. **`git fetch --depth 1 origin <sha>` 只对 ref tip 有效**：基线一旦被 master 甩开就被拒。
   新增 `tools/ci/fetch-kernel.sh` 三级回退（按 SHA 直取 → `--shallow-since=<基线前一天>`
   → 整支 master），每级结束校验 HEAD == 目标 SHA。钉不住宁可失败，
   也不悄悄编一个"上游最新版"——那样就失去可复现的意义了。

### 待跟进
- rc2（run 33262051573）是修完后的第一轮，结果待看
- `kernel` 与 `rootfs` 两个 job 从未跑通过，属首次验证

---

## 贰拾壹 [2026-08-30 00:52] ★ WiFi 打通（WCNSS / wcn36xx）

### 根因
实机上根本没有 wlan0：`msm8953.dtsi` 里 `wcnss: remoteproc@a204000` 默认
`status = "disabled"`，我们的设备树此前也没启用它。模块（`wcn36xx.ko`、
`qcom_wcnss_pil.ko`）和 WCNSS 固件（`wcnss.mdt` + .b00/.b01/.b02/.b04/.b06/.b09
~.b12）其实都在，只是设备树没开门。

### 配置来源（照抄能正常用 WiFi 的 markw）
反编译 `evidence/live-device-backup/pmos-diag/boot/msm8953-xiaomi-markw.dtb`
拿到它的实际配置，再用脚本把 phandle 解成节点名：
```
&wcnss      status=okay  vddpx  -> l5 (1.8V)
&wcnss_iris compatible="qcom,wcn3660b"
            vddxo -> l7   (1.8V)
            vddrfa-> l19  (1.3V)
            vddpa -> l9   (3.3V)
            vdddig-> l5   (1.8V)
```
交叉验证：原厂 DTB（evidence/stock.dts）声明的 iris 四路电压正是
1.8V / 1.3V / 3.3V / 1.8V，与本文件各 LDO 的量程区间吻合。

### 还差一块：板级校准数据
`WCNSS_qcom_wlan_nv.bin`（wcn36xx 的 WLAN_NV_FILE =
`wlan/prima/WCNSS_qcom_wlan_nv.bin`）**原先没有**。它是每台机器不同的射频
校准数据，任何 Debian 包都不提供，也不该进版本库。
在 **persist 分区（mmcblk0p24，我们唯一没动过的原厂分区）** 里找到了：
- WCNSS_qcom_wlan_nv.bin (31723 B)
- WCNSS_wlan_dictionary.dat
- wlan_mac.bin / wlan_random_mac.bin

⇒ 新增 `odin-wlan-nv.service` + `odin-wlan-nv.sh`：开机从 persist 现取到
`/lib/firmware/wlan/prima/`；若驱动已先加载，重新 modprobe 让它读到。
取不到最坏只是没 WiFi，不会拖挂启动。

### 实机验证
```
wcn36xx: firmware WLAN version 'WCN v2.0 RadioPhy vIris_TSMC_4.0 with 48MHz XO'
wlan0 出现、rfkill 未阻塞、扫描到 31 个网络
连上 AP 拿到 192.168.3.165；ping deb.debian.org 3 发 3 收，0% 丢包
路由：默认走 wlan0(metric 600)，172.16.42.0/24 仍走 usb0 ⇒ USB SSH 不受影响
```

### 顺带踩的两个坑
1. **DNS**：该路由器广播 DNS 192.168.3.1，但它根本不应答 UDP 53 ⇒
   能 ping 通 IP 却解析不了域名。装 `systemd-resolved` 才有按序尝试后续
   服务器的能力；连接级可用
   `nmcli con modify <名> ipv4.ignore-auto-dns yes ipv4.dns "1.1.1.1,8.8.8.8"` 覆盖。
2. **时钟**：设备无 RTC，时钟差几个月 ⇒ apt 拒绝 Release 文件
   （`Release file ... is not valid yet`）。装 `systemd-timesyncd` 联网自动校时。

### 交互式管理（用户要求"命令行就能扫描连接，不要改配置文件"）
`nmcli` 本身就是交互式 CLI：
```
nmcli dev wifi list                       # 扫描
nmcli dev wifi connect <SSID> password <密码>   # 连接（自动建持久连接）
nmcli dev status / nmcli con show         # 查看
nmcli con up|down|delete <名>             # 管理
nmtui                                     # 文本界面
```
网络调试工具已按"正常 Debian 服务器"标准装齐：iputils-ping / curl / wget /
bind9-dnsutils / net-tools / traceroute / tcpdump / iperf3 / ethtool / mtr-tiny。

### CI 进展（ci-fixer 主导）
- **lk2nd ✅ / dtb ✅ 已变绿**，kernel 仍在编（约 22 分钟），rootfs 未开始
- ci-fixer 找出两个我漏掉的根因：
  1. `patches/0007` 是坏补丁：hunk 头声明 383 行、正文却有 385 行（手工改过
     compatible 却没同步行数），GNU patch 按 383 行截断 ⇒ dts 少两行没闭合
  2. lk2nd 该钉 **tag 23.1** 而不是 19.0（0002 的 rules.mk 上下文是 23.x 的设备表）
- 我修的：kernel job 其实是**编译成功**后死在 `cp out/kernel/vmlinuz` ——
  脚本 `cd` 进内核树后 $OUT 相对路径失效；四个脚本的 $OUT 统一转绝对路径
- 构建日志已全部改成 `tee` 双写，CI 页面能实时看到编译过程

---

## 贰拾贰、v0.9.1 发布与真机基准验证（2026-08-30）

### 背景与目的
此前真机跑的系统是 8/30 12:01–12:04 手工摆上去的（`/boot/vmlinuz` 时间戳 12:01、
`/boot/dtbs/qcom/*.dtb` 12:04，`uname` 显示 `6.19.0-postmarketos-qcom-msm8953+`），
**不是 CI 制品**，按 AGENTS.md §1.4 只能算开发尝试，不能作为基准。
本轮目的：用 CI 构建的 v0.9.1 完整刷一遍，把验证结果定为后续开发的基准线。

### 13:12 发布 v0.9.1（Pre-Release）
- 基准提交 `4706103`；相对 v0.9.0 只有 3 笔提交（f6feac1 / ea7275f / 4706103）
- CI `release-build` run `33294177252` 五个 job 全绿：
  dtb 34s、lk2nd 50s、kernel 1m42s、rootfs、publish → **completed / success**
- 8 个资产：lk2nd.img / lk2nd-nomarkw.img / 4× dtb / odin-debian.img /
  odin-debian-sparse.img / SHA256SUMS

### 13:36 制品下载与校验（落在 tmp/release-v0.9.1/）
- `shasum -a 256 -c SHA256SUMS` 已下载 7 个全部 **OK**（raw 版 odin-debian.img 未下，仅作回退）
- 本机 md5 存档：
  ```
  1e482a89404cb722c22293150d1323f1  lk2nd-nomarkw.img
  cca537d6140531ffc4ec6a69a858545c  lk2nd.img
  47d2e0017e5882633eef8d23e535f454  odin-debian-sparse.img
  92dbbb8c83b2d6e6235399974120a02f  msm8953-smartisan-odin-ft8716-norolesw.dtb
  9a32ce00d5f7d2c8db521281e8bb9637  msm8953-smartisan-odin-ft8716.dtb
  b67413fc2651536d27dadaec3ac604a8  msm8953-smartisan-odin-norolesw.dtb
  ca210736fe68e615bb091035c2494bd3  msm8953-smartisan-odin.dtb
  ```

### 踩坑：GitHub 下载必须显式去掉代理
本机默认带 `http_proxy`/`https_proxy=http://127.0.0.1:3030`（给别的功能用的），
走它下载 GitHub Release 资产只有 **0.81 MB/s**；直连是 **3.8 MB/s（4.7 倍）**。
实测手法（同一 URL 取前 20 MB 对比）：
```sh
curl -sL -o /dev/null -w '%{speed_download}\n' -r 0-20971519 "$U"      # 走代理
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY curl ...  # 直连
```
**注意**：不加 `-L` 时测出来是 0 B/s（GitHub 会 302 到 objects.githubusercontent.com，
那 4.2s vs 1.2s 的差只是重定向响应耗时，不是带宽）。以后凡是从 GitHub 下大文件，
一律 `env -u http_proxy -u https_proxy ... curl -L`。

### 设备现状记录（刷之前的取证）
- 状态 C：Debian 12 运行中，SSH `user@172.16.42.1` 可达
- `/dev/mmcblk0p57`（PARTLABEL=`userdata`，LABEL=`pmOS_root`）挂载为 `/`
- `/extlinux/extlinux.conf` 在**根下**（不是 `/boot/extlinux/`），`default l0-safe`，两个 label l0 / l0-safe
- **GPT 里没有 `lk2nd` 分区标签**，`/dev/disk/by-partlabel/` 只有 aboot/boot/recovery/
  persist/system/userdata 等原厂名字；但 fastboot 层会导出 `lk2nd`
  （`fastboot getvar all` 报 `partition-size:lk2nd: 0x80000` = 512 KB）
  ⇒ 设备侧看不到、fastboot 侧能刷，这两件事并不矛盾
  ⇒ 设备侧看不到、fastboot 侧能刷，这两件事并不矛盾

### 13:37–13:40 真机刷入 v0.9.1（`flash/flash-all.sh --from 20`）
用户拍板：**完整刷（含 lk2nd）**，**跳过备份**（此前已备份多次，且当前系统
只是开发中的测试系统、无有价值数据；它疑似是 0.9.0 的 CI 版，但不确定，
本轮正是为了确认）。

| 阶段 | 结果 |
|---|---|
| 20 fastboot | ok（40s，改名 extlinux.conf 后重启落进 fastboot） |
| 30 boot | ok `Sending 'lk2nd' (356 KB) OKAY` → `Writing 'lk2nd' OKAY` |
| 40 data | ok（sparse 40s，未用 raw 回退） |
| 50 reboot | USB 网卡 10s 出现 |
| 60 usbnet | PC 拿到 172.16.42.2 |
| 70 ssh | SSH 可达（30s） |
| **80 verify** | **15 项通过 / 1 项失败** |

通过项：hostname、内核版本、面板驱动 ft8716、DSI connected、DSI enabled、
DRM 节点、面板初始化失败数 0、背光 2048、usb0 地址、wcn36xx 已加载、
sshd active、resize2fs 成功、扩容标记、根分区 112G、modprobe 可用。
失败项：**wlan0 不存在**（实际只有 lo / usb0）。

### 13:44–13:51 查 wlan0：真因是时序，且旧补救动作重载错了对象
- `/lib/firmware/` 下 10 个 `wcnss.*` **其实是齐的**（开机 03:49:16 已全部取到），
  我第一次 `ls /lib/firmware/ | head` 只看到前 10 行（ar3k/ath* 开头），
  `wcnss.*` 排在后面被截断，一度误判成"固件没取到"——**记这个坑：别用 head 看目录**
- 真正在的是：
  ```
  [   10.230706] remoteproc remoteproc0: Direct firmware load for wcnss.mdt failed with error -2
  [   25.899417] EXT4-fs (mmcblk0p24): mounted filesystem ...   ← late service 这时才去取
  ```
  内核 **10.230s** 就索要固件，late service **25.9s** 才动手，晚了 15 秒；
  `request_firmware` 失败后 remoteproc 停在 `offline`，补文件也不会重试
- 旧脚本的补救是 `modprobe -r wcn36xx; modprobe wcn36xx`，**但 wcnss.mdt 是
  remoteproc 读的、不是 wcn36xx 读的**，所以那个补救从来没生效过
- 手工验证（确认判断，不作为修法）：
  `echo start > /sys/class/remoteproc/remoteproc0/state` → `Booting fw image wcnss.mdt`
  → `remote processor is now up`（WCNSS Version 1.5 1.2）；
  再 `modprobe -r wcn36xx; modprobe wcn36xx` → **wlan0 出现**，
  nmcli 显示 `wlan0:wifi:disconnected`，固件 `WCN v2.0 RadioPhy vIris_TSMC_4.0`

### 13:58–14:06 修法：把供给动作放进 initramfs（不做事后补救）
用户要求"最合理正确的修复，像一个正常的 Linux 系统，而不是 Workaround"。
按启动时序，正确落点是 **`switch_root` 之前**：那时真正的根已挂载、
systemd 尚未起来、驱动（约 10s 才索取固件）也还没动作。

- 新增 `dist/build/initramfs/sbin/odin-wlan-fw.sh`（POSIX sh；initramfs 是
  busybox ash，**没有 bash**）
  - 目标根以参数接收，另支持 `--check`
  - 用 `/sys/class/block/*/uevent` 里的 **`PARTNAME`** 定位分区 —— initramfs 里
    没有 udev，`/dev/disk/by-partlabel/` 那套符号链接不存在
  - `cmp -s` 幂等（wcnss.b06 有 3.2MB，不必每次开机重写闪存）
- `dist/build/initramfs/init` 在 `switch_root` 前调用；`--check` 判定缺文件时
  才 `remount,rw`，取完 `sync` 立刻 `remount,ro` ⇒ 绝大多数开机根全程只读
- `initramfs-applets.txt` 补 **`cp` 与 `cmp`** —— 原名单里竟然没有 `cp`
- 不再安装 / enable `odin-wlan-fw.service`；`dist/build/rootfs/` 下那两个文件
  留到统一清理轮次再删（apply-staging-fixes.sh 只拷贝、不 enable，留着无副作用）

**真机实测（假根，不动真 `/lib/firmware`）**：12 个文件全部取出，
与旧服务产出的文件 **md5 全部一致** ✅

### 新增 reports/021 —— 固件与驱动的供给策略
把这个坑固化成规范：固件必须在驱动第一次索取之前就位 ⇒ 落点是 initramfs
而非 late service；附"补一个新外设的实施清单"（查谁在要/何时要 → 确认来源分区
→ 判时序 → 写脚本 → 补 applet → **真机假根验证后再发版** → 确认模块加载时机），
以及"禁止的做法"表（late service / modprobe -r 补救 / 硬编码 mmcblk0pNN 等）。

### 顺带记下的事实
- modem 分区（mmcblk0p52）是 **vfat**、persist（mmcblk0p24）是 **ext4**，
  两者都是内核内置（`/lib/modules/*/kernel/fs/` 里找不到它们）⇒ initramfs 可直接挂
- `wcn36xx` / `qcom_wcnss_pil` 在 `/etc/modules-load.d/odin-wlan.conf`，
  由 `systemd-modules-load` 在 `basic.target` 之前加载 ⇒ 固件已在位，首次加载即成功

---

## 贰拾叁、v0.9.3 真机验收 16/16 全通过（2026-08-30）

### v0.9.2 作废、改用 v0.9.3 的经过
v0.9.2 发布后立刻自查发现：`a1fe79f` 声称"initramfs-applets.txt 补 cp 与 cmp"，
**但那个文件根本没进提交** —— `git add -A dist/build/initramfs ...` 只匹配到
**目录** `dist/build/initramfs/`，而 `dist/build/initramfs-applets.txt` 是它的
**同级文件**（名字以 initramfs- 开头），不在那个目录下。既没 add、也没报错，
提交照样成功。没有 cp ⇒ initramfs 里的固件供给会**静默失败**（脚本失败不致命）。

处置（按 §3.4 新写入的版本号准则，未删旧版本）：
1. `gh run cancel` 掐掉 v0.9.2 正在跑的构建
2. 补提交 `ae85275`
3. **开新号 v0.9.3** 重新发布
4. 在 v0.9.3 说明里写明 v0.9.2 为何作废

v0.9.2 的 Release 先留着，删除放统一清理轮次。

### v0.9.3 CI 与刷入
- CI run `33296547668`，**7m19s completed/success**，8 个资产
- 7 个已下载文件 `shasum -a 256 -c SHA256SUMS` 全部 OK
  （odin-debian-sparse.img md5 `4aa736d5567379938624924779d79c22`）
- **下载踩坑**：直连在中途 `connection reset`（只下了 62MB/855MB）。
  `gh release download` 不支持续传，改用
  `curl -L -C - --retry 8 --retry-all-errors --speed-time 30 --speed-limit 1024`
  断点续传救回。**以后下大文件一律带 `-C -` 与重试**。
- 刷入（含 lk2nd，用户已确认）：20 fastboot 30s → 30 lk2nd ok → 40 userdata 40s
  → 50 reboot（USB 网卡 10s）→ 60 usbnet ok → 70 ssh 40s → **80 verify 16/16，失败 0**

### WiFi 修复的决定性证据（这次是真的修好了）
```
[   11.673944] remoteproc remoteproc0: Booting fw image wcnss.mdt, size 7324
[   13.847119] remoteproc remoteproc0: remote processor a204000.remoteproc is now up
[   34.823256] wcn36xx: firmware WLAN version 'WCN v2.0 RadioPhy vIris_TSMC_4.0 with 48MHz XO'
```
- **那句 `failed with error -2` 彻底消失** —— 驱动第一次索取就拿到了
- 时序对比：
  | | 供给时刻 | 索取时刻 | 结果 |
  |---|---|---|---|
  | 修前（v0.9.1） | 25.9s | 10.230s | 失败，且永不重试 |
  | 修后（v0.9.3） | **~4s**（initramfs） | 11.673s | **首次即成功** |
- `/var/log/odin-wlan-fw.log` 时间戳是 `1970-01-01 00:00:04` —— 开机第 4 秒，
  那时还没有 systemd、时钟也没同步，正是 initramfs 阶段，与预期完全吻合
- `remoteproc0/state = running`，`wlan0` 在 `ip link` 与 `nmcli` 里都在

### 一个每次重刷都会撞到的小坑
刷完后 SSH 报 `REMOTE HOST IDENTIFICATION HAS CHANGED` —— 新 rootfs 会重新生成
sshd 主机密钥，PC 上 known_hosts 里的旧记录失效。
处置：`ssh-keygen -R 172.16.42.1`（旧记录自动留档为 `known_hosts.old`），重连即可。

### v0.9.3 已转正式 Release
`gh release edit v0.9.3 --prerelease=false` → 作为阶段性标志与后续开发基准。

### 下一版目标（用户指定）：lk2nd 反复重启
**现象**：刷入 Linux 系统镜像之前，lk2nd 会反复重启，必须人工按住电源键才能停下，
否则一直重启 ⇒ 无法自动接着刷入系统镜像 ⇒ 开发/调试循环不能完全自动走完。
定位方向（尚未验证，仅为待查）：lk2nd 找不到可启动配置后的 reboot 策略 /
看门狗 / `boot_into_fastboot` 未置位。见 reports/018 §零 的状态机 B 态。

---

## 贰拾肆、v0.9.4 目标（2026-08-30，用户指定）

两个目标：**① lk2nd 反复重启需人工按电源键**、**② 构建改用 Makefile**。
历史 Release 与旧文件按用户指示**一律不清理**，留着即可。

版本号规则也按用户要求改了：目标版本成功前用 `v0.9.4-<简述>` 的 Pre-release
（如 `-lk2nd-reboot`、`-makefile`），只有最终验证通过才用干净的 `v0.9.4`。
（用户最初提时间戳，随后改成简述后缀 —— 理由是时间戳记不住"这版在试什么"。）

### ① 现象与链路
刷入 Linux 系统镜像之前（即改名 extlinux.conf 让 lk2nd 落 fastboot 那一步），
设备**反复重启**，必须人工按住电源键才能停 ⇒ 无法自动接着刷 ⇒ 开发循环断在这里。

### 已查到的事实（lk2nd 23.1 源码 + 真机核对）
1. **`lk2nd_scan_devices()` 找到不启动项时只是打一行日志就返回**
   （`lk2nd/boot/boot.c:63`："Bootable file system not found. Reverting to android boot."）
   —— 它**不会**置 `boot_into_fastboot`。
2. 随后 aboot 走 `retry_boot:` → `boot_linux_from_mmc()`
   （`app/aboot/aboot.c:5687`），失败才落到 `fastboot:` 标签（`aboot.c:5723`）。
3. **boot 分区偏移 512KB 处还留着一个原厂 Android 引导镜像** —— 真机实测：
   ```
   offset 0      : A N D R O I D !     ← lk2nd 本体（lk2nd 也是个 Android boot image）
   offset 524288 : A N D R O I D !     ← 残留的原厂 Android 引导镜像
   ```
   分区布局：`lk2nd` = 0…512KB（`getvar` 报 0x80000），`boot` = 512KB…64MB（0x3f80000），
   两者合起来正好是 mmcblk0p21 的 64MB。

⇒ **真因（待最后确认）**：lk2nd 找不到可启动 fs → 回退引导那个残留的 Android 镜像
→ Android 起不来 → 重启 → 回到 lk2nd → **循环**。
这解释了两件事：为什么会重启（不是停在 fastboot）、以及为什么按住电源键能停
（`is_user_force_reset()` 分支，`aboot.c:5580` 会 `goto normal_boot`）。

### 备选修法（尚未定，也未实机验证）
- **A. `fastboot erase boot`** 清掉残留 Android 镜像 ⇒ `boot_linux_from_mmc()` 失败
  ⇒ 干净落到 `fastboot:`。一次性改动，且 `lk2nd` 分区（0…512KB）不受影响；
  evidence/live-device-backup/boot-partition.img 有全量备份可回退。
  属设备侧改动，按 §7 需用户单独确认。
- **B. 改 lk2nd** 让它在找不到可启动 fs 时直接进 fastboot，而不是回退 Android。
  影响面大（改上游行为），但可随 CI 产物交付。
- **C. 让 Linux 侧能 `reboot bootloader`** —— 真机有 `pon@800`，
  `reboot_mode` + `qcom_pon` 驱动已加载，`/sys/kernel/reboot/mode` 存在但只有
  cold/warm/hard；DT 里**没有** reboot-mode 子节点，需要补节点与魔数。
  这条路最"正常 Linux"，但要先把 lk2nd 期望的魔数核对清楚。

### ② Makefile（下一步做）
当前构建入口全是 `bash tools/ci/*.sh`，无 Makefile。

### lk2nd 循环重启：第一轮排查结论（详见 reports/022）

**推翻了两条假设，都没成立：**

1. **"回退引导残留 Android 镜像"** —— 据此写了 `lk2nd/0005`。
   `strings` 对比证实补丁**确实进了镜像**：
   v0.9.3 是 `Reverting to android boot.`，新版是 `Reverting to fastboot.`
   **但真机行为毫无变化，仍然循环。**
   教训：补丁"进没进镜像"（strings 能验）和"有没有用"（行为变没变）是两回事，
   只验前者会得出虚假的安全感。
   另注：0005 写在 `#if WITH_LK2ND_BOOT` 块里，而该宏全树只在 aboot.c 出现 4 次、
   没有任何 .mk 定义它 —— 若为假则补丁是死代码，这是下一步优先要确认的点。

2. **"panic 重启 + 原因读不回来"** —— 查证后发现**读回路径是完整的**：
   `msm_shared/reboot.c:84` 有 `check_hard_reboot_mode()` 的真实实现
   （读 `PON_SOFT_RB_SPARE`，`(v & 0xFC) >> 2`，读后擦除），且 reboot.o 确实编译
   （`ENABLE_REBOOT_MODULE := 1` 在 msm8953.mk:127/144）。

**过程中的两个自我纠偏：**
- 早期日志里"设备进入 fastboot (30s)"那几次，其实是**用户按了电源键**的结果，
  我之前当成自动流程跑通了 —— 这是后面一连串误判的源头。
- 查 `check_hard_reboot_mode` 时加了 `grep -i 8953` 过滤，把真正实现所在的
  `platform/msm_shared/reboot.c` 滤掉了，一度误判"只有弱实现"。
  **查东西别用想当然的过滤条件先剪枝。**

**下一步：诊断构建。** 把 `lk2nd/project/lk2nd.mk:20` 的
`PANIC_REBOOT_MODE ?= FASTBOOT_MODE` 改成 `NO_REBOOT`，
`platform_halt()` 就会打印后停住不重启，panic 原因能留在屏幕上让用户读到。
代价是这版会卡死、只能纯诊断用。

**为什么迭代慢**：每验证一次 lk2nd 都要先进 fastboot，而进 fastboot 正是坏的
⇒ 每次都要用户按电源键。修它和用它互相卡住。

---

## 贰拾伍、容器化构建环境 + gui 变体（2026-08-30，用户指定）

用户给的三件事：① Dockerfile 定义编译专用镜像并用它起容器（旧 `odin-build`
容器整只放弃，不看、不抄）；② Makefile 增加 gui 变体、保留 core；
③ CI 两个变体都编，本地只编 gui（core 是 gui 的子集）。

- **18:59 未提交的那份 gui 草稿丢弃** —— 用户确认不要。按 §1.3 只增不删的原则，
  先 `git diff` 留档到 `tmp/gui-wip/setup-rootfs-gui-uncommitted.patch`，再
  `git checkout` 回去。GUI 内容按用户"真机上手工验证过的那套"重写，不沿用草稿代码。
  - **草稿有三个致命问题**（这也是判断"它没被执行过"的依据）：
    1. 调用了未定义的 `say()` —— `setup-rootfs.sh` 顶部没这个函数，脚本是
       `set -e` ⇒ `ODIN_VARIANT=gui` 时第一条 `say` 就 command not found，
       exit 127，apt 一行都还没跑。
    2. `ODIN_VARIANT` 根本没接线：`build-rootfs.sh` 只传 `ODIN_ROOTFS`。
    3. `apt-get ... 2>&1 | tail -5 || echo WARN` 会吞掉失败（管道退出码取
       `tail` 的，且没开 pipefail）。

- **19:03 CI 缓存"恢复成功但完全用不上"—— 真因找到了**
  - 现象：kernel job 从不到 10 分钟退化到 29 分钟；日志里
    "Cache hit for: kernel-ccache-<sha>-<patchhash>"、恢复 235 MB 看着一切正常，
    但 `ccache -s` 是 **Hits: 89 / 4399 (2.02%)**。
  - **别把"缓存恢复成功"当成"缓存生效"** —— 那只说明文件下载下来了。要看得看
    `Hits` 行。这是这次最大的教训。
  - 真因是两条 ccache 默认值叠加：
    1. `compiler_check` 默认 `mtime` ⇒ 编译器二进制的 mtime 计入哈希。
       CI 每个 job 都全新 `apt-get install` 交叉编译器 ⇒ mtime 每次都变
       ⇒ 全量未命中。**主因。**
    2. `hash_dir` 默认 `true` ⇒ 带 `-g` 时把 CWD 计入哈希。本内核
       `CONFIG_DEBUG_INFO=y`，而 `KDIR` 从旧脚本的 `/tmp/linux-msm8953`
       迁到 Makefile 的仓库内 `tmp/` ⇒ 历史缓存整体作废。
  - **验证方式：不靠推理，做了个 10 秒的小实验**（debian:bookworm-slim 容器，
    ccache 4.7.5，`gcc -g` 编同一个文件）：
    | 场景 | 默认配置 | content + hash_dir=false |
    |---|---|---|
    | 同目录重编 | 100% | 100% |
    | 换目录（CWD 变） | **0%** | 100% |
    | touch 编译器（模拟重装） | **0%** | 100% |
  - 修法：`ccache --set-config compiler_check=content` +
    `hash_dir=false`，max_size 2G→5G。CI 与容器镜像都改。
  - **已知的一次性代价**：改配置会让既有缓存条目全部失效（哈希规则变了），
    下一次构建仍是全量，再往后才稳定命中。已触发一次 CI 建新缓存。

- **19:09 Dockerfile 与容器就位**
  - 依赖清单逐条来自 CI 四个 job 的 apt 行，不是现编的；基础镜像钉 digest
    （`debian:bookworm@sha256:813017…`）不钉 tag，本地已有该层 ⇒ 实测
    `docker build` **没有走网络**（这是用户明确要求，免得网络故障添乱）。
  - 构建 92 秒。容器 `odin-dev` 已起：`--privileged` + 三个挂载
    （仓库 → /work/odin-work、`odin-ccache` 卷 → `/var/cache/odin-ccache`、
    `odin-kernelsrc` 卷 → /work/src）。
  - **内核源码树挂容器自己的卷而不是仓库的 bind mount**：几万个小文件的编译
    走 macOS bind mount 会慢一个量级。ccache 同理挂卷，重建容器不丢缓存。
  - 冒烟验证过：工具链 19 个命令全部就位，ccache 两条配置生效，
    `make print-config` 在容器内正常。

- **19:16 Makefile 变体落地** —— `ODIN_VARIANT ?= gui`，模式规则
  `$(STAMPS)/rootfs-%`（`%` = core/gui）用 `$*` 传变体名，两个变体不抄两遍 recipe。
  - 变体相关路径一律递归展开（`=` 不是 `:=`）：`ODIN_VARIANT` 在 recipe 运行时
    才确定，`:=` 会把解析期默认值钉死 ⇒ 两个变体串台。
  - 戳文件、输出目录、`debootstrap` 的 staging 根目录**都按变体分开**。
    staging 共用会表现为"编了 gui，出来的却是 core"（第二个变体直接复用
    第一个已摆好的根，因为 build-rootfs.sh 是按 `[ ! -d "$ROOT/etc" ]` 判断的）。
  - 镜像名：core 沿用 `odin-debian.img`（flash-all.sh 与文档都按这个名字取默认
    路径，改名没收益），gui 用 `odin-debian-gui.img`。

- **踩坑**：`make -n` 里想用 `$(subst $(space),$(comma),$(VARIANTS))` 拼提示文字，
  但 `space`/`comma` 这两个变量在本 Makefile 里并不存在 —— 直接写死 "core 或 gui"
  了事，别为一行提示文字造变量。

- **19:23 待办 / 下一步**
  - 本次触发的 CI（run 33308322764）跑的是旧 job 定义（单 rootfs），
    只用来验证 ccache 修复；**下一次** CI 才会带上 core/gui 两条 matrix job。
  - gui 变体的包清单从未在 CI 上跑过（只在真机手工装过），第一次 CI 大概率会
    在 `apt-get install plasma-mobile` 处暴露问题。
  - 本地完整构建还没跑过（内核 20+ 分钟），等 CI 结果确认缓存生效后再跑。
  - **本地跑 `make dtb` 与 `make kernel` 必须用两棵不同的内核树**
    （`KDIR=/work/src/linux-dtb` 与 `/work/src/linux-kernel`）：dtb 只打 0007、
    kernel 打 0001-0008，共用一棵树时 kernel 会撞上"0007 已应用"，
    `patch --forward` 跳过并返回 1 ⇒ `set -e` 下直接失败。CI 上是两个 runner
    各自 fetch，永远遇不到。

---

## 贰拾陆、GUI 变体实刷真机 + 缓存/RTC/触摸 三条线（2026-08-30 晚）

上文（贰拾伍）搭好容器化环境与变体之后，本地 GUI 全流程跑通并**实刷真机**，
验收 16/16 全过，Plasma Mobile 起来（屏上有鼠标光标）。随后围绕三个问题推进。

### 1. CI 缓存：连修三处，但**仍未证明有效**（用户 22:00 叫停，先放一放）

| 轮次 | kernel 耗时 | 命中率 | 说明 |
|---|---|---|---|
| 第 1 轮 | 31.5 分钟 | 0.75% | 改了 ccache 规则，旧缓存整体作废，冷编 |
| 第 2 轮 | ~30 分钟 | 0.75% | 恢复的还是那份 235 MB，**纹丝不动** |
| 第 3 轮 | 31m53s | — | v2 新 key，冷编并**存下**缓存 |
| 第 4 轮 | 31m25s | — | 与第 3 轮**并行**跑了，拿不到第 3 轮的缓存 |
| 第 5 轮 | （取消） | — | RTC 配置改动后触发，仍恢复旧缓存 |

三处修复：
1. `compiler_check=content` + `hash_dir=false`（贰拾伍已做）。
2. **缓存键补编译器身份**（版本 + 二进制 md5）—— 关键教训：actions/cache
   **精确命中时跳过上传**，于是 key 不变 ⇒ 缓存永远冻结在第一份快照上。
3. **缓存键补内核配置哈希** —— 同一类问题：改 .config 会改 autoconf.h，
   但 key 不含配置 ⇒ 精确命中旧缓存（用不上）且不回传。

未验证的原因：这几轮要么彼此并行、要么夹着配置变更，始终没有出现
"上一轮存好缓存、下一轮独占跑"的干净对照。**下一轮单独触发即可判定。**

### 2. RTC：修完并已编译进内核（待真机复验）

真机时间错的完整链路：
- 内核 **HCTOSYS/SYSTOHC 两个选项 pmOS 默认关着**（正常 Debian 是开的）⇒
  开机不读 RTC（时钟从 1970 起步，被 systemd 顶到它内置的 epoch = 4 月）；
  NTP 校正后也不回写 RTC ⇒ 一重启就回到错误时间。
- 已开 `CONFIG_RTC_HCTOSYS/SYSTOHC=y`（rtc0 = rtc-pm8xxx），
  并确认 `rtc_hctosys_ret` 符号已在 vmlinux 中。
- 另补两处短板：timesyncd 加国内可达的 NTP 候选（原来一直 "Idle."）、
  装 util-linux-extra（原来连 hwclock 都没有）；时区改 Asia/Shanghai。

### 3. 触摸屏：卡在一个**反直觉的发现**上

- 证据链是完整的：原厂 ROM 的 boot.img 里解出 DTB，触摸在
  **i2c@78b7000（主线 &i2c_3）**，地址 0x38，reset gpio64 / irq gpio65；
  MoKee 的 ueventd.rc 也指向 78b7000，候选地址 0x20 / 0x38 / 0x4b。
- 但**只要启用 &i2c_3，真机就无限重启**（lk2nd 起不来 Linux ⇒ 反复重启）。
  不是触摸节点的问题：单独只开 i2c_3、不带任何设备节点，一样循环。
- DTB 本身是干净的：反编译后与基线的差异**只有一行** `status: disabled → okay`
  （44125 → 44121 字节，字符串表少 4 字节，属正常）。
- 怀疑方向：msm8953 上部分 BLSP QUP 受 TrustZone 保护，主线驱动去访问会触发
  复位 —— 仓库里 daisy/vince 的 DTS 就有"因为 BLSP 被 TZ 保护而改用 GPIO 模拟"的注释。
  **需要用 ramoops（/sys/fs/pstore）里的崩溃日志坐实**，尚未取到。

### 过程中的几个坑（值钱的部分）

- **内核树里的改动不持久**：在 `tmp/linux-dtb`、`tmp/linux-kernel` 里改完 DTS，
  过一会儿会被还原/被打补丁覆盖。补丁必须改 `patches/`，改完要
  `git apply --check` 并在干净树上验证产物。
- **重新生成的补丁不可信**：用 `git diff` 重新生成的 0007 会让 DTB 悄悄变样
  （比原版小 4 字节）。后来改成在**原始补丁文本**上精确插入 + 逐字节验证。
- **相对路径会写进 worktree**：编辑工具把相对路径解析到
  `.codebuddy/worktrees/bg-d58d0c38/`，与主仓库不是同一份文件，踩了两次。
  改文件一律用绝对路径。
- **续行里不能插 `#` 注释**：反斜杠续行会把各行拼成一行，`#` 之后全被吃掉
  （差点漏装 util-linux-extra 与 nftables）。
- **打补丁必须可重跑**：`patch --forward` 遇"已应用过"返回 1，set -e 直接中断
  ⇒ 改配置重编内核根本干不了。已抽成 `tools/ci/apply-patches.sh`，
  三种情形分别判定（含"新建文件被后续补丁改过"这种 0005/0008 的情形）。

### 附带

- 刷机前把当时可用的一套产物存档到 `tmp/release-gui-local-known-good/`
  （含 4.6G 镜像、DTB、lk2nd、校验和），已用于两次回滚。
- 仓库里出现过一份并非我创建的 `dts/msm8953-smartisan-odin-touch.dtsi`
  （含触摸节点，被两个变体 .dts include）。用户说没在并行改，按指示删除，
  内容留档在 `tmp/dts-test/touch.dtsi.存档`。

### 贰拾柒：RTC —— 按 pmOS 的完整流程梳理后改用 fake-hwclock

- **23:18 完成** — 时钟用户态一环改用 Debian 自带的 fake-hwclock（commit `21322f0`），
  报告见 `reports/023-RTC-postmarketOS的完整流程与本机改造.md`
- 要点
  - 干净克隆了三个 pmOS 仓库做对照（`tmp/pmos-refs/`）：pmaports、
    linux-postmarketos-qcom-msm8953、swclock-offset。
  - 关键证据：`device/community/soc-qcom-msm8953/APKBUILD` 里
    `depends="$pkgname-ucm swclock-offset"` —— 方案挂在 SoC 包上，
    markw 等全系 msm8953 机型都会装；全仓共 14 处依赖。
  - pmOS 的流程是四层：内核不读不写（HCTOSYS/SYSTOHC 都关）→ 设备树不加
    allow-set-time → 用户态 swclock-offset 关机存「系统时间 − RTC」的偏差、
    开机 RTC + 偏差还原 → 联网靠 NTP。
  - 本机实测与之吻合：不加 allow-set-time 写 RTC 是 -ENODEV；
    加了则 `hwclock --systohc` 把整机挂死（进程不可中断）。
  - 没照搬它的自制脚本，改用 Debian 的 fake-hwclock：存绝对时间，
    `/etc/fake-hwclock.data`，sysinit 早期 load、关机 save。
  - 补了 pmOS 参考实现缺的一块：fake-hwclock 的每小时存盘靠
    `/etc/cron.hourly/fake-hwclock`，要 cron 才跑，所以一并装 cron ——
    手机很少干净关机，只靠关机存盘一硬复位就全丢。
- **踩坑**：fake-hwclock 的数据文件是 **`/etc/fake-hwclock.data`**，
  不是 `/var/lib/…`（`/sbin/fake-hwclock` 第 14 行 `FILE=` 写死的默认值）。
  之前注释里写错了路径，已更正。
- **踩坑**：bookworm 的 util-linux-extra **没有** hwclock-save.service
  （只有 `/etc/init.d/hwclock.sh` 与 udev 的 hwclock-set，两者开头都是
  `[ -e /run/systemd/system ] && exit 0`）。之前那句 `systemctl mask`
  是照 pmOS 的思路想当然加的，撤掉。
- **踩坑**：本仓库有**另一个会话在并行改同一批文件**。我 23:14 改
  `setup-rootfs.sh` 时它 23:06 刚改过；并发写入把我写入的一行弄坏了
  （混进 `2m` 前缀），已修复。改文件前先看 mtime，改完立刻 commit + push。
- **踩坑**：OrbStack 的 Docker 守护进程会无响应（负载高时更明显），
  `docker` 命令全部挂住；`orbctl stop && orbctl start` 可恢复，
  但会杀掉容器里正在跑的构建。
- **踩坑**：写文件用相对路径会被解析到 `.codebuddy/worktrees/bg-d58d0c38/`
  而不是主仓库（WORKLOG 早先记过，又踩了一次）；报告最后是 `cp` 过去的。

---

## 2026-08-30 23:50 · RTC：照 postmarketOS 的完整流程改造（报告 023）

### 起因

真机时间一直是错的：显示 2026-04-27（systemd 的打包日期，无 RTC 时 systemd
兜底用的就是这个），联网校正后一重启又回去。用户要求：先用**干净克隆**的
postmarketOS 源码做对照分析，把它的完整流程搞清楚，再照着改我们这一套。

### 干净克隆的参考仓库（都在 tmp/pmos-refs/）

| 仓库 | 说明 |
|---|---|
| pmaports（161M，全量） | device-xiaomi-markw、soc-qcom-msm8953、官方内核配置 |
| swclock-offset（全量，24 个提交） | 官方"存文件"方案的实现，不在 pmaports 里，是独立仓库 |
| msm8953-mainline/linux（全量） | **pmOS 的 linux-postmarketos-qcom-msm8953 实际就是从这个仓库构建的**（APKBUILD 里 `url="https://github.com/msm8953-mainline/linux"`）。gitlab.com 上并没有这个仓库，一开始按 gitlab 地址克隆必然 401。 |

### pmOS 的完整流程（四层）

1. **SoC 包把方案钉死**：`device/community/soc-qcom-msm8953/APKBUILD` 写着
   `depends="$pkgname-ucm swclock-offset"` —— markw 等整系 msm8953 机型都会装上。
   全仓共 14 个设备/SoC 包依赖它。
2. **内核不读不写 RTC**：官方配置里 `RTC_HCTOSYS` / `RTC_SYSTOHC` 都关着，
   `RTC_DRV_PM8XXX=m`。与我们基线的 RTC 部分逐项一致。
3. **设备树不加 allow-set-time**：主线所有 msm8953 机型都没有（只有 pmp8074 用过）。
4. **用户态 swclock-offset**：关机把「系统时间 − RTC」存进
   `/var/cache/swclock-offset/offset-storage`，开机 `RTC + 偏差` 还原；
   服务位置是 fsck 之前 load、关机时 save。包描述原文：
   *"Keep system time at an offset to a non-writable RTC"*。

### 本机实测：RTC 只能读，不能写

- 不加 `allow-set-time`：`rtc-pm8xxx` 的 `set_time` 走 `pm8xxx_rtc_update_offset()`，
  它要设备树里名为 `offset` 的 nvmem cell，本机没有 ⇒ `return -ENODEV` ⇒
  `hwclock --systohc` 报 `ioctl(RTC_SET_TIME) ... No such device`。
- 加 `allow-set-time` 让它真写寄存器：`hwclock --systohc` 把整机**挂死**
  （进程卡在不可中断状态，设备端的 `timeout` 都杀不掉）。
- 之前开 `CONFIG_RTC_HCTOSYS/SYSTOHC=y` 的那版，真机出现 5–12 分钟一次的
  周期性硬复位 —— 已撤销，本次需复验确认消失。

### 改造：照流程走，但用户态用 Debian 自带的

既然两边都是"写文件、读文件"，就不自己移植 swclock-offset，改用 bookworm 的
`fake-hwclock`（0.12+nmu1，已解包逐字核对）。额外补的两处：

1. **数据文件路径写错**：是 `/etc/fake-hwclock.data`，不是注释里原先写的
   `/var/lib/…`（`/sbin/fake-hwclock` 里 `FILE=` 写死）。
2. **装上 cron**：fake-hwclock 自带的 `/etc/cron.hourly/fake-hwclock` 要 cron
   才跑得起来，而 minbase 不带 cron。手机很少干净关机，只有关机存盘的话
   一掉电或长按电源硬复位就全丢 —— 这正好补上 pmOS 参考实现的短板
   （它只在关机时存一次）。

顺带撤掉一处想当然的屏蔽：`systemctl mask hwclock-save.service` ——
bookworm 的 `util-linux-extra` 根本没有这个 unit，它只带
`/etc/init.d/hwclock.sh` 与 udev 的 `hwclock-set`，两者开头都是
`[ -e /run/systemd/system ] && exit 0`，systemd 下压根不会去写 RTC。

### 过程中的坑

- **两个会话在改同一个仓库**：对方提交了 `0d8841c`/`eb54960`/`328e50d`，
  报告 023 也是同一时段出现的同名文件。我改 `setup-rootfs.sh` 时撞上并发写入，
  被混入一行 `2m` 前缀的坏行（已修，`bash -n` 通过）。**同时刷机是真实风险**，
  已语音提醒用户关掉一个会话。
- **编辑工具把相对路径解析到 `.codebuddy/worktrees/bg-d58d0c38/`**：
  报告 023 第一次就写进了 worktree，得再复制回主仓库（这个坑贰拾陆里记过）。
- **OrbStack 会被高负载拖垮**：JOBS 用满时 docker 守护进程反复挂掉，
  内核编到一半就断。改用 `JOBS=4` 后稳定。
- **容器里 `git fetch` 会卡死**：取内核那步 20 分钟零增长；
  在 Mac 侧绕代理直接克隆则正常（3.4MB/s）。构建改指向已有的
  `tmp/linux-kernel-pmos`（已在新基线 `770e10fa1` 上）来避开这一步。
- **工作区里有一份未提交的 `allow-set-time` 实验补丁**（对方会话加的），
  与"写 RTC 会挂死"的结论冲突。为保证产物可预期，改用 `git archive HEAD`
  导出的干净副本构建（`tmp/build-head`）。

### 状态

- 分析与代码改动已完成并推送（`21322f0`、`acaebd9`）。
- 完整刷机包正在从 HEAD 干净副本构建（内核 → DTB → rootfs → 汇总）。
- 待真机复验：联网后时间正确；重启后时间停在上次存盘点附近而非 2026-04-27；
  `/etc/fake-hwclock.data` 在更新；连续静置 ≥15 分钟无周期性重启。

### 4. RTC：查到底了，结论是**本机用不了 RTC**（不是没修对）

- 现象：手动把系统时间设对之后，`hwclock --systohc` 依然失败
  `ioctl(RTC_SET_TIME) to /dev/rtc0 ... failed: No such device`。
- 真因（drivers/rtc/rtc-pm8xxx.c）：set_time 有两条路径 ——
  真写寄存器（需要设备树 `allow-set-time`），或把"偏差"存进名为 offset 的
  nvmem cell。后者第一句就是 `if (!nvmem_cell && !use_uefi) return -ENODEV;`。
  **本机 /sys/bus/nvmem/devices/ 是空的**，没有任何 nvmem 设备。
- 参照 pmOS 官方（完整克隆 gitlab.com/postmarketOS/pmaports，见
  tmp/pmos-pmaports）：markw 用的是共享内核包 linux-postmarketos-qcom-msm8953，
  其配置里 `RTC_HCTOSYS` / `RTC_SYSTOHC` **两个都是关的**，
  `CONFIG_RTC_DRV_PM8XXX=m`。即 pmOS 给 msm8953 **也不用 RTC 对时**，靠 NTP。
  另外主线里没有任何 msm8953 机型用 allow-set-time。
- 实测：加上 allowing RTC（allow-set-time + 两个内核开关）之后，
  设备开机约 2 分钟、5 分钟各重启一次（期间没执行任何写 RTC 的命令，
  pstore 为空＝硬复位、无 panic/OOM）；**撤掉之后连续运行 39 分钟以上不重启**。
  用户的一句判断很关键：掉电不可能"立刻重启"，而它是立刻重启 ⇒ 不是掉电。
- 于是撤掉这两处（提交 f137e04），内核配置回到与 pmOS 逐项一致。
  保留的用户态改动：timesyncd 国内可达 NTP 候选、时区 Asia/Shanghai、
  util-linux-extra（hwclock）。
- 遗留：NTP 能否真的校时还需设备联网后复验。

### 5. 另外两件值得记的

- **换用 pmOS 那棵内核树（tmp/linux-kernel-pmos，commit 770e10fa1）的构建失败**：
  编到 drivers/usb/gadget/udc 与 wireguard 时中断（Error 123/1）。
  但同一时段 **OrbStack/Docker 崩了两次**（把编译进程直接杀掉），
  所以更像是环境中断而非代码问题，需要重跑才能定论。
- **OrbStack 在本机不稳定**：这轮崩了两次，docker 守护进程消失，
  需要用 `open -a OrbStack` 拉回；之后 `docker start odin-dev`。
  长时间构建期间要留意这一点。

### 补充（同一篇，重编之后又发现两条）

**坑 4：rootfs 的 staging 目录跨构建复用且从不重置。**
`tools/ci/build-rootfs.sh` 里 `ROOT=${ROOT:-/tmp/odin-rootfs-$VARIANT}`，
靠 `if [ ! -d "$ROOT/etc" ]` 决定是否重跑 debootstrap —— 也就是说
**这个根只会 debootstrap 一次，之后一直复用**。后果：撤掉某个安装步骤之后，
它当初留下的文件与 `systemctl enable` 的符号链接**仍然留在下一次的镜像里**。
这次就撞上了：撤掉 odin-swclock-offset 之后，镜像里
`sysinit.target.wants/odin-swclock-offset-boot.service` 与
`timers.target.wants/odin-swclock-offset-save.timer` 都还在，
于是 fake-hwclock 与 swclock-offset **两套同时开机设时间**，谁后跑谁说了算。
判定方法：挂载镜像看 `.wants/` 下的符号链接，而不是只看包有没有装。
修法：`rm -rf /tmp/odin-rootfs-gui` 后重编（deb bootstrap 约 15 分钟）。
注意 dist/build/rootfs/ 下的同名文件会被 overlay 拷进镜像，但只要没被 enable
就是惰性的 —— 所以"文件还在"不等于"会生效"，要看 .wants。

**坑 5：换内核基线会把设备树一起带坏，而且失败信息不在内核侧。**
切到 pmOS 的 6.19.5/main 之后，DTB 编不过：
`msm8953-smartisan-odin.dts:393 Label or path usb3_dwc3 not found`。
原因：旧树（6.19 tag）的 `msm8953.dtsi:1479` 有 `usb3_dwc3: usb@7000000`，
新树把这个 label 去掉了（USB 节点还在，只是没有这个 label）。
⇒ 只比对内核配置是不够的，**设备树的 label 也是基线的一部分**。
另外 `make dtb` 用的是裸 `patch --forward`（不是 apply-patches.sh），
遇到"已打过"会返回非零并在 set -e 下中断；重编前要先
`git checkout -- arch/arm64/boot/dts/qcom/Makefile` 并删掉生成的 .dts。

---

## 电池与温度适配（2026-09-01 凌晨）— 参数已落地、CI 全绿、刷入后失联

### 做了什么

1. **设备树**（`patches/0007`）补三个节点，四个 DTB 全部获得电量能力：
   `/ { battery: battery { compatible = "simple-battery"; ... }; }`
   + `&pmi8950_fg`（monitored-battery / power-supplies / status=okay）
   + `&pmi8950_smbcharger`（monitored-battery / status=okay）。
   数值来自原厂安卓包的下游 DTB（reports/025）：3500 mAh / 3.4 V / 4.4 V / 100 mA。
   `constant-charge-current-max-microamp` 取 1500000，**不抄**原厂 3500 mA
   （那是 PMI8950 SMBC + SMB1351 并联的能力，主线没有 smb1351 驱动）。
2. **内核配置**：`CONFIG_BATTERY_PMI8994_FG=y`、`CONFIG_HWMON=y`、
   `CONFIG_THERMAL_HWMON=y`。
3. **用户态**：`setup-rootfs.sh` 补装 `upower` + `policykit-1`
   （内核有 psy、没有 upower 就一个都看不到）。
4. **顺带修两个换基线的后遗症**（都是编译 blocker，见下）。

### 顺带修掉的两处（都不是这次电池改动引起的）

**A. 换基线带坏设备树（WORKLOG 坑 5 的正式解法）**
新基线 `msm8953.dtsi` 把 dwc3 合并进了 `usb3` 单节点
（`compatible = "qcom,msm8953-dwc3","qcom,snps-dwc3"`），`usb3_dwc3` 不再存在，
而 `usb_dwc3_hs` 这个端点标签**由 dtsi 内建提供**。
改法照上游写法（同 `qrb2210-rb1.dts`）：`&usb3` 上加 `dr_mode = "otg"`，
端点改用 `&usb_dwc3_hs { remote-endpoint = <&usb_con_hs>; }`。
`dts/msm8953-smartisan-odin-norolesw.dts` 的 `&usb3_dwc3` 一并改指 `&usb3`。

**B. `KERNEL_SHA` 散在五处、只同步了一处（CI 自换基线起一直是红的）**
`eb54960` 把 Makefile 的 SHA 改成 `770e10fa`（分支 `6.19.5/main`），
但 workflow 的 `env.KERNEL_SHA`、`fetch-kernel.sh` 默认值、
AGENTS.md / docs/01 / docs/05 都还写着旧值 `05f7e89`。
make 的 `?=` 不会覆盖环境变量 ⇒ workflow 的旧值静默生效 ⇒ CI 取的是另一棵树
⇒ 补丁 0004（R69006 面板）在旧树上打不上，kernel job 卡在"应用补丁"。
五处已全部对齐，并在 workflow 注释、fetch-kernel.sh、docs/05 第六节各写了
"这四处必须一起改"。

### 坑（这次踩的，都实测过）

- **dtc 1.6.1 不接受"根节点闭合之后的顶层节点"**：
  `battery: battery { ... };` 直接 `syntax error`。必须包进 `/ { ... };` 根覆盖块。
  最小复现验证过：包进根覆盖块正常合并。
- **`make dtb` 用的 GNU patch 会 fuzz，CI 用的 git apply 不会** —— 这是"本地绿、CI 红"的根源。
  0007 的 `dts/qcom/Makefile` hunk 上下文缺了新基线多出来的
  `markw / oxygen / ysl` 三条，GNU patch 靠 fuzz 2 蒙过去（还打印
  "Hunk #1 succeeded at 94 with fuzz 2"），git apply 直接失败。
  ⇒ 以后别把那句 fuzz 提示当噪音。
- **换基线后验证补丁的快办法**（比等 30 分钟 CI 快得多）：
  从 HEAD 把 8 个补丁涉及的原始文件抽到临时目录、`git init` 成临时仓库，
  再按 0001→0008 顺序逐个 `git apply --check` 并落盘。本次用它一次找出了 0007。
- **手工改 patch 必须同步 hunk 行计数**：0007 的 dts 部分 449 → 489 → 501 → 494，
  每次增删都要重数。
- 重编前要恢复内核树的 Makefile 与已生成的 .dts（`git checkout --` + 改名备份）。

### CI 结果（run 33411566563，commit 3b509cb）

dtb ✅ / kernel ✅ / lk2nd ✅ / rootfs-core ✅ / rootfs-gui ✅ / publish skipped（预期）

产物核验（下载后本地验的）：
- DTB：`battery` 节点 3500000 µAh / 3400000 µV / 4400000 µV / 1500000 µA / 100000 µA；
  `fuel-gauge@4000` = `qcom,pmi8996-fg`，status=okay，monitored-battery=0x65，
  power-supplies=0x66；`smbchager@1000` = `qcom,pmi8996-smbchg`，status=okay；
  10 个 thermal zone。
- vmlinuz 里有 `pmi8994_fg`(3 处)、`qcom-battery`、`qcom-smbchg-usb` 字符串 ⇒ 驱动已编进内核。
- 下载走 `env -u http_proxy -u https_proxy ...`，kernel+dtb 16 秒，gui 镜像 19 分钟。

### 刷入结果：镜像刷成功，但设备失联（**当前停在这里**）

- `40 data`：`fastboot flash userdata odin-debian-gui-sparse.img` 成功，
  10 个分块共 290 秒，全 OKAY。
- `50 reboot`：`Rebooting OKAY`。
- 之后 240 秒内 USB 网卡没出现；`60 usbnet` 想静态兜底配 `en0`，
  但 `sudo` 要终端密码（用户不在）⇒ 失败。
- 反复查（重启后 15 分钟内查了 4 轮）：
  `fastboot devices` 空、`ping 172.16.42.1` 全丢、
  `ioreg -p IOUSB` 里只有 "Xiaomi Type-C 5-in-1 Hub" / "Generic CDC" / RTL9210，
  **没有任何 Qualcomm VID（05c6 / 18d1）的设备**。
  镜像里也没预置 WiFi（无 *.nmconnection），所以 WiFi 这条路也不通。

#### 已排除 / 待查

- **已排除"Type-C 角色切换"这一路**：镜像的 `extlinux.conf` 里 `default l0-safe`，
  用的就是安全版 DTB（`dr_mode = "peripheral"`、`/delete-property/ usb-role-switch`、
  `/delete-node/ ports`），UDC 本应恒在、不依赖角色判定。
- 因此更可能是：设备根本没起到能起 gadget 的阶段（内核 panic / 根分区没挂上 /
  某个驱动 probe 卡住），或者 reboot 后掉电关机。
- 没有串口控制台，**无法在无物理操作的情况下进一步区分**。
  按约定（"手机状态无法操作就暂停"）停在这里。

#### 下一步（需要用户动手）

1. 长按电源关机 → 按住【音量减 + 电源】进原厂 fastboot，
   让 PC 上重新出现 `fastboot devices`。
2. 恢复手段（有备件）：
   `fastboot flash boot evidence/live-device-backup/boot-partition.img`
3. 起得来之后再定位：优先看串口/屏幕上的启动日志，
   确认是内核 panic、根分区挂载失败，还是某个驱动 probe 卡住。

### 遗留（本次故意没做）

- `CONFIG_BATTERY_QCOM_FG=y` 是本树 Kconfig 里**不存在**的失效残留
  （旧驱动名 qcom_fg.c，现为 pmi8994_fg.c），olddefconfig 静默丢弃它。
  按"只增不删"暂留，未删。
- 本次全程**没有执行任何删除/清理命令**（按用户要求），
  临时目录 `tmp/battery-probe`、`tmp/patchcheck`、`tmp/pristine-check`、
  `tmp/pristine-check2`、`tmp/ci-artifacts` 与两个 `.odin-bak` 备份都还在，
  等全部完成后再统一整理。

---

## 触摸屏：已可用（2026-09-01 晚）

### 结论

触摸芯片是 **FocalTech FT8716**，与显示集成在同一颗 TDDI 上。用主线的
`edt-ft5x06` 驱动即可，**不改内核配置、不要固件**。

### 硬件参数是从原厂 DTB 里读出来的，不是猜的

`evidence/stock-rom-battery/odin-stock.dts:6367` 的 `focaltech@38`：
i2c@78b7000（主线 `&i2c_3`，BLSP1 QUP3）地址 0x38，reset gpio64 /
irq gpio65，`vcc_i2c-supply` 由 pm8953_l6(1.8V) 供；pinctrl 的驱动强度与
上下拉逐项对齐原厂 :1808-1895（也与主线 `msm8953-xiaomi-common.dtsi:382-431`
一致）。同总线还有个 `novatek@01`，那是 NT36672 面板变体的备选，本机不用。

`edt-ft5x06.c:1530` 有 `focaltech,ft8716`；`CONFIG_TOUCHSCREEN_EDT_FT5X06`
本来就是 `=m`。改动只有 `patches/0007`：`&tlmm` 加 4 个 pin 状态 + 新增
`&i2c_3` 节点。

真机：`/dev/input/event3` 注册为 `generic ft5x06 (8d)`，划屏读到
`ABS_MT_POSITION_X=589 / Y=1504 / BTN_TOUCH=1`，坐标在 1080x1920 内。

### 两个非直觉的点（都踩到了）

**1. "触摸 probe failed" 可能是显示那边的锅。**
FT8716 是 TDDI，要面板先上电才响应。第一次试的时候 probe 失败，翻 dmesg
才看到背光那边 `qcom,wled ... invalid value for 'qcom,ovp-millivolt'` 又回来了
—— 因为我做试验 DTB 时拿的底片是**第一轮**（OVP 修复之前）的产物，
于是背光挂 ⇒ DSI 一直等它 ⇒ 触摸跟着超时。
换成修复后的底片重做，触摸 5.2 秒就 probe 成功（失败那次 31.9 秒还在重试）。

> 教训：`tmp/ci-artifacts/` 下会同时存在多个轮次的产物，**用之前先核验关键值**，
> 别默认它是最新的。这个坑让我多烧了一轮重启，还误报了一次"黑屏"。

**2. `&i2c_3` 不再导致无限重启（旧记录已订正）。**
`WORKLOG.md:1353` 记着"只要启用 &i2c_3 真机就无限重启"，怀疑 BLSP 受
TrustZone 保护。但 msm8953.dtsi 里那三条 TZ 注释说的是 `&i2c_4`
（78b8000，传感器），不是 i2c_3 —— 当时是读串了总线。
本次实测：新基线上启用 `&i2c_3` 一切正常，没有重启（真因未追溯）。

顺带两条操作经验：
- **`fastboot reboot` 仍然起不来**，但系统内 `sudo reboot` 是通的
  —— 以后重启走系统内，别指望 fastboot 那条。
- **`sudo reboot` 是异步的**：命令返回后系统还活着十几秒，
  `ping` 通不代表已经重启过，要等 sshd 重新可用才算数。

### 远程进 fastboot 那条路走不通（与脚本预期不符）

`flash-all.sh` 20 阶段写的是"改名 extlinux.conf ⇒ lk2nd 找不到配置会停在
fastboot"。实测是**反复重启**，不是停下 —— 最后是人工按住
【音量减 + 电源】才停住的。这条脚本注释与文档都需要订正。

### 仍可复用的一个技巧

要在真机上快速试 DTB 改动，**不用等 40 分钟 CI**：
把 CI 编好的 DTB 反编译 → 改 → 重编译 → scp 到 `/boot/dtbs/qcom/` →
改 extlinux.conf 的 fdt 指向它 → 系统内 reboot。
（AGENTS.md 铁律 4：这只能用于探路，不能据此确认"已修好"。）

---

## rootfs 太慢：定位到解包那 9 分钟（2026-09-01 晚）

### 数据（v0.9.4-battery 那轮 CI 的 gui rootfs 日志，job 99846158676）

整段 23.6 分：

| 阶段 | 耗时 | 占比 |
|---|---|---|
| debootstrap | 106.6s (1.8 分) | 7.5% |
| udev + 基础包（setup-rootfs 前段） | 174.7s (2.9 分) | 12.3% |
| **Plasma 装包（setup-rootfs 后段）** | **850.3s (14.2 分)** | **60%** |
| build-image（mke2fs 25s + img2simg 13s + 校验 3s） | 40.7s | 2.9% |
| 其余（checkout / 装工具 / 下上轮 artifact / 上传） | 约 250s | 17.6% |

Plasma 那 850 秒内部（按分钟桶统计 dpkg 输出）：

```
11:59        约  60s   静默（fix_dns + apt-get update + 下载）
12:00–12:08  约 540s   解包 1202 个包，同期配置只有 3 个   ← 大头
12:09–12:12  约 240s   配置 1211 个包（postinst 在 qemu-arm64 下跑）
```

另外 `Processing triggers` 共 23 次，其中 sgml-base、libc-bin(ldconfig)、dbus
各 3 次 —— 三批装包各触发一轮。

### 结论：不是带宽问题，是 dpkg 逐包 flush

**解包 1202 个包花了 9 分钟、每包约 0.45 秒**，而写入量只有几百 MB。这个数字
只能由"每处理一个包就 flush 一次文件系统"解释（dpkg 的 safe I/O）。

### 改法：给三处 apt-get install 加 force-unsafe-io

统一走 `APT_OPTS="-o Dpkg::Options::=--force-unsafe-io"`。

**用命令行选项，不写 `$R/etc/dpkg/dpkg.cfg.d/`**：写文件会留在镜像里，连带影响
真机上以后 apt 升级的行为；命令行选项只在本次装包生效，镜像里不留痕迹。
掉电一致性对这一步没意义 —— 刷进真机的是 build-image.sh 后面 mke2fs 出来的
新镜像，不是这个临时 staging 目录。

### 留到下一轮的（都算过账，不是忘了）

- **合并三批装包**：能省两轮 dpkg trigger（上面那 3× 的 ldconfig/dbus/sgml-base）
  和一到两次 apt-get update。但 udev 那批必须先于后面几个 `systemctl enable`
  （serial-getty / odin-usb-gadget / odin-firstboot-resize），基础包那批又必须先于
  `systemctl enable NetworkManager/cron/fake-hwclock`，合并会打乱这些先后关系，
  风险不小。真要合，先确认 `systemctl enable` 是否真的需要对应包已安装（很可能
  不需要，它只是在建符号链接）。
- **三处 apt-get update**：sources.list 在它们之间没变过，理论上两处冗余；但 298
  行那次是防御性的（前一批 systemd-resolved 的 postinst 会把 resolv.conf 换成
  悬空链接，可能导致更早那次 update 拿到空索引）。单个收益不到 1 分钟。
- **缓存 apt 归档**：只省那 60 秒下载，性价比低。
- **缓存整个 gui staging**：5.7 GB，虽然有 10 GB 上限，但上传下载都很不划算。

### 一条方法论

这次能定位准，靠的是**先按分钟统计日志行分布**再下结论：
一眼看出 12:00–12:08 只有 Unpacking、Setting up 几乎为零，于是矛头直接指向
解包而不是"包太多"或"网络慢"。以后排查构建耗时都该先画这个分布。

---

## 麦克风/扬声器、蓝牙、GPS、视频编解码：一轮摸底（2026-09-01 深夜）

方法照旧：**先在真机上实测现状**，再对原厂 DTB 与 pmOS/主线源码，不靠猜。

### 1. 蓝牙 —— 已可用（本轮搞定）

内核侧本来就是好的，缺的只有用户态：

- 主线 `btqcomsmd` 走 SMD 通道（`APPS_RIVA_BT_ACL` / `APPS_RIVA_BT_CMD`），
  固件与 WiFi 共用 `wcnss.*`（odin-wlan-fw.sh 已取）
- DTB 里 `wcnss_bt`（`qcom,wcnss-bt`）由 msm8953.dtsi 提供、默认启用
- 真机：`hci0` 直接存在，控制器 `02:00:67:DB:FE:B8 (public)`、Powered: yes
  —— **是 public 地址，不用手动 `btmgmt public-addr`**
- 装上 bluez 后 20 秒扫描扫到 10 台周边设备（LYWSD03MMC 温湿度计、
  一台 Apple 设备 RSSI -68）

改的只有包清单：`bluez`（两变体）+ gui 的 `bluez-obexd`、`libspa-0.2-bluetooth`、
`pipewire-alsa`。**没动 DTB、没加固件、没加 udev 规则。**

### 2. 音频（内置扬声器 + 麦克风）—— 路径清楚，本轮只摸清没动手

- 现状：`cat /proc/asound/cards` → `--- no soundcards ---`；
  `devices_deferred` 里 `c0f0000.codec msm8916-wcd-digital-codec: failed to get mclk`
- 真因：**`&lpass`（ADSP remoteproc，msm8953.dtsi:3076）没启用** ⇒
  `q6afecc` 时钟控制器没注册 ⇒ codec 拿不到 mclk。
  mclk 是 LPASS 内部产生的 9.6MHz，**不是某个 GPIO** —— 所以不是 pin 配错
- 三个节点在我们 DTB 里全是 disabled：`remoteproc@c200000`(ADSP)、
  `sound-card@c051000`、`remoteproc@4080000`(modem)
- 硬件（原厂 DT）：无独立 wcd9xxx / slimbus（tasha、wcd9xxx-irq、audio_ext_clk
  全 disabled），用 PM8953 下 `8953_wcd_codec@f000`，digital 基址 `0xc0f0000`。
  **本机无耳机孔**，只有 `qcom,msm-ext-pa = "primary"` 一路外部功放
- 固件：`adsp.mdt` + `adsp.b03/b04/b05/b10/b13` 在 **modem:/image/**（不在 dsp 分区！
  dsp 分区里全是 Android 的用户态 DSP 库：DTS_HPX、DolbyMobile、fastrpc_shell…）
- 待定：内置扬声器功放是不是 AW8738。原厂只给 `ext-pa-enable = gpio132`，
  markw 用 `awinic,aw8738` 挂 gpio96 —— 要对一下

修法：启用 `&lpass` → 固件脚本取 adsp.* → 启用 `&sound_card`（model/routing/pinctrl）
→ 用户态 `alsa-ucm-conf` + `alsa-utils`。顺序不能颠倒。

### 3. 视频编解码（venus）—— 看似简单，实际卡在固件握手

- 节点 `venus@1d00000` 默认已启用，`CONFIG_VIDEO_QCOM_VENUS=m` 已开，
  模块 `venus_core` 等已加载 —— **看起来只差固件**
- 实测把 `venus.mdt` + `venus.b00~b04` 从 modem:/image/ 拷进 /lib/firmware 后，
  `venus.mdt failed with error -2` 确实消失了，**但冒出新错误**：
  ```
  qcom-venus 1d00000.venus: Unsupported property: 0
  qcom-venus 1d00000.venus: probe with driver qcom-venus failed with error -5
  ```
- `Unsupported property` 是 `hfi_parser.c:383` 的 `dev_warn_once`（只打一次，
  实际可能有多个属性不认识）；`-5` = `-EIO`，来自 `hfi.c` 的 HFI 命令封装
  ⇒ **是固件握手失败**：这版 venus 固件（2018 年 Android 7.1）的能力表/初始化
  协议与主线 venus 驱动对不上。**不是缺文件的问题**，要单独立项排查，别当"简单活"

### 4. GPS —— 大工程，不在这轮

- 主线没有 QCOM 的 GNSS 驱动（`drivers/gnss/Kconfig` 只有 MTK/SiRF/u-blox），
  本机 `CONFIG_GNSS` 也未开 ⇒ **内核 GNSS 子系统这条路不存在**
- 定位由基带跑，经 **QRTR 上的 QMI LOC 服务**暴露给 AP。
  本机 `&mpss`(modem) 未启用 ⇒ 没有 QRTR/QMI
- 需要：启用 `&mpss`（脚本注释说要 `pll-supply = <&pm8953_l7>`）+ modem 固件
  （mba.mbn、modem.mdt + b05~b20 都在 modem:/image/）+ `rmtfs`/`tqftpserv`
  + ModemManager/libqmi/geoclue。**Debian 有没有现成的 rmtfs/tqftpserv 包未确认**
- `gpsd` 不适用（没有串口 GPS，也没有 /dev/gnss*）
- 注意：pmOS wiki 说 msm8953 GPS=Works，但那次取证里 QRTR 根本没起来，
  不能当作本机已通的证据

### 5. 一条很实用的操作技巧：让设备上网

设备本身只有 USB 那条 172.16.42.0/24，没有外网。用 SSH 远程端口转发把本机的
代理给它即可（本机 10808 上有代理）：

```sh
ssh -f -N -R 10808:127.0.0.1:10808 user@172.16.42.1
apt-get -o Acquire::http::Proxy=http://127.0.0.1:10808 install bluez
```

实测 6.3 MB 走 13 秒。以后要在真机上现场装包排查都靠这个。

踩到的两个坑：
- 无网络时 `apt-get update` **不会超时退出**，会一直挂着占住
  `/var/lib/apt/lists/lock`，之后所有 apt 都报 lock 错误 —— 要 `pkill -9 apt-get`
- sshd 没设 MaxStartups（默认 10:30:60），密集轮询时会被概率性丢连接，
  表现为间歇性 `Permission denied (publickey,password)`，**不是密码错**，等一会重试即可

### 音频：已推进到"声卡出来但 PCM 打不开（本轮到这）

在真机上按"本地快速改 DTB → scp → 重启"迭代，三步走完：

1. 启用 `&lpass`（remoteproc@c200000，ADSP）。**ADSP 起来了**：
   `remoteproc1 state=running fw=adsp.mdt`。原来的
   `c0f0000.codec failed to get mclk` 随之消失（mclk 由 LPASS 内部产生）
2. 部署 adsp 固件：`adsp.mdt` + `adsp.b00~b13` 共 15 个文件，从
   **modem:/image/** 拷到 /lib/firmware（dsp 分区里没有这些，全是 Android
   用户态 DSP 库，别去 dsp 分区找。下一步要写成常驻脚本，别靠手工 cp。

剩余问题：

- 声卡能注册：`0 [smartisanodin]: smartisan-odin`，
  `/dev/snd` 有 pcmC0D0p / pcmC0D1c / pcmC0D2p / pcmC0D4c / pcmC0D4p、comprC0D3。
  `devices_deferred` 已清空。
- **但 PCM 打不开**：`Playback open error: -22 (Invalid argument)`，
  `arecord` 同样 -EINVAL。这通常是 **q6routing 通路没设（UCM 的活）：
  MultiMedia1 → AFE 端口的 mixer 控件没设，PCM 就无法打开/silent。
  pmOS 侧这一步由 `alsa-ucm-conf`（msm8953-mainline 的 fork）完成，
  bookworm 自带包里**大概率没有 msm8953 profile（未确认）。

下一步（按顺序）：
1. 试直接手工设 mixer 通路（amixer 设 "MultiMedia1 Mixer" → 对应 AFE 端口），
   确认能出声，就知道缺的是 UCM 而不是 DTB。
2. 若确认是 UCM：要么把 pmOS 那份 ucm2 配置引进来，要么写一个最小 UCM profile
   （声卡名 `smartisan-odin`，注意 UCM 是按声卡名匹配的）。
3. 与 markw 的 `&sound_card` 对齐差异：它比我多 `MM_DL3`→MultiMedia3 Playback、
   `MM_DL4`→MultiMedia4 Playback，并在 `&wcd_codec` 里 `/delete-property/ qcom,gnd-jack-type-normally-open` + 设 mbhc 阈值。本机**无耳机孔**，要确认 MBHC 不会误判
   插入（误判会把声音送到不存在的耳机通路 → 扬声器无声）。
4. 扬声器功放：`snd_soc_aw8738` **已加载**（说明 AW8738 猜对了，gpio132 也对
   —— 但要出声后才知道功放是否真的被打开。

注：本轮所有改动都在 `tmp/audio-test/`（试验 DTB 与脚本），**还没进 patches/0007**。
等真机出声后再固化。

### 音频：打通了 PCM，但播放几乎无声、采集录到全零（进展 + 现状）

#### 关键突破：PCM 打不开的根因是 q6routing 没设，不是 DTB 问题

之前 `aplay` 一直 `Invalid argument`。逐个试探后确认：**设上 AFE 端口通路就能打开**。

- 播放侧控件命名：`<端口>_RX Audio Mixer MultiMediaN`
  可用端口：PRI_MI2S_RX / QUAT_MI2S_RX / QUIN_MI2S_RX / TERT_MI2S_RX /
  SEC_MI2S_RX / PRIMARY_TDM_RX_0..7 / DISPLAY_PORT_RX 等
- 采集侧命名是**反的**：`MultiMediaN Mixer <端口>_TX`
  （PORT_TX Audio Mixer MultiMediaN 这种写法不存在，设了返回空）

设上 `PRI_MI2S_RX Audio Mixer MultiMedia1` = on 后：
`aplay -D plughw:0,0` 在 44100/48000、S16_LE、2 声道下**都能打开**。

#### 现状（都还差最后一步）

- **播放**：speaker-test 跑完 rc=0、缓冲区分配正常（buffer_size=130560），
  但真机只听到"很短暂的、很小的震动声"，几乎听不见。
  音量不是原因：`RX1/RX2 Digital Volume` 当前 = **84**，该控件
  `dBscale-min=-84.00dB, step=1.00dB`，所以 84 就是 **0dB 满音量**。
  ⇒ 怀疑是**外部功放（AW8738）没真正打开**：`snd_soc_aw8738` 模块是加载了，
  但 aux-devs / mode-gpios(gpio132) 是否真的把功放使能，还没验证。
  下一步：确认 AW8738 的 mode 引脚电平；对比 markw（它用 gpio96 + awinic,mode=<5>）。
- **采集**：`MultiMedia2 Mixer PRI_MI2S_TX` = on 后 arecord 能开、能录满 3 秒
  （288044 字节 = 3×48000×2+44，长度完全正确），**但内容是全零**
  （144000 个样本，峰值 0、平均 0）⇒ 通路设了但音频没进来。
  下一步：MIC BIAS / AMIC 输入选择（`ADC1/ADC2/ADC3`、MIC BIAS External1/Internal2）
  还没设；markw 的 routing 里有 "AMIC2", "MIC BIAS Internal2"，本机是内置麦克风，
  很可能要走 Internal2 而不是 External。

#### 还要补的（与 markw 的差异）

markw 的 `&sound_card` 比我多两条路由：`MM_DL3`→MultiMedia3 Playback、
`MM_DL4`→MultiMedia4 Playback。实测 **device 2（MultiMedia3）确实打不开**，
正好对上 —— 补上这两条应该就能用。

#### 一条重要的操作经验

`aplay -l` 偶尔会报 "no soundcards found"，但 `/proc/asound/cards` 里卡是在的
—— 是瞬时状态，重跑就好，别当成"声卡没了"。

### 音频：根因锁定 —— 缺 UCM profile（内核日志自己给了诊断）

#### 决定性证据

内核打印：
```
MultiMedia1: ASoC: no backend DAIs enabled for MultiMedia1, possibly missing
ALSA mixer-based routing or UCM profile
```
**内核自己把诊断写出来了**：缺 mixer-based routing 或 UCM profile。

#### 完整因果链（从现象到源码）

1. 现象：aplay 报 "Playing WAVE ..." 看着成功，但一点声音都没有；
   arecord 能录满时长但内容全零
2. dmesg：`q6asm-dai ... q6asm_dai_prepare: stream reg failed ret:-22`
3. 定位源码 `sound/soc/qcom/qdsp6/q6asm-dai.c:265`：失败的是
   **`q6routing_stream_open()`**，不是 open/format 的问题
4. `q6routing.c:375` 的判定：
   ```c
   session = &routing_data->sessions[stream_id - 1];
   if (session->port_id < 0) {
       dev_err(..., "Routing not setup for MultiMedia%d Session\n", ...);
       return -EINVAL;          // 就是那个 -22
   }
   ```
   `session->port_id` 由 mixer 控件 `<BE>_RX Audio Mixer MultiMediaN` 设置
5. **但手工 `amixer cset` 只填了 port_id，没有让 DAPM 把 backend DAI 使能**
   —— 所以 backend 仍 disabled，`q6routing_stream_open` 之后一路失败。
   内核那句 "no backend DAIs enabled" 说的正是这个

#### 已排除的（别再查一遍）

- 音量：`RX1/RX2 Digital Volume = 84`，该控件 `min=-84dB step=1dB`
  ⇒ 84 = **0dB 满音量**，不是音量的锅
- 功放：`aw8738` 驱动已绑定（`/sys/bus/platform/drivers/aw8738/audio-amplifier`），
  **gpio132 = out high**（驱动已把 mode 脚拉高），功放是使能的
- ADM 侧 `MultiMedia1 Mixer PRI_MI2S_RX`：**该控件不存在**。
  `MultiMediaN Mixer <端口>` 只有 TX 方向（采集），播放方向只有
  `<端口>_RX Audio Mixer MultiMediaN` 这一种写法

#### 控件命名（已实测确认，很有用）

- 播放：`<端口>_RX Audio Mixer MultiMediaN`
  可用端口：PRI_MI2S_RX / QUAT_MI2S_RX / QUIN_MI2S_RX / TERT_MI2S_RX /
  SEC_MI2S_RX / PRIMARY_TDM_RX_0..7 / DISPLAY_PORT_RX ...
- 采集（**命名是反的**）：`MultiMediaN Mixer <端口>_TX`
  （`PRI_MI2S_TX Audio Mixer MultiMedia2` 这种写法不存在，设了返回空）
- 含 SPK 的控件实际**只有 `SPK DAC` 一个**（不是 SPK DAC Switch）

#### 下一步（就一件事）

**写 UCM profile**，声卡名 `smartisan-odin`（UCM 按声卡名匹配），
或引进 pmOS 那套 `alsa-ucm-conf`（msm8953-mainline 的 fork，
bookworm 自带包里没有 msm8953 profile）。

UCM 要做的两件事：
1. 设 mixer 控件（`<BE>_RX Audio Mixer MultiMediaN` = on）
2. **设 DAPM 路由把 backend DAI 使能** —— 这一步手工 amixer 做不到，是当前的卡点

可参照 `msm8953-xiaomi-markw.dts` 的 `&sound_card`（model = "xiaomi-markw"、
aux-devs = <&speaker_amp>、audio-routing 含 MM_DL1/DL3/DL4、
pinctrl 用 cdc_pdm_lines_act / _2_act / comp_lines_act）与 pmOS 的 ucm2 配置。

关于多麦克风（用户的提醒）：本机原厂 DT 里 codec 只有一套
（`8953_wcd_codec@f000`），routing 里 AMIC1/AMIC2/AMIC3 分别走
MIC BIAS External1 / Internal2 / External1。内置麦克风很可能要走
**Internal2**（AMIC2），而不是 External —— 等 UCM 通了再逐个试。

### 音频（续）：写了 UCM 初稿，但还没让内核导入成功

已落盘到仓库：`dist/build/rootfs/usr/share/alsa/ucm2/smartisanodin/`
- `smartisanodin.conf`（UseCase HiFi → HiFi.conf）
- `HiFi.conf`（SectionVerb / Speaker / Mic / Modifier）

**关键坑：UCM 目录与主文件名要匹配声卡 id，不是 model。**
`/proc/asound/cards` 显示 `0 [smartisanodin ]: smartisan-odin - smartisan-odin`
—— 方括号里的 `smartisanodin` 才是 id（连字符被去掉），所以目录是
`ucm2/smartisanodin/`，主文件是 `smartisanodin.conf`。第一次写成
`smartisan-odin/` 导致 alsaucm 报 "failed to import ... -2"。

改名后**仍导入失败**（`error: failed to import hw:0 use case configuration -2`、
`alsaucm listcards` 仍为空）⇒ 说明是 **ucm2 语法问题**，不是名字问题，
下一轮要对照 `/usr/share/alsa/ucm2/` 里现成配置的写法逐个字段校对
（怀疑点：SectionModifier 在 Syntax 4 下是否需要、Syntax 声明的写法）。

UCM 里已经写好的关键内容（这些实测确认过，可直接复用）：
- Speaker EnableSequence：`PRI_MI2S_RX Audio Mixer MultiMedia1`=1、
  `SPK DAC`=1、`RX1/RX2 Digital Volume`=84
- Mic EnableSequence：`MultiMedia2 Mixer PRI_MI2S_TX`=1、
  `ADC2 MUX`='AMIC2'、`ADC2`=1

### 音频（再续）：播放侧控件已全通，但仍无声；采集侧找到两处错误

#### 播放侧：控件全设上了，且 DSP 不再报错

设完这四个后，播放**不再产生 "q6asm_dai_prepare: stream reg failed -22"**
（此前每次播放必现）⇒ DSP 侧路由已通：
```
PRI_MI2S_RX Audio Mixer MultiMedia1 = on     # AFE 通路（q6routing）
SPK DAC Switch = on                          # 注意是 SPK DAC，不是 EAR
RX3 MIX1 INP1  = RX1                         # 可选值 ZERO/IIR1/IIR2/RX1/RX2/RX3
RX3 Digital Volume = 128
```

**关于听筒 vs 外放（用户的提醒，已核实）**：
含 EAR/SPK 的控件**只有 `EAR_S` 和 `SPK DAC` 两个** —— 没有 "EAR DAC"，
所以设 `SPK DAC` 走的就是**外放扬声器**，不是听筒。这点没搞错。

**但真机仍然听不到声音**。DSP 不报错 ≠ 有声音，下一步要查：
- AW8738 功放是否真的被拉起来（gpio132 虽是 out high，但 aux-devs 是否生效）
- 是否需要走 `PIN_SWITCH` / `AUX PCM` 而不是 PDM
- codec 侧 `SPK` 之后到外部功放的 DAPM widget 有没有上电

#### 采集侧：两处明确错误（下次直接改）

1. **`ADC2 MUX` 的可选值是 `ZERO / INP2 / INP3`，不是 AMIC2**
   —— 之前 `cset name="ADC2 MUX" 'AMIC2'` 匹配失败，值落在 0（ZERO，即静音）。
   正确值是 **INP2 或 INP3**（正好对应用户说的本机有两个麦克风，要分别试）
2. **`ADC1` / `ADC2` / `ADC3` 这些控件根本不存在**（设了返回空），
   之前脚本里对它们 cset 全是无效操作
3. 控件里**没有任何含 AMIC / MIC BIAS 名字的项** ⇒ routing 里的
   "MIC BIAS External1/Internal2" 是 DAPM 静态路由，不是独立 mixer 控件
4. `Audio Mixer MultiMedia2` 结尾的控件**只有 RX 方向** ⇒ 采集侧必须用
   `MultiMedia2 Mixer <BE>_TX`（这个写法是对的）

#### 下一步（按顺序）

1. 采集：`ADC2 MUX` = INP2 试一次、= INP3 试一次，看哪个有电平
2. 播放：DSP 不报错却无声，重点查功放是否真的使能 + DAPM 后端 widget 上电情况

### 音频：麦克风打通了（本轮最大成果）

完整可用的采集通路（逐个试出来的，别再猜）：

```
MultiMedia2 Mixer TERT_MI2S_TX = 1   # ← 关键！采集后端是 TERT_MI2S_TX，不是 PRI_MI2S_TX
DEC1 MUX = ADC2                       # 接上后才有信号
DEC2 MUX = ADC2
CIC1 MUX = AMIC
ADC2 MUX = INP2 或 INP3               # ← 本机两个麦克风，都通
```

逐个试 `MultiMedia2 Mixer <BE>_TX` 的结果：
```
❌ PRI_MI2S_TX   ❌ QUAT_MI2S_TX   ❌ QUIN_MI2S_TX   ❌ SEC_MI2S_TX
✅ TERT_MI2S_TX  ← 只有它能打开 PCM
```

实测电平（环境噪音，3 秒 48kHz mono）：
```
INP2: 峰值=14  平均=1
INP3: 峰值=28  平均=2   ← 信号更强，应是主麦克风
再测: 峰值=180 平均=3   （设完 DEC 后明显变大）
```

**注意：之前的判断"采集侧用 PRI_MI2S_TX"是错的**，播放与采集的后端并不同名
（播放 PRI_MI2S_RX / 采集 TERT_MI2S_TX）—— 这是靠逐个试试出来的。

另：采集链路**没有** TX/ADC/DEC 的 volume 控件（grep 为空），
增益只能靠 DEC/CIC 的 MUX 选择，或等 UCM/上层（pipewire）来做软件增益。

### 音频（终）：播放后端确认 + 找到"假播放"现象；我的测试脚本自己污染过结果

#### 播放后端确认：是 PRI_MI2S_RX，不是 TERT（纠正上一节的猜测）

上一节我推断"采集用 TERT_MI2S_TX，播放可能也该用 TERT_MI2S_RX"——**实测证明是错的**：
```
PRI_MI2S_RX: aplay 能开 PCM、state=RUNNING 稳定保持 10 秒
TERT_MI2S_RX: 连 PCM 都打不开（state 为空）
```
播放与采集的后端确实不同名，但**不是对称的那一对**：
- 播放 → `PRI_MI2S_RX Audio Mixer MultiMedia1`
- 采集 → `MultiMedia2 Mixer TERT_MI2S_TX`

#### 真正的核心现象：PCM "假播放"，缓冲区塞满但 DSP 不消费

播放中读 `/proc/asound/card0/pcm0p/sub0/status`：
```
state: RUNNING
delay: 24960        ← 正好等于 buffer_size
avail: 0            ← 缓冲区被填满，一个字节都没被取走
avail_max: 18720    ← 曾经释放过约 3 个 period，之后就停了
```
hw_params 正常（S16_LE / 2ch / 48000 / period 6240 / buffer 24960），
dmesg 期间无报错。也就是 **aplay 不报错、状态 RUNNING，但 ADSP 不取数据**。

对照内核机制（`q6asm-dai.c` 的 `event_handler`，见 lkml 2025-10 的
"q6asm-dai: schedule all available frames" 补丁讨论）：
```
ASM_CLIENT_EVENT_CMD_RUN_DONE     → 送第一块数据
ASM_CLIENT_EVENT_DATA_WRITE_DONE  → snd_pcm_period_elapsed() 推进 ALSA 指针
```
**只有 DSP 回 DATA_WRITE_DONE，ALSA 指针才推进**。avail=0 即"DSP 没回报"。

#### DAPM 全链路确认为 On（断点不在上电）

播放中逐个读 debugfs：
```
AFE     PRI_MI2S_RX On / Primary MI2S Playback On
DIGITAL AIF1 Playback On / I2S RX1 On / RX3 MIX1 On / RX3 MIX1 INP1 On / PDM_RX3 On
ANALOG  PDM_RX3 On / SPK DAC On / SPK PA On / SPKR_CLK On / SPK_OUT On
AMP     SpkAmp DRV/IN/OUT 全 On（aw8738 功放已上电）
```
增益也已拉满：`RX3 Digital Volume` min=0 **max=124**，当前 124；
TLV `dBscale-min=-84.00dB,step=1.00dB` ⇒ 124 即 **+40dB**（确认过，
124 就是最大，不是"小数字"）。听筒/外放也确认过：含 EAR/SPK 的控件
只有 `EAR_S` 与 `SPK DAC` 两个，无 EAR DAC，设 SPK DAC 走的是外放。

#### ⚠️ 我自己踩的坑：测试脚本会污染结果

`be.sh` / `sample.sh` 每轮循环都把"其它后端" `cset ... 0`，
最后一遍把 **PRI_MI2S_RX 也清掉了**，导致后续 aplay 报
`q6asm_dai_prepare: stream reg failed -22`、看起来"回到起点"。
**教训：这类"清掉其它后端"的循环，收尾后必须把目标后端恢复。**
现在已恢复（`PRI_MI2S_RX Audio Mixer MultiMedia1 = 1`），
播放返回码 124（跑满 7 秒被 timeout 中断，无报错）。

#### 下一步（按顺序，别再瞎试后端了）

1. 用 dyndbg 抓 q6asm/q6afe/q6adm 日志。注意这些是**模块**，
   `file ... +p` 匹配不到，要用 `module <名> +p`。相关模块名：
   `q6asm q6asm_dai q6afe q6afe_dai q6afe_clocks q6adm q6routing q6core
    snd_q6dsp_common snd_soc_apq8016_sbc snd_soc_msm8916_digital`
2. 重点看有没有 `ASM_CLIENT_EVENT_DATA_WRITE_DONE` / `CMD_RUN_DONE`
   —— 若没有，说明 DSP 侧 stream 没真正 run（查 q6asm_run 的返回）
3. 若 DSP 始终不回报，怀疑 AFE 端口的采样率/时钟配置没下发，
   或 `q6afe` 端口没 start（查 q6afe_port_start 调用路径）
4. 采集侧已可用（TERT_MI2S_TX + ADC2 MUX=INP3），可作对照：
   看采集时 q6asm 的日志长什么样，与播放的对比差异

### 音频（续）：播放侧排查到"缓冲区不被消费"，附两条差点走错路的方法论教训

#### 客观事实（全部实测）

1. **麦克风已验收通过**：INP3 能录到说话声（用户听录音确认）；INP2 几乎无声（应是降噪副麦）
2. **播放静默的确凿证据**（环回法，ffmpeg volumedetect）：
   ```
   不播放时（环境噪音）: mean=-72.8 dB  max=-49.0 dB
   播放时 (QUAT_MI2S_RX): mean=-81.3 dB  max=-63.5 dB
   播放时 (PRI_MI2S_RX) : mean=-80.8 dB  max=-62.7 dB
   原始歌曲            : mean=-18.2 dB  max=  0.0 dB
   ```
   **播放时录到的电平反而比不播放时低 8 dB** ⇒ 扬声器根本没出声，不是"音量小"
3. **DAPM 全链路 On**（debugfs 逐个确认，播放中抓取）：
   ```
   AFE     PRI_MI2S_RX On / Primary MI2S Playback On
   DIGITAL AIF1 Playback On、I2S RX1 On、RX3 MIX1 On、RX3 MIX1 INP1 On、PDM_RX3 On
   ANALOG  PDM_RX3 On、SPK DAC On、SPK PA On、SPKR_CLK On、SPK_OUT On
   AMP     SpkAmp DRV/IN/OUT 全 On（AW8738 功放已上电）
   ```
4. **增益已满**：`RX3 Digital Volume` min=0 max=124，当前 124；
   TLV `dBscale-min=-84.00dB,step=1.00dB` ⇒ 124 = **+40dB**（最大值，确认过）
5. **PCM 卡住的现场**：
   ```
   hw_params: S16_LE / 2ch / 48000 / period_size 6240 / buffer_size 24960
   status: state=RUNNING  delay=24960(=buffer_size)  avail=0
   ```
   ⇒ 缓冲区被填满，ADSP 一个字节都不取
6. 播放期间 dmesg **零新增**（dmesg 本身已验证可用）

#### 两条差点让我走错路的方法论教训（重要）

1. **ftrace 在这个内核上不产出数据**。我追踪 `q6asm_dai_trigger` 等 7 个函数，
   filter 全部设置成功，但 `entries-written: 0`，差点得出"q6asm 没被调用"的结论。
   **做了对照实验才救回来**：追踪 ALSA 核心必调的 `snd_pcm_action` /
   `snd_pcm_do_prepare`，同样是 0 ⇒ 是 ftrace 无效，不是代码没跑。
   ⇒ **任何"追踪不到调用"的结论，都必须先用必被调用的函数做对照。**

2. **dyndbg 对模块要用 `module <名> +p`，不是 `file <路径> +p`**。
   我之前用 `file sound/soc/qcom/qdsp6/* +p` 只匹配到 **7** 条；
   改成遍历 `lsmod` 的模块名 `module q6asm +p` 后是 **119** 条。
   （这些驱动都是 `=m`。）

   另外：`q6asm-dai.c` 里 dev_dbg 极少，所以即便 dyndbg 开对了也几乎没输出
   —— **"没有日志"不能证明"代码没执行"**。

#### 下一步（下一轮从这里开始）

"缓冲区不被消费"最可能的原因，按概率：

a) **BE DAI 的 hw_params/prepare 没被触发** ⇒ `q6afe_port_start()` 没跑
   ⇒ DSP 不取数据。DAPM widget 显示 On 只代表逻辑上电，不代表 substream
   参数已下发。要查 DPCM 的 FE↔BE 是否真连上了
b) `msm8953_qdsp6_add_ops` 这条路径的 dai-link 与本机不匹配
c) ADSP 固件与驱动协议不完全匹配（venus 那边已经遇到同样的固件协议问题）

最靠谱的对照手段：**拿一台跑 postmarketOS 的 msm8953 机器（如 markw）导出
全量 mixer 状态，与本机逐项 diff**。手工猜控件名的效率已经到头了。

### 音频（再续）：修正一个自己的错误判断 + 静态配置全部查完

#### 修正：此前"ADSP 不消费数据"是**错的**

精确采样（每 2 秒一次，共 7 次）：
```
t=1s  hw_ptr:43679    appl_ptr:68639    delay=24960
t=3s  hw_ptr:237119   appl_ptr:262079   delay=24960
t=5s  hw_ptr:430559   appl_ptr:455519   delay=24960
t=7s  hw_ptr:630239   appl_ptr:655199   delay=24960
```
**hw_ptr 稳定推进**（每 2 秒约 +96000 帧 ≈ 48000×2），appl_ptr−hw_ptr 恒为
buffer_size=24960。

⇒ 数据在**正常流动**，DSP 在消费。我之前看到 `avail=0` 就断定"卡住"是**误读**：
aplay 会持续把缓冲区喂满，avail=0 只是"满"，不是"停滞"。

教训：**判断 PCM 是否推进要看 hw_ptr 的变化，不能只看 avail/delay 的瞬时值。**

#### 静态配置已全部查完，全部正常

| 项 | 状态 |
|---|---|
| AFE | `PRI_MI2S_RX` On、`Primary MI2S Playback` On |
| DIGITAL | `AIF1 Playback` On、`I2S RX1` On、`RX3 MIX1` On、`RX3 MIX1 INP1` On、`PDM_RX3` On |
| ANALOG | `PDM_RX3` On、`SPK DAC` On、`SPK PA` On、`SPKR_CLK` On、`SPK_OUT` On |
| AMP | `SpkAmp DRV/IN/OUT` 全 On（AW8738 已上电） |
| 增益 | `RX3 Digital` = 124 = **+40dB**（min 0 max 124，100%） |
| 静音 | `RX3 Mute` = **off** |
| 错误 | 播放期间 dmesg 零新增（dmesg 本身已验证可用） |
| 数据 | hw_ptr 稳定推进 |

**注意控件名带后缀**：`amixer cget name="RX3 Mute"` 取不到值，真实名字是
`RX3 Mute Switch`（numid=18）。`amixer sget "RX3 Mute"` 可以模糊匹配。
（RX1 Mute Switch=16、RX2 Mute Switch=17、RX3 Mute Switch=18）

另：`EAR` / `EAR_S` / `EAR PA` / `PDM_RX1` / `PDM_RX2` 全是 **Off**
⇒ 听筒通路没开，当前只走 SPK，方向没错。

#### 结论

静态配置与数据流都正常，但扬声器物理上不发声（环回录音已证实）。
剩余怀疑集中在 **AFE→PDM→SPK 的时钟/格式**，以及 **AW8738 的 mode 引脚
（gpio132）电平是否真的满足工作要求**（当前是 out high，但 AW8738 不同
mode 对应不同增益/工作模式，`awinic,mode` 我照 markw 填的 5）。

#### 下一轮建议（按性价比）

1. **最直接：拿一台能正常出声的 pmOS msm8953（如 markw）导出全量 mixer
   状态，与本机 `amixer -c 0 contents` 的输出做 diff。** 手工猜控件名的
   办法到这里已经到头了（1118 个控件）。
2. 检查 PDM 时钟：`RXD_PDM_CLK` / `PDM_CLK` 是否与 48kHz 匹配；
   可试改播放采样率（8k/16k/44.1k/48k）看有无变化。
3. 核对 AW8738 的 datasheet，确认 mode 引脚电平对应的工作模式。

### 音频：采样率也排除了 + 一个**从未验证过的关键假设**

#### 多采样率测试（8 秒 440Hz 正弦，播放同时用 INP3 贴近录）

```
8000Hz  播放时录到: 峰值=58 平均=4
16000Hz 播放时录到: 峰值=28 平均=3
44100Hz 播放时录到: 峰值=24 平均=2
48000Hz 播放时录到: 峰值=28 平均=2
（底噪参考: 峰值=42 平均=4）
```
全部不高于底噪 ⇒ **采样率不是原因**，PDM 速率假设排除。

#### ⚠️ 一个从未验证过的关键假设：功放芯片型号

**本机扬声器功放的型号，我们其实并不知道。**

原厂 DT 里关于功放只有两句：
```
qcom,msm-ext-pa = "primary"
qcom,ext-pa-enable = <&tlmm 132 0>      # 只有"使能脚在 gpio132"
```
**没有任何芯片型号信息。**

我现在设备树里的 `awinic,aw8738` 是**照抄 pmOS markw 的**（那台机器确认是
AW8738），plus `mode-gpios = <&tlmm 132>`、`awinic,mode = <5>` —— 全是照抄。

**这与"链路全通但不出声"的现象高度吻合**：AW8738 是通过 mode 引脚的**脉冲
个数**来选工作模式的，不是简单电平。如果本机根本不是 AW8738，驱动按 AW8738
的方式驱动那根脚，功放就永远不会进入工作状态。

#### 下一步（下一轮第一件事，按性价比）

1. **验证功放型号**：拆机看丝印，或在原厂 Android 的 kernel log / dtsi /
   `/sys/bus/i2c` 里找线索（原厂 DT 的 `qcom,msm-ext-pa` 只说明"有外部 PA"）。
   另外 modem:/image/ 里我还看到过 `goodixfp.b02/b03`（指纹），说明原厂
   的外设信息可以从那里挖。
2. **绕过功放直接验证 codec 输出**：把设备树里的 aw8738 节点去掉，
   用 sysfs gpio 手动把 gpio132 拉高（很多功放是高电平使能即可出声），
   再播放测试。若能出声，就证明是功放驱动方式的问题。
3. 前几轮记下的备选：与一台能正常出声的 pmOS msm8953 做全量 mixer diff
   （本机 1118 个控件，手工猜已到极限）。

#### 本轮已排除清单（别再重复）

音量（RX3=124=+40dB 满）、静音（RX3 Mute=off）、采样率（8/16/44.1/48k）、
播放后端（PRI/SEC/QUAT/QUIN/TERT_MI2S_RX 全试）、DAPM 全链路 On、
ADSP 固件已加载、数据流正常（hw_ptr 推进）、播放期间零内核报错。

### 音频：查原厂 ROM，确认"功放型号是我们臆想的"（重要）

#### 原厂 ROM 在哪

`/Volumes/caseSensitiveBar/Pro_user_V4.2.5/SEKSA-mol%odin-rom-4.1.0-odin-user-20180523-005028-32g/`
只有分区镜像（boot.img / NON-HLOS.bin / system 相关是空目录），**没有 mixer_paths.xml**
（apps/ 是刷机工具，sparse_images/ 空）。

#### 从原厂 DTB（evidence/stock-rom-battery/odin-stock.dts）查到的

```
8329:  qcom,ext-pa-enable = <0xbe 0x84 0x00>       ← 0x84 = 132 ⇒ gpio132，引脚没错 ✓
9728:  qcom,msm-ext-pa = "primary"
9734:  启用的 sound 节点（msm8952-audio-codec）的 qcom,audio-routing：
       "RX_BIAS","MCLK" / "SPK_RX_BIAS","MCLK" / "INT_LDO_H","MCLK" /
       "MIC BIAS External","Handset Mic" / "MIC BIAS External2","Headset Mic" /
       "MIC BIAS External","Secondary Mic" /
       "AMIC1","MIC BIAS External" / "AMIC2","MIC BIAS External2" /
       "AMIC3","MIC BIAS External"
       ⇒ **只定义了 MIC 与 BIAS，没有任何到 speaker 的通路**
9764:  sound-9335（tasha）节点 status = "disabled"
9770:  那个 disabled 节点里才有 "SpkrLeft IN","SPK1 OUT"
9791:  qcom,wsa-aux-dev-prefix = "SpkrLeft"（也在 disabled 节点里）
6562-6584: qcom,spkr-sd-n-gpio = <0xbe 0x60 0x00>   ← 0x60 = 96（另一处 speaker 关断脚）
2391:  pinctrl 里有 ext_pa_en_default
```

#### 结论

1. **gpio132 引脚正确**，之前没搞错
2. **原厂没有功放型号、没有 aux-dev、没有 wsa 前缀（那些都在 disabled 的 tasha 节点里）**
   —— 只有一个 `ext-pa-enable = gpio132` 使能脚
3. **所以设备树里的 `awinic,aw8738`（连 `awinic,mode = <5>` 一起照抄 pmOS markw）是我们臆想的**
4. 原厂启用的通路上，speaker 输出靠 codec 内部固定（"SPK_RX_BIAS" → SPK），
   外部功放只由一个 GPIO 使能

#### 下一步（下一轮第一件事）

1. **去掉设备树里的 aw8738 节点与 `aux-devs = <&spk_amp>`**，改成一个单纯的
   GPIO 使能（主线常见做法：`gpio-leds` 或 `spk-amp-gpio`，
   要查 apq8016_sbc.c 到底支持什么；若不支持，可用 `gpio-hog` 让 gpio132
   开机即拉高 —— 这样最简单，也能立刻验证）
2. 用 `gpio-hog` 让 gpio132 常高后播放测试：若出声，就证明问题一直是
   "aw8738 驱动按 AW8738 的方式驱动了那根脚，而本机功放不认"
3. 另一个 GPIO 线索：`qcom,spkr-sd-n-gpio = gpio96`（原厂另一处 speaker 关断脚，
   注意 sd-n 是低有效 ⇒ 正常工作时要**拉低** gpio96）⇒ 这条也要一起试

### 音频：从原厂线刷包挖到了 Android 的 speaker 通路定义（重要）

#### ROM 结构（之前漏看了，被 head -60 截断）

`/Volumes/caseSensitiveBar/Pro_user_V4.2.5/SEKSA-mol%odin-rom-4.1.0-odin-user-20180523-005028-32g/`
共 103 个文件。除了 boot.img / NON-HLOS.bin，**还有 `system_1.img` ~ `system_36.img`**
（system 分区切成 36 块，squashfs，数据未压缩 ⇒ **可以直接 grep 到文件内容**）。
另有 recovery.img / persist_1.img / splash.img / mdtp.img / 各种 .mbn。
`apps/` 是刷机工具，`full_flash/`、`fastboot-flash/`、`nv_image/`、`sparse_images/` 都是空目录。

#### 挖到的 Android mixer_paths（在 system_4.img，共 7517 个 <ctl name>）

**speaker 通路定义共 9 个版本，其中 7 个完全相同，只有两步：**
```xml
<path name="speaker">
    <ctl name="RX3 MIX1 INP1" value="RX1" />
    <ctl name="SPK" value="Switch" />
</path>
```
另外两个版本（不同机型）：
```xml
<!-- offset 59850985 -->
<path name="speaker">
    <ctl name="RX3 MIX1 INP1" value="RX1" />
    <ctl name="RX3 Digital Volume" value="79" />     ← 注意是 79，不是 124
    <ctl name="LINE_OUT" value="Switch" />
</path>
<!-- offset 60268837：tasha/WSA 版，本机不用 -->
<path name="speaker">
    <ctl name="SLIM RX1 MUX" value="AIF1_PB" />
    <ctl name="SLIM_0_RX Channels" value="One" />
    <ctl name="RX4 MIX1 INP1" value="RX1" />
    <ctl name="SPK DAC Switch" value="1" />
    <ctl name="COMP0 Switch" value="1" />
</path>
```

#### 对本机的推断

1. **`RX3 MIX1 INP1 = RX1` 与我们的做法一致**（说明 SPK 走 RX3 是对的，不是 RX1/RX2）
2. **`SPK = Switch` 这个控件本机不存在**（`amixer sget "SPK"` 报 Unable to find；本机含 SPK 的控件**只有 `SPK DAC`**）
   主线 msm8916-wcd-analog 把 SPK 做成了 DAPM widget（`SPK_OUT`），而 DAPM 里
   `SPK DAC`/`SPK PA`/`SPKR_CLK`/`SPK_OUT` **都已经是 On** ⇒ 这一步应已等价满足
3. **音量值差异值得注意**：Android 那一版用 `RX3 Digital Volume = 79`（-5dB），
   我们一直用 124（+40dB）。但实测 **79 / 100 / 124 三个值都无效**
   （播放时录到峰值 24 / 56 / 22，均不高于底噪 42）⇒ 音量也不是原因

#### 下一步（下一轮）

静态配置层面已经查无可查，剩下的只有两种可能：

a) **硬件连接与我们假设的通路不符** —— 例如本机扬声器实际接在 LINE_OUT 而非 SPK
   （Android 第二个定义就是 LINE_OUT 版）。可试把 LINE_OUT 通路拉起来
   （DAPM 里 `LINEOUT`/`LINEOUT PA`/`LINEOUT_OUT` 现在全是 Off）
b) **外部功放没被正确使能** —— 原厂只给了 `ext-pa-enable = gpio132`（已 out high）
   和 `spkr-sd-n-gpio = gpio96`（**sd-n 低有效，正常工作需拉低**；这根脚本机没管过）

⇒ 下一轮优先试：把 gpio96 拉低（可用 gpio-hog）+ 试 LINE_OUT 通路。

#### 一个实用技巧（可复用）

原厂 ROM 的 system 是 squashfs 但**数据未压缩**，所以不需要 simg2img/unsquashfs，
直接 `grep -a` 就能搜到 XML 内容；提取某个 <path> 的完整定义用 Python 找
`<path name="xxx">` 到 `</path>` 之间的字节即可。比先解包快得多。

### ⚠️ 我测试中的严重错误（必读，别再犯）

**`/tmp` 是 tmpfs，重启即清空。** 我多次重启设备后直接跑 `aplay /tmp/song.wav`，而文件早已不存在 —— `aplay` 报
`No such file or directory` 后立刻退出。**那些"播放"全是空放**，据此得出的
"链路全通但不出声"里，至少有一批数据是废的。

**修正后的重测（文件确实在，5.7MB，aplay 正常显示 Playing）：**
```
底噪（不播放）  : 峰值=11 平均=0
播放时录到      : 峰值=10 平均=0
```
⇒ **结论不变：扬声器确实不响。** 但从此以后，**每次重启后第一件事必须是重新上传测试音频**，
并用 `ls -l` 确认，再相信播放结果。

顺带记一个诊断手法：判断"播放到底有没有真的跑"，看 aplay 是否立刻返回 + 是否有 `Playing WAVE` 输出，
以及 `hw_ptr` 是否推进（详见前面一节）。

### 本轮其它实测结论

1. **gpio-hog 抢 gpio132 会让整个声卡消失**（`no soundcards`）
   ⇒ 反证 `aw8738` 驱动确实在依赖 `mode-gpios = <&tlmm 132>`。
2. **只 hog gpio96（拉低）不会破坏声卡**，重启后 `smartisan-odin` 正常注册；但也没带来声音。
3. 该内核**没开 sysfs GPIO**（`/sys/class/gpio` 不存在），也没有 `gpioset`/libgpiod 工具
   ⇒ 运行期改 GPIO 电平只能靠设备树的 `gpio-hog`。
4. Android 的 speaker 通路（从原厂 ROM 挖出）是 `RX3 MIX1 INP1=RX1` + `SPK=Switch`；
   本机有前者、**没有 `SPK` 控件**（只有 `SPK DAC`），但 DAPM 里 SPK 全链已 On。

### 收尾时的总状态

| 项 | 状态 |
|---|---|
| 触摸屏 | ✅ 可用（FT8716 + 主线 edt-ft5x06） |
| 蓝牙 | ✅ 可用（hci0 + bluez，扫到 10 台） |
| 麦克风 | ✅ 可用（INP3 主麦，用户听录音确认） |
| 扬声器 | ❌ 未通：静态链路全 On、数据流动、增益满、零报错，但物理不发声 |
| 视频 venus | ❌ 固件 HFI 握手 -EIO（协议不匹配） |
| GPS | ⏸ 需 modem + QRTR + rmtfs/tqftpserv |

### 扬声器剩下的两个方向（下一轮）

1. **功放型号** —— 原厂 DT 只有一个 `ext-pa-enable=gpio132`，没有型号；
   `awinic,aw8738` 是我们照抄 markw 的。请拆机看功放丝印。
2. **LINE_OUT 通路** —— Android 的第二版 speaker 定义走 `LINE_OUT` 而非 SPK；
   DAPM 里 `LINEOUT`/`LINEOUT PA`/`LINEOUT_OUT` 现在全 Off，值得拉起来试。

（注：设备当前跑的是 `odin-hog96.dtb【只 hog 了 gpio96】；要回到有声卡但不 hog 的状态用
`odin-audio-test.dtb`。）

## ================= 本轮收尾交接（2026-09-01 深夜，暂停） =================

### 成果（三项可用，均经真机验证）

1. **触摸屏** ✅ —— FocalTech FT8716，走主线 `edt-ft5x06`（`focaltech,ft8716`）。
   已固化进 `patches/0007`（`&i2c_3` + AW8738 之外还加了 4 个 pinctrl 状态。
   划屏能读到 `ABS_MT_POSITION_X/Y` 与 `BTN_TOUCH`，坐标落在 1080×1920 内。

2. **蓝牙** ✅ —— `hci0` 本来就存在（`btqcomsmd` 内核侧是现成的），只缺用户态的 `bluez`。
   已加进 `dist/build/setup-rootfs.sh`（基础包 `bluez`，gui 另加 `bluez-obexd`、
   `libspa-0.2-bluetooth`、`pipewire-alsa`）。实测扫到 10 台周边设备，控制器是
   public 地址（`02:00:67:DB:FE:B8`），**不需要**手工 `btmgmt public-addr`。

3. **麦克风** ✅ —— INP3 主麦能录到人声（用户听录音确认过），INP2 是降噪副麦几乎无声。
   采集通路（逐个试出来的）：
   ```
   MultiMedia2 Mixer TERT_MI2S_TX = 1     ← 关键！不是 PRI_MI2S_TX
   DEC1 MUX = ADC2、CIC1 MUX = AMIC、ADC2 MUX = INP3

### 未通

- **扬声器**：链路 DAPM 全 On、数据在流（hw_ptr 推进）、增益满（RX3=124=+40dB）、
  零报错，但物理不发声。放大 20dB 后重测仍听不到 ⇒ 之前"有一点点声音"是误听。
- **视频 venus**：固件 HFI 握手 `-EIO`（`hfi_parser` "Unsupported property"），
  是固件与驱动协议不匹配，不是缺文件。
- **GPS**：需 modem（`&mpss`）+ QRTR + rmtfs/tqftpserv + ModemManager，独立大工程。

### 设备当前状态（接手时注意）

- 跑的是 **`odin-hog96.dtb`**（在音频版基础上只加了 gpio96 的 gpio-hog，拉低）。
  `l0-safe` 指向它，重启后依然有效；但 `/tmp` 会被清空 ⇒ 任何播放测试都要先重新
  传音频文件。回到不带 hog 的版本用 `odin-audio-test.dtb`。
- 这些都是 `tmp/audio-test/` 下的**试验品**，**没有进 `patches/0007`**（除触摸屏外）。
  麦克风与扬声器的成果要固化，需要把 `&lpass`、`&sound_card`、`audio-codec@f000`
  的启用写进 `patches/0007` 并走 CI 验证。

### 重新开工的一句话

> 读 `WORKLOG.md` 最后几节，接着调 ODIN 的音频。第一件事：把 `&lpass`、
> `&sound_card`、`audio-codec@f000` 的启用写进 `patches/0007`（麦克风这条已验证），
> 走 CI 出正式版；扬声器按"功放型号"与"LINE_OUT 通路"两个方向继续查。

### 三条方法论（本轮踩过的坑，已单独立节详述）

1. `/tmp` 是 tmpfs，重启即清空 ⇒ 重启后必须先重传测试文件再信播放结果。
2. ftrace 在这个内核上不产出数据 ⇒ 任何"追踪不到调用"都要先用必调函数做对照。
3. dyndbg 对模块要用 `module <名> +p`，不是 `file <路径> +p`；且"没日志"推不出
   "代码没执行"。

另外：原厂 ROM 的 system 是未压缩 squashfs，直接 `grep -a` 就能搜内容，不用解包。

## ================= 2026-09-02 凌晨：视频硬编解码（venus） =================

- **00:22 T1 完成** — 定位到 venus probe -EIO 的真因：固件回的 SYS_INIT_DONE
  属性表**尾部一条被截断 8 字节**，而主线 `hfi_parser()` 把"声明长度超出报文余量"
  当成致命错误，直接放弃整个 core init，前面已解析的 78 条能力全部作废。

- 要点
  - 手段：给 venus 驱动临时加报文转储与解析跟踪（**只改 `tmp/linux-msm8953`，
    不进 `patches/`**，原文件留 `*.odin-bak`），抓到固件原始回包，离线用 Python
    逐 word 复现 `hfi_parser` 的游标推进 —— 与真机 89 步 trace **逐步对齐**，
    无一处游标不符。
  - 回包：`hdr.size=2576 pkt_type=0x20001 error_type=0x0 num_properties=76`，
    payload 2560 字节 / 640 word；驱动共走 89 步（真属性 79 个 + 零字 10 个）。
  - 断点（报文最后 4 word，0x0a00 起）：
    ```
    07 10 00 00  01 00 00 00  14 00 00 00  10 00 00 00
    ↑CAPABILITY  ↑num=1       ↑type=LCU_SIZE  ↑min=16
                              ← 缺 max 与 step_size，共 8 字节 →
    ```
    `rem_bytes=12 < ret=20` ⇒ `return HFI_ERR_SYS_INSUFFICIENT_RESOURCES`
    ⇒ `core->error != HFI_ERR_NONE` ⇒ `hfi_core_init()` 返回 `-EIO`（hfi.c:73）。
  - 修法（`patches/0009`）：这个情形当作属性表结束，`break` 出循环 +
    `dev_warn_once`，已解析的能力继续有效。TLV 遍历在"余量不足"时只能这么办。
  - `Unsupported property: 0` 只是 `dev_warn_once` 的**噪音**，不是致命错；
    那些 0 是固件插在属性之间的零填充（3 处：4/4/2 个 word），驱动走 default
    分支 1 word 1 word 地蹭过去，不受影响。别再被它带偏。

- **00:36 T1 附带结论** — **更正**旧判断"固件与驱动协议不匹配"：协议是对的，
  属性表也逐条解析成功了，只是末尾一条残缺。固件文件本身也**完全正确** ——
  真机 `/lib/firmware/venus.*` 与原厂 ROM 的 `NON-HLOS.bin`（裸 FAT16）
  里 `/IMAGE/VENUS.MDT + VENUS.B00~B04` md5 逐个相等（b02 `f9fb73a1…`、
  mdt `afb36166…`）。`venus.b04` 只有 32 字节（`0xdeadadd0` 填充），极易漏掉。

- **00:47 T1 附带结论** — 两条**被排除**的怀疑（别再查）：
  1. `msm8953.dtsi` 的 venus 节点定义了 `venus_opp_table` 却没有
     `operating-points-v2`（sdm845 有）—— **不是问题**。原因：V3 走
     `core_get_v1`，它只 `devm_pm_opp_set_clkname()`，从不 `dev_pm_opp_of_add_table()`
     （后者只在 `res->opp_pmdomain` 存在时才调，而 msm8953 没有 cx 电源域）；
     而 OPP 核心对**空表**有专门兜底（`drivers/opp/core.c:1435`）：
     `if (!_get_opp_count(opp_table)) return config_clks(...)`，
     即 `dev_pm_opp_set_rate()` 退化成 `clk_set_rate()`。所以时钟能调。
  2. HFI 版本要用 1XX 还是 3XX —— **用 3XX，不要改**。原厂 DT 明写
     `qcom,hfi-version = "3xx"`，且 `qcom,reg-presets` 三组寄存器与主线
     `msm8953_reg_preset[]` 逐字对应（主线就是照这份抄的）。

- **00:43 T2 完成** — 补 venus 固件的供给机制（此前是手工拷进 /lib/firmware 的）
  - `dist/build/initramfs/sbin/odin-venus-fw.sh` + `init` 里的钩子 —— 正确时序：
    venus 是 platform 驱动，开机早期就被 udev 加载并立刻 `request_firmware`，
    必须落在 `switch_root` **之前**（与 `odin-wlan-fw.sh` 同源同理，见 reports/021）。
  - `dist/build/rootfs/usr/local/sbin/odin-venus-fw.sh` + `odin-venus-fw.service`
    —— 用户态兜底。venus 是模块，缺固件导致 probe 失败后不会自己重试，
    取完固件重载即可；这条兜底让"已经刷好的机器"也能拿到能力。
  - 段文件数量随 ROM 版本可能变，两个脚本都**不写死列表**，把 `modem:/image/`
    下所有 `venus.*` 都搬过去（大小写不敏感，FAT 目录项是大写 `VENUS.MDT`，
    挂载后小写也可用）；校验只认 `venus.mdt`（段表在里面，qcom_mdt 按表取段）。

- **00:45 T3 完成** — 用户态：venus 暴露的是 **V4L2 M2M**（decoder/encoder 各占
  一个 `/dev/videoX`），**不是 VA-API**。装 `ffmpeg` + `v4l-utils`，
  FFmpeg 用 `-c:v h264_v4l2m2m` 调用。
  ⚠️ pmOS 的 `mesa-venus` 是 VirtIO-GPU 的 Vulkan 驱动（给虚拟机用的），
  与裸机 qcom venus **同名不同物**，不要装。
  另加体检脚本 `dist/build/rootfs/usr/local/sbin/odin-video-check.sh`
  （看固件/设备/格式 + 真跑一次编码再解回来）。

- **⚠️ 踩坑（我自己造的事故，必读）** — 调试代码里为了看环形队列状态，在
  `venus_isr_thread` 里 deref 了 `hdev->queues[IFACEQ_MSG_IDX].qhdr`，结果
  **空指针 Oops**（`q->q_size` 在结构里偏移正好 0xc，报错地址就是 `0000000c`），
  IRQ 线程 `irq/84-venus` 死掉；随后 `insmod` 卡在 D 状态（core->lock 被死掉的
  线程握着），`sudo reboot` 被它挡住没能完成 —— 设备停在"网络在（ping 通）、
  SSH 已停（connection refused）、telnet 救援端口也没开"的**半关机**状态，
  只能长按电源键。**已语音提醒。**
  教训：给内核加调试打印时，**不要 deref 那些"应该非 NULL"的内部指针**；
  而且这种半死状态比整机重启难收拾得多 —— 一旦 `rmmod`/`insmod` 卡住，
  后面所有验证都做不了，先想清楚再下手。

- 待办（设备回来后）
  1. 重传 `venus-core.ko`（已编好、只含 0009 的正式修复，无调试代码），
     `rmmod` + `insmod`，看 probe 是否成功、`/dev/videoX` 是否出现；
  2. 装 `ffmpeg` `v4l-utils`，跑 `odin-video-check.sh` 真编一帧再解回来；
  3. 把结论补进 reports/029，走 CI 出正式版。

## ================= 2026-09-03：venus 用户态判据修正（真机未动，只改代码） =================

背景：真机停在半关机状态（网络在、SSH 已停），用户指示**先不动真机、只修代码**，
等 CI 出包再刷。所以这一轮全部是静态核对 + 脚本修复，没有任何真机实测。

- **10:00 完成** — 拉主线源码（`770e10fa…`）到 `tmp/venus-review/` 静态核对，
  确认 `patches/0009` 落点正确、理由成立。
  - `hfi_msgs.c:269-276`：`hfi_parser(core, inst, pkt->data, pkt->hdr.size - sizeof(*pkt))`
    ⇒ `rem_bytes = 2576 - 16 = 2560`，与 reports/029 §4 的数字逐字对上。
  - `hfi_parser.c:388` 就是补丁改的那一行，上下文（switch 的各 case、循环
    `while (words < frame_size)`、`rem_bytes -= 4`）与补丁一致 ⇒ **补丁能干净应用**。
  - 顺带核对四项，**都排除**（写入 reports/029 §10.6，别再查）：
    `msm8953_res.max_load = 1036800`（非 0）、ICC 路径已拿到、
    `venus_enumerate_codecs()` 对 3XX 直接 return 0、模块名是
    `venus-core`/`venus-dec`/`venus-enc`（Makefile 实锤）。

- **10:15 完成（重要）** — 修掉 venus 用户态**两个真实 bug**，根源是同一个错误判据。
  - **踩坑（真机取证实锤）**：`compgen -G '/dev/video*'` 在本机是**恒真**判据。
    摄像头（CAMSS / `msm_vfe`）占着 `video0`~`video5`
    （`evidence/device-probe/05-hardware-full.txt:149-154`）。
    后果有两处，都很致命：
    1. `odin-venus-fw.sh` 的重载条件 `copied>0 && ! compgen -G '/dev/video*'`
       恒为假 ⇒ **模块重载分支从不执行** —— 用户态兜底（已刷机器唯一的补救
       路径）一直是死代码；
    2. 结果判定 `if compgen -G '/dev/video*'` 恒为真 ⇒ 日志永远谎报
       "venus 已就绪"，venus 完全没起来也报成功。
  - 正确判据（主线源码实锤）：设备名是驱动写死的 ——
    `vdec.c:1796` = `qcom-venus-decoder`，`venc.c:1584` = `qcom-venus-encoder`。
    摄像头 name 是 `msm_vfe*_video*`，不冲突。
    判据抽成共享库 `dist/build/rootfs/usr/local/lib/odin/venus-devs.sh`，
    两个脚本共同 source —— 这次的 bug 正是"两个脚本各写一套错判据"。
  - 顺带修 `odin-video-check.sh`：原来按发现顺序把第一个支持压缩格式的设备当
    decoder、第二个当 encoder，同样不可靠。

- **10:20 完成** — 重建 probe 改用 **platform driver 的 unbind + bind**，
  不再 `modprobe -r` + `modprobe`。
  理由：WORKLOG 记过一次事故 —— `insmod` 卡在不可中断的 D 状态（`core->lock`
  被死掉的 IRQ 线程握着），`sudo reboot` 被它挡住没能完成，设备停在"网络在、
  SSH 已停"的半关机状态，只能长按电源键。unbind/bind 不卸载模块，
  `struct module` 全程没动，没有这条路径。
  - **踩坑（写法上的）**：bind 的目标要从 `/sys/bus/platform/devices/` 找，
    不能从 `.../drivers/qcom-venus/` 找 —— probe 失败后驱动核心已经把设备解绑了，
    驱动目录是空的，但 platform 设备本身还在。写错就永远走不到 bind。
  - `modprobe` 保留为退化路径（`venus-core` 还没加载时，本服务跑在 udev 之前）。
  - 顺带把"固件齐了就 exit 0"改成"固件取完后一定检查 venus 是否真的起来了，
    没起来就重建 probe" —— 固件齐但 probe 一直失败正是这个服务存在的理由。

- **10:25 完成** — initramfs 侧 `check()` 防半套固件。
  原来只认 `venus.mdt`；若拷贝被断电打断，会留下只有 `.mdt` 的半套固件，
  而 `check()` 一直返回真、之后再也不补。现在额外要求至少一个 `venus.b*`
  （`.b04` 只有 32 字节、内容全是 `0xdeadadd0` 填充，最容易漏）。

- 验证（本机可做范围内的）
  - 四个脚本 `bash -n` 全通过。
  - 假 sysfs 树冒烟：混入 `msm_vfe*` 的 video0/video1 后，
    `odin_venus_devs` 仍精确输出 `dec /dev/video6`、`enc /dev/video7`，
    摄像头被正确忽略。
  - `check()` 语义：只有 `.mdt` 判"缺（需重取）"，有 `.mdt` + `.b00` 判"齐全"。

- 待办（设备回来后）
  1. 跑 reports/029 §7 的验证（`odin-video-check.sh`），把结果补进 §7；
  2. 走 CI 出带 0009 与本次脚本修正的正式版，刷入验证。

## ================= 2026-09-03 上午：启动/SSH 正确性排查（用户要求） =================

用户要求：排查"有什么会让设备无法启动或无法连到 SSH"的错误。真机未动，全静态核对。
结论是**三个问题，其中一个会让 v0.9.4-venus 刷了也白刷**。

- **11:00 完成（P0）** — initramfs 缺 **head** applet ⇒ venus/WiFi 固件永远取不到
  - 依赖 head 的三处：
    `initramfs/sbin/odin-venus-fw.sh:42`（part_dev 找 modem 分区）、
    `initramfs/sbin/odin-wlan-fw.sh:56`（同）、`initramfs/init:22`（usb_up 取 UDC）。
  - 缺 applet = 直接 not found、**不回退**。项目自己有实锤：ae85275 记过 v0.9.2
    缺 `cp` ⇒ initramfs 里 odin-wlan-fw.sh 静默失败 ⇒ WiFi 起不来且无报错。
  - **为什么一直没暴露**：0a07508 说过，odin-wlan-fw.sh 的 `--check` 因为固件
    已预置而直接返回 0，压根没走到 part_dev。而 **venus 固件没有任何预置途径**
    （构建脚本里没有任何往 /lib/firmware 放 venus.* 的地方，全靠 initramfs 现取）
    ⇒ part_dev 是必经之路 ⇒ 必挂。
  - 后果：venus 固件取不到 ⇒ venus 起不来；WiFi 固件同样取不到；
    initramfs 救援通道（telnet 172.16.42.2→23）也失效。
  - 修法：补 head（顺带补 kill；ash 里 kill 是内建，留着只是保险）。
    补完重扫三个 initramfs 脚本，命令已无缺失。
  - **方法论**：这类"缺 applet"是本项目反复踩的一类坑（cp、cmp、date/printf/
    rmdir/stat/tr、mktemp/readlink、现在是 head）。根因是名单靠手维护，而脚本
    失败都不致命 ⇒ 静默。以后新增/修改 initramfs 脚本必须同步核这份名单。

- **11:10 完成（P1，我自己引入的回归）** — venus 每次开机都重建 probe
  - 127b7b0 让 odin-venus-fw.sh 在"venus 没起来"时重建 probe，没限制次数。
    这台机器 venus 从没起来过 ⇒ **每次开机都重建一次**。
  - 而"venus 相关操作卡在不可中断状态、sudo reboot 被挡住、设备停在'网络在、
    SSH 已停'的半关机、只能长按电源键"是本机实锤记录的故障模式（reports/029 §7）。
    每次开机都撞一次 = 把小概率启动失败放大成每开机必赌一次。
  - 修法：只重试一次（`/var/lib/odin-venus-retried` 标记）；venus 真起来后
    自动清标记，将来再坏还能再自动重试一次。

- **11:20 完成** — 首刷默认改回 **l0-safe**（用户拍板）
  - extlinux.conf 在 ce27c95（09-02 20:56）被改成 `default l0`，但所有文档与
    AGENTS.md §8 决策表第 3 条一直写的都是首刷 l0-safe ⇒ 代码与文档脱节。
  - l0 依赖 Type-C 角色切换，而这条链路在 fc3e971（同日 23:05）被**整体重写**：
    删 FUSB301 与 SMBCHG OTG boost 两个内核补丁共 665 行、新增 qcom-smbchg 的
    usb-role-switch 补丁、改设备树 89 行与内核配置。**WORKLOG 里零验证记录。**
  - SSH 是唯一远程生命线：角色切换不工作 ⇒ 无 usb0 ⇒ 无 172.16.42.1 ⇒ 无 SSH，
    无屏设备只剩 UART。
  - README 的"双 label 引导"表格同步更新（原来写着 l0 是默认）。

- 顺带核对、确认没问题的（别再查）
  - `debootstrap --include=...ssh...` ⇒ sshd 在；`parted`/`e2fsprogs` 也在。
  - 扩容不需要 `growpart`：镜像是刷进 userdata 分区的，分区本就是全尺寸，
    只要 `resize2fs` 把 fs 撑满即可；`growpart` 失败是无害的（脚本也只记日志）。
  - initramfs 组装：`build-rootfs.sh:131` 是 `cp -a dist/build/initramfs/.`，
    sbin 下的脚本都会被收进去；applet 按清单建符号链接。
  - `pack_initramfs.sh` 打包整个 staging 目录，没有白名单会漏文件。

- **方法论教训（给自己）**：上一轮我改 odin-venus-fw.sh 时，只想着"让兜底真的生效"，
  没有反过来问"它现在会在什么条件下被触发、触发多少次"。补"自愈"逻辑时，
  **触发频率本身就是正确性的一部分** —— 一次性的补救和每次开机都跑的循环
  是完全不同的风险等级。

- **15:27 T? 完成** — USB 角色切换链路源码级排查：无功能性 bug，仅修 README 文档漂移
  - 核对对象：qcom-smbchg.c / dwc3-qcom.c / msm8953.dtsi（内核 commit 770e10fa）、
    patches/0007、dts/*-norolesw.dts、odin-usb-role.sh、99-odin-usb-role.rules、
    apply-staging-fixes.sh 生成的 odin-usb-gadget.{service,timer}、extlinux.conf、config-postmarketos。
  - 结论：fc3e971 的 USB 重写链路正确自洽。`msm8953.dtsi` 的 usb3 本就带
    `usb-role-switch` + `role-switch-default-mode="peripheral"`，smbchg 的
    `usb-role-switch=<&usb3>` 能解析到 DWC3 的 role switch；device 模式（SSH 那条）
    由 DWC3 默认 peripheral 保证 UDC 恒在，即便 smbchg 角色切换失效也不影响。
    唯一真问题：README 第 193 行"默认进 l0"与首刷默认 l0-safe 政策自相矛盾，已改。
  - **踩坑/补记**：WORKLOG 此前记 fc3e971"零验证记录"的担忧经源码核对可排除；
    但真机验证（fastboot 刷入后实跑）仍待补，本机 Windows 缺 fastboot 驱动暂未刷。

## ================= 2026-09-03 傍晚：v0.9.4-venus-applets 实刷 + venus 真机验证 =================

### 刷机：v0.9.4-venus-applets core 实刷真机，**验收 16/16 全通过**

- 从原厂 fastboot 起（`serialno 67dbfeb9`、`version 0.5`、只导出 cache/userdata/system
  三个分区、**没有 lk2nd 分区**），全程 4m23s：
  - `30 boot`：刷 `lk2nd` 分区失败（`partition table doesn't exist`）→ 自动回退
    `fastboot flash boot` → OKAY。**这正是原厂 fastboot 下的正确刷法**
    （`docs/02:156`、`reports/018:191` 都是这么写的），所以那条 warn 是正常的，
    不是故障。
  - `40 data`：sparse 分 3 块共 77.6s；`50 reboot` → USB 网卡 15s；
    `70 ssh` 90s；`80 verify` **16/16，失败 0**；根分区 112G（已扩容）。
- **这是 v0.9.4-* 系列第一次真机验收**，结束了自 09-01 电池版"刷入后失联"以来
  的无验证状态。

### venus：补丁 0009 在真机上成立，reports/029 §7 的判据全部满足

- dmesg 只有一条 `truncated property 0x1007: need 20 bytes, 12 left`，
  **没有 probe 失败** —— 与 0009 的预期逐字吻合。
- `/dev/video0` = `qcom-venus-decoder`、`/dev/video1` = `qcom-venus-encoder`
  （本镜像里 CAMSS 没开，摄像头不再占 video0~5）。
- initramfs 取固件成功（日志：`已取 venus.b00~b04 + venus.mdt ← modem`），
  证明 1365629 补的 `head` applet 生效了 —— 没有它 venus 与 WiFi 固件都取不到。
- 解码能力：H264 / HEVC / VP8 / VP9 / VC1 / MPEG4 / MPEG2 / H263 / XVID。
  编码能力：H264 / VP8 / HEVC / MPEG4 / H263。

### 用户实际用法：硬件编码必须加 `-pix_fmt nv12`，否则打不开编码器

用户原命令失败的真实原因是**三个独立问题叠在一起**，逐个排除（证据
`evidence/venus/final-commands.txt`）：

| 变体 | 结果 |
|---|---|
| 原命令 | ❌ `Could not find a valid device` |
| 只改音频 `-c:a aac` | ❌ `Encoder requires nv12 pixel format` |
| 只加 `-pix_fmt nv12` | ❌ `Could not write header`（pcm_s16le 不能进 mp4） |
| **video 组 + 两项都改** | ✅ 2539744 字节 / 7.3s |

1. **`user` 不在 `video` 组**：`/dev/video*` 是 `root:video 660`，
   `video:x:44:` 组成员为空 ⇒ ffmpeg 打不开设备 ⇒ 报 "Could not find a valid device"
   （它把打不开的设备直接跳过，报错信息完全不提权限）。已在真机上
   `usermod -aG video user` 验证通过，**还没进构建流程**。
2. **源是 `yuvj420p` 时 ffmpeg 不会自动转成 nv12**，必须显式 `-pix_fmt nv12`。
   对照：用 lavfi 生成 `yuv420p` 时 ffmpeg 会自动插 `auto_scale` 转成 nv12，
   所以这个问题在合成源测试里**暴露不出来**。
3. `-c:a copy` 把 `pcm_s16le` 塞进 mp4 不合法，与 venus 无关（软件编码同样报错）。

### 实测能跑通的档位（`-pix_fmt nv12`，源 1920x1440 HEVC）

- 硬件**解码** ✅：`ffmpeg -c:v hevc_v4l2m2m -i in.mov -f rawvideo -pix_fmt nv12 out.raw`
  → 149 帧 617932800 字节，**2.5 秒**。
- 硬件**编码** ✅：1920x1440 / 1280x720 / 854x480 / 640x480 / 320x240 全通过。
- 硬件编码 ❌：**1920x1080 稳定段错误**（rc=139，连续 3 次复现；内核侧无任何消息）。
- 硬解 + 硬编在同一条命令里（全硬件转码）❌ 段错误；分开跑各自都正常。

### 一次未定位的重启（19:41:38）

- 现象：SSH 断连，`up 1 min`。**不是** panic —— pstore 空、无 Oops、
  无 Call trace、无 `/dev/watchdog`；电池 61% / 4.07V / 28°C、温度 44~49°C，
  电池与热都正常。
- 已排除：
  - 纯 CPU 满载（8 路 `sha256sum` 跑 25s）→ 不重启；
  - 1920x1080 的段错误本身（`dmesg -w` 全程跟踪，零内核消息）→ 不重启；
  - 死亡那一刻正在跑的软件 HEVC 解码（干净状态下原样重跑）→ 618MB 正常产出。
- **唯一的相关前置状态**：19:28:50 有
  `qcom-venus 1d00000.venus: wait for cpu and video core idle fail (-110)`
  （我强杀了一个正占着编码器的 ffmpeg 留下的），19:36:21 我 unbind 时又触发
  `WARNING: venus/core.c:540 venus_remove+0xd8 x0=-22(-EINVAL)`
  （上游 `WARN_ON(ret < 0)`，`pm_runtime_get_sync` 返回 -EINVAL，**无害**）。
- 结论：**根因没抓到**。已复现不出来。唯一可复用的线索是"venus 被强杀后进入
  卡死态"这个高危前置条件 —— 与 reports/029 §7 记的"卡 D 状态、只能长按电源键"
  是同一类。以后调试 venus 时不要强杀 ffmpeg。

### 踩坑

- **`odin_sudo` 走的是 `sh`，而 Debian 的 `/bin/sh` 是 dash**：实测
  `sh -c 'echo ${@:3}'` → `Bad substitution`。所以往 `odin_sudo` 的 heredoc 里
  写 bash 数组语法会失败。调试时改用"scp 脚本上去再跑"（`tmp/venus-check/exec.sh`）。
- **`odin_ssh 'bash -s' < 本地脚本` 会被 ssh 吃掉行首字符**（`echo` 变 `ho`、
  `for` 变 `or`），必须改用 scp 传文件。
- 从 GitHub 下载要走 `env -u http_proxy -u https_proxy`（本机默认有
  `http_proxy=http://127.0.0.1:3030`）。core sparse 1.1GB 用 3m43s，可接受。
- macOS 没有 `timeout`：外层等待用 Python `subprocess.run(..., timeout=)` 包一层。
- 写后台采样器时别用裸 `wait` —— 它会把无限循环的采样器一起等进去，永远不返回。

## ================= 2026-09-03 晚：USB OTG 专题（外接 SSD 只亮灯、不出块设备） =================

### 结论：不是配置坏了，是设备跑在 `l0-safe` 上，而那个变体**原理上**不支持 OTG

真机只读诊断（`evidence/usb-otg/diag-02.txt`）：

```
/sys/firmware/devicetree/base/soc@0/usb@7000000  dr_mode=peripheral  usb-role-switch=no
/sys/class/usb_role/                             空
/sys/class/udc/7000000.usb                       存在（gadget/device）
/sys/bus/usb/devices/                            空
/dev/sd*                                        不存在
```

内核栈是齐的：`CONFIG_USB_DWC3=y`、`CONFIG_USB_DWC3_QCOM=y`、
`CONFIG_USB_ROLE_SWITCH=y`、`CONFIG_TYPEC=y`、`CONFIG_EXTCON=y`、
`CONFIG_USB_STORAGE=y`、`CONFIG_USB_UAS=y`、`CONFIG_BLK_DEV_SD=y`。

### 源码级根因（推翻 09-03 上午那份"链路正确自洽"的静态核对）

`drivers/usb/dwc3/core.c:1603 dwc3_core_init_mode()`：

```c
switch (dwc->dr_mode) {
case USB_DR_MODE_PERIPHERAL:  → dwc3_gadget_init()      /* 不注册 role switch */
case USB_DR_MODE_HOST:        → dwc3_host_init()        /* 不注册 role switch */
case USB_DR_MODE_OTG:         → dwc3_drd_init()         /* 才注册 */
}
```

role switch 只在 `drivers/usb/dwc3/drd.c:500 dwc3_setup_role_switch()` 里注册，
且只能由 `dwc3_drd_init()` 触发（`drd.c:546-548`，条件
`ROLE_SWITCH && device_property_read_bool(dwc->dev, "usb-role-switch")`）。

而 `dts/msm8953-smartisan-odin-norolesw.dts` 四件事全做了：
删 `&usb3` 的 `usb-role-switch`、删 `ports`、`dr_mode` 改 `peripheral`、
删 `&pmi8950_smbcharger` 的 `usb-role-switch`。

⇒ **l0-safe 下 DWC3 根本不会注册 role switch**，smbchg 的
`smbchg_check_role_switch()`（`qcom-smbchg.c:878`）重试 60 次后打出
`USB role switch is not found` —— 与真机日志逐字对应。

**早上那份核对错在哪**：只看了 smbchg 侧能解析 phandle（"能解析到 DWC3 的
role switch"），没看 DWC3 侧会不会去注册。方向反了。

### `l0` 的配置是齐的（这次逐项核过）

- `msm8953.dtsi:2299` —— `usb3` 节点自带 `usb-role-switch;` 与
  `role-switch-default-mode = "peripheral";`
- `patches/0007` —— `&usb3 { status = "okay"; dr_mode = "otg"; }`
- `patches/0007` —— `&pmi8950_smbcharger { usb-role-switch = <&usb3>; otg-vbus {...}; }`
- 用户态 —— `odin-usb-role.sh`（`want_role()` 读 extcon、`apply_host()` 解绑 UDC
  并停 dnsmasq、`apply_device()` 等 UDC 后重配 gadget）+ `99-odin-usb-role.rules`
  （UDC add/remove、typec change、extcon change 三个触发器，走 systemd 标签）
  + `odin-usb-gadget.service/timer` 看门狗。

事实来源是 PMI8950 SMBCHG 的 USB-ID 检测（不是 Type-C 芯片），由 `qcom-smbchg`
调 `usb_role_switch_set_role()`。**缺的一直是真机验证，不是配置。**

### 一条无效功（记下来别再试）

想让 l0-safe "彻底不碰 OTG"，试过去掉 DTS 里的 `otg-vbus` 子节点 —— **没用**。
`qcom-smbchg.c:1608-1626` 是 `devm_regulator_register()` 无条件注册，
`otg_rdesc.of_match = "otg-vbus"` 只用于匹配 init_data，删了子节点既不阻止
probe 也不阻止 OTG 尝试。要真禁掉得改驱动侧。

### 那次重启（外接 SSD 触发）

时序（上一轮 journal）：
```
20:14:34  qcom-smbchg: OTG regulator failure        ← 插 SSD，硬件尝试供 VBUS 失败
20:14:53  qcom-smbchg: USB role switch is not found ← 重试 60 次后放弃
20:16:05  重启
```
电池当时并非没电（事后 20:19 测得 77% / 4.13 V / 28 °C / charging / capacity 100%）。
用户是插回电脑才自动开机的。**根因未定位**，但已排除：非 panic（pstore 空）、
非热（44–49 °C）、非电池低电量。

### 顺带查出的电池信息两处不准

1. **能量值虚高约 14%**：upower 报 `energy-full: 15.4 Wh`，而 15.4 Wh ÷ 3.5 Ah
   = 4.4 V —— 它拿 `VOLTAGE_MAX_DESIGN`（充满上限电压）算的，不是标称电压
   （Li-ion 约 3.85 V）。按标称应为 **13.5 Wh**。`energy`/`energy-full`/
   `energy-rate` 全都偏高。
2. **电池健康度读不到**：uevent 只有 `CHARGE_FULL_DESIGN`（设计 3500 mAh，
   与 reports/025 一致），**缺 `CHARGE_FULL`（实测满充容量）** ⇒ upower 的
   `capacity: 100%` 是"设计值÷设计值"，**恒为 100%，反映不出老化**。
   真正可信的百分比（77%）是 PMIC fuel gauge 的 SOC。

### 本轮改动

`extlinux.conf` 的 `default` 从 `l0-safe` 改回 `l0`。理由：当初选 l0-safe 的
唯一前提是"SSH 是唯一远程生命线"，而**现在 WiFi 已打通**（实测可经
192.168.18.251 局域网 SSH 登录），这个前提不成立了；而 `l0-safe` 是原理上
不支持 OTG，留着它就永远用不了外接 USB 设备。
`l0-safe` 保留为救援 label。README §四/§七/§八 与 extlinux.conf 注释同步更新。

> ⚠️ `l0` 从未在真机上验证过。刷入验证需用户点头（属 AGENTS.md §7 不可逆级）。

## 2026-09-04 音频专项（续）：声卡 -22 与 ADSP 固件静默跳过

- **22:15 完成** — 定位到 `--- no soundcards ---` 的两个独立真因，都已修（待 CI 验证）
- 要点
  - **真因 A：`&sound_card` 从来没写过 `model`。** `sound/soc/soc-core.c` 的
    `snd_soc_register_card()` 开头就是 `if (!card->name || !card->dev) return -EINVAL;`，
    **不带 dev_err**；而 `snd_soc_of_parse_card_name()` 又把"属性不存在(-EINVAL)"吞成 0。
    于是整条 probe 一路顺利、最后一步静默 -22，dmesg 里只剩 driver core 那句通用的
    `probe ... failed with error -22`。上游所有 msm8953 板都写了 model。
    取 `smartisan-odin`（仓库 UCM 目录 `conf.d/smartisan-odin/` 就是照卡名匹配的）。
  - **真因 B：`dist/build/initramfs/sbin/odin-adsp-fw.sh` 以 100644 入的库。**
    initramfs 里 `[ -x /sbin/odin-adsp-fw.sh ]` 恒假 ⇒ 取 ADSP 固件那段**一次都没执行过**。
    判据：真机 `/lib/firmware` 里 venus.* / wcnss.* 是 `Jan 1 1970`（initramfs 放的），
    adsp.* 是 `Sep 4 20:40`（我手动跑用户态脚本放的）。
    `apply-staging-fixes.sh:193` 会按 `*/sbin/*` 补 0755，所以用户态那份反而没事 ——
    这层"自动补权限"把仓库里 100644 的事实掩盖了，initramfs 树不走它于是露馅。
  - 两层修法：脚本 git 模式改 100755；`build-rootfs.sh` 拷完 initramfs 树显式
    `chmod 0755 "$ISTAGE"/sbin/*.sh` —— 让"能不能执行"由构建步骤决定，而不是由
    `git add` 的姿势决定。
  - 用户态兜底的竞态：服务 40.0s 跑完，adsp remoteproc 40.5s 才注册，差 0.5 秒，
    每轮都只留下"没有找到 adsp remoteproc，跳过"。改成每秒轮询、最多等 40s。
  - 功放路由从 **OUTL** 取而不是 DRV —— 照抄主线 `msm8916-wingtech-wt88047`
    （同样 WCD + 同样 simple-audio-amplifier + 同样 enable-gpios）。
    09-03 那版"为绕开 VCC 故意从 DRV 取"的取舍作废：缺 `VCC-supply` 时
    `devm_regulator_get(dev,"VCC")` 解析成 dummy regulator，不挡路。
  - `MM_DL1` / `MM_UL2` 那三条板级路由**不需要** —— `q6asm-dai.c:1200` 的
    `SND_SOC_DAPM_AIF_IN("MM_DL1", "MultiMedia1 Playback", ...)` 带流名，
    ASoC 按流名自动连前端 DAI。mido/markw/tissot 那三条是历史遗留。
- **踩坑**
  - **改 diff 文件要用 Edit，old_string 必须带上行首的 `+`**。漏了 `+` 时 Edit 会
    **按子串匹配成功**，于是新插入的注释行少了 `+` 前缀、补丁立刻损坏
    （`git apply` 报 `补丁在第 831 行损坏`）。
  - 手改 patch 后 **`@@ -0,0 +1,N @@` 的 N 要重算**，且不能用"grep -c '^+' 全文件"
    （会把 Makefile 那个 hunk 的 3 行算进去）。正确做法：只数 DTS hunk 头之后、
    `-- ` 之前、且以 `+` 开头的行。本次 740 → 778。
  - 判断"某段 initramfs 代码到底有没有跑"，看产物的时间戳比看代码可靠：
    initramfs 阶段还没设 RTC，落地文件会是 `Jan 1 1970`。
  - `apply-patches.sh` 有一支"目标文件已存在 ⇒ 当作已打过、跳过"，
    所以本地改完 patch 后**直接重跑是看不到效果的**，必须先
    `git apply --check` 验证（要先把目标文件让位），再 `git apply` 真正打上。

## 2026-09-04（续）v0.9.4-audio-model 真机验证：声卡终于出来了

- **23:30 完成** — 刷入 v0.9.4-audio-model，验收 16/16；声卡注册成功、ADSP 开机自起
- 两个真因都被真机证实
  - `cat /proc/asound/cards` → `0 [smartisanodin]: smartisan-odin`；
    aplay 有 device 0/2/4（MultiMedia1/3/VoiceMMode1），arecord 有 1/4。
  - ADSP 固件时间戳从 `Sep 4 20:40`（我手动补的）变成 `Jan 1 1970`（initramfs 放的），
    与 venus/wcnss 一致 —— initramfs 那段之前**一次都没执行过**，现在执行了。
- 播放侧证据（播 1 kHz 时抓 debugfs）
  - 全链 On：AIF1 Playback → I2S RX1 → RX3 MIX1 → RX3 INT → PDM_RX3 → SPK DAC →
    SPK PA → SPK_OUT，且 `gpio132 : out high`（外置功放已开）。
- **控件名的陷阱（本轮最值钱的一条）**
  - `amixer scontrols` 走 alsa-lib simple 层，会把尾部 `" Switch"` / `" Volume"` 剥掉；
    `cset name=` 走原始元素名。两边不一样：
    `SPK DAC`↔`SPK DAC Switch`、`RX3 Digital`↔`RX3 Digital Volume`、
    `Ext Spk`↔`Ext Spk Switch`、`ADC2`↔`ADC2 Volume`。
  - 上游 apq8016-sbc 的 UCM 里 `RX3 Digital Volume` 写 **128**，本机上限是
    **124**（1 dB/档，84 = 0 dB）—— 写 128 直接 -EINVAL，
    **这才是 `alsaucm set _dev Speaker` 失败的真因**，不是文件结构问题。
- 采集侧：后端是 **Tertiary MI2S**（`MultiMedia2 Mixer TERT_MI2S_TX`），不是 Primary。
  写错时内核报 `MultiMedia2: ASoC: no backend DAIs enabled`，arecord 只给
  `Invalid argument`，完全看不出是混音器没配对。
- 麦克风扫描：DEC1 MUX 逐个试，只有 **ADC1（AMIC1）** 的录音能量明显高于本底
  （5.5 vs 1.2），ADC2/ADC3 与本底齐平，两个 DMIC 恒 0.0。
  ⚠️ 但用 1 kHz 谱线做 A/B 时 ADC1 上也没有明确的 1 kHz 分量
  （关 8.1 / 开 9.0）—— 那个 RMS 抬升更像整体噪声，不是收到了音。
  "主麦 = AMIC1"**待耳朵复核**。
- **踩坑**
  - `alsaucm set _dev` 在本机恒定 -EINVAL，**连上游 apq8016-sbc 的配置也一样**，
    而同样的 cset 用 `amixer cset` 逐条手工跑全部成功。已排除 Syntax 3/4、
    卡名写法、ConflictingDevice、空 EnableSequence、batch vs 单次。未定位。
    不影响 amixer 直接控音（播放/采集通路本身是通的）。
  - `alsaucm` 必须**在同一个进程里**先 `set _verb` 再 `set _dev`：
    每次单独调用 `alsaucm` 都是新进程，verb 带不过去。用 `-b -`（batch）喂一串命令。
  - 普通用户不在 audio 组时，`amixer -c 0 ...` 报的是
    `Invalid card number '0'` —— 看着像卡不存在，实际是打不开 controlC0。
    已把 user 加进 audio 组（setup-rootfs.sh）。
  - `sshpass` 偶发失败（弹 `ssh_askpass: exec(/usr/X11R6/bin/ssh-askpass)`），
    重试一次就好，别当成密码错了。
  - 刷机脚本 stage 10 的备份这轮又没拉回来（curl rc=7，连不上 172.16.42.1:8080），
    已知问题，不阻塞刷机。

## 2026-09-04（续二）人工听音：听筒与麦克风确认可用，只剩扬声器

- **23:50 完成** — 用户用 odin-audio-test.sh 跑完，结果已记进 reports/034 §7
- 结果
  - 听筒：3 秒提示音 ✅、**《暖暖》前 30 秒 ✅ 正常**
  - 麦克风：录 6 秒 **RMS ≈ 327**（本底 1~2），信号很强 ⇒ **采集完全正常**
  - 麦克风回放听不到 —— 因为回放走的是扬声器，不是采集的问题
  - 扬声器：提示音与音乐都 ❌ 没声音
- 由此得到的三个结论
  1. 听筒通了 ⇒ ADSP / q6afe / q6routing / 数字 codec / 模拟 codec 全都是好的，
     上游可以整段排除。
  2. **§6.5 里"主麦克风 = AMIC1 待复核"的疑问解除**。当时 RMS 只有 5.5 是因为
     **ADC1 Volume 还是默认 0**；脚本里设成 8 之后直接跳到 327。
     UCM 里 `DEC1 MUX = ADC1` 是对的。
  3. 扬声器的问题范围已经很窄：只可能在"SPK 那一条腿"或"外置功放"上。
- 下一轮的起点（第 7.2 节）
  - 我把扬声器接在 `SPK_OUT` 上，但主线 msm8916-wingtech-wt88047 的扬声器功放
    是**从 HPH_R 取**的。本机没有 3.5mm 耳机口，HPH_L/HPH_R 空着 ——
    外置功放很可能挂在它们上面。去原厂 mixer_paths_mtp.xml（reports/033 已解出）
    查证。

## 2026-09-05 扬声器不响的真因：功放是 AW87318，MODE 脚要打脉冲

- **00:03 完成** — 定位并修完，已推 v0.9.4-aw8738 触发 CI（run 33892957697），待听音确认
- 现象里最费解的一点：DAPM 全 On、`gpio132 : out high` 确实拉高了，**但就是没声**。
  "拉高"和"功放开了"之间还差一步。
- 原厂源码（ext/smartisan-kernel，msm8x16-wcd.c）给的答案
  - `/* lineout to AW87318 */` + `{"AW_SPK_PA", NULL, "LINEOUT PA"}`
    ⇒ **音频输入是 LINEOUT，不是 SPK_OUT**
  - `aw_speaker_pa_enable()` 在 POST_PMU：先拉高，再打 5 个 (低,高) 脉冲
    = **一共 6 个上升沿**；用的脚来自 `qcom,ext-pa-enable`，正是 DTS 里的 GPIO 132
  - ⇒ 这颗 AW 功放**靠 MODE 脚的脉冲个数选模式**，不是拉高就开
- 三条结论
  1. `simple-audio-amplifier` 只会把脚拉高 ⇒ 永远等不到模式脉冲 ⇒ 一直关着 ⇒ 没声。
     这正是"GPIO 是 high"与"没声"能同时成立的原因。改用主线自带的 `awinic,aw8738`。
  2. `awinic,mode = <6>`：上游驱动从 low 起打 `mode` 个 (0,1)，凑下游的 1+5=6 个上升沿。
  3. routing 改成 `"Speaker Amp INL", "LINEOUT_OUT"`；UCM 补 `cset name='LINEOUT' Switch`
     （LINEOUT 这个 mux 不打，功放输入端就没信号）。
- 两个干扰项（都排掉了，别再被带偏）
  - codec 里另一个 `Ext Spk` widget 走**电平**驱动，GPIO 由 `qcom,msm-spk-ext-pa` 指定 ——
    **整个原厂 DTS 树里没有任何一份定义这个属性**，对 ODIN 是死代码。
  - `mixer_paths_mtp.xml` 的 `<path name="speaker">` 写 `SPK = Switch`，看着像"走 SPK_OUT"。
    但那份 XML 是 **mtp 参考设计的通用配置**，`SPK` 指内部小喇叭；ODIN 的大喇叭在原厂
    由 `AW_SPK_PA` 承载。两者不是一回事 —— 我一开始照 XML 接 SPK_OUT，所以没声。
- **踩坑**
  - 往 DTS 注释块里贴 C 代码时，`/* ... */` 会造成**注释嵌套** ⇒ dtc 直接 syntax error。
    贴之前要把里面的 `/*` `*/` 去掉或改成 `#`。中过两次（`/* = 5 */` 和原厂那行注释）。
  - 改完 patch 一定要 `git apply --check` + 真编一遍 DTB，光看 diff 看不出注释嵌套。
  - `dts/*.dtb` 在 .gitignore 里（`*.dtb`），`git add dts/*.dtb` 会静默不生效、提交变成空操作。

## 2026-09-05（续）v0.9.4-aw8738 刷入后声卡注册失败：端点名 IN/OUT 不是 INL/OUTL

- **00:45 完成** — 定位并修完，已推 v0.9.4-aw8738-2 触发 CI（run 33896890250）
- 刷入 v0.9.4-aw8738 后**声卡直接没了**（比上一版更糟）：
      qcom-apq8016-sbc c051000.sound-card:
          ASoC: Failed to add route LINEOUT_OUT -> Speaker Amp INL(*)
          ASoC: Failed to add route Speaker Amp OUTL(*) -> Ext Spk
- ⚠️ **读这条报错要小心**：`(*)` 标的是**缺失的那一端**，不是"→ 左边那个"。
  所以我第一反应是"LINEOUT_OUT 不存在"，方向全错。实际缺的是 `Speaker Amp INL` / `Speaker Amp OUTL`。
- 真机上驱动那一侧都是对的（`audio-amplifier` 已绑到 aw8738 驱动、
  `awinic,mode` 读到 6、`snd_soc_aw8738` 模块已加载），是我把 widget 名写错了：

                    simple-amplifier        aw8738（本驱动）
      输入          INL / INR               IN     ← 只有一个
      输出          OUTL / OUTR             OUT    ← 只有一个

      sound/soc/codecs/aw8738.c:
          SND_SOC_DAPM_INPUT("IN"),
          SND_SOC_DAPM_OUT_DRV_E("DRV", ...),
          SND_SOC_DAPM_OUTPUT("OUT"),
          routes: IN → DRV → OUT

  我沿用了之前 `simple-audio-amplifier` 的 INL/OUTL（当时确实对），换驱动没跟着改。
  加 sound-name-prefix "Speaker Amp" 后实际名字是 `Speaker Amp IN` / `Speaker Amp OUT`。
- 改两处（`"Speaker Amp INL"` → `"Speaker Amp IN"`，`"Speaker Amp OUTL"` → `"Speaker Amp OUT"`），
  hunk 头 808 → 816，DTB 重编 63431 / 63279 字节。
- **踩坑**
  - 换 codec 驱动时，**DAPM 端点名不是通用的**，必须重新看目标驱动的
    `snd_soc_dapm_widget` 数组，不能沿用上一个驱动的写法。
  - 刷机 stage 20 这次没能自动进 fastboot（改名 extlinux.conf 后重启，420s 没等到），
    最后靠用户手动按【音量减+电源键】进的原厂 fastboot，然后 `--from 30` 续刷成功。
    远程进 fastboot 那条路不是每次都灵。

## 2026-09-05 里程碑：扬声器 / 听筒 / 麦克风全部打通

- **07:50 完成** — v0.9.4-aw8738-2 刷入，验收 16/16；用户听音确认**扬声器、
  听筒、麦克风全部正常**。整机音频链路打通。
- 从"一条声卡都没有"（2026-09-04 早上）到全通，一共卡了四处，每一处都是
  **不带日志**或**报错会带偏**的那种：
  1. `&sound_card` 缺 `model` ⇒ `snd_soc_register_card()` 静默 -EINVAL
     （dmesg 只有 driver core 那句通用的 `failed with error -22`）
  2. initramfs 取固件脚本 git 模式是 100644 ⇒ `[ -x ]` 恒假 ⇒ ADSP 固件从未就位
     （`apply-staging-fixes.sh` 会给 rootfs 里的 sbin 脚本补 0755，把这事实掩盖了）
  3. 外置功放是 AW87318，MODE 脚要打 **6 个脉冲**才开机，不是拉高就开
     （表现：DAPM 全 On、GPIO 132 确实是 high、可就是没声）
  4. aw8738 的 DAPM 端点是 **IN / OUT**，不是 INL / OUTL；照 simple-amplifier
     写两条路由全 ENODEV，**声卡直接注册不起来**（v0.9.4-aw8738 的教训）
- 这四处共同的特点：**看内核源码能确认，但看日志看不出来**。真正省时间的是
  原厂开源内核（`ext/smartisan-kernel`）和原厂 `mixer_paths_mtp.xml`——
  机器自带的配置才是权威，比猜和比照抄同 SoC 的其他板子都靠谱。
- 用户实测撞到的小坑：**`RXn Digital Volume` 不是百分比**
  - `min=0 max=124`，**84 = 0 dB**，1 dB/档。填 30 = **−54 dB**。
  - 表现：音量调到 30，扬声器还勉强有声，**听筒完全没声** —— 像听筒坏了。
  - 主线**没有** `EAR PA Gain`（下游有）；原厂 handset 是 `RX1 Digital Volume=84`
    **加** `EAR PA Gain=POS_6_DB`，缺的 6 dB 只能由数字音量补 ⇒ UCM 听筒给 90。
  - 测试脚本改成扬声器/听筒各存各的音量（VOL / EVOL），所有显示处换算成 dB。
- 刷机：这回 stage 20（远程改 extlinux.conf 再重启落 fastboot）**自动成功**了，
  上一回超时 420s 需要手按【音量减+电源键】。同样的流程，结果不同 —— 待观察。

## 2026-09-05（续）更正：UCM 从来没坏过，是我命令用错了；麦克风客观确认

- **麦克风客观确认**（扬声器/听筒通了之后这个测试才做得出来）
  - 让扬声器播 1 kHz 同时录：1000 Hz 谱线 **关 7.8 → 开 7342.4**（约 940 倍），
    整体 RMS **81.3 → 5635.5**（约 69 倍）。扬声器确实在发声、麦克风确实收到了。
  - 这个测试在 v0.9.4-audio-model 时做过一次，开/关都是 8~9 —— 当时是扬声器
    不响（功放脉冲模式没对），不是麦克风的问题。
- **更正 §6.6：`alsaucm set _dev` 不是 bug，是我用错了 identifier**
  - alsa-lib 1.2.8 `src/ucm/main.c` 的 `snd_use_case_set()` 只认
    `_fboot/_boot/_defaults/_verb/_enadev/_disdev/_enamod/_dismod/_swdev/<x>/_swmod/<x>`
    —— **没有 `_dev`**，所以必然 -EINVAL，对任何配置任何机器都一样。
  - 改用 `_enadev` / `_disdev` 后一切正常：Enable/DisableSequence 都能执行
    （实测 Speaker 的 RX3 MIX1 INP1 / LINEOUT / Ext Spk 三条都被正确开关；
    听筒的 RX1 MIX1 INP1 / EAR_S / Earpiece 同样）。
  - 两个当时误导我的细节：
    1. 跨进程时 `_disdev` 报 ENOENT —— alsaucm 每次调用都是新进程，active 列表
       是空的。用 `-b -` 把一串命令喂进同一进程。
    2. `set_device()` 开头有幂等短路（`device_status()==enable` 就直接 return 0，
       不跑序列）。我测出"disdev 没生效"是因为同一串里又 `set _verb HiFi`
       把 active 列表清了。
  - 教训：日志里"Invalid argument"且**换任何配置都一样**时，先怀疑**自己用的
    API/命令**，而不是怀疑配置。读源码比继续做黑盒对照实验快得多。
- 音量百分比映射（已做进测试脚本）
  - 原来让用户直接填原始值 0~124（84 = 0 dB），容易被当百分比：填 30 实为
    −54 dB，扬声器勉强有声、听筒直接静音，用户实测撞到过。
  - 现在按**百分比**输入、内部换算，同时显示原始值和 dB：
    0%→0（−84 dB） / 68%→84（0 dB） / 100%→124（+40 dB）。
    保留 `r<数字>` 直通原始值。

## 2026-09-05 内存与 swap 两个问题（详见 reports/035）

- **内存 4 GiB 只识别 3.46 GiB —— 不是故障，是这台机器的正常水位**
  - 3840 MiB：bootloader 只把 0x10000000..0x100000000 报成 RAM（两个 bank：
    0x10000000+1792MiB、0x80000000+2048MiB，其实首尾相接）。低 256 MiB 没报。
    `msm8953.dtsi` 里 memory 节点基址写死 0x10000000，大小由 bootloader 填。
  - −205 MiB reserved-memory（modem/mpss 106 占大头，还有 other-ext 30、
    cont-splash 20、adsp 17、qseecom 8、wcnss 7、venus 7、ramoops 1 …）
  - −32 MiB CMA，−58 MiB 内核自身 ⇒ MemTotal 3629956 kB = 3.46 GiB
  - 可抠的只有零头：cont-splash 我们只用 6.2 MB 却预留 20 MB（补丁里没改写这个节点，
    所以还是 dtsi 的 20 MB）；CMA 32→16。不值得为十几 MiB 重刷。
  - **⚠️ 读 /proc/device-tree 的 reg 时，`od -tx8` 在 ARM64 上按小端解释会骗人**
    （会把 0x0000000010000000 显示成 0000001000000000）。必须用 `-tx1` 逐字节看。
- **swap 一直是 0 —— 两个毛病叠在一起**
  1. **unit 被 systemd 静默丢弃**：`sysinit.target → odin-swap → firstboot-resize
     → multi-user.target → sysinit.target` 成环（swap 服务 After 了一个属于
     multi-user.target 的单元）。systemd 的破环手段是把本 unit 整个丢掉 ⇒
     脚本一次都没跑过，journal 0 条、日志不存在、status 是 `inactive (dead)`。
     指纹：`Type=oneshot`+`RemainAfterExit=yes` 成功跑完应是 `active (exited)`。
  2. **swapfile 在本机根本建不起来**：根分区 ext4 为 lk2nd 能读 extlinux.conf
     而 `mke2fs -O ^extents`，而 swapfile 走 iomap **需要 extents**。对照实验：
     块设备(loop)✅、zram✅、带 extents 的 ext4✅、根分区(无 extents)❌。
     失败时内核不打任何日志，只剩 `Invalid argument`。
- 改用 zram（CONFIG_ZRAM=m 已有，实测可用）：不写 eMMC、不碰磁盘（环自动消失）。
  1 GiB 逻辑容量 / 优先级 100 / 可 ODIN_ZRAM_SIZE 覆盖。swappiness 20→80。
  实测重启后 `Swap: 1.0Gi`、服务 `active (exited)`、journal 有记录。

## 2026-09-05 lk2nd 只读 extents 专项完成并刷真机成功（详见 reports/036）

- **结果：引导成功，swap 起来了 4.5 GiB，声音正常。刷机验收 16/16。**
- 做了什么
  - `lk2nd/0005`（新补丁，3 文件 +194/−2）：给 ext2 驱动加只读 ext4 extents 支持
    - ext2_fs.h 补 ext4 常量与结构体（数值按内核 fs/ext4/ext4.h / ext4_extents.h 逐条核对）
    - ext2.c 补 incompat 门禁（原来完全不检查 —— 遇到不支持特性不会拒绝，而是读文件时
      用间接块方式解析 extent 树，读出**错误块号**而不是报错，比拒绝更难查
  - io.c 新增 ext2_extent_lookup()，按 eh_depth 逐层下钻；i_block 未经 endian_swap_inode
    （那里刻意跳过块指针），字段自己套 LE16/LE32；i_flags 过了 LE32SWAP，是主机序
  - 顺带修 UB：pos[4] 未初始化 + LTRACEF 读 pos[1..3] ⇒ clang -O1 下 level 变垃圾
    （本该 0，实测 3），本来能读的文件读不出来。-O0 与 -O1+sanitizer 都正常，是只在
    特定编译配置现形的 bug。
  - Makefile：0005 加进**第一组**补丁（它影响完整版和精简版，必须在编完整版之前打上）
  - build-image.sh：extents 由「关」改「开」，自检改成正向断言
  - odin-swap.sh 重写：swapfile 4 GiB（优先级 10）撑峰值 + zram 512 MiB（优先级 100）打底
  - odin-swap.service：改挂 multi-user.target（建 swapfile 依赖 resize2fs，挂在 sysinit 会成环）
- **宿主机仿真台 `tools/lk2nd-fs-sim`（新，已入库）—— 这个专项最值钱的东西**
  - lk2nd 的 ext2 驱动只依赖 6 个函数（bio_read + 5 个 bcache_*）和 dprintf ⇒ 能整个搬到
    宿主机编译。迭代从「刷机 5 分钟 + 变砖风险」变成「本地秒级」，还能做回归与矩阵测试
  - build.sh 先把补丁打进源码副本再编译 —— **测的就是真正会编进 lk2nd.img 的那份代码**
  - 矩阵：无 extents / 开 extents × 小文件(167B) / 大文件(30MiB 连续) / 稀疏(64MiB 含洞)
    三种文件两种配置 fnv1a 校验和**完全相同**；稀疏文件 extent 树 depth=1，索引层下钻被走到
    16392 次。NOPATCH=1 可复现改前失败做对照
  - 刷机前用它直接读 CI 产出的真实镜像：新旧镜像的 /extlinux/extlinux.conf 校验和一致
- 调研时决定工作量的两个发现
  1. build-image.sh 的 -O **已经关掉了 64bit / metadata_csum / huge_file / dir_nlink /
     extra_isize**，只差 extents 一个 ⇒ 不用处理 group descriptor 布局变化与校验和
  2. ext2 驱动挂载时只校验 ro_compat，完全不检查 incompat（见上）
- 真机：根分区 extents 已开、swapfile fallocate 秒级建成（无 extents 时 fallocate 不可用，
  只能 dd 写 4 GiB。这也是开 extents 的直接好处）。声卡、扬声器/听筒 DAPM 链都正常，
  用户听音确认声音正常。
- 顺手修：刷机验收的「DSI 已使能」会随机失败（SSH 一通就查，DRM 还没 modeset）。改成等最多 20 秒再判。
- **根分区还剩 5 个 ext4 特性没开**：64bit（lk2nd group desc 按 32 字节读）、metadata_csum
  （ro_compat 白名单卡住）。huge_file / dir_nlink / extra_isize 影响为零（实测 crtime 都没丢）。
  唯一有实际收益的后续项是 metadata_csum（lk2nd 只读不需真校验，放开白名单即可，能检测元数据损坏）。

## 2026-09-05 根分区开 metadata_csum，以及 v0.9.4-csum 的 CI 失败真因

- **CI run 33938156357：dtb / kernel / lk2nd 全过，rootfs（core 与 gui 两条）都失败。
  镜像本身是对的，是 build-image.sh 的自检把自己判死了。**
- 失败输出里的自相矛盾是线索：

      extent         OK
      metadata_csum  OK
      ro_compat      0x403 (masked 0x400)
      lk2nd mountable WILL REFUSE
      e2fsck -fn     clean
      check_sparse   IDENTICAL

  特性名清单说 metadata_csum OK，位掩码那边又说不行。
- 真因：build-image.sh 里有**两处**独立判断 lk2nd 能不能挂
  1. 正向断言 `for want in extent metadata_csum`（特性名清单）—— 上一版 dfebe72 改了
  2. 一行硬编码位掩码 `MRO=$(( RO & ~3 ))` —— **漏了**
  `~3` 只放行 sparse_super(0x1) 与 large_file(0x2)，正好挡掉新放行的 metadata_csum(0x400)。
  0x403 是补丁 0006 之后的**期望**组合。
- 修法：`~3` 换成按位命名的 `RO_ALLOWED = 0x1|0x2|0x400`，与 lk2nd 0006 的
  `EXT2_FEATURE_RO_COMPAT_SUPP_READONLY` 对齐；并把这条教训写进注释。
- **踩坑：同一件事在两个地方判断，改一处漏一处。** 而且这两处性质不同——特性名清单
  是给人看的描述，位掩码才是 lk2nd 真正的挂载门槛。描述改了、门槛没改，表现就是
  "明明都 OK 却判失败"，比直接报错难查。
- 宿主机按位核对（tmp/audio/verify-mask.sh）：0x403 → masked 0x0 放行；
  反向回归 huge_file(0x08) / dir_nlink(0x20) / extra_isize(0x40) 全部仍 WILL REFUSE；
  边界 0x003 仍 OK。
- 另两处描述同步：`docs/01-复现构建.md:275` 的约束表、`tools/lk2nd-fs-sim/test-csum.sh`
  的头部注释（仍把 0006 写成待办）。
- 重发为 pre-release **v0.9.4-csum-gate**（版本号严格递增，不回头改旧号），run 33940084505。

## 2026-09-05 v0.9.4 正式发布（首启 15min39s → 63s）

- **首启耗时：63 秒**（12:05:57 reboot → 12:07:00 SSH 可达）。修之前 15min39s。
  `Startup finished in 16.679s (kernel) + 38.427s (userspace) = 55.107s`
- 阶段 80 验收 **16/16**；`odin-fs-verify.sh` **14/14**。
- 关键证据：本次启动只挂载过 `mmcblk0p57`（根）与 `mmcblk0p24`（persist，取 WiFi
  校准数据）——**没有 p53/p54** ⇒ initramfs 找根走的是快路径，没掉暴力扫描。
- 改了三处（详见提交 f211334）
  1. 找根第 1 顺位改按 **GPT 分区名 userdata**（读 sysfs PARTNAME），不用读超级块、
     与 mmcblk0/1 编号无关。原来 findfs 与 devtmpfs 建节点一撞车就掉进扫 57 个
     分区，而整轮扫描在**一次函数调用里**跑完，把 30s 重试循环钉死 2 分钟。
  2. 暴力扫分区挪出循环（只在 30s 窗口失败后跑一次）+ `blkid -s TYPE` 筛掉非 ext4
     ⇒ 真机实测要 mount 的次数 **57 → 5**。
  3. 三段固件的 remount/sync 合并成一轮；三个 fw 脚本里 `copy_from` 的全局 sync
     去掉（sync 是全局的，会把根分区所有脏页一起刷，init 抽完统一 sync 一次就够）。
- **踩坑（判据写糙）**：`odin-fs-verify.sh` 首跑把 p24 persist 当成"退化到暴力扫
  分区"的证据。其实取 WCNSS 校准数据每次都要挂它。改成按 PARTNAME 排除
  persist/modem 之后才对。教训：写判据时先问"这个值在正常情况下会是什么"。
- **踩坑（环境）**：宿主默认 shell 是 zsh，**未加引号的 `$OPTS` 不做词分割**，
  整串 ssh 选项被当成一个参数传给 ssh，报 "keyword stricthostkeychecking extra
  arguments at end of line"。脚本是 bash 不受影响，但我手敲命令踩了两次。
  另：`sshpass` 时灵时不灵（有时走 ssh_askpass 然后 Permission denied），
  走脚本自己的 `odin_sudo` 通道就稳。
- 发版：`v0.9.4`（干净三段式，非 Pre-release），CI run 33943856041 排队中。
  之前一共走过 27 个后缀版，收敛路径写在 Release 说明里。

## 2026-09-05 lk2nd 专题：按键真机验证通过，引导失败自动停 fastboot 仍未解决

### 已确认修好：按键（补丁 0008）

用户在真机菜单上实测：音量上 / 音量下 / Home 都能用了，方向也对。
根因与修法见提交 55623e6。要点：三个键全是 TLMM GPIO（85/86/87，低电平有效），
原厂还把 PMIC 的 RESIN 显式 disable 了，所以 lk2nd 默认的
`target_volume_down() -> pm8x41_resin_status()` 恒为 0，音量下必然没反应。

### 仍未解决：找不到可启动 fs 时不会自动停在 fastboot（补丁 0007）

现象照旧：改名 extlinux.conf 之后设备反复重启，必须人工按键才能停在菜单。

已排除的：
- 不是 watchdog。`project/msm8952.mk:118 ENABLE_WDOG_SUPPORT := 0`，
  且 lk2nd 在 `target/msm8953/init.c:496` 就 `pm8x41_clear_pmic_watchdog()`。
- 补丁确实编进去了。产物里能搜到 "Reverting to fastboot" 与 gpio-keys 节点，
  DTB 里 lk2nd,code = 0x115/0x116/0x122、gpios pin 85/86/87 flags 0x11 逐字节核对过。

实测到的 boot 分区决定性事实：/dev/mmcblk0p21 里有 **4 个原厂 ANDROID! 镜像**，
偏移 0 / 271236 / 524288 / 787184。这正是 `boot_linux_from_mmc()` 会去引导的东西。

### 这轮踩到的环境与流程坑（记下来，下次别再踩）

1. **本机有两种 fastboot，别混**：
   - 原厂 aboot 的：`kernel:lk`、`version:0.5`、只有 cache/userdata/system 三个分区，
     **没有 lk2nd 分区名**。`fastboot flash lk2nd` 在这里会报
     "partition table doesn't exist"。这里要刷 lk2nd 用 `fastboot flash boot`
     （原厂视角的 boot 就是物理偏移 0，正是 lk2nd 所在）。
   - lk2nd 自己的：会导出 `lk2nd` 分区（= boot+0..512KB）并把 `boot` 指向 512KB。
     `dist/FLASH.md` 里写的手动刷法 `fastboot flash boot lk2nd-odin.img` 是**原厂那个**。
2. `fastboot reboot` 之后立刻 `fastboot devices` 会看到设备还在（假阳性）。
   要先等它消失，再等它出现，否则结论是错的。
3. macOS 的 `nc -z` 也会假阳性（报端口通，实际 python connect 是 refused）。
   判端口通不通用 python socket。
4. 验一串补丁能不能应用**不能用 --dry-run 串起来**：前一条没真落盘，
   后一条要改的文件还不存在，`patch` 会挂住等我从 stdin 输入文件名 —— 白等 3 分钟。
5. 复制子模块源码要排除 .git（它是个 gitlink 文件，指向父仓的 .git/modules），
   否则在副本里跑 git 会报
   "not a git repository: .../gen/../../.git/modules/ext/lk2nd"。

## 2026-09-05（续）lk2nd 三个问题全部解决

### 结论：三个都修好了

1. **按键**（补丁 0008）—— 用户真机实测通过：音量上/下、Home 都能用，方向也对。
2. **UI 文案** —— 屏幕第二行 `23.1-nomarkw-odinport` → `23.1-odin`；
   文件名 `lk2nd-nomarkw.img` → `lk2nd-odin.img`（连带 flash 脚本、CI 校验、8 个文档）。
3. **引导失败不再反复重启**（补丁 0007 + 0009）—— 擦掉 userdata 后重启，
   设备 48s 进 fastboot，**稳住 120 秒没重启**。

### 中间走了很长一段弯路，根因是我自己把测试弄脏了

13:37 那次 `fastboot flash userdata` 被超时中断，但它**已经把 extlinux.conf 写回去了**。
于是后面每一轮"改名 extlinux.conf → 重启"其实都没真的禁用掉：
lk2nd 照样找到配置、去引导 Linux，而那个文件系统是半截的 → kernel panic → 复位。
**我观察到的所有"循环"都是坏 userdata 造成的，不是 lk2nd。**

教训：做 A/B 验证之前先确认前置状态真的成立了，别只看"我发过命令"。
（`fastboot erase userdata` 比"改名配置"更干净 —— 直接让可启动 fs 不存在，
不会被之前残留的内容干扰。）

### 0007 到底修的是什么

擦掉 userdata 之后，lk2nd 扫不到任何可启动 fs。上游在这里只打一行日志就返回，
aboot 接着走 `boot_linux_from_mmc()`，去引导 boot 分区里的原厂安卓镜像
（/dev/mmcblk0p21 实测有 **4 个 ANDROID!**，偏移 0 / 271236 / 524288 / 787184）——
那个镜像挂不上 system 就复位，于是无限循环。0007 让它在扫不到时直接 goto fastboot。
注意 `if (!boot_into_fastboot)` 是在 `lk2nd_boot()` **之前**判的，所以必须在之后
重判一次，否则置位也没用。

### 0009 修的是什么（菜单默认项是 Reboot）

`menu_options[0]` 是 Reboot，而 `sel` 初值是 0。菜单画出来之后只要 wait_key()
返回一个确认键，就执行 `opt_reboot` → reset。KEY_POWER 在这台机器上没有 GPIO
（原厂放在 PMIC PON 上），只能退回 `pm8x41_get_pwrkey_is_pressed()`，这条路径不可靠
（已排除另一个可能：`lk2nd,single-key-navigation` 只在三台 msm8226 上设了，我们没有）。
改成默认选中 Continue 之后，同一个事件只会"再试一次引导" ——
不是修"为什么会误触发"，而是修"**误触发的后果不该是复位**"。

### 补充：块设备编号这次又漂了

上一版是 mmcblk0p57，这版是 mmcblk1p57 —— 正好印证改用 GPT 分区名找根是必要的。

### 真机验收（刷回系统后）

`odin-fs-verify.sh` **14/14 全过**；`Startup finished in 16.859s (kernel) +
32.037s (userspace) = 48.896s`；swap 两级 4607 MiB。

## 2026-09-05（再续）新推断：lk2nd 是在"扫描分区"时崩的，不是引导失败路径的问题

### 推翻之前的结论

之前我说"擦掉 userdata 后稳住 120 秒 = 循环打破"，这个结论**站不住**：
那次观察被三件事污染 —— 坏掉的 userdata、后来才发现的 cmd_continue 里
`fastboot_stop()` 位置错误、以及我没确认停在哪一种 fastboot。用户当场指出来了。

### 关键实测（14:19 之后）

- `evidence/flash-state.env` 显示 `extlinux_disabled=1` 写于 **14:19** →
  确认改名成功，设备确实没有可启动配置。
- 但设备仍然循环，而且**菜单一次都没出现过**；主机连续 6 分钟
  `fastboot devices` 完全看不到设备。
- 用户按住所停下的菜单，屏幕上能看到 lk2nd 的版本信息。

### 新推断：崩在扫描阶段

| 场景 | 有没有扫描 | 结果 |
|---|---|---|
| 正常启动 | 有 | 画开机画面 → 扫描 → 崩 → 复位（循环，菜单从不出现） |
| LK2ND_FORCE_FASTBOOT=1 | **跳过** | 菜单正常显示 |
| 擦掉 userdata | 没有分区可扫 | 不崩 → 0007 → fastboot，稳定 |

三条互相印证：0007 大概是对的，但它前面那次扫描就崩了，根本轮不到它执行。

### 已排除的

- 不是 watchdog（`ENABLE_WDOG_SUPPORT := 0`；lk2nd 早期 `pm8x41_clear_pmic_watchdog()`）
- 不是 `lk2nd,single-key-navigation`（只在三台 msm8226 上设了）
- 不是符号问题：`nm build-lk2nd-msm8953/lk` 里 `boot_into_fastboot` 只有一个
  BSS 全局符号，`extern` 解析正确
- 不是宏没开：`config.h` 里 `WITH_LK2ND_BOOT 1`
- 代码位置也对了：构建树的 `normal_boot:` 段确实是
  `lk2nd_boot(); if (boot_into_fastboot) goto fastboot;`

### 下一步：带屏幕标记的诊断版（已编好）

`tmp/lk2nd/diag2`（干净源码树 + 0001..0009），额外加了 5 个屏幕标记，
`display_fbcon_message()` 只在 `ENABLE_FBCON_LOGGING` 打开时输出，而项目里
`project/msm8952.mk:148` 已经是 `=1`，所以会真的画出来：

| 标记 | 位置 |
|---|---|
| M1 | `lk2nd/boot/boot.c`，`lk2nd_boot()` 入口 |
| M2 | 同文件，`lk2nd_scan_devices()` 末尾置位之后 |
| M3 | `app/aboot/aboot.c`，`fastboot:` 标签之后 |
| M4 | `lk2nd/device/menu/menu.c`，菜单头部画完之后 |
| M5 | 同文件，`wait_key()` 返回后（会打印按键码） |

用法：设备进 fastboot 后 `fastboot boot tmp/lk2nd/diag2/build-lk2nd-msm8953/lk2nd.img`
（**只加载到内存，不写入分区**）。看屏幕上出现哪几个 M 就知道卡在哪：
- 只有 M1 → 崩在扫描里（支持新推断）
- M1 M2 但没有 M3 → `goto fastboot` 没生效
- 有 M3 M4 → 进了 fastboot，问题在菜单之后

注意：`fastboot boot` 在设备不在 fastboot 时会一直 `< waiting for any device >`
挂住，跑之前先确认 `fastboot devices` 有输出。

### 又一记：把"屏幕显示"当成了"设备可用"（2026-09-05 14:24~14:43）

**最大的一个误判**：我看到/听说"设备停在 lk2nd 菜单界面"，就默认它在 fastboot 里、
能用 fastboot 操作。于是后面所有 `fastboot` 命令都超时，我却把失败解释成
"lk2nd 崩了""菜单默认项触发了 Reboot"，一路往错误的方向推了三轮。

真相：**USB 线松了**。主机侧 `system_profiler SPUSBDataType` 里根本没有任何
fastboot/qcom/android 设备，`ifconfig` 里连 usb0 都没了 —— 屏幕上那个菜单还在
（设备自己还在跑），只是和主机没有连接。

**判设备在不在线要查主机侧，不要问屏幕**：
    system_profiler SPUSBDataType | grep -iE 'fastboot|qcom|android'
    fastboot devices
两边都对上才算数。屏幕只说明"设备自己活着"，不说明"链路通"。

顺带一条：区分两种 fastboot 不能看 `version` / `kernel` / `product`（lk2nd 复用
aboot 的 fastboot 代码，这几个值两边一样）。要看 `partition-size:lk2nd` ——
lk2nd 自己的会导出 0x80000，原厂的不导出这个分区名。

### 做诊断版这件事本身的坑（2026-09-05 15:2x~15:37）

为了让 lk2nd 把日志留在屏幕上，做了个诊断版。过程中踩了五个坑，都值得记：

1. **`cp -a` 到已存在的目录不会覆盖，会变成 `目标/源目录名/`。**
   上一版诊断镜像因此带了 `xiaomi-markw`（刷成了完整版），用户看到"变成小米那款、
   按键又坏了"。**刷之前必须用 `strings` 核 `markw/rosy` 计数，不能只看文件名。**

2. **`.mk` 里赋值行后面不能跟 `/* */` 注释** —— 会被原样塞进 `config.h`，
   报 `macro names must be identifiers`。注释要单独一行。

3. **`--disassemble='_dputc' | grep "bl.*fbcon_putc"` 查不到 ≠ 没生效。**
   编译器生成的是**尾跳转 `b <fbcon_putc>`**，不是 `bl`。模式用错会得出反的结论。

4. **日志级别：`SPEW` 的值就是 2，不是 3**（`debug.h`：`CRITICAL 0 / INFO 1 / SPEW 2`）。
   而 `DEBUGLEVEL` 取的是 `DEBUG` 宏的值 —— `lk2nd/project/base.mk:12` 里 `DEBUG := 1`，
   所以 SPEW 日志一直被裁掉。**改 `include/debug.h` 的默认值没用**（被 `DEBUG` 覆盖），
   而且改了也不会触发重编（LK 构建缺头文件依赖跟踪），得 `touch` 所有 `.c`。

5. **屏幕输出不能配 SPEW。** `fbcon_putc` 是逐字符画、还可能滚屏重绘，
   SPEW 全开之后日志量大到"像 tree 一直在滚、几分钟停不下来"，根本没法看。
   诊断版要 **DEBUG=1（INFO）+ 强制 fbcon 输出**，十几行就够定位。

收获（虽然被上面这些耽误了）：SPEW 那版**持续打印、没有重启** ——
说明 lk2nd 在扫描阶段**没有崩溃**。上轮列为最可能的"扫描时崩"被排除。

## 2026-09-05（终）lk2nd 重启循环：根因是 oem panel 命令注册用错宏

### 结论：三个问题全部解决，完整流程走通

完整流程（用户要的走法）：
1. 刷 Linux 系统（userdata）
2. 让 Linux 无法启动 —— 改名 `/extlinux/extlinux.conf`（系统保留完好）
3. 重启，**不按任何键**

实测（主机侧，不依赖屏幕）：
```
reboot rc=0
[1s]  已离线
[4s]  ✅ 自己回来了（离线 4s 后）
✅     稳住 60 秒没重启
       lk2nd:version    = 23.1-odin
       lk2nd:model      = Smartisan U2 Pro (ODIN)
       lk2nd:compatible = smartisan,odin
       lk2nd:panel      = qcom,mdss_dsi_ft8716_1080p_video
       partition-size:lk2nd = 0x80000
```
用户同时在屏幕侧确认"没按任何按钮，看着它自动停在了 fastboot 界面"。
两边独立印证 —— 这是这个项目第一次有可靠证据的自动停机。

### 根因（见提交 f1abcfe）

0003 补丁加 `fastboot oem panel` 时用了 `FASTBOOT_INIT(cmd_oem_panel)`，用错了宏：

    #define FASTBOOT_INIT(func) static void (*_fastboot_init_##func)(void) \
            __SECTION(".fastboot_init") __USED = (func)
    // 消费者（app/aboot/fastboot.h:65）
    for (func = &__fastboot_init_start; func < &__fastboot_init_end; ++func)
            (*func)();       ← 按 void(*)(void) 调用，不传参数

`cmd_oem_panel` 是 `void (*)(const char*, void*, unsigned)`，类型不匹配。
跳进去时 r0/r1/r2 没设置，函数却去读 arg/data/sz，读到垃圾 → 崩在
`aboot_fastboot_register_commands()`。

上游为这个用途准备了 `FASTBOOT_REGISTER(prefix, handlefunc)`（生成 void(void) 包装函数），
所有 oem 命令都用它，只有我们用了 FASTBOOT_INIT。

**0007 从头到尾都是对的**：`goto fastboot` 确实执行了，屏幕也打出了
`Reverting to fastboot`，只是下一步注册命令就崩了，轮不到菜单和 USB。
我前几轮把它判断成"补丁没生效"是错的。

### 定位方法（这次真正管用的）

不是读代码读出来的，是**用屏幕标记二分出来的**。在诊断版 `fastboot:` 之后沿调用序列
插 INFO 级 dprintf：

    M3(进标签) → M3a(注册命令后) → M3b(partition_dump 后) → M4(进菜单) → M5(返回什么键)

实测最后一行停在 M3，一次就把范围缩到"注册命令那一步"，然后才回头看代码找到那个宏。
**以后遇到"某个环节之后就没动静了"这类问题，优先用这种二分打点，别先去通读代码。**

### 又一个坑：设备树字符串带 NUL

`/proc/device-tree/chosen/lk2nd,version` 是 `23.1-odin\0`，直接 `cat` 会把后面的
输出吞掉（表现为"命令没输出"）。要用 `tr '\0' '\n' < 文件`。

## 2026-09-05 USB OTG 专题：真机实测（外接 960G SATA SSD + 绿联硬盘盒）

### 结论先行：这个专题的大部分工作早就做过了，而且能用

仓库里已有完整的用户态角色切换机制，我之前的调研完全没查到，是疏忽：
- `dist/build/rootfs/etc/udev/rules.d/99-odin-usb-role.rules`
  （UDC add/remove、typec change、extcon change 都触发）
- `dist/build/rootfs/usr/local/sbin/odin-usb-role.sh`
  （device=建 NCM gadget+usb0+dnsmasq / host=解绑 UDC+停 dnsmasq）
- `odin-usb-gadget.timer` 每 30s 自愈看门狗

日志证明它工作：
```
16:40:31 host: unbound UDC '7000000.usb'
16:40:31 host: dnsmasq stopped
```

**插上移动硬盘 → 角色自动切 host、内核自动开 VBUS、识别为 /dev/sda**，全链路通。
所以：角色切换 ✅、GPIO 33 通路 ✅、用户态机制 ✅。FUSB301 没驱动也不影响
（靠 `&pmi8950_smbcharger { usb-role-switch = <&usb3>; }` 就够）。

### 唯一的问题：VBUS 会自己掉，且不恢复

实测两次，间隔**不固定**：
```
第一次：1579s 识别 → 1815s 掉   （撑约 4.5 分钟）
第二次：2538s 识别 → 2578s 掉   （只撑 40 秒）
报错都是：[...] qcom-smbchg ...: OTG regulator failure → usb 1-1: USB disconnect

用户确认：**拔掉重插能恢复** ⇒ 是可重试的瞬态保护。

### 两条代码事实（源码级）

1. **中断处理不对称**（drivers/power/supply/qcom-smbchg.c）
   | 中断 | handler | 行为 |
   |---|---|---|
   | `otg-oc`（过流） | `smbchg_handle_otg_oc` | ✅ 有重试：关掉→延时重试，最多 NUM_OTG_RESET_RETRIES 次 |
   | **`otg-fail`** | `smbchg_handle_otg_fail`（1066） | ❌ **只发一次 REGULATOR_EVENT_FAIL 通知就 return，不重试** ← 中招的是这个 |

   设备树 compatible 是 `qcom,pmi8996-smbchg`（PMI8950 声明成 pmi8996 兼容），
   那份 data 的 `reset_otg_on_oc` 为**真** —— 重试机制本来启用着，
   只是 `otg-fail` 这条路径没走它。

2. **`detect_work` 会主动关 OTG**（同文件 918 行）
   ```c
   if (!otg_present && has_role_sw)
           smbchg_otg_switch(chip, false);
   ```
   ID/OTG 检测一报"不在"就关 VBUS。这条解释了"用户没动设备它自己掉"。

### 另外一个悬挂状态

```
/sys/class/regulator/regulator.33/  name=smbcharger-otg-vbus  state=enabled  users=0
```
`enabled` 但 `users=0` —— VBUS 是驱动绕过 regulator framework 直接写寄存器开的
（`detect_work` 954 行 `smbchg_otg_switch(chip, !usb_present)`），**没有正式 consumer**，
所以 fail 通知也没人接，`&usb3` 节点缺 `vbus-supply`。

> 注意：设备树给 `&usb3` 补 `vbus-supply` 有坑 —— `smbchg_otg_enable()` 里有
> `WARN_ON_ONCE(chip->role_sw)`，主线设计上 role switch 与 regulator 不该混用。

### 硬件/格式备注

- 识别为 `/dev/sda` 894.3G，KIOXIA EXCERIA SATA SSD，绿联硬盘盒（ASMedia 174c:55aa，走 UAS）
- `sda1` 200M vfat LABEL "EFI"；`sda2` 894.1G **apfs**（这是块 Mac 盘）
- **内核没有 apfs 模块**（`modprobe apfs` not found）⇒ sda2 **不要挂载**，有损坏风险
- 内核支持的文件系统：ext2/3/4、vfat、ntfs3、f2fs、fuseblk —— **没有 exFAT**
- core 变体**没装 udisks2** ⇒ 插上不会自动挂载

## 2026-09-05 USB OTG 专题续：重刷 v0.9.5 后**全部正常**

### 背景

上一轮折腾（反复插拔 OTG 设备）之后系统坏掉了 —— 重启卡在 lk2nd 菜单。
于是用**刚发布的 v0.9.5 正式 CI 制品**重刷了 lk2nd + userdata
（`gh release download v0.9.5`，SHA256 校验通过）。

> 值得记一笔：系统坏掉时 lk2nd **自动停在菜单**而不是反复重启 ——
> 这正是这轮修的 0007 + FASTBOOT_REGISTER 在起作用，问题反而变得好处理了。

### 重刷后的实测（设备连着电脑 → 换移动硬盘 → 换回电脑）

记录器（每 2s 采样）完整记录：
```
role=device udc=7000000.usb usb0=172.16.42.1/24 dnsmasq=active | extcon=USB-HOST=0
                                                    ← 连着电脑，USB 网卡正常
role=host   extcon=USB-HOST=1                       ← 插移动硬盘，角色自动切 host
role=host   sda=/dev/sda  dev=1-1 id=174c:55aa speed=480 prod=Ugreen Storage Device
                                                    ← 硬盘识别（USB2.0 高速，走 UAS）
role=host   usb0=none dnsmasq=inactive               ← 用户态脚本按设计停掉 gadget
（拔掉硬盘）
role=host   sda=none  extcon=USB-HOST=0
role=device udc=7000000.usb                         ← 2 秒后切回 device，UDC 回来
role=device usb0=172.16.42.1/24 dnsmasq=active      ← 15 秒后 USB 网卡完全恢复
```

**两个之前报的问题都不复现了**：
1. ✅ 移动硬盘不再"几秒就掉" —— 长时间插着灯一直亮
2. ✅ 拔掉 OTG 后 USB 网卡自动恢复（15 秒内）

之前那次"几秒掉 + 网卡不恢复"，很可能**是同一个根因：系统当时已经损坏**，
不是角色切换机制的 bug。新线 + 干净的 v0.9.5 系统下全通。

### 端到端验证（只读，没动硬盘数据）

```
sda     894.3G
├─sda1  200M  vfat  LABEL "EFI"
└─sda2  894.1G apfs
mount -o ro /dev/sda1 /tmp/otg-efi   ✅ 成功
ls /tmp/otg-efi   →  $RECYCLE.BIN  EFI  System Volume Information  it-removed-amfi-80-in-config
umount            ✅ 已卸载，sda 上无挂载点
```
这是一块 Mac 用过的盘（APFS + EFI 分区），**sda2 的 APFS 始终没碰**。

### 内核/用户态现状（这轮的真正缺口）

- 支持的文件系统：ext2/3/4、vfat、ntfs3、f2fs、fuseblk
- ❌ **没有 exFAT** —— 普通 U 盘最常见的格式，插上大概率读不出来
- ❌ **没装 udisks2** —— core 变体不会自动挂载
- ❌ **没有 apfs 模块** —— 苹果盘读不了，也不打算支持
- 硬件本身没问题：`CONFIG_USB_DWC3_DUAL_ROLE`、`USB_ROLE_SWITCH`、`XHCI_HCD`、
  `USB_STORAGE`、USB 网卡模块（ax88179/smsc95xx/dm9601/cdc_ether）全在

### 过程中的几个坑（都值得记）

1. **`pkill -f usb-watch.sh` 自杀**：承载这条命令的 `sh -c` 自身命令行里
   就含 "usb-watch.sh"，pkill 会连它一起杀 ⇒ 后面的 `nohup` 根本没执行。
   要么把 pkill 和启动拆成两条命令，要么用更精确的匹配。
2. **zsh 里 SSH 的 `-o` 参数不能放进变量**（`$SSHO` 不分词）⇒
   `command-line line 0: keyword stricthostkeychecking extra arguments`。
   内联写死，别省这点字符。（同一天踩了三次。）
3. 记录器踩样：只把 bMaxPower 放进"变化检测"变量却不打印 ⇒ 日志里看不到。
   变化检测和日志输出要用同一份字符串。

## 2026-09-05 v0.9.6-usb-oops（方案 A）真机复测：Oops 不再触发，但暴露一个新问题

### 环境

用 CI 制品重刷（lk2nd + core rootfs），验收 16/16 全过。
默认启动项 `l0`（完整版，带 OTG 角色切换），dtb 用的是
`msm8953-smartisan-odin-ft8716.dtb`（**不是** norolesw）。ramoops 确认已加大：
```
ramoops: using 0x200000@0x9ff00000, ecc: 0      ← 2 MB（原 1 MB）
```

### 好消息：方案 A 生效，Oops 不再触发

| 测试 | 之前 | 现在 |
|---|---|---|
| 硬盘只读挂载 | 成功后 67 秒掉电 | **成功并稳定** |
| 连续读 220 MB | 一读就掉 | **正常（31 MB/s），无报错** |
| 内核 Oops | 每次插拔都触发 | **未触发**（`/sys/fs/pstore/` 全程空 = 从未崩溃） |
| 拔掉后 USB 网卡 | 不恢复 | **恢复**（PC 侧 en36 拿到 172.16.42.2，ping 通，dnsmasq active） |

另外，之前反复发生、把系统搞坏两次的那个 Oops 现在一次都没出现。
**这是最重要的进展。**

### 但暴露了一个新问题：usb0 的 sysfs 节点变成悬空符号链接

插回电脑后，同一瞬间对照两个来源，结论相反：

```
[ -L /sys/class/net/usb0 ] => YES      ← 符号链接还在
[ -d ] [ -e ] [ -r ]      => NO        ← 但目标不可访问
ip -o link show usb0      => usb0: <UP,LOWER_UP> state UP   ← netlink 里存在且 up

根因：
  usb0 -> ../../devices/platform/soc@0/7000000.usb/gadget.0/net/usb0
  但 /sys/devices/platform/soc@0/7000000.usb/gadget.0/net/  目录已经不存在
  （gadget.0 目录是 18:36 插回电脑时重建的，可 net/ 子目录没跟着建起来）

⇒ 内核里网络设备还在（netlink 看得到、地址在、网络通），但它的 sysfs 目录已注销。
```

**对脚本的影响**：`usb0_exists()` 用的是 `[ -d /sys/class/net/usb0 ]`，
在悬空链接下会误判为"不存在"，于是脚本走"跳过 ip 调用"分支，日志里持续出现
```
device: usb0 not present yet, skip ip calls
device: usb0 10s 内未 up（exists=no），仍尝试启动 dnsmasq（看门狗会重试）
```
这次结果侥幸是对的（netlink 里残留的 usb0 还带着地址和 UP 状态，网络实际是通的），
但**这很脆弱** —— 不能指望每次都这么幸运。

### 下一步

- 这个"sysfs 注销但设备还在"的状态本身要查：是 NCM gadget 在拔插重建时的
  已知行为，还是另一种竞态。ramoops 现在 2 MB，下次能拿到转储，有条件查。
- `usb0_exists()` 需要更稳健：现在至少应该把"悬空链接"和"真的不存在"区分开，
  并且脚本在 usb0 不可用时要有明确的重建动作，而不是只 skip + 靠看门狗重试。
- 方案 B（修 `rtnl_link_get_size()` / `rtnl_link_get_af_size()` 对 gadget 网卡的竞态）
  仍是最终方案，等上述查清后做。

## 2026-09-05 内核基线升级：6.19.5/main → 7.1.3/main（落后 33279 提交）

- **23:45 完成** — 换钉点 + 删 0011，提交推送并发 `v0.9.7-upstream-713` 触发 CI
- **为什么升级**：038 报告里那个把我们折腾了两个版本的内核 Oops，上游早就修好了
  - `ec35c1969650`（2026-03-09）f_ncm: Fix net_device lifecycle with device_move
  - `e1eabb072c75`（2026-03-11）u_ether: Fix race between gether_disconnect and eth_stop
  - `e002e92e88e1`（2026-03-16）u_ether: Fix NULL pointer deref in eth_get_drvinfo
  - 三个都**晚于我们的钉点（2026-02-21/03-01）16~23 天**。我们钉在 `6.19.5/main` 的 tip 上，
    这根分支上游从此不再推进 —— **光看"自己这根分支有没有新提交"永远看不到进展**
- **关键认知**：上游按内核稳定版**开新分支**（6.19.5 → 7.0.9 → 7.0.2 → 7.1.3），
  判断"是否落后"要看 `git branch -r` 的分支列表，不是看自己分支的提交数
- **实测过的兼容性**
  - 9 个补丁用项目自己的 `tools/ci/apply-patches.sh` 在 7.1.3 上跑：**9/9 打上，退出码 0**
  - 0010（OTG pulse skip）**仍需**：7.1.3 的 `smbchg_otg_switch()` 里只有 `OTG_EN_BIT`
    一个写操作，grep `TRIM6|pulse` 为空
  - 配置漂移：olddefconfig 会静默丢弃 14 个符号（ARM64_PAN/LSE、CRYPTO_AES_ARM64_CE、
    CRYPTO_GHASH、CRYPTO_SM3_*、CRYPTO_RNG_DEFAULT、NFS_V4_1、NF_CT_PROTO_UDPLITE、
    MDIO_BUS、以及 3 个内部 select 符号），**逐一定性后确认对本机无影响**
  - 新增 315 个符号，按硬件关键词筛完全是别家机器的驱动，默认 =n 正确
- **删了 0011**：我们手写的 `ncm_unbind` 清 `netdev->dev.parent`，
  被上游 `ec35c1969650` 取代（人家是用 device_move 管生命周期，更正规）。
  原件存 `tmp/superseded-patches/`
- 详见 `reports/041-我们与上游的关系-基线从6.19.5升到7.1.3.md`
- **风险待 CI 回答**：补丁落得上去 ≠ 编得过。DRM panel / DSI 的 API 若在 7.1 有变化，
  0004/0005/0006/0008 可能编译失败；0007 的 binding 若改名，dtb job 会失败
- **不假设**：不认为"升了基线 OTG 掉电就好了" —— 040 已量过那是电池内阻 0.54Ω，硬件问题

## 2026-09-05/06 升级 7.1.3 的第一轮 CI：dtb 挂了，真因是上游改了标签名

- **00:00 完成** — 本地复现 + 修好 + 提交推送，等 kernel job（冷缓存约 35 分钟）再发新版
- 本地装了 homebrew 的 dtc 1.7.2，**可以直接跑 `KDIR=ext/linux-msm8953 dts/build-dtb.sh`**
  复现 CI 的 dtb job —— 不用等 35 分钟才知道结果。这条以后都用。
- **dtb 失败真因**：不是接线错，是 7.1.3 把 `msm8953.dtsi` 里 `&tlmm` 下 6 个 PDM 状态
  **改了名**（`_act`→`_default`、`_sus`→`_sleep`），按 pinctrl-names 统一命名。
  引脚定义（gpio67~74 / cdc_pdm0 / 8mA、2mA+bias-disable）**一字未改**，跟着改名即可。
  改完本地四个 DTB 全过（63475 / 63323 / 63475 / 63323 字节），Makefile dtb 自检也全过。
- **顺手查到的一个真实行为变化**（不是编译问题）：上游给 PMI8950 补了正经支持
  - 6.19.5：`pmi8950.dtsi` 写 `compatible = "qcom,pmi8996-smbchg"`（借的）+ DT 属性 `smbchg-lite`
  - 7.1.3：改成 `qcom,pmi8950-smbchg`，驱动新增 `smbchg_pmi8950_data`，属性删掉
  - 差异只有 iterm/ilim 两张表（改用电 pmi8994 的）；`reset_otg_on_oc` 与 `smbchg_lite`
    **都没变**（前者两版都是 true，后者 6.19.5 靠属性、7.1.3 靠 data，都等效 true）
  - ⇒ 是修好不是回归；OTG 相关开关位完全一致，真机留意充电电流档位
- **预先排除了编译风险**（不用等 CI 猜）：`include/drm/drm_panel.h`、`drm_mipi_dsi.h`
  两版只多了一个 `MIPI_DSI_FMT_RGB101010`；`hfi_parser.c` **完全没动**；
  三块面板驱动用到的 mipi_dsi_*/drm_panel_*/devm_* 签名全不变

## 2026-09-06 FAT32 中文文件名：用 utf8=1 就够了，不重编内核

- **00:05 完成** — 已提交推送，待真机（SSH 现在要密码，进不去）
- 之前 README 第八节决策 1 写的是"放弃 FAT32 中文、不做 nls_utf8"，**这条撤销**
- 卡住的不是内核缺模块，是**选项写错了**
  - `iocharset=utf8` 错：vfat 仍要走 `load_nls(iocharset)`
    （`fs/fat/inode.c:1797`，注释就写着 "FIXME: utf8 is using iocharset for upper/lower conversion"），
    缺 `nls_utf8` 直接挂载失败
  - `utf8=1` 对：`opts->utf8=1`，名字转换改走 `utf16s_to_utf8s()` / `utf8s_to_utf16s()`，
    这两个在 **fs/nls/nls_base.c**，`obj-$(CONFIG_NLS)` 就编进去，**与 CONFIG_NLS_UTF8 无关**
- 本镜像 `CONFIG_NLS=y` + `CONFIG_NLS_ISO8859_1=y` + `CONFIG_NLS_CODEPAGE_437=y`
  + `CONFIG_FAT_DEFAULT_IOCHARSET="iso8859-1"` ⇒ 两个 load_nls 都拿得到，**零改动可用**
- 唯一副作用可接受：大小写比较仍走 iso8859-1 的 `nls_strnicmp`，
  ASCII 仍不区分大小写、非 ASCII 不折叠，对中文名无影响
- 顺手改正一个事实错误：exfat **支持** iocharset（`super.c:254`），
  只是默认值已经是 utf8，不需要给

## 2026-09-06 v0.9.7-upstream-713b 真机验收：7.1.3 起来了，16/16 全通过

- **08:38 完成** — 刷完跑验收 **16 项全过**，设备 `uname -r` = `7.1.3-postmarketos-qcom-msm8953`
- 刷机全程 2 分 10 秒（自动进 fastboot 10s、刷 lk2nd 0.1s、刷 userdata 43s、
  重启到 USB 网卡 15s、SSH 40s）
- **唯一的"失败"是验收脚本自己的期望值过期**：`flash/flash-all.sh:262` 硬写了
  期望 `6.19`。改成 `7.1`（只钉主次版本，第三位留给 7.1.4 这类稳定版升级）后重跑全过
- 下载教训：`gh release download` **不带 -p 会把 gui 那 5.6 GB（6 个分片）也下下来**，
  18 分钟没下完。刷机只下 core：`-p lk2nd-odin.img -p '*.dtb' -p odin-debian-sparse.img
  -p SHA256SUMS`，**1 分 57 秒**
- DTB 大小从 63431 → 63475 字节（+44，就是 PDM 改名那段注释）

## 2026-09-06 FAT32 中文：真机实测结论（决定性证据）

用只读方式挂设备上现成的 vfat 分区 `/dev/mmcblk0p52`（modem，不写盘）：

```
### A) iocharset=utf8（老写法）—— 挂载失败
mount: /tmp/a: wrong fs type, bad option, bad superblock on /dev/mmcblk0p52, ...
dmesg:
  FAT-fs (mmcblk0p52): utf8 is not a recommended IO charset for FAT filesystems,
                       filesystem will be case sensitive!
  FAT-fs (mmcblk0p52): IO charset utf8 not found          ← 卡在这里

### B) utf8=1（新写法）—— 挂载成功
/dev/mmcblk0p52 on /tmp/b type vfat (ro,relatime,fmask=0022,dmask=0022,
        codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro)
                                                    ^^^^ utf8 生效了

### C) nls_utf8 确实不存在
modprobe: FATAL: Module nls_utf8 not found in directory /lib/modules/7.1.3-...
ls .../kernel/fs/nls/ → 只有 nls_ucs2_utils.ko
```

三条合起来坐实：`utf8=1` 生效、`iocharset` 仍是默认的 iso8859-1、
全程不需要 `nls_utf8`。与提交时在源码里查到的路径完全一致。

**遗留**：core 镜像里**没有 dosfstools**（`mkfs.vfat` 不存在），所以没能在本机造
带中文名的盘做"写入→读回"的闭环。上面的只读对比已经足够证明挂载与名字转换路径
是对的，等手上有 FAT32 U 盘时再补一次端到端确认。
（顺带：设备没有外网，apt 装不了 dosfstools。）

## 2026-09-06 OTG 持续读取稳定性测试（第一轮：纯电池供电）

- **08:48 结束** — 撑了 **3 分 17 秒（197 秒 / 20 轮）**就掉电，**但系统没被拖垮**
- 方法：sda1 raw 直读 `dd iflag=direct`（绕开页缓存，真实打 USB 总线），
  每轮 200 MB、30.3~30.4 MB/s，同时每秒级记电压/电流/电量/dmesg 报错
- 掉电瞬间三条（顺序很清楚）：
  ```
  qcom-smbchg ...: OTG regulator failure
  sd 0:0:0:0: [sda] tag#12 data cmplt err -71 uas-tag 1 inflight: CMD
  usb 1-1: USB disconnect, device number 2
  ```
- 电压一路下滑：3.862 V（n=1）→ 3.410 V（n=19），电流 -390~-450 mA，
  电量 87%→82%。跟 040 号报告量的 0.54Ω 内阻完全对得上 —— **7.1.3 也改变不了它**
- **这次的关键成果：掉电没再拖垮系统**
  - 0 个 Oops / BUG / panic / Call trace（grep 到的 4 条全是 ramoops 初始化日志）
  - pstore 空
  - 根文件系统仍 `rw`，**没有** remount 成只读，0 个 EXT4 错误
  - ssh/sshd active，负载 0.67，内存正常
  - ⇒ 上一版（6.19.5 + 手写 0011）掉电是会把系统搞坏的；换成上游 `ec35c1969650`
    的正统修法后，掉电退化成"这块盘用不了"，系统照常跑。这就是要的健壮性底线。

## 2026-09-06 顺带查清的三件事（都在真机上实测）

- **NTFS3 是内建的**：`CONFIG_NTFS3_FS=y`、`modinfo ntfs3 → (builtin)`、
  `/proc/filesystems` 有 ntfs3。虚拟盘实测读写 + 中文名全正常。
  镜像里**没有** ntfs-3g（也不需要，ntfs3 更好）。
- **UAS 硬盘盒从来不会被自动挂载**（已修）：udev 报 `ID_BUS=ata`（SCSI 层按 ATA 报），
  不是 usb ⇒ 规则与脚本双双 skip。现在 USB 硬盘盒基本都走 UAS，等于核心场景一直是坏的。
- **NTFS 盘会挂不上**（已修）：`blkid` 报 `TYPE="ntfs"` 不是 `ntfs3`；
  我们既无老 ntfs 驱动也无 `mount.ntfs` ⇒ 自动探测必然 `unknown filesystem type 'ntfs'`。
  对比实测：显式 `-t ntfs3` 可用；不指定类型时，装了 ntfs-3g 走 fuseblk、没装就失败。
- **镜像缺 fsck 工具**（已补）：debootstrap --include 原本只有 e2fsprogs。
  OTG 掉电后外接盘很可能要 fsck，vfat/exFAT 的一个都没有 ⇒ 补 dosfstools、exfatprogs。
  刻意**不装** ntfs-3g：装了会让自动探测优先走 fuseblk（实测），而内核 ntfs3 更好。

## 2026-09-06 OTG 第二轮：带电源的 USB Hub（进行中）

- **08:58 开始** — 20 分钟，跑到 09:18
- 顺带验证了 UAS 修复**在真机上生效**（脚本已手动推到设备上）：
  ```
  08:57:26 mount /dev/sda1 (vfat → -t vfat) -> /run/media/sda1 [...,utf8=1]
  /dev/sda1 on /run/media/sda1 type vfat (rw,...,utf8,errors=remount-ro)
  ```
  之前是 `ID_BUS='ata' != usb, skip`，现在自动挂上了，且生效选项里有 `utf8=1`
- 按用户要求全程只读：脚本把自动挂载的 rw 改成 ro 才开始测

## 2026-09-06 传感器（i2c-gpio）落地 + 一轮真机代码评审

### 结果：光感/距离 + 加速度/陀螺 都通了（变体 F，受控实验）

- **12:51 受控实验**（scp 传 DTB + 写前/写后/重启后三次 md5 校验）：
  设备端 `/boot/dtbs/qcom/msm8953-smartisan-odin-ft8716.dtb`
  三次都是 `c47c8464761cf55717579d730a6a6100`（= 本地 tmp/dtbs-F 那一份）
- 开机后自动出现：
  ```
  0-0048 0-0068 1-0038 2-0025
  iio:device0 stk3310      ← 光感 + 距离
  iio:device2 bmi160       ← 加速度 + 陀螺
  ```
- 读数：**als = 58 58 58 59 59 59（×0.1 = 约 5.8 lux，室内弱光，合理）**，ps = 672
  ⇒ 之前"开机 als 恒为 0"**不是硬件问题**，是下面两条干扰造成的假象
- 芯片实测（0x48 寄存器）：`0x3E = 0x15` = STK3311A 的 ID；驱动使能后
  `0x00 = 0x03`（ALS+PS 都开）、`0x11/12 = 02 a4`(676)、`0x13/14 = 00 33`(51)

### 踩坑 1：用 base64 往设备写 DTB —— 不能只校验字节数

- 之前那版脚本是 `echo '<base64>' | base64 -d > xxx.dtb`，写完只 `stat -c %s` 看字节数。
  字节数对（64032）但**内容可能已经坏掉**，而坏 DTB 照样能开机、照样能 probe 出设备，
  只是行为诡异（als 恒 0）。
- **改法**：一律 `scp` 二进制传，写前/写后/重启后**各查一次 md5**，
  `tmp/swap_dtb_scp.py` 已经把这三步固化进去了。

### 踩坑 2：上一轮的后台任务还在跟我抢设备（这次的"灵异事件"就是这个）

- 现象：`/boot` 里的 DTB 在 09:37:10（重启前 2 秒）自己从 64032 变成 **63944**，
  而且是一次干净的 systemd reboot。查遍仓库也没有任何用户态代码会写 `/boot/dtbs`。
- 真因：**63944 正好是 `tmp/dtbs-B`（变体 B，11:29 编）的大小** —— 是上一轮会话
  遗留的后台任务（`devstate.py --watch` 那条，以及"变体B稳定性检查"）在我眼皮底下
  写 DTB + 重启。已 `TaskStop` 停掉。
- **教训**：真机操作前先确认没有遗留后台任务；每一步都验证"机器上现在是哪一份"。

### 踩坑 3：`fastboot boot` 在这台机器上根本不可用（代码层面就是废的）

- 实测：`Booting  FAILED (remote: 'dtb not found')`
- 代码位置（ext/lk2nd）：
  - `app/aboot/aboot.c:3442-3453` —— 先 `copy_dtb()`（走 header 的 `dt_size`，偏移 40），
    没找到才去内核尾部找 appended DTB，再找不到就 `fastboot_fail("dtb not found")`
  - `platform/msm_shared/dev_tree.c:1281-1298` —— `dev_tree_appended()` 的 DTB 偏移是
    **从内核镜像 0x2C 处读 4 字节**（`dev_tree.h:49  DTB_OFFSET 0x2C`），
    我们的内核那 4 字节是 0 ⇒ 直接当没找到
  - 也就是说：**要么在 header 的 dt_size 里给，要么往内核 0x2C 写偏移**，
    单纯 `cat vmlinuz dtb > x` 是没用的（上一轮 `vmlinuz-with-dtb` 里 0x2C 实测也是 0）
- 结论（用户拍板）：**恢复一律走 `flash/flash-all.sh` 刷写，不要再试 fastboot boot**

### 代码评审发现：DTS 里给 stk3310 挂的 `vdd-supply` 是装饰品

- `drivers/iio/light/stk3310.c` 里**没有任何 regulator 调用**（grep 为空）
  ⇒ DTS 写 `vdd-supply = <&pm8953_l10>` 它一个字都不会去使能
- 对照 `drivers/iio/imu/bmi160/bmi160_core.c:714`：`regulator_bulk_enable(...)`，
  bmi160 是**真的**会开 l10/l6 的
- 真机实测：现在 `l10 = disabled(2.8V)`、`l6 = enabled(1.8V)`（bmi160 空闲后把 l10 关了），
  **光感照样读到 51~59** ⇒ 这颗芯片根本不靠 l10 供电，属性该删

### 13:03 变体 G：去掉光感的装饰性 `vdd-supply` 后复验通过

- G = F 去掉 `light-sensor@48` 里的 `vdd-supply = <&pm8953_l10>`
  （理由见上一条：stk3310 驱动不申请 regulator，这行写了不生效，只会误导后来人）
- 编译：64032 → **64016** 字节（-16 = 一个属性），md5 `cf1a1f464fdbdbff45ae5d93ac577950`
- 受控实验（写前/写后/重启后 md5 三次一致）：
  ```
  0-0048 0-0068 1-0038 2-0025
  iio:device0 stk3310   als = 57 57 57 57 57 57      ps = 675
  iio:device1 bmi160
  ```
  与 F 的 58 / 672 一致 ⇒ 那行属性本来就没起作用，删掉不影响功能
- 复用 `tmp/build_dtbs_variant.sh <KDIR> <输出目录>` 编四个变体，输出不落到 dts/ 下

**遗留**：
- bmi160 的 `mount-matrix` 还是占位值（照抄 daisy），要等真机把机器转几个方向
  看符号才能定 —— 需要用户动手
- 地磁没找到（三条总线上所有常见罗盘地址都无应答），指示灯 aw2013 还没定位到总线

## ⚠️ 2026-09-06 事故：把 &mpss(modem) 随整包刷进去，真机反复重启（未恢复）

### 时间线
- 13:24~13:29 本地 Docker 编出一套完整镜像（内核 16s / rootfs 1min，都是缓存命中）
- **13:30 把 `&mpss { status = "okay"; }`（modem）编进 DTB，随整包刷入**
- 13:33 设备反复重启（lk2nd），SSH 完全拿不到 → 用户人工恢复到"原厂 fastboot"
- 13:33~13:38 我接着刷（--from 30）→ 等 USB 网卡 240s 超时，还是没起来
- 13:40~13:45 换**今天刷成功过两次、验收 16/16 的 CI 镜像**（tmp/ci-core-usb）再刷
  → 同样卡在"等 USB 网卡 240s 超时"
- 13:46 起 `fastboot getvar` 挂住、`fastboot devices` 为空、SSH 不通
  ⇒ 设备处于重启循环 / 离线，**我现在完全联系不上它**
- 用户已出门，无法现场恢复。**停手，等用户回来。**

### 教训（这条最重要）
**任何"新使能某块硬件"的 DTS 改动，绝不能随整包镜像一次刷入。**
本机有 TrustZone 保护的前科：2026-08-30 单独使能 `&i2c_4`（BLSP 被 TZ 保护）
就会无限重启。modem(mss) 是同类风险区 —— `drivers/remoteproc/qcom_q6v5_mss.c`
会调 `qcom_scm_pas_mem_setup()` / `qcom_scm_assign_mem()` 等 SCM(TZ) 调用。
一旦踩雷，DTB 是启动时就要用的，机器直接陷在重启循环里，只能人工进原厂 fastboot 重刷。

**正确做法：先用"运行时设备树覆盖"在内存里试**（内核 `CONFIG_OF_OVERLAY=y`、
`CONFIG_CONFIGFS_FS=y` 都已开）：
```
mkdir -p /sys/kernel/config/device-tree/overlays/mpss
cat mpss.dtbo > /sys/kernel/config/device-tree/overlays/mpss/dtbo
dmesg | tail          # 看 mss 有没有 probe、有没有 SCM 报错
rmdir /sys/kernel/config/device-tree/overlays/mpss   # 撤销
```
覆盖层只在内存里、**重启即失效**，最坏情况就是"这一次开机挂了"，不会把机器锁住。
源码与产物都已备好：`tmp/gps/mpss-overlay.dts` / `tmp/gps/mpss.dtbo`
（用 target-path 而不是 &mpss 引用 —— 我们的 DTB 编译时没带 -@，没有 __symbols__）。

### 处置
- `patches/0007` 里 `&mpss` 已改回 `status = "disabled"`，并在原地写清原因与验证方法
  （不改回 disabled 的话，下一个人编出来又是一颗雷）
- GPS 的路径没变（**定位挂在 modem 上**：主线给的 gps_mem 只是 memshare 用，
  真正的定位是 modem 的 QMI LOC 服务，走 QRTR/SMD），但**必须先过"覆盖层验证"这一关**
- 顺带准备好的东西（都没经过真机验证，别直接刷）：
  · `dist/build/rootfs/usr/local/sbin/odin-modem-fw.sh` —— 从原厂 modem 分区
    取 mba.mbn + modem.mdt/bXX，再把 modem remoteproc 拉起来
  · `dist/build/rootfs/etc/systemd/system/odin-modem-fw.service` + 已在
    `apply-staging-fixes.sh` 里 enable
  · `tmp/gps/src/rmtfs`（交叉编译好的 rmtfs 守护进程）、`tmp/gps/qrtr-look.c`
    （查 QRTR 上有没有 LOC(16) 服务的探针）

### 恢复预案（等用户回来，需人工）
1. 长按电源关机 → **音量减 + 电源** 进原厂 fastboot
2. 确认 `fastboot devices` 能看到设备
3. `dist/` 里现在放的就是 tmp/ci-core-usb 那套（今天 12:18 / 12:44 两次 16/16 通过，
   ft8716.dtb 的 md5 = 076f0dcb747909b5830b625a09b0e332），直接：
   `bash flash/flash-all.sh --from 30`
4. 若还是起不来，按 flash-all.sh 第 30 阶段的注释用
   `evidence/live-device-backup/boot-partition.img` 把 lk2nd 恢复回来

### 另外两条流程上的坑（今天各踩一次）
- `make dtb` 有产物缓存：`ODIN_DTB_CACHE_HIT` 为真时直接跳过编译，
  我改了 DTS 却拿到旧 DTB，一度以为改动没生效
- `tools/ci/apply-patches.sh` 判定"已打过"很严格：我删掉编译树里的 DTS 想让它重新打，
  它反而报"要创建的文件不存在，也不像打过"直接失败。**不要手动删编译树里的文件**，
  本地编 DTB 用 `tmp/build_dtbs_variant.sh <KDIR> <输出目录>` 更省事
- `make publish-*` 只在自己的时间戳过期时才重新汇总，`out/publish/` 里可能还是旧 DTB；
  刷之前一定 `md5 -q dist/*.dtb` 与 `out/dtb/*.dtb` 对一下

### 恢复预案的更正（补记）
上一条预案第 4 步提到的 `evidence/live-device-backup/boot-partition.img` **根本不存在**
（库里只有 fastboot-getvar-all.txt / rootfs-full.tar / STATE*.txt），以它为准会扑空。
可用的 lk2nd 产物是 `tmp/ci-core-usb/lk2nd-odin.img`（今天刷成功两次，366608 字节）。

判断"现在这个 fastboot 是谁的"是恢复的关键：
- `evidence/live-device-backup/fastboot-getvar-all.txt`（8-30 正常状态）里有
      (bootloader) partition-type:lk2nd:raw
      (bootloader) partition-size:lk2nd: 0x80000
  也就是说**lk2nd 活着的时候，fastboot 会导出 lk2nd 这个 512KB 的分区**
- 如果 `fastboot getvar all` 里**没有** lk2nd 分区 ⇒ 当前是**原厂 fastboot**，
  此时 flash-all.sh 第 30 阶段会回退去刷 `boot`，而按该阶段的实测注释，
  刷 boot 只写到偏移 512KB、动不了偏移 0 的 lk2nd ⇒ 刷完还是进不了 Debian。
  这种情况下得先把 lk2nd 装回偏移 0，具体办法要等拿到 `fastboot getvar all`
  与分区表之后再定（不要凭猜动手）。

所以恢复第一步一定是：**进 fastboot 后先 `fastboot getvar all` 存一份，
看有没有 lk2nd 分区，再决定怎么刷。**

## 2026-09-06 待恢复：设备当前完全不在 USB 总线上

14:00 复查：
- `fastboot devices` 空、`ssh user@172.16.42.1` 不通
- `ioreg -p IOUSB` 里**只有集线器**（USB3.2 Hub / Xiaomi Type-C 5-in-1 Hub / USB2.0 Hub），
  **没有任何高通的 VID**（0x05c6 / 0x18d1 一类）
⇒ 手机压根没挂在 USB 上：可能是线被拔了、关机了、或者被人带走了。
这种情况**刷机脚本什么也做不了**（它要能看见 fastboot 才动）。

### 已备好、设备一回来就能直接用的东西
| 文件 | 用途 |
|---|---|
| `tmp/odin-accept-all.sh` | **一键验收**：传感器按"有值 / 不为 0 / 会波动"逐项判 PASS/FAIL；震动录基线+震动两段 wav；`--with-modem` 才开 modem（走运行时覆盖层） |
| `tmp/rms.py` | 回宿主机后算两段录音的 RMS，判定马达到底振没振 |
| `tmp/ffvib` | 震动触发（input 力反馈 FF_RUMBLE），已交叉编译 |
| `tmp/gps/mpss-overlay.dts` / `mpss.dtbo` | 开 modem 的**运行时覆盖层**（内存里，重启即失效，最坏不会锁机） |
| `tmp/gps/qrtr-look` | 查 QRTR 上有没有 LOC(16) 定位服务，已交叉编译（只依赖 libc） |
| `tmp/gps/src/rmtfs/rmtfs` | modem 要的 EFS 守护进程，已交叉编译（依赖 libudev.so.1，Debian 里有） |
| `tmp/swap_dtb_scp.py` | 换 DTB：scp 传 + 写前/写后/重启后三次 md5 |

### 设备回来后的最短路径
1. 插线、进 fastboot（长按电源关机 → 音量减+电源）
2. **先 `fastboot getvar all` 存一份**，确认有没有 `partition-type:lk2nd`
3. `bash flash/flash-all.sh --from 30`（dist/ 里是今天刷成功两次的 CI 镜像）
4. 起来后：传 `odin-accept-all.sh / ffvib / qrtr-look / mpss.dtbo` → 跑一遍 → 拿证据

### 又一个坑：手工改 patch 只做 `git apply --check` 是不够的（会静默截断）
14:14 sensors4 的 dtb 任务失败。本地 `make dtb` 复现：
```
/dts/msm8953-smartisan-odin.dts:978:9: error: unterminated comment
```
真因：我上一轮把 `&mpss` 改成 `status = "disabled"` 并加了一大段注释，
**却没重算 hunk 行数** —— 声明还是 979，实际 995。`git apply --check` 照样通过，
但正经应用时 git 按声明的行数截断，把 `&mpss {` 之后的内容全丢掉 ⇒ 注释没闭合 ⇒ 编译失败。

**规矩：改完 patches/*.patch 之后必须做两件事，缺一不可**
1. 重算 hunk 头的行数（`@@ -0,0 +1,N @@`）
2. 本地跑一次 `make dtb`（容器里），确认真的编得出来

只做 `--check` 会漏掉"截断"这种错误 —— `--check` 只验证上下文对得上，不管行数对不对。

## 2026-09-06 晚：三项真机验收（设备 20:51 接回后）

### 1. 震动马达 —— ✅ 用户当场确认在振
- 官方 sensors5 内核**确实带** `qcom-spmi-haptics`（`strings vmlinuz | grep spmi-haptics` 命中
  `qcom,spmi-haptics` / `drivers/input/misc/qcom-spmi-haptics.c`，是内建所以没有 .ko）
- 真机上出现了 `event0 name=spmi_haptics ff=107030000`（支持力反馈）—— 之前从来没有过
- `tmp/ffvib` 走 input 的 FF_RUMBLE 接口触发：`找到 FF 设备 /dev/input/event0 → 效果已上传 → 振 3 秒`，
  **用户在旁边确认"确实震动成功"**
- ⚠️ 麦克风录音这条路**没走通**：`arecord -D plughw:CARD=smartisanodin,DEV=1` 报 `audio open error:
  Invalid argument`（capture 通路没配好，跟马达无关）。所以 RMS 对比证据这次没有，
  结论是靠用户耳朵确认的。

### 2. 传感器 —— ✅ 8/8，全部"非 0 且有波动"（判据按用户要求）
官方镜像 DTB（64016 字节，md5 cf1a1f46…）换上后：

| 通道 | 采样（8 次） | 结论 |
|---|---|---|
| 光感 lux | 38~39 | 非 0 且波动 |
| 距离 prox | 672~676 | 非 0 且波动 |
| 加速度 x/y/z | 402~462 / -1355~-1304 / -16170~-16096 | 非 0 且波动，z×scale ≈ 9.63 m/s² |
| 陀螺 x/y/z | 2~3 / -13~-11 / -10~-8 | 非 0 且波动 |

（早先 12:51 / 13:03 那两次是同一套传感器，数值也吻合：als 58→57→36~40，随环境光变）

### 3. GPS / modem —— 有实质进展，但**没修好**，先关着
- 弄清楚了：**定位挂在 modem 上**。主线那个 `gps_mem` 只是给 memshare 用的；
  真正的定位是 modem 通过 QMI 的 LOC(16) 服务提供，走 QRTR/SMD。
- `&mpss status="okay"` **本身不会让机器重启**！换上后系统正常起来（uptime 连续），
  `remoteproc1 name=4080000.remoteproc fw=mba.mbn` 出现了，固件也被 `odin-modem-fw.sh` 从原厂
  modem 分区取到位（mba.mbn 238464、modem.mdt 7964，日志"固件就位"）
  ⇒ 下午那次"反复重启"不能全算在 &mpss 头上（当时是随整包一起刷的，还有别的变量）
- 卡在供电，报错很明确：
      qcom-q6v5-mss 4080000.remoteproc: Failed to request voltage for 0
      unbalanced disables for regulator-dummy
  驱动要两路（`msm8953_mss`）：proxy `"pll"` 100mA、active `"mss"` 1.05V 100mA；我们没写 ⇒
  `devm_regulator_get` 拿到 dummy ⇒ `regulator_set_voltage` 必然失败
- 从**原厂 DTB** 挖到了该接哪两路（phandle 已解析）：
      vdd_mss-supply = pm8953_s2      vdd_pll-supply = pm8953_l7_ao
      vdd_cx-supply  = pm8953_s2_floor_level   vdd_mx-supply = pm8953_s7_level_so
- **试了一次**：补 `pm8953_s2: s2`（1.00~1.15V）+ `pll-supply=<&pm8953_l7>` `mss-supply=<&pm8953_s2>`
  → 编出来 64115 字节（md5 e9d7a985…），换上后**起不来了，停在 fastboot**。
  已用官方镜像重刷恢复（2 分 25 秒，验收 16/16）。
- 下一步（不要再随整包刷）：先搞清 s2 在主线里到底该怎么写 —— 原厂 s2 是 **RPM 管理的**
  （只有 s2_level 有 0x10~0x180 的 level 范围，没有 uV），直接给它 min/max-microvolt 可能
  与 RPM 冲突。可以先只加 `pll-supply`（l7 已在用、风险小）单独试，确认不炸再加 mss 那一路。

### 4. 顺带确认的两件事
- 运行时设备树覆盖这条路**走不通**：`CONFIG_OF_OVERLAY=y` 但 `CONFIG_OF_CONFIGFS` 没开，
  所以 `/sys/kernel/config/device-tree/overlays` 目录根本不存在（之前判断错了，以为 OF_OVERLAY 就够）
- lk2nd 的"启动失败停在 fastboot"**这次正常工作了**（K 版 DTB 起不来后自动停在 fastboot，
  没有无限重启），所以有救回来的余地

### 5. modem 供电：四种接法全试过，结论是主线在这台机器上过不去（2026-09-06 21:20~21:50）

驱动（msm8953_mss）两阶段供电，只有 `uV > 0` 的才会调 regulator_set_voltage：
- proxy  `"pll"` 100mA（uV=0，只 enable）
- active `"mss"` 1.05V/100mA ← **真正调 set_voltage 的就是这路**，报错里的 0 指的是它

四种接法与结果：

| # | 接法 | DTB | 结果 |
|---|---|---|---|
| 1 | 什么都不写 | 64012（J，ece1ab08） | 开机正常，但 `Failed to request voltage for 0` + `unbalanced disables for regulator-dummy` |
| 2 | pll=l7 + mss=**新定义 s2**（写死 1.00~1.15V） | 64115（K，e9d7a985） | **起不来，停 fastboot** |
| 3 | 只加 pll=l7（隔离变量） | 64028（L，4805bcfe） | 开机正常，但仍是 mss 那路失败（证明 pll 不是问题） |
| 4 | pll=l7 + mss=**s2 空定义**（不写死电压） | 64083（M，43f96a9a） | 开机正常，但 `s2: voltage operation not allowed` |
| 5 | pll=l7 + mss=**l1**（1.0~1.1V 空闲 LDO） | 64071（N，2b79c36a） | **起不来，停 fastboot** |

**决定性证据（第 4 种）：**
```
s2: voltage operation not allowed
qcom-q6v5-mss 4080000.remoteproc: Failed to request voltage for 0.
unbalanced disables for s2
```
原厂 DTB 里 modem 的 `vdd_mss-supply` 确实是 **pm8953_s2**，但 s2 是 **RPM 管理的轨**
（原厂只有 `s2_level` 带 0x10~0x180 的 level 范围，没有 µV），**Linux 侧不允许直接 set_voltage**。
也就是说：主线这个驱动要求"能直接设 1.05V 的 regulator"，而本机给 modem 供电的那路
恰恰是 RPM 轨 —— 这就是所有主线 msm8953 板子都把 &mpss 留成 disabled 的原因。

**当前处置：`&mpss` 保持 disabled**（patches/0007 里就是这么写的），GPS 暂时不做。
真要做，路只有两条，且都不轻：
1. 给内核打补丁：让 msm8953 的 mss 走 RPM level 调压（或改用 power-domains 设性能态），
   而不是 regulator_set_voltage；
2. 或者绕过 mss，直接用 WCNSS 那颗芯片的 GNSS（如果有）—— 但主线 wcn36xx 只管 WiFi，
   没有 GNSS 支持。
另外：就算 modem 起来了，还得有 rmtfs（已交叉编译好）+ QRTR 上的 LOC(16) 客户端
（tmp/gps/qrtr-look 探针已就绪，但还没在真机上跑过）。

### 6. 内核补丁 0011 之后：modem 往前走了一大步（2026-09-06 21:57~22:36）

**参考对象**：Moto G7 (motorola-river) —— **SDM632，本质就是 msm8953 的马甲**，pmOS wiki 上它的
GPS / 短信 / 移动数据都是 Works。它的 DTS 里 modem 只有：
```dts
&mpss {
	firmware-name = "qcom/msm8953/motorola/river/mba.mbn",
			"qcom/msm8953/motorola/river/modem.mbn";
	pll-supply = <&pm8953_l7>;
	status = "okay";
};
```
为什么它能起来？因为 **SDM632 走的是另一条路**：驱动里 `sdm632_mss` **没有 active_supply**，而是
`.proxy_pd_names = { "cx", "mx", "mss" }`，靠 **RPM 电源域 SDM632_VDDMD** 给 modem 供电：
```dts
// sdm632.dtsi
&mpss {
	compatible = "qcom,sdm632-mss-pil";
	power-domains = <SDM632_VDDCX>, <SDM632_VDDMX_AO>, <SDM632_VDDMD>;
	power-domain-names = "cx", "mx", "mss";
};
```
而 **msm8953 的 VDDMD 被上游删掉了**（`pmdomain: qcom: rpmpd: remove VDDMD* from MSM8953`），
取而代之要求板级给 `mss-supply`（1.05V 的 regulator）—— 这就是我们卡住的根子。参考 river 是没用的，
因为 msm8953 没有 VDDMD 可用。

**补丁 0011**（patches/0011）：把 `msm8953_mss.active_supply` 的 `.uV` 从 1050000 改成 0
（驱动只在 `uV > 0` 时才 set_voltage），即**不再设电压，只 enable + set_load，电压交给 RPM**。

**结果（两轮）**：

| 配置 | 现象 |
|---|---|
| 0011 + mss=s2（s2 空定义） | ✅ 系统正常起来！供电错误消失，modem 进入启动流程：<br>`powering up 4080000.remoteproc` → `Booting fw image mba.mbn` → **`PBL boot timed out`**（-110） |
| 0011 + mss=s2（写死 1.05V） | ❌ **黑屏挂住**：启动 Linux 时黑屏、USB 网络不出现、也不自动重启，只能人工按进 fastboot |

`PBL boot timed out` 的原因也查到了：**s2 实际只有 0.744V**（`cat /sys/class/regulator/*/microvolts`
测得），而 modem 要 1.05V —— 但 s2 是 RPM 轨，设备树里一写死 min/max-microvolt 系统就起不来
（这次是黑屏挂死，之前 K 版是停 fastboot）。**s2 这条路走不通。**

**当前状态**：`patches/0007` 里 s2 又撤成空定义（避免后人踩），`&mpss` 暂时保持 disabled，
设备刷回官方 sensors5 镜像（16/16）。补丁 0011 留在库里但**未验证到最终成功**（它解决了供电报错，
但 modem 仍起不来）。

**下一步真正的方向**（按可行性排）：
1. **把 msm8953 的 VDDMD 加回 rpmpd**（撤销上游那个删除），然后照抄 SDM632：驱动加
   `.proxy_pd_names += "mss"`、DTS 的 &mpss 加第三个 power-domain —— 这是唯一跟 river 对齐的做法，
   但要动 rpmpd 驱动，风险不低。
2. 或者查原厂/厂商内核里 modem 上电的**完整时序**（vdd_cx/mx/mss/pll 谁先谁后），
   也许还差 `vdd_cx` / `vdd_mx` 两路（原厂是 s2_floor_level / s7_level_so）。
3. 再或者：接受 GPS 做不了 —— 主线 msm8953 全线设备都没开 modem，不是我们一台的问题。

### 7. ✅ 找到正解：mss-supply 该接 **s1**（照抄同芯片的 Asus Zenfone 3）

用户提示"这款手机使用 625 芯片（= MSM8953），GPS 能用，参考 Asus Zenfone 3 (asus-zenfone3)"——
**这次找对人了**：Zenfone 3 就是 MSM8953，它的 DTS 就在我们的内核树里：

```dts
// msm8953-asus-common.dtsi
pm8953_s1: s1 {
	regulator-min-microvolt = <870000>;
	regulator-max-microvolt = <1156000>;
};

&mpss {
	mss-supply = <&pm8953_s1>;
	pll-supply = <&pm8953_l7>;
	status = "okay";
};
```

**我们之前一直在死磕 s2（RPM 轨，不能 set_voltage），方向就错了。** s1 是普通 SMPS，0.87~1.156V
正好覆盖驱动要的 1.05V。而且我们自己的 DTS 里 `pm8953_s1: s1` **本来就定义了**（192 行，之前 grep 漏了）。
补丁 0011（改 uV=0）随之作废，移到 tmp/superseded-patches/。

**实测（DTB 7999fb53）**：
```
remoteproc1 name=4080000.remoteproc state=running fw=mba.mbn
qcom-q6v5-mss: MBA booted without debug policy, loading mpss
remoteproc1: remote processor 4080000.remoteproc is now up     ← modem 真的起来了！
```
❗但**不稳**：约每 50 秒崩一次并自动恢复（`crash #3/#4/#11`），报错：
```
fatal error received: dog.c:1526:Watchdog detects stalled initialization
```
查到的下一步嫌疑：**镜像里没有 rmtfs 用户态守护进程**（只有内核模块 rmtfs_mem +
/dev/qcom_rmtfs_mem1）。modem 起来后要靠 rmtfs 读写 EFS（modemst1/2），没有它初始化就卡住 ——
跟 watchdog 报的"stalled initialization"对得上。rmtfs 已交叉编译好（tmp/gps/src/rmtfs/rmtfs），
在设备上以 `rmtfs -r -P -s -o /var/lib/rmtfs` 起过，但**还没成功跑起来**（报
`unable to open remoteproc "state" control file`，待排查是权限还是路径）。

另：QRTR 探针 tmp/gps/qrtr-look 在真机上**段错误**，还没修。

**当前取舍**：&mpss 保持 enabled 在库里（modem 能起来但 crash 循环）。若嫌耗电/不稳，
可临时把 status 改回 disabled。传感器在这版镜像上复验正常（stk3310 + bmi160，加速度 z 有波动
-16082~-16202；室内恒定灯光下 lux 稳定在 40 不跳，属环境真稳定，不是传感器不动。

### 8. ✅ rmtfs 跑对了 —— modem 从"每 50 秒崩一次"变成完全稳定（2026-09-06 22:56~23:10）

qrtr-look 段错误修好了：原因是 `qrtr_decode()` 内部解引用第 4 个参数 `sq->sq_port`，
我传了 NULL。改成用 `qrtr_recvfrom()` 拿到 node/port 组成 sockaddr_qrtr 再传进去；
顺手加"只有 poll>0 才 recv"，免得刷屏 `Resource temporarily unavailable`。

**rmtfs 的正确启动方式**（之前一直没起来，两个原因）：
1. 必须以 root 跑（`rmtfs -r -P -s -o /var/lib/rmtfs`）—— 之前没用 sudo
2. **EFS 文件要预先建好**，否则 modem 一请求就 stalled：
   ```
   /boot/modem_fs1 → modemst1 (或 modem_fs1)
   /boot/modem_fs2 → modemst2 (或 modem_fs2)
   /boot/modem_fsc → fsc / modem_fsc
   /boot/modem_fsg → fsg / modem_fsg
   ```
   实测日志先是 `requested '/boot/modem_fs1'`，补齐后又变成 `requested '/boot/modem_fsg'` —— 四个都要建。

**效果（决定性）**：
```
崩溃计数（前）: 35
崩溃计数（后）: 35        ← 60 秒内 0 次新崩溃
remoteproc1 name=4080000.remoteproc state=running
```
之前是每约 50 秒 `Watchdog detects stalled initialization` → crash → recover，循环不停。
现在三个 remoteproc 全 running，且稳定。

**QRTR 上现在有一整套 modem 服务**（说明 modem 真在工作）：
```
0 CTL  1 WDS  2 DMS  3 NAS  4  5 WMS  7  8  11 12 14(RMTFS) 15 17 22 23 24 26 29 34 36 42 46 47 48 54 68 71 769
```
❗但**没有 16 (LOC，就是 GPS)**，也没有 6 (PDS 老 GPS)。所以 modem 通了，**GPS 还没通**。

**还差的**：
- ModemManager：镜像里被 mask 了（`ModemManager.service -> /dev/null`）。unmask 后能起来，
  但 `mmcli -L` 说 `No modems were found` —— MM 没识别到 QRTR modem，还得配（udev 规则 / MM 的 QRTR 后端）。
- **Debian bookworm 里没有 rmtfs 包**（`apt-cache search rmtfs` 空；只有 libqrtr-glib0）。
  所以 rmtfs 得自己提供：要么把上游源码（github.com/andersson/rmtfs）编进镜像，
  要么预置二进制 + systemd 服务 + 那四个 EFS 文件。目前是**手工跑的，重启就没了**，
  下一步要固化进镜像才算真解。

## 2026-09-06 夜间总结：三件事两件成了，GPS 差最后一步

### 今晚的最终状态

| 项目 | 结论 | 证据 |
|---|---|---|
| **震动马达** | ✅ **通过** | 真机出现 `event0 name=spmi_haptics`（支持力反馈）；`tmp/ffvib` 走 FF_RUMBLE 触发成功，**用户当场确认"确实震动成功"**。麦克风录音没录成（`arecord` 报 `audio open error: Invalid argument`，capture 通路没配好），所以 RMS 数值证据缺失，结论靠耳朵确认 |
| **传感器** | ✅ **8/8 通过** | 光感 38~39、距离 672~676、加速度三轴与陀螺三轴全部"非 0 且有波动"，重力自检 z×scale ≈ 9.63 m/s² |
| **GPS** | ❌ **还没通，但 modem 本身通了** | modem 稳定运行 + QRTR 上有一整套 QMI 服务，唯独缺 16 (LOC = GPS) |

### 传感器的判据说明（别再纠结"lux 不动"）
室内恒定灯光下 `lux` 稳定在 40 不跳 —— 这是**环境光真的稳定**，不是传感器死了。同一时刻加速度 z 一直在 -16082~-16202 之间跳，证明传感器在正常工作。之前也测到过 lux 变化（24→31、38→39），只要环境光一变它就跟着变。

### GPS 这一路的完整链条（今晚的进展）
1. `&mpss` 能起来，但每约 50 秒崩一次：`Watchdog detects stalled initialization` → crash → recover 循环
2. **根因 1（已解）**：`mss-supply` 接错了轨。
   之前死磕 s2（RPM 管理的轨，不能 set_voltage：`s2: voltage operation not allowed`）。
   **正解 = 照抄同芯片的 Asus Zenfone 3（Snapdragon 625 = MSM8953）**：
   ```dts
   pm8953_s1: s1 { regulator-min-microvolt = <870000>; regulator-max-microvolt = <1156000>; };
   &mpss { mss-supply = <&pm8953_s1>; pll-supply = <&pm8953_l7>; status = "okay"; };
   ```
   我们 DTS 里 `pm8953_s1` 本来就定义了（192 行，之前 grep 漏了）。
   改完 modem 能"is now up"，但仍 crash 循环。
3. **根因 2（已解）**：**镜像里没有 rmtfs 用户态守护进程**（只有内核模块 rmtfs_mem + /dev/qcom_rmtfs_mem1）。
   modem 起来后要靠 rmtfs 读写 EFS，没有它就 stalled —— 正好对上 watchdog 的报错。
   正确起法（两个条件缺一不可）：
   - 必须以 **root** 跑：`rmtfs -r -P -s -o /var/lib/rmtfs`
   - **EFS 文件要先建好**（modem 按路径要）：
     `/boot/modem_fs1→modemst1`、`/boot/modem_fs2→modemst2`、`/boot/modem_fsc→fsc`、`/boot/modem_fsg→fsg`
   效果：崩溃计数 35 → 60 秒后仍是 35（**0 次新崩溃**），三个 remoteproc 全 running。
4. **固化（已落库 + 已在真机验证）**：新建
   `dist/build/rootfs/etc/systemd/system/odin-rmtfs.service`，
   通过 `tmp/gps/install_rmtfs.sh` 装到真机并 `enable --now`：
   - 起不来一次（`start-limit-hit`，`bind(14): Address already in use`）—— 是**之前手工跑的
     rmtfs（PID 4057）占着 QRTR socket**。杀掉 + `systemctl reset-failed` 后
     服务 **active**，journal 只有 `Started odin-rmtfs.service`，
     `remoteproc0 a204000 / remoteproc1 4080000 / remoteproc2 adsp` 全 running。
   - ⚠️ 手工装的只活在这一次开机；重刷镜像会丢（二进制不在仓库），见 P0。

### 顺手修好的工具
- `tmp/gps/qrtr-look` 段错误：原因是 `qrtr_decode()` 内部解引用第 4 个参数 `sq->sq_port`，我传了 NULL。改用 `qrtr_recvfrom()` 取 node/port 组成 sockaddr_qrtr 再传；加了"只有 poll>0 才 recv"，不再刷屏 EAGAIN。

### 下一步 TODO（按优先级）

**P0 — 把 rmtfs 固化进镜像**（现在 rmtfs 是手工跑的，**重启就没了，modem 会回到崩溃循环）。
- 源码：`github.com/andersson/rmtfs`（pmOS 用 `695d0668`）。我已经交叉编好 aarch64 版本：`tmp/gps/src/rmtfs/rmtfs`。
- 要落的：二进制 + systemd 服务（我们不是 OpenRC）：
  ```ini
  ExecStartPre=/bin/mkdir -p /var/lib/rmtfs（并建 4 个 EFS 文件）。
  ExecStart=/usr/sbin/rmtfs -P -s
  ```
- ⚠️ 二进制不入库（AGENTS 铁律 5：二进制不进版本库），要么在 CI 里加一步编它，要么预置。
- ✅ **服务文件已经进仓库了**（上面第 4 条），真机上已 active；**缺的只是二进制**。

**P1 — 继续查 GPS**
- QRTR 上的服务：`0 CTL 1 WDS 2 DMS 3 NAS 4 5 WMS 7 8 11 12 14(RMTFS) 15 17 22 23 24 26 29 34 36 42 46 47 48 54 68 71 769 —— **没有 16 (LOC)，也没有 6 (PDS 老 GPS)。
- 试过 ModemManager：镜像里被 mask（`ModemManager.service -> /dev/null`）；unmask 后能起，但 `mmcli -L` 说 `No modems were found`，得配 udev 规则 / MM 的 QRTR 后端。
- 待确认：是不是这版 modem 固件不含 GNSS，还是 LOC 要额外触发。

**P2 — 传感器扫尾**
- `mount-matrix` 还是**占位值**（照抄 daisy）：需要把手机平放/立起/侧翻读加速度原始值来定符号。要用户动手。
- 地磁：三条总线上 `0x0c/0x0d/0x0e/0x1e/0x2e 全无应答 —— 暂缺。
- 指示灯（aw2013）：还没定位到在哪个 BLSP 总线上（⚠️ 有 TZ 复位风险，一次只试一条）。
- 环境光 tcs3400 / nxu8010：硬件大概率没焊，放弃。
- 霍尔：原厂没有。

**提示**：如果暂时不搞 GPS，建议把 `&mpss` 改回 `status = "disabled"` —— 免得重启后没 rmtfs 又进崩溃循环，白耗电。

### 参考：pmOS 的用户态 modem 栈（已查本地 pmaports：`modem/` 目录）
- `qrtr`（linux-msm/qrtr v1.1，提供 libqrtr
- `rmtfs`（andersson/rmtfs）：装到 `/usr/sbin/rmtfs`；initd 逻辑：
  - `rmtfs_files_path` 没设 → 加 `-P`（用**真实的 EFS 分区** modemst1/modemst2）
  - `rmtfs_avoid_writing="true"`（默认）→ 加 `-r`（只读不回写）
  - 没有下游 preload 库 → 加 `-s`（rmtfs 顺带管 modem rproc 启停）
- `pd-mapper`（andersson/pd-mapper）：老平台用不上 —— 我们 modem 已经起来了，说明不需要 ✅

**参数含义（读源码确认）**：
- `-o` 存 EFS 镜像的目录；与 `-P` 一起用时表示"从这个目录里按名字找原始分区
- `-P` 使用原始 EFS 分区（modemst1/modemst2）
- `-r` read_only，不回写存储
- `-s` 同步 mss rproc（modem 启停交给 rmtfs 管
- `-S` A/B 分区的 slot 后缀
- `-v` verbose

## 2026-09-07 P0 完成：rmtfs 进 CI，不再手工装二进制

上一版（sensors6-rmtfs）只把**服务文件**进了仓库，二进制还是手工 scp 到真机的 ——
重刷镜像就丢，modem 回到崩溃循环。这一版把**编译**也搬进 CI：镜像自带 `/usr/sbin/rmtfs`。

### 为什么不能只是「装个 libudev-dev:arm64 交叉编译」

按上游默认编法，rmtfs 用 libudev 读共享内存设备的两个 sysfs 属性。这条依赖在 CI 上有两个硬伤：

1. **glibc 版本错配**：runner 是 Ubuntu（24.04 → glibc 2.39），设备是 Debian bookworm（2.36）。
   链进去的符号版本一旦高于 2.36，设备上是**运行时**才炸（`GLIBC_2.xx not found`），
   构建期全绿 —— 属于最难查的那类问题。
2. **静态不了**：Debian 的 `libudev-dev` **不带 `libudev.a`**（实测确认），所以想靠
   全静态链接绕开版本问题也绕不开。

### 正解：绕开 libudev，改成读 sysfs

上游源码里**本来就有**一套不用 libudev 的实现（原来的 ANDROID 分支），直接读
`/sys/class/rmtfs/qcom_rmtfs_mem%d/{phys_addr,size}`。逐项核实过这条路对本机成立：

- 内核 `drivers/soc/qcom/rmtfs_mem.c`：`rmtfs_class` 的 `.name = "rmtfs"`、
  设备名 `"qcom_rmtfs_mem%d"`、属性 `phys_addr / size / client_id`（0444）。
- **真机实测**：`cat /sys/class/rmtfs/qcom_rmtfs_mem1/phys_addr` → `0x00000000f2d00000`，
  `size` → `0x0000000000180000`（`%pa` 打的、带 `0x` 前缀，`strtoull(..,16)` 能解析）。

于是补丁 `tools/ci/rmtfs/0001-sharedmem-drop-libudev-read-sysfs.patch` 只改 3 行：
把开关从 `#ifndef ANDROID` 换成 `#ifdef RMTFS_USE_LIBUDEV`（默认走 sysfs），
并把 `<sys/endian.h>` 改成 `<endian.h>`（前者是 musl/BSD 的拼法，glibc 只有后者）。

去掉 libudev 之后就能**全静态链接**（-static，870696 字节），运行期不依赖设备上任何
.so，构建机是 Ubuntu 还是 Debian、什么版本，都不再影响产物能不能跑。构建脚本里加了
一道自检：产物不是静态链接就直接失败，不等到刷机才暴露。

### 落地改动

- `tools/ci/build-rmtfs.sh`（新）：取 qrtr @ `27d2c9df`（上游无 tag，钉 SHA）+
  rmtfs @ `v1.3`（=`b30a3eb`），手工编 `libqrtr.a`（躲开 meson 交叉文件），再静态链 rmtfs。
  用 `git fetch --depth 1 origin <ref>`：钉 SHA 时能且只能这么取，对 tag 同样成立，两个仓库一套代码。
- `Makefile`：新增 `rmtfs` 目标与 `RMTFS_OUT`；`rootfs-%` 依赖它并传 `ODIN_RMTFS_BIN`。
- `tools/ci/build-rootfs.sh`：把二进制装进 `$ROOT/usr/sbin/rmtfs`。
  刻意放在 staging 缓存判断**之外** —— rmtfs 是构建期产物、不进那份 tar，
  放里面就会出现「改了 rmtfs 却因缓存命中而没进镜像」的静默失效。
- CI rootfs job 的 apt 行加 `gcc-aarch64-linux-gnu`。

### 真机验证（换上静态版之后）

- 服务 active，rmtfs 进程在，`ls /proc/<pid>/fd` 显示 **fd 5 → `/dev/qcom_rmtfs_mem1`** ——
  新代码路径真的打开了共享内存设备。
- 崩溃计数 **35 → 35**（无新增），三个 remoteproc 全 running，稳定运行 4 分钟以上。
- journal 干净，只有 `Started odin-rmtfs.service`。

### 踩坑

- **裸跑 `/usr/sbin/rmtfs` 会永久阻塞**：它是前台守护进程，加 `| head -3` 也没用
  （不输出）。脚本里想"看看能不能执行"要改用 `ldd` / `file`，不要直接跑。
- **zsh 不做词分割**：`SSHOPT="-o A -o B"; scp $SSHOPT ...` 会把整串当成一个参数，
  报 `keyword connecttimeout extra arguments at end of line`。ssh 的 `-o` 要逐个写。
- **SSH 登录方式**：镜像里 `PermitRootLogin no`，要用 `user`/`user` 且必须
  `-o PreferredAuthentications=password -o PubkeyAuthentication=no`
  （否则先卡在 publickey，sshpass 传的密码永远轮不上）。见 docs/04。

## 2026-09-07 触摸屏回归修复：不是芯片坏了，是 probe 比面板早了 5 秒

### 症状

真机上 `/proc/bus/input/devices` 里**没有触摸屏**，dmesg 只有一句
`edt_ft5x06 1-0038: touchscreen probe failed` / `... failed with error -5`。
看着像硬件或驱动坏了，其实芯片好得很。

### 根因：TDDI 依赖面板先上电，而时序反了

FT8716 与显示集成在同一颗 **TDDI** 上，面板没上电时它不响应 I2C。
但 `msm`(DRM) 与 `panel_ft8716` 都是模块、靠 udev 冷插逐个加载，实测这条链
到 48s 才跑完，而触摸在 43s 就 probe 了：

```
[33.776] ibb: disabling                              ← 面板 probe 试过一次，推迟，释放负压轨
[43.152] edt_ft5x06 1-0038: supply vcc not found, using dummy regulator
[43.729] edt_ft5x06 1-0038: touchscreen probe failed  ← 触摸先到，拿 -5(EIO)
[48.466] msm_dpu 1a01000.display-controller: bound 1a94000.dsi   ← 显示才起来
[48.962] [drm] fb0: msmdrmfb frame buffer device
```

失败后内核**不会重试**，于是整个会话都没有触摸设备。
（2026-09-01 那次能用，是因为当时面板 5 秒就起来了，没有 race。）

**决定性验证**：开机后手工 `modprobe -r edt_ft5x06 && modprobe edt_ft5x06`
（此时面板已起）立刻成功：
`input: generic ft5x06 (8d) as .../1-0038/input/input6`。

### 为什么不在 DT 里补 vcc-supply

同芯片的 vince 是 `vcc-supply` + `iovcc-supply` 都声明的（内核树
`msm8953-xiaomi-vince.dts:188`），看起来照抄就行。但**原厂 DTS**
（`evidence/stock-rom-battery/odin-stock.dts:6367`）里 focaltech@38
**只声明了 `vcc_i2c-supply`**，没有独立主电 —— 说明主电就是跟显示共享的，
没有第二路轨可以指。照抄 vince 是猜，不如直接把时序理顺。

### 修法

`odin-touchscreen.service`（绑 `dev-dri-card0.device`）+ `odin-touchscreen.sh`：
等显示真就绪了再强制重新 probe 一次。与既有的 `odin-venus-fw` 是同一个套路
（依赖就绪后重建 probe），已在 apply-staging-fixes.sh 里注册启用。

### 真机验证

- 卸掉模块模拟失败态 → 跑脚本 → `✅ 触摸已注册`，`generic ft5x06 (8d)` 回来；
- 手摸屏幕，`/dev/input/event5` 采到真实事件：
  `BTN_TOUCH=1`、`ABS_MT_POSITION_X=138/139`、`ABS_MT_POSITION_Y=13/17/19`、`EV_SYN`。

### 待办

- 需要**重启一次**验证开机时序下也生效（重启有丢 SSH 的风险，先问用户）。
- 顺带发现：显示要 48s 才起来，比老记录的 5s 慢很多，值得单独查一轮。

## 2026-09-07 第三个 rootfs 变体 kb：core + BuffyBoard 触屏键盘

BuffyBoard 是跑在 framebuffer 上的触屏虚拟键盘（LVGL 写的），用 uinput 造一个
虚拟键盘设备，给"SSH 不通、图形界面也没有"的场合当交互方式。
参考 https://wiki.postmarketos.org/wiki/Buffyboard 。

### 前提都在（先逐项核实过）

- `CONFIG_INPUT_UINPUT=m`、`CONFIG_DRM_FBDEV_EMULATION=y`、`CONFIG_FB=y`；
- 真机 `/dev/fb0` 与 `/dev/uinput` 都在。

### 为什么在 chroot 里编，不交叉编译

BuffyBoard 依赖 libinput / libudev / libdrm / xkbcommon / inih，全是动态库。
跟 rmtfs 是同一道题：交叉编译就要在 runner（Ubuntu）上装这些的 arm64 版，
链接进去的 glibc 符号版本高于设备上 bookworm 的 2.36 ⇒ 设备上运行时才炸。
所以改成**在 debootstrap 出来的 arm64 根里借 qemu 直接编**，用的就是根目录自己
的 bookworm 库，ABI 天然一致。

代价是慢：471 个编译单元，原生 arm64 约 19 秒，qemu 下整个脚本约 10 分钟。
编完 purge 构建依赖 + 删源码树 + apt clean，镜像里只留产物（921200 字节）。

### 踩坑

1. **忘了装 gcc**。meson 不会自带编译器，报
   `Unknown compiler(s): [['cc'], ['gcc'], ...]`。BUILD_DEPS 里显式写 gcc。
2. **chroot 里没 DNS**：`Temporary failure resolving 'deb.debian.org'`。
   Debian 把 resolv.conf 做成指向 systemd-resolved 的符号链接，构建 chroot 里
   是悬空的。照 setup-rootfs.sh 的 fix_dns 拿构建环境的顶上；自己的脚本里也
   加了一道，不依赖调用顺序（导出前 build-rootfs.sh 会换回 stub 链接）。

### 落地

- `tools/ci/build-buffyboard.sh`（新）：chroot 内 apt 装依赖 → 取 buffybox @ 3.6.0
  + lvgl 子模块 @ 85aa60d1 → `meson setup -Dman=false -Dsystemd=true` → 编 buffyboard
  → 装二进制/配置/systemd unit → 预加载 uinput → 启用 buffyboard.service 与
  getty@tty1.service → purge 清理。
  `-Dsystemd=true` 不能省：带上 meson 才生成 buffyboard.service 与
  getty@.service.d/buffyboard.conf（后者在新 getty 会话时给 buffyboard 发
  SIGUSR1 让它重绘），自己手写容易漏掉这个联动。
- `Makefile`：VARIANTS 加 kb，补 rootfs-kb / publish-kb，变体校验改 core|gui|kb。
- `build-rootfs.sh`：setup-rootfs.sh 之后、变体=kb 时调用（必须在 setup 之后，
  那时包与 DNS 才就位）。
- CI：rootfs 矩阵加 kb，publish 下载 odin-rootfs-kb。

### 本地验证（容器里对 arm64 根副本跑了一遍）

- `/usr/bin/buffyboard` 921200 字节，aarch64，`chroot` 里 `--help` 正常；
- `ldd` 链的是根目录自己的 bookworm 库（libinih/libinput/libudev/libc 2.36）；
- 四个文件都在：/etc/buffyboard.conf、buffyboard.service、
  getty@.service.d/buffyboard.conf、modules-load.d/odin-uinput.conf；
- `multi-user.target.wants/` 里有 buffyboard.service，`getty.target.wants/` 里有
  getty@tty1.service；
- /usr/src/buffybox 已清掉，gcc 已 purge。

## 2026-09-07 BuffyBoard 真机实测：键盘能出、能摸，但会被控制台抢屏

### 现象

键盘画得出来、uinput 虚拟键盘设备也造出来了（`/proc/bus/input/devices` 里
多一个 `buffyboard`），libinput 也认到了触摸屏（`New input device: generic ft5x06 (8d)`）。
但**一登录或 exit，键盘区域就整块变黑**；还能触摸，只是手指按到的那一小块会
重新显形，其余仍是黑的。

### 原因不是 fbdev 加速

换 drm 后端重编（`-Dlvgl_backends=drm`）后症状**一样**，所以不是 framebuffer
那一套的问题。本质是**控制台和 BuffyBoard 抢同一个 CRTC**：控制台每次整屏刷新
（登录 / exit / 清屏）就把自己那份 buffer 翻上去，把 BuffyBoard 顶掉；之后 LVGL
只把被触摸的那一小块标脏重画，于是只有那一小块回来。

（顺带查实：本机 fbdev 的加速路径确实是残的 —— `screen_buffer` 为空，
`sys_fillrect/copyarea/imageblit` 全是空操作，dmesg 报
`fb0: sys_fillrect: framebuffer is not in virtual address space.`。
所以后端照样选 drm，不碰这条坏通路。）

### 解法：周期全量重绘（用户拍板用这个）

上游本来就有重绘接口：**SIGUSR1** → `main.c: on_new_terminal()` →
`lv_obj_invalidate(keyboard)`，也就是整块键盘标脏全量重画。getty 那个 drop-in
（`getty@.service.d/buffyboard.conf`）用的就是它。

于是做成 `odin-buffyboard-redraw.timer`（1 秒一跳）+ 同名 oneshot 服务，周期性
发 SIGUSR1。控制台抢屏之后最多 1 秒键盘自己补回来。不发私有信号、不改上游代码。

周期是实测选的：0.5s 几乎无感但退出时会明显闪；**1s 仍能"闪一下之后整块亮回来"，
CPU 再省一半**，取 1s。

### 另外补掉的两处

- **libinput-bin 没装**：它提供 `/usr/share/libinput/*.quirks`。只留 libinput10 时
  libinput 报 `failed to find data files ... This will negatively affect device behavior`
  —— 触摸屏 quirks 不生效。已加进 RUN_DEPS。
- **redraw timer 不能在 build-buffyboard.sh 里 enable**：它的 unit 在
  dist/build/rootfs/ 覆盖树里，而覆盖树要到 apply-staging-fixes.sh 才铺下去，
  那时 enable 会因为文件不存在而失败。改走 enable_from_tree。

### 本地验证（把容器里编好的二进制直接上机）

- `buffyboard --help` 正常，ldd 缺的只是 libinih/libinput（设备没网，从 arm64 根
  里带过去放 /opt/buffy-libs，用 LD_LIBRARY_PATH 指，不动系统文件）；
- 启动后输入设备列表多出 `buffyboard`；
- 1 秒重绘生效后，登录/退出时键盘会闪一下然后整块亮回来，可用。

## 2026-09-07 电源键开关屏：三个坑，一个个踩过来

### 坑 1：我把自己的脚本文件覆盖成了压缩包（提交里带了个垃圾文件）

写过一个 scp 循环：
```
for f in thd.tgz thd-libs.tgz odin-screen-toggle.sh; do
  scp ... tmp/buffy/out/$f dist/build/rootfs/usr/local/sbin/odin-screen-toggle.sh
done
```
变量名用错 ⇒ 把 `thd-libs.tgz` 拷到了**仓库里脚本的路径**上（1371839 字节，
gzip 魔数 `037 213`），然后 `git add -A` 把它提交进了 1ab6bba。设备上装到的
也就是这个压缩包，于是 sh 报 `odin-screen-toggle.sh: not found` / `Exec format error`。
教训：**scp 的目标路径别用变量拼，尤其别和源混在一个循环里。**

### 坑 2：thd 的 --triggers 给目录不生效

真机实测（triggerhappy 0.5.0-1.1+b2）：传 `/etc/triggerhappy/triggers.d/`
一条触发器都不执行，journal 里只有 `Device /dev/input/event0 not suitable.`；
改成传**具体文件**立刻就执行了。
（Debian 自带的 triggerhappy.service 传的是目录，但它被我们 mask 了。）

### 坑 3：用 console blank 会"灭了马上又亮"

第一版写 `/sys/class/graphics/fb0/blank`。真机现象是按下后灭一下立刻亮回来 ——
**console blank 会被任意输入事件自动解除**，而按电源键的抬手、甚至一次触摸
都算输入。改用**背光**：`/sys/class/backlight/*/bl_power`（0 亮 / 1 灭），
关的是 WLED 背光本身，输入事件管不着它。没有背光设备的机器再退回 console blank。

### 验证

手动跑脚本：关 → `bl_power=1` 且 buffyboard 停；开 → `bl_power=0` 且 buffyboard 起。
脚本里加了带时间戳的日志，方便判断"一次物理按键到底触发几次"。

## 2026-09-07 按键映射修正（照原厂 DTB + 报告 002）

### 症状

只按**电源键**一下，`thd --dump` 却抓到两个事件：
```
EV_KEY KEY_POWER     1  /dev/input/event2   (pm8941_pwrkey)
EV_KEY KEY_VOLUMEDOWN 1  /dev/input/event3   (pm8941_resin)
```
thd 一看到两个键同时按下就匹配不上单键触发器 `KEY_POWER 1` ⇒ "按了电源键没反应"。

### 原厂铁证（不是猜的）

`evidence/stock-rom-battery/odin-stock.dts`：

- **:11643 gpio_keys** —— 三个实体键都走 TLMM GPIO，全部 low-active、debounce 15：
  · `vol_up`   GPIO85 → linux,code 0x73(115 KEY_VOLUMEUP)
  · `vol_down` GPIO86 → linux,code 0x72(114 KEY_VOLUMEDOWN)
  · `key_home` GPIO87 → linux,code 0x66(102 KEY_HOME)，带 `gpio-key,wakeup`
- **:7932 qcom,pon_2** —— RESIN 是 `status="disable"`。
  **原厂根本没把 RESIN 当音量-用**，音量- 是 GPIO86。

我们之前的 DTS 是：gpio-keys 只有 volume-up（GPIO85），
再 `&pm8953_resin { linux,code = <KEY_VOLUMEDOWN>; status = "okay"; }` —— 两处都错。

### 改法（patches/0007）

- gpio-keys 补齐 volume-down(GPIO86) 与 key_home(GPIO87)，三个键都加 debounce-interval = <15>，
  key_home 带 `wakeup-source`；
- `&pm8953_resin` 改成 `status = "disabled"`。

### 验证

- `git apply --check` 通过（hunk 行数用脚本重算，没手数 —— 之前手数错过一次）；
- 本地容器编译 4 个 DTB 全过；反编译产物核对：
  volume_up=115/85、volume_down=114/86、key_home=102/87，debounce 全 15，与
  原厂 DTB 逐项一致。DTB 64071 → 64309 字节。

## 2026-09-08 kb 变体首次刷机：成功，但暴露两个"只在真镜像里才看得见"的问题

`v0.9.7-keymap2` 刷入真机，flash-all.sh **16 项验收全过**（面板/DSI/DRM/背光/
usb0/wlan0/sshd/扩容…）。按键映射也确认生效：`pm8941_resin` 不再出现在输入设备
列表里 —— 说明 `&pm8953_resin { status = "disabled" }` 起作用了。

但刷完发现两个问题，都是**仓库里的漏子**，靠"本地手工改过"是盖不住的：

### 1. buffyboard 装错目录（跟之前那次同源）

`build-buffyboard.sh` 把二进制装到 `/usr/bin/buffyboard`，而 meson 生成的
`buffyboard.service` 里 `ExecStart` 写死 `@bindir@` = `/usr/local/bin/buffyboard`。
结果：
```
Failed to locate executable /usr/local/bin/buffyboard: No such file or directory
(status=203/EXEC) → Restart 5 次 → Start request repeated too quickly → failed
```
之前在旧机上我是靠"手动再拷一份到 /usr/local/bin"绕过去的，**脚本本身没改**，
于是新镜像一刷就复现。已把脚本改成装 `/usr/local/bin`（本机编译的软件放这里
本来也更合规），并把相关的 strip、大小报告、文件头说明一并改掉。

### 2. odin-rmtfs 从来没进过启用清单

刷完是 `disabled; inactive (dead)`。它只在 `apply-staging-fixes.sh` 之外被
`install_rmtfs.sh` 手工 enable 过，镜像里当然没有。已加进 enable_from_tree。

### 教训

"我在真机上手工改好了"不等于"修好了"。刷一次全新镜像才是唯一可靠的验证 ——
这次两个漏子都是这么暴露的。

## 2026-09-08 开机慢与占用大的调查（都有结论，都已修）

### 开机 1min43s：内核只要 7.6s，慢全在用户空间

```
systemd-analyze: 7.636s (kernel) + 1min 35.846s (userspace)
critical-chain:
  graphical.target @1min35.7s
  └─multi-user.target
    └─odin-touchscreen.service @1min32.3s +3.4s   ← 一直等到 92 秒才开始
      └─basic.target @29.6s
        └─systemd-udev-settle.service @7.8s +21.6s
```

**真凶是我自己写的 `After=dev-dri-card0.device`**：
`systemctl show dev-dri-card0.device` → `ActiveState=inactive`、
`ActiveEnterTimestamp` **为空** —— 那个 device unit 在这台机器上**从来没激活过**
（device unit 由 udev 事件创建，`/dev/dri/card0` 节点存在不代表 unit 激活）。
于是 systemd 死等它，等到 DefaultDeviceTimeout(90s) 才放行。

改法：不依赖 device unit，改由脚本自己轮询 `/dev/dri/card0` 是否真的出现
（上限从 30s 放宽到 120s，本机 DRM 约 36.9s 起来）。

顺带：`systemd-udev-settle` 21.6s 也省掉 —— 换成 odin-hotkey 的
ExecStartPre 精确等 `pm8941_pwrkey`（见 odin-hotkey-wait.sh）。

### 占用 4.9G：4.0G 是 swapfile

```
du -ax / | sort -rh | head
  4194308  /swapfile      ← 就是它
   758276  /usr
```
默认 `ODIN_SWAP_SIZE=4G` → 降到 2G（core / kb 不跑桌面够用；要调大仍可覆盖环境变量）。

注：已装好的机器不会因为改默认值而缩小现有 swapfile（脚本见到文件存在会跳过重建），
刷新镜像才会生效。

## 2026-09-08 更正：swapfile 不该由我缩小，改回并设为 5 GiB

上一节我写"默认 4G → 2G"，理由是"它是 / 下最大的单项、看着占地方"。
**这个改动是错的，用户明确否掉了，已改回。**

- swap 大小是**权衡过的选择**，不是我该替用户省的东西。我看到"占 4 GB"就自作主张
  缩减，属于拿自己的判断覆盖用户的取舍 —— 该做的是把事实摆出来（它是最大单项、
  占了 4.0 GiB），由用户决定。

- 现在按用户定的设成 **5 GiB**：
  最早就想建 5 GiB，当时根分区 ext4 为了迁就 lk2nd **关了 extents**，而 swapfile
  走 iomap 需要 extents ⇒ `swapon: Invalid argument`，才临时退到 4 GiB。
  reports/036 之后 lk2nd 支持只读 extents、根分区已开 extents
  （实测 `tune2fs -l` 的 features 里有 `extent`），5 GiB 的障碍已经没了。

上一节关于开机的结论仍然成立（那个确实是真 bug，已修）。

## 2026-09-08 版本号指示

用户指定：**下一次还需要发版的话用 `v0.9.11`**（不是 0.9.10）。
（当前已发到 v0.9.9；v0.9.8 已取消、v0.9.7 已取消。）

## 2026-09-08 音频路由固化进镜像（v0.9.11-audio）

- **现象**：新刷机音频完全不可用，`aplay`/`arecord` 一律 `Invalid argument`（048 报告）。
- **真因**：路由**从来没被应用过**。
  - `/var/lib/alsa/` 是空的 ⇒ Debian 自带的 udev 规则 `90-alsa-restore.rules`
    （`ACTION=="add", KERNEL=="controlC*"` → `alsactl restore`）没有状态可恢复。
  - UCM 也救不了：卡片实际用的是 `ucm2/smartisanodin/`（Syntax 4）那份**旧**路由
    （`PRI_MI2S_TX` / `ADC2`，与硬件不符）；换成 `conf.d/smartisan-odin` 指向的正确
    路由后 `alsaucm set _verb HiFi` 能过，但 `set _dev Speaker/Earpiece` 在
    alsa-lib 1.2.8 上一律 EINVAL —— 而逐条 `amixer cset` 全都成功，所以既不是控件名
    也不是取值的问题（`${CardId}` 未定义是另一处坑，改写成 hw:0,x 后仍失败）。
  - 045 报告里"麦克风/听筒/扬声器 ✅"是在**手工 cset 过**的旧机上验的，镜像里没固化。
- **修法**：真机调通路由 → `alsactl store` 成 `dist/build/rootfs/var/lib/alsa/asound.state`
  （1130 个控件 / 178512 字节）随镜像发布，由系统自带 udev 规则在声卡出现时自动恢复。
  **不新增任何 systemd 服务。**
- **实测**：故意把 5 个关键控件打回默认值 ⇒ `aplay: audio open error: Invalid argument`
  （与 048 报告症状一致）；`alsactl restore -f` 之后 aplay RC=0、arecord RC=0；
  播放 1 kHz 正弦时麦克风回环录到 Peak −36.1 dB / RMS −55.8 dB，用户耳朵确认"有声音"。

## 2026-09-08 venus 用静态 ffmpeg 实测（用户要求"装一个测一下"）

- 设备无外网装不了包 ⇒ 从 johnvansickle.com 下 **arm64 静态** ffmpeg 7.0.2，scp 进设备跑。
- **解码可用**：`h264_v4l2m2m` 解 720p H.264，20.8× 实时（60 帧源）。
- **编码可用但有边界**：640×480 / 800×480 / 1024×576 / 1280×704 / 736 / 768 / 800 /
  **1920×1088** 全部成功；**高度 720（1280×720、640×720）以及 1280×240/360/688/752
  一律 SIGBUS（ffmpeg 崩，内核无日志）** —— 规律接近"高度需 32 对齐"，最常见的
  720p 正好踩雷。
- 解码会掉帧：默认缓冲下 60 帧只出 46/59 帧，日志明示
  `All capture buffers returned to userspace. Increase num_capture_buffers`；
  调到 32 反而卡死（4 分钟不返回）。

## 2026-10-20 触摸"突然失效"真因：buffyboard 输入扫描与触摸 rebind 的开机竞态

详见 `reports/050-触屏失效真因-buffyboard输入扫描与触摸rebind竞态.md`。要点：

- **现象**：用户报"之前触摸屏是好的，现在不能触摸了"。SSH 进真机只读排查。
- **内核层是好的**：`/dev/input/event5` 直读 8 秒 534 个完美事件（坐标、
  BTN_TOUCH、SYN 齐全），中断只在触摸时增长、CRC 错误为 0。
- **真因**：buffyboard 用 libinput **path 模式**（strings 里没有任何
  `libinput_udev_*` 符号），启动扫一次 `/dev/input` 之后**永不重扫、不支持
  热插拔**；fd/epoll 里都没有 event5 ⇒ 键盘从不消费触摸（端到端探测：
  触摸 38 事件、uinput 注入 0）。
- **竞态**：FT8716 是 TDDI，首次 probe 必失败，event5 要等
  `odin-touchscreen.service` rebind 后才出现（本次开机 20:56:22.3，节点
  mtime 实测），而 buffyboard 20:56:20 就已扫描完毕 —— 晚 1.8 秒，整场错过。
  10-08 开机同样是 ~2 秒差 ⇒ 输成的开机就整场没触摸，这就是"之前好、
  现在坏"的来源，纯随机启动顺序，不是硬件退化。
- **修法（真机已验证）**：`buffyboard.service` 加 `After=odin-touchscreen.service`
  （drop-in `/etc/systemd/system/buffyboard.service.d/odin-after-touchscreen.conf`；
  不用 Requires=，odin-touchscreen 失败不挡 buffyboard）。重启 buffyboard 后
  fd 出现 event5，端到端注入出 `KEY_J / KEY_H`，用户确认成功。
- **回写构建树**：新增
  `dist/build/rootfs/etc/systemd/system/buffyboard.service.d/odin-after-touchscreen.conf`。
  覆盖树整树拷贝自动随 staging 部署，无 enable 符号链接需要；只影响 kb 变体
  （buffyboard 只在 kb 里装）。下次刷机/重建 staging 后开机即生效。

教训：这类"启动扫描一次、不热插拔"的消费者（buffyboard 于 libinput path 模式）
跟"设备生成晚会完成"的生产者（TDDI 触摸）之间，**必须显式 systemd 排序**，
靠运气迟早输 —— 本机已经输过至少两场（10-08、10-19 两次开机）。
