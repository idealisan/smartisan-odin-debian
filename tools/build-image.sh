#!/bin/bash
# ODIN Debian 根镜像导出管线（可复现，容器内执行）。
#
#   build-image.sh <staging-dir> <out-img> <blocks> [label]
#
# 例：
#   tools/build-image.sh /mnt/stage /mnt/img/odin-debian.img 524288 pmOS_root
#
# 每一条约束都对应 reports/013 解包复核的一个实测教训：
#   1. staging 必须是"未挂载的普通目录"——挂载态复制会让超级块 free 计数与位图不一致
#   2. 特性集保守：lk2nd 的 ext2 驱动只接受 ro_compat ⊆ {sparse_super, large_file,
#      metadata_csum}（lib/fs/ext2/ext2.c，它完全不检查 compat/incompat。
#      metadata_csum 是补丁 lk2nd/0006 放行的 —— ro_compat 语义就是"只读可忽略"。
#      详见下面"3. 建文件系统"那节的完整说明，以及 verify 里的 ro_compat 位核对。）
#   3. 必须保留 resize_inode + reserved GDT：否则在线扩容在第 128 组（16GiB）处
#      命中 fs/ext4/resize.c 的 "No reserved GDT blocks, can't resize" 而 EPERM
#   4. 导出后 e2fsck 至干净、img2simg、check_sparse、逐项回读校验，任一失败即非零退出
set -e

STAGE=${1:?usage: build-image.sh <staging-dir> <out-img> <blocks> [label]}
OUT=${2:?}
BLOCKS=${3:?}
LABEL=${4:-pmOS_root}

REPO=$(cd "$(dirname "$0")/.." && pwd)
SPARSE="${OUT%.img}-sparse.img"

# GitHub Release 单个资产上限 2147483648 字节（且是"小于"）。
#
# 超过上限**不再是致命错误**：publish 阶段会把大资产切成片段再上传，
# 用户下载后 cat 回来即可（见 .github/workflows/release-build.yml 与 dist/FLASH.md）。
# 所以这里只提示"这个要分片"，把判定的责任交给上传环节。
#
# 但仍留一道硬上限：某次改动让镜像失控（比如误装一整套 TeX）时，
# 宁可在这里炸掉，也不要悄悄产出一个 20 GiB 的东西。
ASSET_LIMIT=2147483648
HARD_LIMIT=8589934592          # 8 GiB

say()  { echo "[build] $*"; }
fail() { echo "[build] FATAL: $*" >&2; exit 1; }

# ---------------------------------------------------------------- 0. 前置检查
[ -d "$STAGE" ] || fail "staging not found: $STAGE"
for f in boot/vmlinuz boot/initramfs.cpio.gz extlinux/extlinux.conf .odin-debian \
         usr/lib/systemd/systemd etc/fstab; do
  [ -e "$STAGE/$f" ] || fail "missing in staging: /$f"
done
DTB=$(ls "$STAGE"/boot/dtbs/qcom/*.dtb 2>/dev/null | head -1)
[ -n "$DTB" ] || fail "no dtb under /boot/dtbs/qcom"

# 内核版本不能写死：scripts/setlocalversion 在"工作树不干净"时会追加一个 +，
# 而 CI 里补丁是打在工作树上的（git 里永远是脏的），实际目录名是
# 7.1.3-smartisan-odin+ —— 少那个 + 就找不到模块。
KVER=$(ls "$STAGE/usr/lib/modules" 2>/dev/null | head -1)
[ -n "$KVER" ] || fail "no kernel modules under /usr/lib/modules"
say "staging OK: $STAGE ($(du -sh "$STAGE" | cut -f1)), kernel $KVER"

# ------------------------------------------------- 1. 模块树统一为标准 kernel/ 布局
# 现状：msm8953 模块是手工拷贝进来的，缺 kernel/ 层级，而 modules.builtin 用
# kernel/ 前缀 —— 两套前缀并存会让后续 apt 重装内核头/模块时路径错位。
normalize_modules() {
  local base="$1" root="$2" ver d e
  [ -d "$base" ] || return 0
  for d in "$base"/*; do
    [ -d "$d" ] || continue
    ver=$(basename "$d")
    [ "$ver" = "build" ] || [ "$ver" = "source" ] && continue
    if [ -d "$d/kernel" ]; then
      say "modules $ver: already standard layout"
      continue
    fi
    say "modules $ver: moving into kernel/ ..."
    mkdir -p "$d/kernel"
    for e in "$d"/*; do
      case "$(basename "$e")" in
        kernel | modules.* | build | source) continue ;;
      esac
      mv "$e" "$d/kernel/"
    done
    # depmod 的 basedir 必须是 rootfs 根（merged-usr 下 /lib -> usr/lib）
    depmod -b "$root" "$ver"
    say "modules $ver: depmod regenerated"
  done
}
normalize_modules "$STAGE/usr/lib/modules" "$STAGE"

# ---------------------------------------------------------------- 2. 干净化清单
# machine-id 非空 ⇒ 每台刷出来的设备 ID 相同（并会让 journal 目录沿用旧 ID）。
# 注意：只清空 /etc/machine-id 没用——实测 systemd 会从 /var/lib/dbus/machine-id
# 回填旧值（/etc/machine-id 为空时的 dbus 兼容路径），两个都必须清。
: > "$STAGE/etc/machine-id"
[ -f "$STAGE/var/lib/dbus/machine-id" ] && : > "$STAGE/var/lib/dbus/machine-id"
# SSH 主机私钥同理：镜像要公开发布，带一把固定私钥等于所有设备共用同一身份。
# 由 odin-ssh-hostkeys.service 在首启用 ssh-keygen -A 生成（apply-staging-fixes.sh 装的）。
rm -f "$STAGE"/etc/ssh/ssh_host_*_key "$STAGE"/etc/ssh/ssh_host_*_key.pub
rm -f  "$STAGE/var/lib/systemd/random-seed"
rm -rf "$STAGE"/var/log/journal/*
rm -f  "$STAGE/var/log/wtmp" "$STAGE/var/log/btmp" "$STAGE/var/log/lastlog"
rm -f  "$STAGE/root/.bash_history"
rm -rf "$STAGE"/tmp/* "$STAGE"/var/tmp/* 2>/dev/null || true
rm -rf "$STAGE/mnt/dist"
# apt 缓存与包索引：装完包就再没用了。**GUI 变体光这一项就是 1.2 GiB**（实测），
# 占镜像体积的四分之一，清掉是纯赚，且不影响任何功能。
rm -rf "$STAGE"/var/cache/apt/* "$STAGE"/var/lib/apt/lists/*
say "cleanup done (machine-id/random-seed/journal/wtmp/lastlog/apt-cache)"

# ---------------------------------------------------------------- 3. 建文件系统
#
# 特性集怎么定的（2026-09-05 改：extents 从"关"改成"开"）：
#
#   extents          **开**。之前关掉它是为了迁就 lk2nd —— 它要读根分区里的
#                    /extlinux/extlinux.conf，而它的 ext2 驱动不认识 extents。
#                    代价是根文件系统残缺：swapfile 走 iomap，**需要 extents**，
#                    于是基于文件的 swap 根本建不起来（实测 swapon: EINVAL）。
#                    现在 lk2nd 由补丁 lk2nd/0005 补上只读 extents 支持，
#                    这个枷锁可以摘掉了。详见 reports/035、reports/036。
#
#   metadata_csum    **开**（2026-09-05 再改：之前也关着，理由是"lk2nd 只读不做校验，
#                    开着徒增不兼容面".后来想清楚：metadata_csum 是 ro_compat，
#                    语义就是"只读可忽略"。实测它不改 lk2nd 解析所需的布局（超级块、
#                    组描述符、inode 前半段都不动，目录块尾部多出的 12 字节 fake dirent
#                    lk2nd 的目录扫描能正常跳过。收益是能检测出 eMMC 位翻转造成的
#                    元数据静默损坏。lk2nd 那边由补丁 0006 放行 ro_compat 白名单。
#   extra_isize      关。会让 inode 变大，没必要。
#   huge_file        关。Dir_nlink 同理。
#   dir_nlink        关。
#
# 保留 resize_inode（=> mke2fs 会分配 reserved GDT blocks），为后续 resize 留余地。
#
# -N 显式指定 inode 数量：默认 mke2fs 按"文件系统总大小 / inode_ratio"来分配，
#   而文件系统大小是调用方给的保守估值（通常远大于实际内容），于是白白多出一大张
#   inode 表。更要紧的是 **resize2fs -M 只收缩数据块，不会收缩 inode 表** ——
#   实测：内容 813 MiB，按 1.875 GiB 建的 fs 紧缩后仍要 1.36 GiB，多出来的
#   580 MiB 主要就是那张按大尺寸分配、又缩不回去的 inode 表。
#   所以必须在这里就按实际文件数给准，后面才紧缩得下去。
#   留 20% 余量 + 2000 个固定富余，覆盖 mke2fs -d 期间可能新建的条目。
nfiles=$(find "$STAGE" | wc -l)
ninodes=$(( nfiles * 12 / 10 + 2000 ))
say "inode 数按实际条目算: ${nfiles} 条目 → -N ${ninodes}"
rm -f "$OUT"
mke2fs -q -F -t ext4 -L "$LABEL" \
  -O resize_inode,extents,metadata_csum,^64bit,^huge_file,^dir_nlink,^extra_isize \
  -I 256 -b 4096 -N "$ninodes" -d "$STAGE" "$OUT" "$BLOCKS"
say "mke2fs done ($BLOCKS blocks)"

# 灌入后立即修一次：mke2fs -d 不会同步 free 计数到最终状态
e2fsck -f -y "$OUT" > /dev/null 2>&1 || true
say "e2fsck pass done"

# ------------------------------------------------- 3b. 紧缩到"实际需要 + 冗余"
#
# 为什么需要这一步：调用方给的 BLOCKS 只能是个保守的估值（要留足 mke2fs 期间
# 元数据扩张的余地），实际内容往往只占一半。实测 813 MiB 的内容躺在 1.875 GiB
# 的镜像里，多出来的 1 GiB 全是空的，却要照付构建、上传、下载、刷入的时间。
#
# 做法不是去猜一个更准的系数，而是**让文件系统自己说出它需要多大**：
#   1) resize2fs -M  → 收缩到理论最小（这个最小值是精确的，不是估算）
#   2) +SLACK        → 留一点余量，避免首次启动后连装个包就满
#   3) truncate      → 把镜像文件本身也截到新尺寸，否则只是 fs 小了文件没小
#
# 注意 resize2fs -M 只能对已卸载、已 e2fsck 干净的文件系统做，所以放在这里。
SLACK_MIB=${SLACK_MIB:-100}
BS=4096
min_blocks=$(resize2fs -M "$OUT" 2>&1 | sed -n 's/.*now \([0-9]*\).*blocks long.*/\1/p' | tail -1)
if [ -z "$min_blocks" ]; then
  # 某些版本输出措辞不同，回退到从超级块读
  min_blocks=$(dumpe2fs -h "$OUT" 2>/dev/null | awk -F: '/^Block count/{gsub(/ /,"",$2); print $2}')
fi
if [ -n "$min_blocks" ]; then
  slack_blocks=$(( SLACK_MIB * 1024 * 1024 / BS ))
  want_blocks=$(( min_blocks + slack_blocks ))
  # 对齐到 16 MiB，避免产生零头
  align=$(( 16 * 1024 * 1024 / BS ))
  want_blocks=$(( (want_blocks + align - 1) / align * align ))
  say "紧缩: 最小 ${min_blocks} 块 ($((min_blocks*BS/1048576)) MiB) + 冗余 ${SLACK_MIB} MiB → ${want_blocks} 块"
  resize2fs -f "$OUT" "$want_blocks" > /dev/null 2>&1
  # fs 缩小后文件本身还没变小，必须截断，否则前面全白做
  truncate -s $(( want_blocks * BS )) "$OUT"
  e2fsck -f -y "$OUT" > /dev/null 2>&1 || true
  say "紧缩后: $(du -h "$OUT" | cut -f1)（调用方原本给的是 $BLOCKS 块）"
else
  say "紧缩: 读不到最小块数，跳过（保持调用方给的 $BLOCKS 块）"
fi

# ---------------------------------------------------------------- 4. 导出 sparse
rm -f "$SPARSE"
img2simg "$OUT" "$SPARSE"
say "img2simg done: $(du -h "$SPARSE" | cut -f1)"

for f in "$OUT" "$SPARSE"; do
  s=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
  if [ "$s" -ge "$HARD_LIMIT" ]; then
    fail "$f 有 $s 字节，超过硬上限 $HARD_LIMIT 字节（8 GiB）—— 多半是误装了什么，查 staging 内容"
  elif [ "$s" -ge "$ASSET_LIMIT" ]; then
    say "注意: $f 有 $s 字节，超过 GitHub 单资产上限 $ASSET_LIMIT，publish 阶段会切成片段上传"
  fi
done

# ---------------------------------------------------------------- 5. 回读校验
rc=0
note() { printf '  %-34s %s\n' "$1" "$2"; }

echo "[build] === verify ==="

FEAT=$(dumpe2fs -h "$OUT" 2>/dev/null | sed -n 's/^Filesystem features: *//p')
LBL=$(dumpe2fs -h "$OUT" 2>/dev/null | sed -n 's/^Filesystem volume name: *//p')
# e2fsprogs 1.47 的 dumpe2fs -h 不再打印 Reserved GDT blocks，直接读超级块 0xCE
RDT=$(od -A n -j 1230 -N 2 -t u2 "$OUT" | tr -d ' ')
RO=$(od -A n -j 1124 -N 4 -t u4 "$OUT" | tr -d ' ')
note "features" "$FEAT"
note "reserved GDT blocks" "${RDT:-0}"
note "label" "$LBL"

case "$FEAT" in *resize_inode*) note "resize_inode" "OK" ;;
  *) note "resize_inode" "MISSING"; rc=1 ;; esac
[ "${RDT:-0}" -gt 0 ] && note "reserved GDT > 0" "OK" || { note "reserved GDT > 0" "ZERO"; rc=1; }
# 正向断言：这两个是**必须**开着的
#   extents        —— swapfile 需要它；lk2nd 靠补丁 0005 提供只读支持
#   metadata_csum  —— 元数据校验，能检测出静默损坏；lk2nd 靠补丁 0006 放行 ro_compat
for want in extent metadata_csum; do
  case "$FEAT" in *$want*) note "$want" "OK" ;;
    *) note "$want" "MISSING"; rc=1 ;; esac
done
# 其余仍是 lk2nd 的 ext2 驱动读不了的，必须关着
for bad in 64bit huge_file dir_nlink extra_isize; do
  case "$FEAT" in *$bad*) note "forbidden feature: $bad" "PRESENT"; rc=1 ;; esac
done
#
# lk2nd 的 ext2 驱动挂载门槛（lib/fs/ext2/ext2.c）。ro_compat 的语义是"只读可忽略"，
# 它放行的是：
#     sparse_super   0x001
#     large_file     0x002
#     metadata_csum  0x400   ← 补丁 0006 加的（只读不需要验证校验和，实测也不改
#                               lk2nd 解析所需的布局，见 reports/036 §7）
#   合计 0x403。多出任何一位 lk2nd 都会拒绝挂载 ⇒ 引导不了，所以这里按位核对，
# 而不是只看特性名清单（清单是给人看的，位掩码才是真正决定 lk2nd 会不会拒绝的东西。
# 2026-09-05 就栽在这：开了 metadata_csum 但这里还是老的 ~3 掩码，镜像明明是对的，
# 自检却报 WILL REFUSE，rootfs job 直接失败。）
RO_ALLOWED=$(( 0x1 | 0x2 | 0x400 ))
MRO=$(( RO & ~RO_ALLOWED ))
note "ro_compat" "0x$(printf '%x' "$RO") (allowed 0x$(printf '%x' "$RO_ALLOWED"), masked 0x$(printf '%x' "$MRO"))"
[ "$MRO" -eq 0 ] && note "lk2nd mountable" "OK" || { note "lk2nd mountable" "WILL REFUSE"; rc=1; }
[ "$LBL" = "$LABEL" ] || { note "label" "expected $LABEL"; rc=1; }

# e2fsck -fn 干净时退出码为 0（1.47 的输出里没有 "clean" 字样，只能看退出码）
if e2fsck -fn "$OUT" > /tmp/_fsck.out 2>&1; then
  note "e2fsck -fn" "clean ($(grep -c . /tmp/_fsck.out) lines)"
else
  note "e2fsck -fn" "DIRTY (rc=$?)"; grep -vE "^Pass|^$" /tmp/_fsck.out | head -8; rc=1
fi

# debugfs 对不存在的路径也返回 0，必须看输出里有没有 Inode 行
exists() { debugfs -R "stat $1" "$OUT" 2>&1 | grep -q "^Inode: [0-9]"; }

python3 "$REPO/tools/check_sparse.py" "$SPARSE" "$OUT" > /tmp/_sparse.out 2>&1 \
  && note "check_sparse" "$(cat /tmp/_sparse.out)" \
  || { note "check_sparse" "FAILED: $(cat /tmp/_sparse.out)"; rc=1; }

# initramfs / vmlinuz 与仓库 stage 副本一致性
if [ -f "$REPO/dist/stage/initramfs.cpio.gz" ]; then
  A=$(debugfs -R "cat /boot/initramfs.cpio.gz" "$OUT" 2>/dev/null | md5sum | cut -d' ' -f1)
  B=$(md5sum "$REPO/dist/stage/initramfs.cpio.gz" | cut -d' ' -f1)
  [ "$A" = "$B" ] && note "initramfs md5" "$A" || { note "initramfs md5" "image=$A repo=$B"; rc=1; }
fi
for p in /extlinux/extlinux.conf /boot/vmlinuz /boot/dtbs/qcom/$(basename "$DTB") /.odin-debian \
         /usr/local/sbin/odin-firstboot-resize.sh /etc/NetworkManager/conf.d/99-odin-usb0.conf \
         /usr/lib/modules/$KVER/kernel/drivers/gpu/drm/panel/panel-r69006.ko; do
  exists "$p" && note "present $p" "OK" || { note "present $p" "MISSING"; rc=1; }
done
# 发布态不得带这些残留
for p in /var/lib/odin-resize-done /var/lib/systemd/random-seed /mnt/dist \
         /boot/msm8953-smartisan-odin.dtb /usr/lib/modules/$KVER/drivers; do
  exists "$p" && { note "residual $p" "PRESENT (should be gone)"; rc=1; } || note "residual $p" "absent"
done
# 扩容服务必须处于启用态；machine-id 必须为空（否则所有设备同 ID）
exists /etc/systemd/system/multi-user.target.wants/odin-firstboot-resize.service \
  && note "resize service enabled" "OK" || { note "resize service enabled" "NOT ENABLED"; rc=1; }
MID=$(debugfs -R "cat /etc/machine-id" "$OUT" 2>/dev/null | tr -d '\0\r\n')
[ -z "$MID" ] && note "machine-id" "empty (regenerates on first boot)" \
  || { note "machine-id" "NOT EMPTY: $MID"; rc=1; }
DID=$(debugfs -R "cat /var/lib/dbus/machine-id" "$OUT" 2>/dev/null | tr -d '\0\r\n')
[ -z "$DID" ] && note "dbus machine-id" "empty (no stale id to restore)" \
  || { note "dbus machine-id" "NOT EMPTY: $DID"; rc=1; }

echo "[build] ========================"
[ "$rc" -eq 0 ] && echo "[build] ALL CHECKS PASSED -> $OUT" || echo "[build] CHECKS FAILED"
exit "$rc"
