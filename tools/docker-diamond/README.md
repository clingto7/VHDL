# tools/docker-diamond - Mac 上用 Diamond 无头综合 MachXO2 工程

目标：在 Mac 上完成 exp2 的综合→布局布线→出 `.jed`，再由宿主机 `openfpgaloader` 烧板。
综合结果与课程环境同源（同一 Diamond 工具链），报告所需的资源占用与 warning 也从这里拿。

## 已验证 / 未验证

- 已验证：Apple Silicon 上 `--platform linux/amd64` 容器（rockylinux:8 + yum）可正常运行。
- 未验证：Diamond 安装与无头综合流程（缺 rpm，无法构建镜像前先写好）；
  `diamondc` 是否在所选 Diamond 版本里（脚本已做 Xvfb 回退）；
  license 生效；烧录（需板子接上）。

## 一次性准备（需要你做的两件人工活）

1. **下载 Diamond Linux 安装包**（账号墙，只能浏览器做）：
   注册/登录 https://www.latticesemi.com → Products → Design Software → Lattice Diamond
   → 下载 "Diamond 3.14 64-bit for Linux"（约 1-2 GB）
   → 放到 `tools/docker-diamond/rpm/` 下，文件名不改。
2. **申请 license**（同样要账号）：Lattice Licensing Portal 申请 Node-locked Free License，
   MAC 填 `02:50:F2:00:00:42`（这是容器固定 MAC，run-synth.sh 里 `--mac-address` 与之对应）。
   收到的 license 文件放 `tools/docker-diamond/license/license.dat`。

其余全部脚本化：

```sh
cd tools/docker-diamond
./build-image.sh     # 构建镜像（首约 10-30 分钟，视网速）
./run-synth.sh       # 一次完整综合，产物在 out/
```

`out/` 里应有 `<top>_impl1.jed` 加 `*.mrp`（资源占用）、`*.tw1`（时序）、`synthesis.log`（warning，报告素材）。

## 烧板（宿主机，无需容器）

```sh
# 0) 若报"无法打开设备"，先放行 USB（Intel 时代做法，Apple Silicon 可能被 SIP 挡，见下）
sudo kextunload -b com.apple.driver.AppleUSBFTDI

# 1) 插上小脚丫，烧 SRAM（掉电丢失，调试用）
openfpgaloader -c ft232H out/breathing_led_top_impl1.jed

# 2) 或写内部 flash（上电自启动）
openfpgaloader -c ft232H -f out/breathing_led_top_impl1.jed
```

若 kextunload 被 SIP 挡住：备选是 VMware Fusion / UTM 里跑 Linux 虚拟机 + USB 直通，
在虚拟机里 `apt install openfpgaloader`（或源码编译）执行同样命令。

## 结构

```
Dockerfile      rockylinux:8 + Diamond rpm，amd64 模拟
build.sh        容器内入口：跑 build.tcl，收 .jed/.mrp/.tw1/log 到 /work/out
build.tcl       prj_project open -> Synthesis/Map/PAR/Export(Bitgen) -> close
exp2.ldf        手写 Diamond 工程文件（XML，参照往届跑通的 ldf），顶层 breathing_led_top
run-synth.sh    宿主侧包装：挂 src/constraints/license/out，固定 MAC 02:50:F2:00:00:42
build-image.sh  宿主侧镜像构建（缺 rpm 时打印指引）
rpm/            你放的安装包（不入库）
license/        license.dat（不入库）
out/            综合产物（不入库）
```

## 已知不确定点（跑通后回填）

- `prj_run Export -impl impl1 -task Bitgen` 的任务名按社区通用写法写，未实测；若报错看 build.sh
  打印的 bin 目录内容，改 build.tcl。
- `diamondc` 在 3.14 Linux 里存在与否未验证，不存在则走 Xvfb + `diamond -t` 回退。
- Node-locked license 校验的是容器 eth0 MAC，`--mac-address` 已固定；若 Lattice license 还要求
  hostid 其他形式（如磁盘），需回退到 Gekkio 的做法（挂载宿主 MAC）。
- LSE 综合对 `integer range`/无 latch 风格代码的处理与 nvc 仿真已尽量对齐，但综合警告需人工过一遍。
