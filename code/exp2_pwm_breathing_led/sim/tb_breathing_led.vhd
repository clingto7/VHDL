-- ============================================================================
-- tb_breathing_led : 实验二自检式 testbench
--
-- 加速策略：通过 generics 把板级参数缩小：
--   PWM_PERIOD 12000 -> 1200 (PWM 周期 100us)
--   STEP_BASE_CLKS 250 -> 25 (呼吸周期随之缩小 100 倍, 默认档 10ms)
--   DEBOUNCE_MS 40 -> 1 (消抖 1ms)
--   各逻辑量之间的比例关系与板级配置完全一致, 全部激励 < 0.2s 仿真时间。
--
-- 验证点：
--   T1 复位释放后从全灭开始呼吸; 默认亮度可达满占空比 (同时证明 PWM 周期正确);
--      默认档呼吸周期 10ms (对应板上 1s)
--   T2 Key1 切换呼吸速度 (10ms -> 15ms, 对应板上 1s -> 1.5s)
--   T3 Key4 切换亮度上限 (点亮峰值占空比降至 75%)
--   T4 Key3 复位: 立即回默认档 (周期 10ms, 亮度 100%), 重新呼吸
--   T5 按键毛刺不触发切换 (消抖有效)
--
-- 测量方法（被动监视器，无层次化引用，任何仿真器可跑）：
--   点亮峰值时长 mon_peak : 每个点亮窗口长度取最大 -> 反映占空比上限
--   触底时刻   mon_bottom : 相邻点亮窗口间隔 > 0.85 个 PWM 周期, 即 duty 谷底;
--                           相邻两次触底时刻之差 = 呼吸周期
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity tb_breathing_led is
end entity tb_breathing_led;

architecture sim of tb_breathing_led is

	constant CLK_PERIOD  : time    := 83.333 ns;	-- 12MHz
	constant PWM_PERIOD  : integer := 1200;		-- 缩放后 PWM 周期
	constant STEP_BASE   : integer := 25;		-- 缩放后步进基准
	constant DEBOUNCE_MS : integer := 1;		-- 缩放后消抖时间

	constant PWM_T       : time := CLK_PERIOD * PWM_PERIOD;			-- 100us
	constant HALF_BREATH : time := CLK_PERIOD * PWM_PERIOD * STEP_BASE * 2;	-- 默认档半周期 5ms
	constant BOTTOM_TH   : time := PWM_T * 0.85;	-- 触底判据

	signal clk12m   : std_logic := '0';
	signal key1     : std_logic := '1';
	signal key3     : std_logic := '1';
	signal key4     : std_logic := '1';
	signal led8     : std_logic;
	signal sim_done : boolean := false;

	-- 监视器输出
	signal mon_peak   : time := 0 ns;	-- 自上次清零以来最长点亮时长
	signal mon_bottom : time := 0 ns;	-- 最近一次触底时刻
	signal mon_clr    : boolean := false;	-- 峰值清零脉冲

begin

	uut : entity work.breathing_led_top
		generic map (
			PWM_PERIOD     => PWM_PERIOD,
			STEP_BASE_CLKS => STEP_BASE,
			DEBOUNCE_MS    => DEBOUNCE_MS
		)
		port map (
			clk12m => clk12m,
			key1   => key1,
			key3   => key3,
			key4   => key4,
			led8   => led8
		);

	clk_gen : process
	begin
		while not sim_done loop
			clk12m <= '0';
			wait for CLK_PERIOD / 2;
			clk12m <= '1';
			wait for CLK_PERIOD / 2;
		end loop;
		wait;
	end process clk_gen;

	-- ------------------------------------------------------------------
	-- 被动监视器: 从 led8 波形测量点亮峰值时长与触底时刻 (led8 低 = 点亮)
	-- ------------------------------------------------------------------
	mon : process (led8, mon_clr)
		variable t_fall    : time := 0 ns;	-- 上次点亮开始时刻
		variable t_rise    : time := 0 ns;	-- 上次点亮结束时刻
		variable have_rise : boolean := false;
	begin
		if mon_clr then
			mon_peak <= 0 ns;
		elsif falling_edge(led8) then
			-- 本次点亮距上次熄灭的间隔超过阈值 -> duty 接近 0 (一次呼吸的谷底)
			if have_rise and (now - t_rise) > BOTTOM_TH then
				mon_bottom <= now;
			end if;
			t_fall := now;
		elsif rising_edge(led8) then
			if (now - t_fall) > mon_peak then
				mon_peak <= now - t_fall;
			end if;
			t_rise    := now;
			have_rise := true;
		end if;
	end process mon;

	-- ------------------------------------------------------------------
	-- 激励与自检
	-- ------------------------------------------------------------------
	stim : process
		variable fails     : integer := 0;
		variable cycle_est : time;

		-- 断言助手：通过则打印 PASS，失败则计数
		procedure check(cond : boolean; msg : string) is
		begin
			if cond then
				report "PASS: " & msg;
			else
				report "FAIL: " & msg severity error;
				fails := fails + 1;
			end if;
		end procedure check;

		-- 带机械抖动的按键按下（抖动总时长远小于消抖时间，应被过滤），再弹起
		procedure press_key(signal k : out std_logic) is
		begin
			k <= '0'; wait for 10 us;
			k <= '1'; wait for 20 us;
			k <= '0'; wait for 15 us;
			k <= '1'; wait for 10 us;
			k <= '0'; wait for 2.5 ms;	-- 稳定按下 (> 消抖 1ms)
			k <= '1';
			wait for 2 ms;
		end procedure press_key;

		-- 只有毛刺、从不稳定按下的"假按键"（不应触发任何切换）
		procedure glitch_key(signal k : out std_logic) is
		begin
			k <= '0'; wait for 30 us;
			k <= '1'; wait for 100 us;
			k <= '0'; wait for 50 us;
			k <= '1'; wait for 200 us;
			k <= '0'; wait for 20 us;
			k <= '1';
			wait for 1 ms;
		end procedure glitch_key;

		-- 等待下一次触底事件簇结束 (簇内事件间隔 ~1 个 PWM 周期,
		-- 簇间间隔 >= 呼吸周期 - 簇宽度, 用 3ms 无事件判簇结束),
		-- 返回该簇最后一个触底时刻
		procedure next_bottom_end(t_out : out time) is
			variable t_last : time;
		begin
			wait until mon_bottom'event;
			t_last := mon_bottom;
			loop
				wait until mon_bottom'event for 3 ms;
				exit when not mon_bottom'event;
				t_last := mon_bottom;
			end loop;
			t_out := t_last;
		end procedure next_bottom_end;

		-- 相邻两次触底簇结束时刻之差 = 当前呼吸周期
		procedure measure_cycle(cycle_est : out time) is
			variable t1, t2 : time;
		begin
			next_bottom_end(t1);
			next_bottom_end(t2);
			cycle_est := t2 - t1;
		end procedure measure_cycle;

	begin
		report "TB: start (scaled: PWM_PERIOD=" & integer'image(PWM_PERIOD) &
			", STEP_BASE=" & integer'image(STEP_BASE) &
			", DEBOUNCE_MS=" & integer'image(DEBOUNCE_MS) & ")";

		-- T1: 上电, 按住 Reset(Key3) 2.5ms 后释放, 呼吸应从全灭开始
		key3 <= '0';
		wait for 2.5 ms;
		key3 <= '1';
		mon_clr <= true;
		wait for 1 ns;
		mon_clr <= false;
		report "T1: reset released, breathing starts";

		-- 等第一个谷底出现并完成一次峰值, 再测默认档呼吸周期
		wait for 8 ms;		-- t ~= 10.5ms
		check(mon_peak >= PWM_T * 0.95,
			"T1a default brightness reaches full duty (implies PWM period ~100us)");
		measure_cycle(cycle_est);
		check(cycle_est >= HALF_BREATH * 2 * 0.9 and cycle_est <= HALF_BREATH * 2 * 1.1,
			"T1b default breath cycle ~= 10ms (board: 1s), measured " & time'image(cycle_est));

		-- T2: Key1 切到 1.5s 档 (缩放后 15ms)
		report "T2: pressing Key1 (speed -> 1.5s)";
		press_key(key1);
		wait for 22 ms;
		measure_cycle(cycle_est);
		check(cycle_est >= 13.5 ms and cycle_est <= 16.5 ms,
			"T2 breath cycle ~= 15ms after Key1 (board: 1.5s), measured " & time'image(cycle_est));

		-- T5: 只给毛刺不给稳定低电平, 亮度档不应被误触发
		report "T5: glitch-only presses on Key4 (should be filtered)";
		glitch_key(key4);
		wait for 16 ms;
		check(mon_peak >= PWM_T * 0.95,
			"T5 brightness unchanged by glitch-only presses");

		-- T3: Key4 切亮度 75% (缩放后占空比上限 900/1200)
		report "T3: pressing Key4 (brightness -> 75%)";
		press_key(key4);
		mon_clr <= true;
		wait for 1 ns;
		mon_clr <= false;
		wait for 12 ms;
		check(mon_peak >= PWM_T * 0.70 and mon_peak <= PWM_T * 0.78,
			"T3 peak on-time ~= 75% duty after Key4, measured " & time'image(mon_peak));

		-- T4: Key3 复位, 回默认档 (周期 10ms, 亮度 100%), 重新从全灭呼吸
		report "T4: pressing Key3 (reset to defaults)";
		press_key(key3);
		mon_clr <= true;
		wait for 1 ns;
		mon_clr <= false;
		wait for 8 ms;
		check(mon_peak >= PWM_T * 0.95, "T4a brightness back to 100% after reset");
		measure_cycle(cycle_est);
		check(cycle_est >= HALF_BREATH * 2 * 0.9 and cycle_est <= HALF_BREATH * 2 * 1.1,
			"T4b breath cycle back to ~= 10ms after reset, measured " & time'image(cycle_est));

		-- 总结
		sim_done <= true;
		if fails = 0 then
			report "TB: ALL CHECKS PASSED";
		else
			report "TB: FAILED with " & integer'image(fails) & " check(s)" severity failure;
		end if;
		wait;
	end process stim;

end architecture sim;
