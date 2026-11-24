# 实验二 基于 PWM 调制技术的呼吸灯系统设计

## 1. 实验要求（对应评分记录表检查项）

2026 年实验二属于"实验二~四选二"的限选实验，每项 5 分 = 基本要求 2 分 + 现场按要求修改 2 分 + 独创性内容展示 1 分。

| 要求 | 实现 | 状态 |
|---|---|---|
| LED8 呼吸效果，每 1s 亮灭一次 | 三角波 `ramp` 控制 PWM 占空比，默认档周期 1s | 已仿真 |
| Key1 在 0.5/1/1.5/2s 四档间循环切换 | `speed_idx` 0..3，公式化步进间隔 | 已仿真 |
| Key4 调亮度（等级自定义） | `bright_idx` 0..3：100/75/50/25%，不改变呼吸周期 | 已仿真 |
| Reset 键有效（评分记录表检查项） | Key3：回默认档，并从全灭重新呼吸 | 已仿真 |
| 检测时现场修改代码展示 | 见第 6 节，5 条预案已仿真验证 | 已仿真 |
| 独创性内容展示（1 分） | **尚未实现** | 待做 |

"已仿真"指逻辑功能通过 nvc 仿真；**尚未在 Lattice Diamond 中综合，也没有上板**（见第 8 节）。

## 2. 设计框图

```
                +------------------+ key1_pressed
 key1 (L14) ----> key_debounce    +---------------+
                |  40ms 消抖       |               v
                +------------------+      +---------------------+
                +------------------+      |  breath_engine      |  pwm_out (高=点亮)
 key4 (N14) ----> key_debounce    +----->|  . 速度/亮度档位     +---------------+
                |  40ms 消抖       |      |  . 三角波 ramp      |               |
                +------------------+      |  . 亮度缩放 -> duty  |               |  取反
                +------------------+      |  . PWM 计数器+比较器 |               v
 key3 (M14) ----> key_debounce    +----> rst_n (异步, 低有效)        +----------+
                |  40ms 消抖       |                                  | led8 ~pwm|--> P9
                +------------------+                                  +----------+
 clk12m (C1, 12MHz) --> 全局时钟
```

模块划分：

- `key_debounce.vhd`：消抖单元。两级触发器同步，40ms 计数消抖，输出消抖后电平和按下沿单周期脉冲。
- `breath_engine.vhd`：呼吸引擎。三角波斜坡（计数器 + 方向逻辑）、档位控制、PWM 相位计数器与比较器。
- `breathing_led_top.vhd`：顶层。例化三个消抖单元和一个引擎，按板上极性取反后驱动 LED8。

## 3. 关键参数推导

- PWM 频率 = 12MHz / PWM_PERIOD(12000) = 1kHz，高于人眼闪烁融合阈值。`pwm_cnt < duty` 时输出点亮。
- 三角波 `ramp` 在 0..12000 之间往返，每 `STEP_BASE_CLKS x (speed_idx+1)` = 250 x (speed_idx+1) 个时钟走一步。
  - 半周期 = 12000 x 250 x (speed_idx+1) 个时钟 = 0.25s x (speed_idx+1)，即 0.25 / 0.5 / 0.75 / 1s；呼吸周期为 0.5 / 1 / 1.5 / 2s。
  - 验算默认档 speed_idx=1：12000 步 x 500 clk = 6,000,000 clk = 0.5s 半周期，呼吸周期 1s。
- 占空比阈值 `duty = ramp x (BRIGHT_LEVELS - bright_idx) / BRIGHT_LEVELS`，亮度档只做缩放。
- 速度与亮度解耦：呼吸周期只由 Key1 决定，调亮度不会让呼吸变快或变慢（题目要求"每 1 秒钟亮灭一次"）。

## 4. 板级连接与极性（依据 STEP-MXO2 V2.1 原理图）

| 信号 | 引脚 | 说明 |
|---|---|---|
| clk12m | C1 | 12MHz 晶振 |
| key1 | L14 | 速度切换，按下 = '0'（板上有 10K 上拉） |
| key3 | M14 | Reset，按下 = '0' |
| key4 | N14 | 亮度切换，按下 = '0' |
| led8 | P9 | '0' 点亮（LED 阳极经 470R 接 3.3V），顶层取反 |

约束文件：`constraints/breathing_led.lpf`。写法与往届小组在本板上跑通的工程约束一致，只用 `BLOCK RESETPATHS` / `BLOCK ASYNCPATHS`、`LOCATE COMP`、`IOBUF PORT ... IO_TYPE=LVCMOS33`，注释全 ASCII。按键已有外部上拉，没有开内部上拉。**该文件还没有在 Diamond 里实际加载过。**

## 5. 仿真验证（nvc，自检式 testbench）

TB 通过 generic 把板级参数缩小 100 倍（PWM 周期 100us，默认呼吸周期 10ms，消抖 1ms），全程约 0.32s 仿真时间。监视器只看 led8 波形：点亮窗口的最大时长反映峰值占空比；相邻点亮窗口之间熄灭超过 0.85 个 PWM 周期记为谷底，相邻两簇谷底之差就是呼吸周期。TB 带 2s 看门狗，激励挂住时报失败而不是无限等待。

| 组 | 检查内容 | 结果 |
|---|---|---|
| T0 | 上电不按键：直接以默认档呼吸（周期 10ms，亮度 100%） | PASS |
| T1 | Key3 复位：从全灭重新呼吸，回默认档 | PASS |
| T2 | Key1 后周期 15ms | PASS（15.0ms） |
| T5 | 只有毛刺的按键不触发亮度或速度切换 | PASS |
| T3 | Key4 到 75%：峰值 75%，周期仍 15ms | PASS（75%，15.0ms） |
| T6 | Key4 到 50%：峰值 50%，周期仍 15ms | PASS（49%，15.0ms） |
| T7 | Key4 到 25%：峰值 25%，周期仍 15ms | PASS（24%，15.0ms） |
| T4 | Key3 复位：回 100% 与 10ms | PASS |

共 25 项检查，`nvc` 退出码 0。

另外三组对照运行：

- **旧版本引擎**（已推送到 GitHub 的第一版，调亮度会连带改周期）：同一 TB 报 3 项 FAIL，75/50/25% 亮度下周期分别为 11.2 / 7.5 / 3.8ms。说明新增的解耦检查确实能抓到这个错误。
- **寄存器上电全 0 的副本**（把所有声明初值改成 0，模拟综合器不保留初值）：25 项全过。上电后复位先保持一个消抖周期，LED 不亮，随后以默认档开始呼吸。
- **VHDL-93 分析与 elaboration**（`nvc --std=1993`）：通过，无 error/warning。

复现（在本目录）：

```sh
nvc -a src/key_debounce.vhd src/breath_engine.vhd src/breathing_led_top.vhd sim/tb_breathing_led.vhd \
    -e tb_breathing_led -r --wave=breath.fst
```

波形 `breath.fst` 用 GTKWave 查看，不入库。`nvc --wave` 输出的一律是 FST 格式，与扩展名无关。

**未验证的部分**：本机没有 Diamond 和 ModelSim，综合结果（是否报 latch、资源占用、warning）、`.lpf` 是否被接受、上板后的实际亮度与按键响应、TB 在 ModelSim 下能否编译运行，都还没有验证。

## 6. 检测现场修改预案

往届小组实验二被要求的修改是"将复位默认档位调整为最快最亮"。下表每条都给出改哪里；"已仿真"的几条在副本上实际改过并跑过 TB。

| 现场要求 | 改哪里 | 验证 |
|---|---|---|
| 默认档改为最快 | `ramp_proc` 复位分支 `speed_idx <= 1` 改成 `0`（亮度默认已是 100%） | 已仿真：上电和复位后周期 5ms（板上 0.5s） |
| 亮度改成 8 档 | 常量 `BRIGHT_LEVELS := 8` | 已仿真：第一次按 Key4 峰值 87%（7/8） |
| 速度也改成 8 档 | 常量 `SPEED_LEVELS := 8` | 仅 nvc elaboration 通过，默认档行为不变 |
| 慢呼（变暗段的步进间隔是变亮段的 2 倍） | 见下方代码 | 已仿真：默认档总周期 15ms（设计上 5ms 变亮 + 10ms 变暗，仿真只测了总周期） |
| 整体放慢一倍 | 顶层 generic `STEP_BASE_CLKS => 500` | 未验证 |

慢呼的改法（`breath_engine.vhd`，三处一起改，否则 `step_limit` 超出整数范围）：

```vhdl
signal step_limit : integer range 0 to STEP_BASE_CLKS * SPEED_LEVELS * 2 - 1;
signal pre_cnt    : integer range 0 to STEP_BASE_CLKS * SPEED_LEVELS * 2 - 1 := 0;

step_limit <= STEP_BASE_CLKS * (speed_idx + 1) * 2 - 1 when ramp_up = '0' else
              STEP_BASE_CLKS * (speed_idx + 1) - 1;
```

改完默认值或档数之后，TB 里写死的期望值（10ms、15ms、75/50/25%）会跟着对不上，这是预期的；看 FAIL 行里的 measured 数值是否符合新预期即可。

## 7. 上板步骤（Diamond）

以下按 Diamond 的常规流程写，首次上板时请逐步核对。

1. New Project：器件 LCMXO2-4000HC，封装对应型号里的 MG132（CSBGA132），速度等级 4；语言 VHDL。
2. 加入 `src/` 下三个 `.vhd`，把 `breathing_led_top` 设为顶层。
3. 约束：Diamond 每个工程只读工程目录下与工程同名的 `.lpf`。把 `constraints/breathing_led.lpf` 的内容贴进工程自动生成的那个 `.lpf`。
4. 综合实现后导出 bitstream，再打开 Programmer 下载。下载文件在 `impl1/` 里（`<顶层名>_impl1.jed`），Programmer 默认路径可能要手动改到这个目录。
5. 观察 LED8 呼吸；按 Key1 变速、Key4 变亮、Key3 复位。

编码：源码注释是 UTF-8。往届工程里有用 UTF-8 注释在 Diamond 3.12（LSE 综合）下编过的先例，综合日志里没有编码报错；Diamond 编辑器里中文可能显示成乱码。ModelSim 对 UTF-8 注释没有先例，往届小组实验二的源码和 TB 都是 GBK。如果 `vcom` 因编码报错，生成一份 GBK 副本再编：

```sh
mkdir -p gbk && for f in src/*.vhd sim/*.vhd; do iconv -f UTF-8 -t GBK "$f" > "gbk/$(basename "$f")"; done
```

ModelSim 运行 TB 的命令（未在 ModelSim 下验证）：`vlib work && vcom <源文件与 tb> && vsim tb_breathing_led -do "run -all"`。

## 8. 待办与风险

- [ ] Diamond 综合：确认无 latch 和其他 synthesis 问题，记下资源占用与 warning（报告要用）。
- [ ] 上板：确认 `.lpf` 被接受、上电即默认档、三个按键和 LED 极性与第 4 节一致。
- [ ] ModelSim 下跑通 TB，截带注释的波形。
- [ ] 独创性功能（1 分）：目前没有任何独创性内容，需要一个能当场演示的功能。
- [ ] 检测时随机抽一名组员演示并现场修改，每位组员都要能独立讲清三个模块和第 6 节的改法。
