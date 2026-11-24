-- ============================================================================
-- breath_engine : 呼吸灯控制引擎（PWM 发生器 + 亮度斜坡 + 档位控制）
--
-- 呼吸原理（见"实验二基于脉宽调制的呼吸灯原理简述"）：
--   PWM 计数器 T 对 12MHz 时钟分频，计数范围 0..PWM_PERIOD-1；
--   输出 Q='1' 当 T < M。则
--     PWM 频率   = f_clk / PWM_PERIOD = 12MHz / 12000 = 1kHz（高于人眼闪烁阈值）
--     占空比     = M / PWM_PERIOD
--   令占空比 M 随时间缓慢线性增减（呼吸斜坡），LED 亮度即缓缓变亮、缓缓变熄。
--
-- 参数化设计（检测现场修改的抓手，改公式常数即可改档位，无需查表）：
--   呼吸速度档位 : 4 档，半周期步进间隔 = STEP_BASE_CLKS x (speed_idx+1)
--                  板级默认对应呼吸周期 0.5 / 1 / 1.5 / 2 s
--   亮度档位     : 4 档，上限占空比 = PWM_PERIOD x (4-bright_idx) / 4
--                  即 100% / 75% / 50% / 25%
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity breath_engine is
	generic (
		PWM_PERIOD     : integer := 12000;	-- PWM 周期(时钟数)，12000@12MHz = 1kHz
		STEP_BASE_CLKS : integer := 250		-- 斜坡步进基准间隔(时钟数)
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

	-- 呼吸速度档位 0..3：0.5s / 1s / 1.5s / 2s，默认 1s（题目基准要求）
	-- 初值同时作为 FPGA 上电默认状态（Lattice 器件支持寄存器初值）
	signal speed_idx : integer range 0 to 3 := 1;
	-- 亮度档位 0..3：100% / 75% / 50% / 25%，默认 100%
	signal bright_idx : integer range 0 to 3 := 0;

	-- 当前占空比计数 M，0..PWM_PERIOD
	signal duty : integer range 0 to PWM_PERIOD := 0;

	signal ramp_up : std_logic := '1';	-- '1' 变亮段 / '0' 变暗段
	signal pre_cnt : integer range 0 to STEP_BASE_CLKS * 4 - 1 := 0;	-- 斜坡预分频计数
	signal pwm_cnt : integer range 0 to PWM_PERIOD - 1 := 0;		-- PWM 相位计数
	signal pwm_on  : std_logic;

begin

	-- ------------------------------------------------------------------
	-- 档位控制 + 呼吸斜坡（异步复位）
	-- ------------------------------------------------------------------
	ramp_proc : process (clk, rst_n)
	begin
		if rst_n = '0' then
			speed_idx  <= 1;	-- 默认 1s 呼吸周期
			bright_idx <= 0;	-- 默认 100% 亮度
			duty       <= 0;	-- 从全灭开始缓缓变亮
			ramp_up    <= '1';
			pre_cnt    <= 0;
		elsif rising_edge(clk) then

			-- Key1：呼吸速度 1s -> 1.5s -> 2s -> 0.5s -> ... 循环
			if key_speed = '1' then
				if speed_idx = 3 then
					speed_idx <= 0;
				else
					speed_idx <= speed_idx + 1;
				end if;
			end if;

			-- Key4：亮度 100% -> 75% -> 50% -> 25% -> ... 循环
			if key_bright = '1' then
				if bright_idx = 3 then
					bright_idx <= 0;
				else
					bright_idx <= bright_idx + 1;
				end if;
			end if;

			-- 斜坡步进：每 STEP_BASE_CLKS*(speed_idx+1) 个时钟 duty 变化 1
			if pre_cnt >= STEP_BASE_CLKS * (speed_idx + 1) - 1 then
				pre_cnt <= 0;
				if ramp_up = '1' then
					if duty >= PWM_PERIOD * (4 - bright_idx) / 4 then
						-- 到达亮度上限，转入变暗段
						-- （若亮度刚被调低，此处同时把 duty 钳到新上限，立即变暗）
						duty    <= PWM_PERIOD * (4 - bright_idx) / 4;
						ramp_up <= '0';
					else
						duty <= duty + 1;
					end if;
				else
					if duty = 0 then
						ramp_up <= '1';	-- 到全灭，转入变亮段，周而复始
					else
						duty <= duty - 1;
					end if;
				end if;
			else
				pre_cnt <= pre_cnt + 1;
			end if;
		end if;
	end process ramp_proc;

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

	pwm_on  <= '1' when pwm_cnt < duty else '0';
	pwm_out <= pwm_on;

end architecture rtl;
