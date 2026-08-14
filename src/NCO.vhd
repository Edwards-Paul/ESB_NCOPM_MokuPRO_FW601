library IEEE;
use IEEE.Std_Logic_1164.All;
use IEEE.Numeric_Std.All;
use IEEE.Fixed_Pkg.All;

entity NCO is
    generic (
        LUT_ADDR_WIDTH   : integer := 16;   -- Look-up address width
        LUT_DATA_WIDTH   : integer := 16;   -- Look-up data width
        PHASE_ACC_WIDTH  : integer := 16;   -- Phase accumulator width
        VOLTAGE_OFFSET   : integer := 32768;-- Normalize signed input [0,65535]
        CLOCK_FREQ       : real    := 312_500_000.0;
        MIN_FREQ         : real    := 1_000_000.0;   -- NCO min. freq.
        MAX_FREQ         : real    := 100_000_000.0;   -- NCO max. freq.
        MOD_INDEX_SCALER : real    := 1.0            -- Phase index scaling (PM depth)
    );
    port (
        Clk        : in  std_logic;                -- Clock signal
        Reset      : in  std_logic;                -- Reset signal
        DC         : in  signed(15 downto 0);      -- DC input for carrier frequency control
        Mod_Signal : in  signed(15 downto 0);      -- Phase modulation signal input
        Result     : out signed(15 downto 0)       -- Output signal
    );
end entity NCO;

architecture Behavioral of NCO is
    -- Phase accumulator registers
    signal r_phase_accumulator : unsigned(PHASE_ACC_WIDTH-1 downto 0) := (others => '0');
    signal r_fcw               : unsigned(PHASE_ACC_WIDTH-1 downto 0) := to_unsigned(1, 16);

    -- For PM we reuse this as instantaneous phase offset (not accumulated)
    signal r_pmod_accumulator  : unsigned(PHASE_ACC_WIDTH-1 downto 0) := (others => '0');

    signal r_lut_address       : std_logic_vector(LUT_ADDR_WIDTH-1 downto 0);
    signal r_lut_data_out      : std_logic_vector(LUT_DATA_WIDTH-1 downto 0);
    signal r_lut_signed_out    : signed(LUT_DATA_WIDTH-1 downto 0);
    signal r_result_reg        : signed(LUT_DATA_WIDTH-1 downto 0);

    -- Pipeline registers (carrier path unchanged)
    signal norm_dc_reg             : integer;
    signal v_scaled_voltage_reg    : ufixed(15 downto 0);
    signal v_frequency_reg         : ufixed(30 downto 0);
    signal fcw_reg                 : unsigned(PHASE_ACC_WIDTH-1 downto 0);

    constant VOLTAGE_FULL_SCALE : real := 2.0 * VOLTAGE_OFFSET;

    -- Note: Lut size equals 2^PHASE_ACC_WIDTH (top PHASE_ACC_WIDTH bits of phase used)
    constant LUT_SIZE : real := 2.0**PHASE_ACC_WIDTH;

    constant UFIX_FREQ_MIN : ufixed(28 downto 0) := to_ufixed(MIN_FREQ, 28, 0);
    constant FREQ_COEF     : ufixed(12 downto -1) := to_ufixed((MAX_FREQ - MIN_FREQ) / VOLTAGE_FULL_SCALE, 12, -1);
    constant FCW_COEF      : ufixed(0 downto -26) := to_ufixed(LUT_SIZE / CLOCK_FREQ, 0, -26);

    -- Phase modulation scaling:
    -- We implement: phase_offset_codes ≈ Mod_Signal * (2^(PHASE_ACC_WIDTH-16)) * MOD_INDEX_SCALER
    -- using fixed integer math with a Q-format constant.
    constant MOD_Q_FRAC   : integer := 12;
    constant MOD_SCALE_Q  : integer := integer(MOD_INDEX_SCALER * real(2**MOD_Q_FRAC) + 0.5);
begin
    U_SINE_BRAM : entity WORK.sine_bram
        port map (
            Clk      => Clk,
            Address  => r_lut_address,
            Data_out => r_lut_data_out
        );

    -- Main pipeline
    process (Clk, Reset)
        variable v_temp_voltage      : integer;
        variable v_scaled_voltage    : ufixed(15 downto 0);
        variable v_frequency         : ufixed(30 downto 0);

        -- PM variables (integer math)
        variable temp_mod_scaled     : integer;
        variable phase_widen_factor  : integer;
    begin
        if rising_edge(Clk) then
            if Reset = '1' then
                -- Reset all registers
                r_phase_accumulator    <= (others => '0');
                r_fcw                  <= (others => '0');
                r_pmod_accumulator     <= (others => '0');
                r_lut_address          <= (others => '0');
                r_lut_signed_out       <= (others => '0');
                r_result_reg           <= (others => '0');
                Result                 <= (others => '0');

                norm_dc_reg            <= 0;
                v_scaled_voltage_reg   <= (others => '0');
                v_frequency_reg        <= (others => '0');
                fcw_reg                <= (others => '0');

            else
                -- Pipeline Stage 1: Normalize DC input signal
                v_temp_voltage := to_integer(DC) + VOLTAGE_OFFSET;
                norm_dc_reg    <= v_temp_voltage;

                -- Pipeline Stage 2: Calculate scaled voltage
                v_scaled_voltage      := to_ufixed(v_temp_voltage, 15, 0);
                v_scaled_voltage_reg  <= v_scaled_voltage;

                -- Pipeline Stage 3: Calculate frequency from DC input and generics
                v_frequency      := UFIX_FREQ_MIN + FREQ_COEF * v_scaled_voltage_reg;
                v_frequency_reg  <= v_frequency;

                -- Pipeline Stage 4: Calculate frequency control word (FCW)
                fcw_reg <= to_unsigned(to_integer(v_frequency_reg * FCW_COEF), PHASE_ACC_WIDTH);

                -- Pipeline Stage 5: Update carrier phase accumulator
                r_fcw               <= fcw_reg;
                r_phase_accumulator <= r_phase_accumulator + r_fcw;

                -- Phase Modulation: instantaneous phase offset (no integration)
                -- temp_mod_scaled starts as Mod_Signal * MOD_SCALE_Q (Q12)
                temp_mod_scaled := to_integer(Mod_Signal) * MOD_SCALE_Q;

                -- Widen or narrow Mod_Signal from 16-bit to PHASE_ACC_WIDTH bits
                if PHASE_ACC_WIDTH > 16 then
                    phase_widen_factor := 2**(PHASE_ACC_WIDTH - 16);
                    temp_mod_scaled    := temp_mod_scaled * phase_widen_factor;
                elsif PHASE_ACC_WIDTH < 16 then
                    phase_widen_factor := 2**(16 - PHASE_ACC_WIDTH);
                    temp_mod_scaled    := temp_mod_scaled / phase_widen_factor;
                else
                    phase_widen_factor := 1;
                end if;

                -- Remove Q12 fractional scaling
                temp_mod_scaled := temp_mod_scaled / (2**MOD_Q_FRAC);

                -- Store as unsigned 2's-complement bit pattern for modulo addition
                r_pmod_accumulator <= unsigned(to_signed(temp_mod_scaled, PHASE_ACC_WIDTH));

                -- LUT Access Stage: Calculate LUT address and obtain LUT data
                r_lut_address     <= std_logic_vector(unsigned(r_phase_accumulator) + r_pmod_accumulator);
                r_lut_signed_out  <= to_signed(to_integer(unsigned(r_lut_data_out)) - VOLTAGE_OFFSET, LUT_DATA_WIDTH);
                r_result_reg      <= r_lut_signed_out;
                Result            <= r_result_reg;
            end if;
        end if;
    end process;
end architecture Behavioral;
