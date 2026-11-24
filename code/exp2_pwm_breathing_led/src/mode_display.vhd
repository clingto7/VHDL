-- ============================================================================
-- mode_display : 档位数码管显示（实验二独创性功能）
--
-- 功能（利用核心板自带的双 7 段数码管，无需底板）：
--   左管（DIG1）：当前呼吸速度档位，显示 1..SPEED_LEVELS
--   右管（DIG2）：当前亮度档位，显示 1..BRIGHT_LEVELS
--   Key3 按住复位期间：两管显示 '-'，松开后恢复，复位过程可见
--   右管小数点 DP2：呼吸心跳指示，变亮段亮 / 变暗段灭
--
-- 极性（依据 STEP-MXO2 V2.1 原理图 + 往届在本板跑通的代码）：
--   段选 a..g 高有效（'1' 点亮）；位选 DIG 低有效（共阴极，'0' 选通）。
--   两位数码管段线各自独立、位选恒选通，无需扫描分频。
--   若实测 DP 极性相反，只需改本文件末尾 dp1/dp2 两行取反。
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity mode_display is
	generic (
		SPEED_LEVELS  : integer := 4;	-- 与 breath_engine 保持一致
		BRIGHT_LEVELS : integer := 4
	);
	port (
		clk         : in  std_logic;	-- 仅用于把译码输出打一拍，避免毛刺直上引脚
		rst_n       : in  std_logic;	-- '0' = 复位进行中（显示 '-'）
		speed_tier  : in  integer range 0 to SPEED_LEVELS - 1;
		bright_tier : in  integer range 0 to BRIGHT_LEVELS - 1;
		heart       : in  std_logic;	-- '1' = 变亮段（DP2 心跳）

		seg1 : out std_logic_vector(0 to 6);	-- 左管 a..g，高有效
		seg2 : out std_logic_vector(0 to 6);	-- 右管 a..g，高有效
		dp1  : out std_logic;
		dp2  : out std_logic;
		dig1 : out std_logic;			-- 位选，低有效，恒选通
		dig2 : out std_logic
	);
end entity mode_display;

architecture rtl of mode_display is

	type seg_table_t is array (0 to 8) of std_logic_vector(0 to 6);
	-- 下标 0..6 = 段 a..g，对应约束 seg[0]..seg[6] -> SEG-A..SEG-G
	constant SEG7 : seg_table_t := (
		"1111110",	-- 0
		"0110000",	-- 1
		"1101101",	-- 2
		"1111001",	-- 3
		"0110011",	-- 4
		"1011011",	-- 5
		"1011111",	-- 6
		"1110000",	-- 7
		"1111111"	-- 8
	);
	constant SEG_DASH : std_logic_vector(0 to 6) := "0000001";	-- 只有 g 段

	-- 档位转显示字符：档位 0 显示 '1'，1 显示 '2' ...；超出表范围显示 0
	function tier_char(tier : integer; levels : integer) return std_logic_vector is
	begin
		if tier >= 0 and tier < levels and tier + 1 <= 8 then
			return SEG7(tier + 1);
		else
			return SEG7(0);
		end if;
	end function tier_char;

	signal seg1_r : std_logic_vector(0 to 6);
	signal seg2_r : std_logic_vector(0 to 6);

begin

	decode_proc : process (clk)
	begin
		if rising_edge(clk) then
			if rst_n = '0' then
				seg1_r <= SEG_DASH;
				seg2_r <= SEG_DASH;
			else
				seg1_r <= tier_char(speed_tier, SPEED_LEVELS);
				seg2_r <= tier_char(bright_tier, BRIGHT_LEVELS);
			end if;
		end if;
	end process decode_proc;

	seg1 <= seg1_r;
	seg2 <= seg2_r;
	dp1  <= '0';
	dp2  <= heart;
	dig1 <= '0';	-- 两位各自独立段线，恒选通，无需扫描
	dig2 <= '0';

end architecture rtl;
