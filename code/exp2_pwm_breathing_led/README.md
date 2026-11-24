# 实验二 基于 PWM 调制技术的呼吸灯系统设计

## 1. 实验要求（对应评分记录表检查项）

| 要求 | 实现 | 检查项 |
|---|---|---|
| LED8 呼吸效果，默认每 1s 亮灭一次 | 默认档呼吸周期 1s（0.5s 变亮 + 0.5s 变熄） | 呼吸是否平滑 |
| Key1 循环切换 0.5/1/1.5/2s 四档速度 | speed_idx 0..3，公式化步进间隔 | 模式是否可调 |
| Key4 亮度可调（等级自定义） | bright_idx 0..3：100/75/50/25% | 亮度是否可调 |
| Reset 键有效 | Key3：回默认档 + 从全灭重新呼吸 | Reset 键是否有效 |
| 检测时现场简单修改代码展示 | 参数全部公式化，改常数即可改档位（见 §6） | 按要求修改展示 |

## 2. 设计框图

```
                +------------------+ key1_pressed
 key1 (L14) ----> key_debounce    +---------------+
                |  40ms 消抖       |               v
                +------------------+      +------------------+
                +------------------+      |  breath_engine   |  pwm_out (高=点亮)
 key4 (N14) ----> key_debounce    +----->|  . 速度/亮度档位  +---------------+
                |  40ms 消抖       |      |  . 呼吸斜坡(duty) |               |
                +------------------+      |  . PWM 发生器    |               |  取反
                +------------------+      +------------------+               v
 key3 (M14) ----> key_debounce    +----> rst_n (异步, 低有效)        +----------+
                |  40ms 消抖       |                                  | led8 ~pwm|--> P9
                +------------------+                                  +----------+
 clk12m (C1, 12MHz) --> 全局时钟
```

模块划分（标准单元可识别）：
- `key_debounce.vhd` — **消抖单元**：两级同步 + 40ms 计数消抖 + 按下沿单周期脉冲
- `breath_engine.vhd` — **呼吸引擎**：内含 PWM 相位**计数器**、占空比斜坡（带方向的状态逻辑）、档位控制
- `breathing_led_top.vhd` — 顶层：例化三个消抖 + 引擎，处理板上极性取反

## 3. 关键参数推导

- PWM 频率：12MHz / PWM_PERIOD(12000) = **1kHz**（高于人眼闪烁融合阈值）
- 占空比 = duty / PWM_PERIOD；`pwm_cnt < duty` 时输出点亮
- 呼吸斜坡：duty 每 `STEP_BASE_CLKS x (speed_idx+1)` 个时钟 ±1
  - 变亮半周期 = 12000 步 x 步进间隔 → speed_idx=1（默认）时 = 12000 x 500 clk = 0.5s → 呼吸周期 1s ✓
- 亮度上限 = PWM_PERIOD x (4-bright_idx)/4 → 100/75/50/25%
- 速度四档与亮度四档均为公式生成，**不使用查找表**，方便现场改档位数

## 4. 板级连接与极性（依据 STEP-MXO2 V2.1 原理图）

| 信号 | 引脚 | 说明 |
|---|---|---|
| clk12m | C1 | 12MHz 晶振 |
| key1 | L14 | 速度切换，按下='0'（10K 上拉） |
| key3 | M14 | Reset，按下='0' |
| key4 | N14 | 亮度切换，按下='0' |
| led8 | P9 | **'0' 点亮**（LED 阳极经 470R 接 3.3V），顶层取反 |

约束文件：`constraints/breathing_led.lpf`。

## 5. 仿真验证（nvc，自检式 testbench）

TB 通过 generic 缩放 100 倍加速（PWM 周期 100us、默认呼吸周期 10ms、消抖 1ms），
全部激励 <0.15s 仿真时间。被动监视器从 led8 波形测：点亮峰值时长（→亮度上限）、
相邻点亮窗口间隔 >0.85 PWM 周期判 duty 谷底（→呼吸周期）。

| 检查 | 结果 |
|---|---|
| T1 默认档呼吸周期 ≈10ms（板上 1s）、亮度可达满占空比 | PASS（测得 9.99996ms） |
| T2 Key1 后周期 ≈15ms（板上 1.5s） | PASS（测得 15.0ms） |
| T3 Key4 后点亮峰值 ≈75% | PASS（测得 74.67us/100us） |
| T4 Key3 复位后回默认档、重新呼吸 | PASS |
| T5 仅毛刺按键不触发切换 | PASS |

复现：`nvc -a src/*.vhd sim/*.vhd -e tb_breathing_led -r`
（ModelSim：`vlib work && vcom src/*.vhd sim/*.vhd && vsim tb_breathing_led -do "run -all"`）
波形文件 `breath.vcd`（GTKWave 查看，nvc `--wave` 重新生成，不入库）。

## 6. 检测现场修改预案（重点背诵）

检测时老师可能要求现场修改，以下是"要求 -> 改哪里"对照：

| 现场要求 | 修改位置（breath_engine.vhd） |
|---|---|
| 改呼吸周期档位（如 1/2/3/4s） | `ramp_proc` 中步进公式 `(speed_idx+1)` 的倍率，或顶层 generic `STEP_BASE_CLKS` |
| 增加亮度级数（如 8 档） | 把两处 `(4 - bright_idx)` 改为 `(N - bright_idx)` 并把 range `0 to 3` 改 `0 to N-1` |
| 改默认亮度/速度 | 复位分支 `bright_idx <= 0; speed_idx <= 1;` 的初值 |
| 改 PWM 频率（如 2kHz） | 顶层 generic `PWM_PERIOD => 6000` |
| 只在按下瞬间切换/长按连切 | 已实现按下沿单脉冲切换（key_pressed）；长按连切可改为电平触发 |
| 呼吸样式变化（如先快后慢） | duty 更新处把 ±1 改为非线性步进（如 ±(1+duty/2000)） |

## 7. 上板步骤（Diamond）

1. New Project -> 器件 LCMXO2-4000HC-4MG132（小脚丫 V2）
2. 加入 `src/` 三个 .vhd，Set as Top：`breathing_led_top`
3. Translate 前关联 `constraints/breathing_led.lpf`（或手动 Place & Route 界面输引脚）
4. Export Bitstream -> 下载到板（FT232 一根 USB 线完成供电+下载）
5. 观察 LED8 呼吸；Key1 变速、Key4 变亮、Key3 复位
6. 注：源码注释为 UTF-8，若 Diamond 编辑器中文乱码不影响综合；介意可转 GBK

## 8. 待办 / 风险

- [ ] 实机验证（本地只有 nvc 逻辑仿真；上板后确认亮度档位肉眼可辨）
- [ ] 若检测要求 Reset 用其他按键，改顶层 u_key3 对应输入即可
