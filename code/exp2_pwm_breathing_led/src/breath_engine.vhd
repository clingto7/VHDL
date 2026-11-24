-- ============================================================================
-- breath_engine : 呼吸灯控制引擎（PWM 发生器 + 亮度三角波 + 档位控制）
--
-- 呼吸原理（见"实验二基于脉宽调制的呼吸灯原理简述"）：
--   PWM 计数器 T 对 12MHz 时钟分频，计数范围 0..PWM_PERIOD-1；
--   输出 Q='1' 当 T < M。则
--     PWM 频率   = f_clk / PWM_PERIOD = 12MHz / 12000 = 1kHz（高于人眼闪烁阈值）
--     占空比     = M / PWM_PERIOD
--   令占空比 M 随时间缓慢线性增减（呼吸斜坡），LED 亮度即缓缓变亮、缓缓变熄。
--
-- 设计要点：速度与亮度解耦
--   ramp : 0..PWM_PERIOD 的三角波，步进间隔只由速度档决定 -> 决定呼吸周期
--   duty : ramp x (BRIGHT_LEVELS - bright_idx) / BRIGHT_LEVELS，
--          只由亮度档缩放 -> 决定峰值占空比
--   两个按键互不影响：调亮度不改变呼吸周期，任何亮度下都保持"每 T 秒亮灭一次"
--   （题目要求：每 1 秒钟亮灭一次，周期只由 Key1 决定）
--
-- 参数化设计（检测现场修改的抓手，改常数即可改档位）：
--   呼吸速度 : SPEED_LEVELS 档，步进间隔 = STEP_BASE_CLKS x (speed_idx+1)
--              半周期 = PWM_PERIOD 步，板级默认对应呼吸周期 0.5 / 1 / 1.5 / 2 s
--   亮度     : BRIGHT_LEVELS 档，峰值占空比 = (BRIGHT_LEVELS - bright_idx) / BRIGHT_LEVELS
--              板级默认对应 100% / 75% / 50% / 25%
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity breath_engine is
	generic (
		PWM_PERIOD     : integer := 12000;	-- PWM 周期(时钟数)，须为 BRIGHT_LEVELS 的倍数
		STEP_BASE_CLKS : integer := 250		-- 最快档的斜坡步进间隔(时钟数)
	);
	port (
		clk        : in  std_logic;
		rst_n      : in  std_logic;		-- 异步复位，低有效（来自 Key3 消抖后电平）
		key_speed  : in  std_logic;		-- Key1 按下脉冲：切换呼吸速度
		key_bright : in  std_logic;		-- Key4 按下脉冲：切换最大亮度
		pwm_out    : out std_logic		-- '1' = 点亮时段（顶层按板上极性取反）
	);
end entity breath_engine;

architecture rtl of breath_engine is

	constant SPEED_LEVELS  : integer := 4;	-- 速度档数
	constant BRIGHT_LEVELS : integer := 4;	-- 亮度档数（取 2 的幂时除法是移位，最省资源）

	-- 呼吸速度档位 0..SPEED_LEVELS-1：板级默认 0.5s / 1s / 1.5s / 2s，默认第 2 档（1s）
	-- 亮度档位 0..BRIGHT_LEVELS-1：板级默认 100% / 75% / 50% / 25%，默认第 1 档（100%）
	-- 声明初值只为仿真上电服务；板上默认档位由复位分支决定，
	-- 不依赖综合器是否保留初值（两种上电情形均已在 testbench 中验证）。
	signal speed_idx  : integer range 0 to SPEED_LEVELS - 1 := 1;
	signal bright_idx : integer range 0 to BRIGHT_LEVELS - 1 := 0;

	-- ramp：与亮度无关的三角波，0..PWM_PERIOD 往返一次 = 一个呼吸周期
	signal ramp    : integer range 0 to PWM_PERIOD := 0;
	signal duty    : integer range 0 to PWM_PERIOD;	-- 当前占空比阈值 M
	signal ramp_up : std_logic := '1';		-- '1' 变亮段 / '0' 变暗段

	signal step_limit : integer range 0 to STEP_BASE_CLKS * SPEED_LEVELS - 1;	-- 当前步进间隔-1
	signal pre_cnt    : integer range 0 to STEP_BASE_CLKS * SPEED_LEVELS - 1 := 0;	-- 斜坡预分频计数
	signal pwm_cnt    : integer range 0 to PWM_PERIOD - 1 := 0;		-- PWM 相位计数

begin

	-- ------------------------------------------------------------------
	-- 档位控制 + 三角波斜坡（异步复位）
	-- ------------------------------------------------------------------
	ramp_proc : process (clk, rst_n)
	begin
		if rst_n = '0' then
			speed_idx  <= 1;	-- 默认 1s 呼吸周期
			bright_idx <= 0;	-- 默认 100% 亮度
			ramp       <= 0;	-- 从全灭开始缓缓变亮
			ramp_up    <= '1';
			pre_cnt    <= 0;
		elsif rising_edge(clk) then

			-- Key1：呼吸速度 1s -> 1.5s -> 2s -> 0.5s -> ... 循环
			if key_speed = '1' then
				if speed_idx = SPEED_LEVELS - 1 then
					speed_idx <= 0;
				else
					speed_idx <= speed_idx + 1;
				end if;
			end if;

			-- Key4：亮度 100% -> 75% -> 50% -> 25% -> ... 循环
			if key_bright = '1' then
				if bright_idx = BRIGHT_LEVELS - 1 then
					bright_idx <= 0;
				else
					bright_idx <= bright_idx + 1;
				end if;
			end if;

			-- 斜坡步进：每 STEP_BASE_CLKS x (speed_idx+1) 个时钟 ramp 变化 1
			if pre_cnt >= step_limit then
				pre_cnt <= 0;
				if ramp_up = '1' then
					if ramp = PWM_PERIOD then
						ramp_up <= '0';	-- 到波峰，转入变暗段
					else
						ramp <= ramp + 1;
					end if;
				else
					if ramp = 0 then
						ramp_up <= '1';	-- 到波谷，转入变亮段，周而复始
					else
						ramp <= ramp - 1;
					end if;
				end if;
			else
				pre_cnt <= pre_cnt + 1;
			end if;
		end if;
	end process ramp_proc;

	-- 当前档位对应的步进间隔
	step_limit <= STEP_BASE_CLKS * (speed_idx + 1) - 1;

	-- 亮度档只做缩放：占空比阈值 = 三角波 x (BRIGHT_LEVELS - bright_idx) / BRIGHT_LEVELS
	duty <= ramp * (BRIGHT_LEVELS - bright_idx) / BRIGHT_LEVELS;

	-- ------------------------------------------------------------------
	-- PWM 发生器：相位计数器 T 与阈值 M（duty）比较
	-- ------------------------------------------------------------------
	pwm_proc : process (clk, rst_n)
	begin
		if rst_n = '0' then
			pwm_cnt <= 0;
		elsif rising_edge(clk) then
			if pwm_cnt = PWM_PERIOD - 1 then
				pwm_cnt <= 0;
			else
				pwm_cnt <= pwm_cnt + 1;
			end if;
		end if;
	end process pwm_proc;

	pwm_out <= '1' when pwm_cnt < duty else '0';

end architecture rtl;
