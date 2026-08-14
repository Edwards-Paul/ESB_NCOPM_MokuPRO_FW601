library IEEE;
use IEEE.Std_Logic_1164.All;
use IEEE.Numeric_Std.All;

architecture NCOWrapper of CustomWrapper is
    signal address : std_logic_vector(10 downto 0);
    signal sine_data : std_logic_vector(15 downto 0);
begin
    -- NCO instance
    U_NCO: entity WORK.NCO
        port map (
            Clk    => Clk,
            Reset  => Reset,
            DC     => InputA,  -- Use InputA of Slot for driving address calculation
            Mod_Signal => InputB, -- Use InputB of Slot for phase modulating the NCO signal
            Result => OutputA -- OutputB of Slot for phase-modulated RF signal based on mod. and DC signals
        );

end architecture NCOWrapper;




