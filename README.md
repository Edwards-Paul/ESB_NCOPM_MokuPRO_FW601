
---

## Hardware parameters

| Parameter | Value |
|---|---|
| Target platform | Moku:Pro (UltraScale+ FPGA) |
| Core clock | 312.5 MHz |
| Phase accumulator width `P` | 16 bits |
| LUT address width `A` | 16 bits |
| Sample width `N` | 16 bits |
| NCO frequency range | 1 – 100 MHz |
| PM index scale factor `S_PM` | 1 (adjustable generic) |

The NCO frequency-code spacing is

$$\Delta f_\mathrm{NCO} = \frac{f_\mathrm{clock}}{2^P}
= \frac{312.5\ \mathrm{MHz}}{65536} \approx 4.77\ \mathrm{kHz},$$

corresponding to an equivalent cavity-displacement code step of
approximately 10 pm for the 59.0 cm measurement cavity described
in the paper.

---

## Build example — firmware 601

> ⚠️ **Legacy firmware notice**
> The `build_example/` folder contains a pre-compiled bitstream and
> project files targeting **Moku:Pro firmware 601**.
> Firmware 601 is a **legacy release** and is scheduled for
> end-of-life closure by **end of September 2026**.
> New projects should target the current production firmware.
> Liquid Instruments will not guarantee Cloud Compile compatibility
> with firmware 601 after that date.

The build example is provided as a reference for the configuration
used in the measurements reported in the paper. It should not be
used as the basis for new deployments without updating to a supported
firmware version.

---

## Building with Moku Cloud Compile

Moku Cloud Compile (MCC) is the browser-based IDE for synthesising
custom VHDL instruments for Moku platforms.

**IDE:** https://compile.liquidinstruments.com/

### Minimal build instructions

1. **Open the IDE** at https://compile.liquidinstruments.com/ and
   sign in with your Liquid Instruments account.

2. **Create a new project** and select **Moku:Pro** as the target
   platform. Choose the current production firmware version
   (not 601 unless reproducing the legacy build).

3. **Upload source files.** Add the following files from `src/` to
   the project in order:
   - `sine_bram.vhd`
   - `nco.vhd`
   - `esb_top.vhd` (set as the top-level entity)

4. **Set the top-level entity** to `esb_top` in the project settings.

5. **Configure generics** if needed. The defaults match the
   experimental parameters in the paper:
   - `F_CLK = 312_500_000.0`
   - `F_MIN = 1_000_000.0`
   - `F_MAX = 100_000_000.0`
   - `P = 16`, `N = 16`, `A = 16`

6. **Run synthesis.** Click **Compile**. Build time is typically
   several minutes. The IDE will report any timing or resource
   violations.

7. **Deploy to instrument.** Once synthesis succeeds, download the
   bitstream and load it onto the Moku:Pro via the Moku app or
   Python API. The custom instrument will appear as a slot option
   in Multi-Instrument Mode (MiM).

8. **Connect in MiM.** Assign the NCO/PM instrument to a slot,
   route the Laser Lock Box PI output to the NCO control input,
   and route the fixed-frequency LO copy to the PM input, as
   described in Section II A of the paper.

For full MCC documentation see:
https://apis.liquidinstruments.com/mcc/

---

## Citation

If you use this code in published work, please cite the associated
paper:
