-- ============================================================================
-- tb_breathing_led : 实验二自检式 testbench
--
-- 加速策略：通过 generics 把板级参数缩小：
--   PWM_PERIOD 12000 -> 1200 (PWM 周期 100us)
--   STEP_BASE_CLKS 250 -> 25 (呼吸周期随之缩小 100 倍, 默认档 10ms)
--   DEBOUNCE_MS 40 -> 1 (消抖 1ms)
--   各逻辑量之间的比例关系与板级配置完全一致。
--
-- 验证点：
--   T0 上电后不按任何键：直接以默认档呼吸（周期 10ms、亮度 100%）
--      本 TB 还会在"去掉全部声明初值"的源码副本上重跑一遍，模拟综合器
--      不保留初值、寄存器上电为 0 的情形（做法见 README 第 5 节）
--   T1 Key3 复位：回默认档，并从全灭重新呼吸
--   T2 Key1 切换呼吸速度 (10ms -> 15ms, 对应板上 1s -> 1.5s)
--   T5 按键毛刺不触发切换 (消抖有效)
--   T3/T6/T7 Key4 依次切到 75% / 50% / 25%：峰值占空比随之下降，
--      而呼吸周期保持 15ms 不变（速度与亮度解耦）
--   T4 Key3 复位：从 25% 亮度状态回默认档 (周期 10ms, 亮度 100%)
--
-- 测量方法（被动监视器，无层次化引用，任何仿真器可跑）：
--   点亮峰值时长 mon_peak : 每个点亮窗口长度取最大 -> 反映占空比上限
--   谷底时刻     mon_bottom : 相邻点亮窗口之间熄灭超过 0.85 个 PWM 周期,
--                           即 duty 谷底; 相邻两簇谷底之差 = 呼吸周期
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

	constant PWM_T       : time := CLK_PERIOD * PWM_PERIOD;	-- 100us
	constant CYCLE_1S    : time := CLK_PERIOD * PWM_PERIOD * STEP_BASE * 4;	-- 默认档 10ms
	constant CYCLE_1P5S  : time := CLK_PERIOD * PWM_PERIOD * STEP_BASE * 6;	-- 1.5s 档 15ms
	constant BOTTOM_TH     : time := PWM_T * 0.85;	-- 谷底判据
	constant CLUSTER_GAP   : time := 1 ms;	-- 判定谷底事件簇结束的无事件间隔
	constant BOTTOM_TIMEOUT : time := 60 ms;	-- 等下一次谷底事件的上限
	constant WATCHDOG_T   : time := 2 sec;	-- 整个 TB 的时间上限

	signal clk12m   : std_logic := '0';
	signal key1     : std_logic := '1';
	signal key3     : std_logic := '1';
	signal key4     : std_logic := '1';
	signal led8     : std_logic;
	signal sim_done : boolean := false;

	-- 监视器输出
	signal mon_peak   : time := 0 ns;	-- 自上次清零以来最长点亮时长
	signal mon_bottom : time := 0 ns;	-- 最近一次谷底事件时刻
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

	-- 看门狗: 正常全程 < 0.5s; 2s 时 stim 还没置 sim_done 说明激励挂住, 判失败.
	-- stim 正常结束后本进程永久等待, 不再产生事件, 仿真自然结束.
	watchdog : process
	begin
		wait until sim_done for WATCHDOG_T;
		if not sim_done then
			report "TB: TIMEOUT after " & time'image(WATCHDOG_T) severity failure;
		end if;
		wait;
	end process watchdog;

	-- ------------------------------------------------------------------
	-- 被动监视器: 从 led8 波形测量点亮峰值时长与谷底时刻 (led8 低 = 点亮)
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

		-- 清掉峰值记录
		procedure clear_peak is
		begin
			mon_clr <= true;
			wait for 1 ns;
			mon_clr <= false;
		end procedure clear_peak;

		-- 等待下一次谷底事件簇结束, 返回该簇最后一个谷底时刻.
		-- 簇内相邻事件间隔 = 1 个 PWM 周期(100us); 正确设计中相邻两簇至少隔
		-- 1.7 x 半周期 (最快档也有 4.25ms). 取 1ms 无事件判簇结束, 两侧都有余量.
		-- 最多等 BOTTOM_TIMEOUT, 超时置 ok=false: 被测设计有错时报 FAIL 而不是挂死.
		procedure next_bottom_end(t_out : out time; ok : out boolean) is
			variable t_last : time;
			variable seen   : boolean;
		begin
			wait until mon_bottom'event for BOTTOM_TIMEOUT;
			seen := mon_bottom'event;
			if seen then
				t_last := mon_bottom;
				loop
					wait until mon_bottom'event for CLUSTER_GAP;
					exit when not mon_bottom'event;
					t_last := mon_bottom;
				end loop;
				t_out := t_last;
			else
				t_out := now;
			end if;
			ok := seen;	-- out 形参只在最后赋值 (VHDL-93 不允许读 out 形参)
		end procedure next_bottom_end;

		-- 呼吸周期检查：相邻两簇谷底结束时刻之差, 期望值 +/- 10%
		procedure check_cycle(expect : time; name : string) is
			variable t1, t2 : time;
			variable ok1, ok2 : boolean;
		begin
			next_bottom_end(t1, ok1);
			next_bottom_end(t2, ok2);
			check(ok1 and ok2, name & ": bottom events observed");
			if ok1 and ok2 then
				cycle_est := t2 - t1;
				check(cycle_est >= expect * 0.9 and cycle_est <= expect * 1.1,
					name & ": breath cycle ~= " & time'image(expect) &
					", measured " & time'image(cycle_est));
			end if;
		end procedure check_cycle;

		-- 峰值亮度检查：清零后等满一个以上呼吸周期(最长 15ms)再读 mon_peak,
		-- 期望占空比百分比 +/- 5 个百分点
		procedure check_peak(expect_pct : integer; name : string) is
			variable meas_pct : integer;
		begin
			clear_peak;
			wait for 17 ms;
			meas_pct := (mon_peak * 100) / PWM_T;
			check(meas_pct >= expect_pct - 5 and meas_pct <= expect_pct + 5,
				name & ": peak duty ~= " & integer'image(expect_pct) &
				"%, measured " & integer'image(meas_pct) & "%");
		end procedure check_peak;

		-- 按下 Key3 再松开, 检查复位生效:
		-- 松开被识别后 LED 应先保持熄灭 60us (duty 从 0 重新爬升), 随后亮度回到 100%
		procedure check_reset(name : string) is
			variable t_rel  : time;
			variable off_ok : boolean := true;
		begin
			key3 <= '0';
			wait for 2.5 ms;
			key3 <= '1';
			wait for 1 ms + 10 * CLK_PERIOD;	-- 松开经消抖被识别
			t_rel := now;
			while now < t_rel + 60 us loop
				if led8 /= '1' then
					off_ok := false;
				end if;
				wait for 1 us;
			end loop;
			check(off_ok, name & ": breathing restarts from fully dark after reset");
			check_peak(100, name & ": brightness 100% after reset");
		end procedure check_reset;

	begin
		report "TB: start (scaled: PWM_PERIOD=" & integer'image(PWM_PERIOD) &
			", STEP_BASE=" & integer'image(STEP_BASE) &
			", DEBOUNCE_MS=" & integer'image(DEBOUNCE_MS) & ")";

		-- T0: 上电后不按任何键, 应直接以默认档呼吸
		report "T0: power-up, no key pressed";
		check_peak(100, "T0a default brightness reaches full duty after power-up");
		check_cycle(CYCLE_1S, "T0b default breath cycle 10ms after power-up (board: 1s)");

		-- T1: Key3 复位, 应回默认档并从全灭重新呼吸
		report "T1: reset (Key3) press and release";
		check_reset("T1");
		check_cycle(CYCLE_1S, "T1 breath cycle 10ms after reset");

		-- T2: Key1 切到 1.5s 档 (缩放后 15ms)
		report "T2: pressing Key1 (speed -> 1.5s)";
		press_key(key1);
		check_cycle(CYCLE_1P5S, "T2 breath cycle 15ms after Key1 (board: 1.5s)");

		-- T5: 只给毛刺不给稳定低电平, 不应有任何切换
		report "T5: glitch-only presses on Key4 (should be filtered)";
		glitch_key(key4);
		check_peak(100, "T5a brightness unchanged by glitch-only presses");
		check_cycle(CYCLE_1P5S, "T5b speed unchanged by glitch-only presses");

		-- T3/T6/T7: Key4 依次切到 75% / 50% / 25%, 周期应保持 15ms 不变
		report "T3: pressing Key4 (brightness -> 75%)";
		press_key(key4);
		check_peak(75, "T3a peak duty 75% after Key4");
		check_cycle(CYCLE_1P5S, "T3b breath cycle still 15ms at 75%");

		report "T6: pressing Key4 (brightness -> 50%)";
		press_key(key4);
		check_peak(50, "T6a peak duty 50% after Key4");
		check_cycle(CYCLE_1P5S, "T6b breath cycle still 15ms at 50%");

		report "T7: pressing Key4 (brightness -> 25%)";
		press_key(key4);
		check_peak(25, "T7a peak duty 25% after Key4");
		check_cycle(CYCLE_1P5S, "T7b breath cycle still 15ms at 25%");

		-- T4: Key3 复位, 从 25% 亮度状态回默认档
		report "T4: pressing Key3 (reset to defaults)";
		check_reset("T4");
		check_cycle(CYCLE_1S, "T4 breath cycle back to 10ms after reset");

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
