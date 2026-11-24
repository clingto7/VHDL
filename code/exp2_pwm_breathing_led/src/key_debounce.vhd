-- ============================================================================
-- key_debounce : 按键消抖 + 按下沿检测（标准单元，各实验可复用）
--
-- 原理（见实验要求书"设计提示"）：
--   小脚丫核心板按键经 10K 电阻上拉到 3.3V，按下接地 -> 低有效（按下='0'）。
--   机械弹片闭合/断开瞬间伴随一连串抖动，按要求书读取按下时刻之后约 40ms
--   的电平作为可信状态。
--   实现：先两级触发器同步异步输入（防亚稳态），再用计数器过滤抖动——
--   只有当输入电平连续保持 DB_CLKS 个时钟周期不等于当前状态时才翻转状态。
--
-- 输出：
--   key_level   : 消抖后电平，'0' 表示按下（可直接用作异步复位电平）
--   key_pressed : 按下沿产生的单时钟周期脉冲，供模式切换逻辑使用
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity key_debounce is
	generic (
		CLK_FREQ_HZ : integer := 12_000_000;	-- 系统时钟频率
		DEBOUNCE_MS : integer := 40		-- 消抖时间，按要求书取 40ms
	);
	port (
		clk         : in  std_logic;
		key_in      : in  std_logic;	-- 原始按键输入，低有效
		key_level   : out std_logic;	-- 消抖后电平，'0'=按下
		key_pressed : out std_logic	-- 按下沿单周期脉冲
	);
end entity key_debounce;

architecture rtl of key_debounce is

	-- 消抖计数目标值：12MHz x 40ms = 480000 个时钟周期
	constant DB_CLKS : integer := (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

	signal sync_r0    : std_logic := '1';	-- 第一级同步
	signal sync_r1    : std_logic := '1';	-- 第二级同步
	signal key_state  : std_logic := '1';	-- 消抖后的稳定状态，'1'=弹起
	signal prev_state : std_logic := '1';	-- 上一拍状态，用于边沿检测
	signal db_cnt     : integer range 0 to DB_CLKS := 0;

begin

	debounce_proc : process (clk)
	begin
		if rising_edge(clk) then
			-- 两级同步，防止亚稳态传播
			sync_r0 <= key_in;
			sync_r1 <= sync_r0;

			-- 消抖：新电平稳定保持 DB_CLKS 拍后才更新状态，否则计数器清零
			if sync_r1 = key_state then
				db_cnt <= 0;
			elsif db_cnt = DB_CLKS then
				key_state <= sync_r1;
			else
				db_cnt <= db_cnt + 1;
			end if;

			prev_state <= key_state;
		end if;
	end process debounce_proc;

	key_level <= key_state;
	-- 两个寄存器信号比较，天然是单周期脉冲
	key_pressed <= '1' when (key_state = '0') and (prev_state = '1') else '0';

end architecture rtl;
