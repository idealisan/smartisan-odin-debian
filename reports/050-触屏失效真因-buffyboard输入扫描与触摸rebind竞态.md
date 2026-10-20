# 050 — 触摸"突然失效"真因：buffyboard 输入扫描与触摸 rebind 的开机竞态

日期：2026-10-20　设备：ODIN（Smartisan U2 Pro, msm8953）　基线：v0.9.9（kb 变体）

现象：用户报告"之前触摸屏是好的，现在不能触摸了"。SSH 进真机（172.16.42.1，
user/user）排查，全程只读诊断；定位后真机验证修复，再回写构建树
（`dist/build/rootfs/etc/systemd/system/buffyboard.service.d/odin-after-touchscreen.conf`）。

---

## 一、内核层是好的（先排除硬件）

- 触摸 IC 是 **FT8716**（I2C 1-0038，`edt_ft5x06` 驱动绑定，中断 msmgpio/65）。
- 直接读 `/dev/input/event5`（python unpack input_event，24 字节/事件）：
  **8 秒抓到 534 个完美事件** —— ABS_MT_POSITION_X/Y 流畅滑动
  （X 625→736、Y 1610→1466）、BTN_TOUCH 1/0、ABS_MT_TRACKING_ID 281→285、
  SYN_REPORT 齐全。
- `/proc/interrupts` 中 `ft8716` 中断计数只有触摸时才增长（静置 5s 计数不变），
  CRC/header 错误均为 0。DT 分辨率 `touchscreen-size = <1080> <1920>` 正确。
- 结论：**硬件、I2C、驱动、evdev 全部正常。**

## 二、真因：buffyboard 从没打开过 event5

1. `/proc/$(pgrep buffyboard)/fd` 里**没有** `/dev/input/event5`——只有
   `fb0`、`/dev/input/event0`（spmi_haptics，按键震动反馈）、自创建的 `/dev/uinput`。
2. `/proc/PID/fdinfo/4`（epoll）监听的 fd 里也**没有 event5**。
3. 同窗口做端到端探测（同时监听 event5 与 buffyboard 的 uinput event4）：
   触摸产生 38 个内核事件，**uinput 0 事件** —— buffyboard 根本没消费。
4. `strings /usr/local/bin/buffyboard` 只有 `libinput_path_add_device` /
   `libinput_path_create_context`，**没有任何 `libinput_udev_*` 符号** ⇒
   buffyboard 用的是 libinput **path 模式**：启动时扫一遍 `/dev/input`
   （二进制里有 `/dev/input`、`/dev/input/%s` 扫描字符串），**此后永不重扫、
   不支持热插拔**。`odin-buffyboard-redraw` 每 2 秒的 SIGUSR1 也只走到
   `lv_obj_invalidate(keyboard)`（见 odin-buffyboard-redraw.sh 头部注释），
   不补扫设备。

## 三、竞态时间线（2026-10-19 20:55:55 这次开机）

| 时刻（wall） | 事件 |
| --- | --- |
| +15s | spmi_haptics 注册（event0，buffyboard 后来只抓到它） |
| buffyboard Started 20:56:20 | `After=getty.target`，启动后**当场扫 /dev/input**（当时 event5 还不存在） |
| 20:56:22.3 | `odin-touchscreen.service` 里 `modprobe -r + modprobe edt_ft5x06` 完成，**event5 节点此刻才出现**（节点 mtime 实测） |
| 20:56:24 | `[touch] ✅ 触摸已注册` |

`journalctl -b -1` 显示上一次开机（10-08）**同样的 ~2 秒顺序**（buffyboard
23:32:54 起、event5 23:32:56 生）⇒ 这两次开机都输了竞态；历史上摸得着的开机
都是 buffyboard 恰好晚于触摸注册。"之前是好的、现在突然不能摸"就是这两个
unit 的随机启动顺序，不是硬件退化。

---

## 四、修复与真机验证

修法（示例 `buffyboard.service.d/odin-after-touchscreen.conf`）：

```ini
[Unit]
After=odin-touchscreen.service
```

`After=` 对 Type=oneshot 的语义是等它 ExecStart 跑完；这样 buffyboard
启动扫描时 event5 必然已在。**不用 Requires=**：odin-touchscreen 若失败
（如等不到显示链）也不该挡住 buffyboard 起来。

真机验证（2026-10-20 20:11）：

1. drop-in 放入 → `systemctl daemon-reload` → `systemctl show` 的 After 里
   出现 `odin-touchscreen.service` ✓
2. `systemctl restart buffyboard` → fd 列表出现 **`/dev/input/event5`** ✓
3. 端到端复测：触摸产生 28 个内核事件，uinput 注入 11 个事件，键值为
   `KEY_J / KEY_H / KEY_H` —— **键盘恢复了**，用户当场确认。

> 修复前 buffyboard 的设备列表是在启动时冻结的，本次真机还顺带解释了一个
> 疑似断点：22 小时的运行中 libinput 层 suspend/resume 只会**重开已有列表里的
> 设备**（fd 时间戳变化），不会重新扫描 —— 所以触摸问题不会自行好转。

回写构建树：

- 新增 `dist/build/rootfs/etc/systemd/system/buffyboard.service.d/odin-after-touchscreen.conf`
  （同样只有 After= 一行 + 完整注释）。
  `apply-staging-fixes.sh` 的覆盖树整树拷贝会把它带进 staging；drop-in 无需
  enable 符号链接。buffyboard.service 本体在 `/usr/lib/systemd/system`（meson
  `-Dsystemd=true` 产物，见 tools/ci/build-buffyboard.sh），`/etc` 里的 drop-in
  与其叠加生效。
- 该 drop-in 只影响 kb 变体（buffyboard 只在 kb 里装）；其它变体没有这个
  unit，After 指向的 odin-touchscreen.service 覆盖树里必有，无不良影响。
