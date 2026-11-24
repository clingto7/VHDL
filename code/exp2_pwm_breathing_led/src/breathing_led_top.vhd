-- ============================================================================
-- breathing_led_top : 实验二 PWM 呼吸灯 顶层
--
-- 板级连接（STEP-MXO2 V2，见实验要求书管脚分配表）：
--   clk12m : C1  - 12MHz 晶振
--   key1   : L14 - 呼吸速度切换（0.5/1/1.5/2s 四档循环，默认 1s）
--   key3   : M14 - Reset，按下回到默认档位并重新开始呼吸（评分记录表检查项）
--   key4   : N14 - 亮度切换（100/75/50/25% 四档循环）
--   led8   : P9  - 呼吸灯输出
--
-- 极性（依据 STEP-MXO2 V2.1 原理图，代码取反原因）：
--   LED 阳极经 470R 接 +3.3V，FPGA 引脚输出 '0' 时点亮 -> 低有效
--   按键经 10K 上拉到 +3.3V，按下接地          -> 低有效
--
-- 仿真加速：generic 可在 testbench 中缩小（板上综合使用默认值），
--   缩放时 PWM 与呼吸斜坡的比例关系保持不变。
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity breathing_led_top is
	generic (
		PWM_PERIOD     : integer := 12000;	-- 板级默认：1kHz PWM
		STEP_BASE_CLKS : integer := 250;	-- 板级默认：呼吸周期 0.5/1/1.5/2s
		DEBOUNCE_MS    : integer := 40		-- 板级默认：40ms 消抖
	);
	port (
		clk12m : in  std_logic;
		key1   : in  std_logic;
		key3   : in  std_logic;
		key4   : in  std_logic;
		led8   : out std_logic
	);
end entity breathing_led_top;

architecture rtl of breathing_led_top is

	signal key1_pressed : std_logic;	-- Key1 按下脉冲
	signal key4_pressed : std_logic;	-- Key4 按下脉冲
	signal key3_level   : std_logic;	-- Key3 消抖后电平，用作复位
	signal pwm_out      : std_logic;	-- 高有效点亮时段

begin

	-- Key1 消抖：只取按下脉冲
	u_key1 : entity work.key_debounce
		generic map (
			CLK_FREQ_HZ => 12_000_000,
			DEBOUNCE_MS => DEBOUNCE_MS
		)
		port map (
			clk         => clk12m,
			key_in      => key1,
			key_level   => open,
			key_pressed => key1_pressed
		);

	-- Key4 消抖：只取按下脉冲
	u_key4 : entity work.key_debounce
		generic map (
			CLK_FREQ_HZ => 12_000_000,
			DEBOUNCE_MS => DEBOUNCE_MS
		)
		port map (
			clk         => clk12m,
			key_in      => key4,
			key_level   => open,
			key_pressed => key4_pressed
		);

	-- Key3 消抖：取电平作异步复位
	u_key3 : entity work.key_debounce
		generic map (
			CLK_FREQ_HZ => 12_000_000,
			DEBOUNCE_MS => DEBOUNCE_MS
		)
		port map (
			clk         => clk12m,
			key_in      => key3,
			key_level   => key3_level,
			key_pressed => open
		);

	u_engine : entity work.breath_engine
		generic map (
			PWM_PERIOD     => PWM_PERIOD,
			STEP_BASE_CLKS => STEP_BASE_CLKS
		)
		port map (
			clk        => clk12m,
			rst_n      => key3_level,
			key_speed  => key1_pressed,
			key_bright => key4_pressed,
			pwm_out    => pwm_out
		);

	-- 板上 LED 低电平点亮，输出取反
	led8 <= not pwm_out;

end architecture rtl;
