# tools/docker-diamond - Mac 上用 Diamond 无头综合 MachXO2 工程

目标：在 Mac 上完成 exp2 的综合→布局布线→出 `.jed`，再由宿主机 `openfpgaloader` 烧板。
综合结果与课程环境同源（同一 Diamond 工具链），报告所需的资源占用与 warning 也从这里拿。

## 已验证（2026-11-25）

- Apple Silicon 上 amd64 容器可运行（Rosetta；Docker Desktop，无 QEMU 回退需求）。
- 镜像 `diamond-mxo2` 已从安装器的 7z 分段直接组装完成（目录树齐全，bin/lin64 833 个文件）。
- `diamondc`（实为 pnmainc 包装脚本）在容器内正常启动，Tcl 引擎可用；
  失败点只剩 FlexNet license：Feature `LSC_DIAMOND_A`，查找路径即我们配置的
  `/work/license/license.dat` —— 与设计完全一致，license 到位即通。
- 官方安装器是 Qt IFW GUI（不是 BitRock，`--mode` 不存在），无界面模式
  下 xcb 平台 FPE 崩溃（Rosetta）、minimal 平台挂死——故采用 7z 分段直接组装。

## 一次性准备

1. **安装包**（已完成）：`installer/3.14.0.75.2_Diamond_lin.run`（2.1GB）。
   `carve.py` 把它解剖成 7z 分段（`installer/carved/`），Dockerfile 跳过
   questasim(1.1GB) 和 micosystem 段直接解包组装。若换新版本安装器，重跑
   `python3 carve.py` 并检查 `seg*.7z` 的目录映射（脚本内注释）。
2. **license**（唯一待办）：Lattice Support → Licensing → Node-Locked License
   （LSC-SW-NL，免费），MAC/Host ID 填 `00:0c:29:d5:14:8e`（容器固定 MAC，
   run-synth.sh 的 `--mac-address` 与之对应）。license 文件存到
   `license/license.dat`。绑容器 MAC：换电脑/重装不影响。

其余全部脚本化：

```sh
cd tools/docker-diamond
./build-image.sh     # 已完成，镜像 diamond-mxo2 就绪（改动后重建约 3-5 分钟）
./run-synth.sh       # 一次完整综合，产物在 out/
```

`out/` 里应有 `breathing_led_top_impl1.jed` 加 `*.mrp`（资源）、`*.tw1`（时序）、
`synthesis.log`（warning，报告素材）。

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
在虚拟机里装 openfpgaloader 执行同样命令。

## 结构

```
Dockerfile      rockylinux:8 + carved 7z 分段组装（跳过 questasim/micosystem）
build.sh        容器内入口：跑 build.tcl，收 .jed/.mrp/.tw1/log 到 /work/out
build.tcl       prj_project open -> Synthesis/Map/PAR/Export(Bitgen) -> close
exp2.ldf        手写 Diamond 工程文件（XML，参照往届跑通的 ldf），顶层 breathing_led_top
carve.py        从官方 .run 安装器解剖 7z 分段
installer/      官方 .run（不入库）+ carved/ 分段（不入库）
run-synth.sh    宿主侧包装：挂 src/constraints/license/out，固定 MAC 00:0c:29:d5:14:8e
build-image.sh  宿主侧镜像构建
license/        license.dat（不入库）
out/            综合产物（不入库）
```

## 已知不确定点（跑通后回填）

- `prj_run Export -impl impl1 -task Bitgen` 的任务名按社区通用写法写，未实测；报错看 out/ 日志改 build.tcl。
- license 校验是否只看 MAC（FlexNet hostid=eth0），`--mac-address` 已固定；若 Lattice 还绑
  其他 hostid 形式需回退 Gekkio 挂宿主 MAC 的做法。
- LSE 综合对现有 VHDL 的处理与 nvc 仿真已尽量对齐，但综合 warning 需人工过一遍（报告素材）。
