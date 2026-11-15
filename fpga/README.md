# Tertium Datur Hardware Implementation (Sipeed Tang Nano 20K)

This directory synthesizes balanced ternary logic (`{-1, 0, +1}`) onto a Gowin `GW2AR-18C` FPGA using one-hot ternary encoding (`3'b100 = -1`, `3'b001 = 0`, `3'b010 = +1`), mirroring the isotropic 120-degree Y-hexagon geometry on hardware.

## Three Physical Representations

1. **Physical Buttons and One-Hot LEDs**:
   * **Onboard Pushbuttons (`I_btn[0]` pin 88, `I_btn[1]` pin 87):**
     * Press `BTN0` (`pin 88`): Cycle `trit[0]` clockwise (`0 -> +1 -> -1 -> 0`).
     * Press `BTN1` (`pin 87`): Cycle `trit[0]` counter-clockwise (`0 -> -1 -> +1 -> 0`).
     * Press `BTN0 + BTN1` simultaneously (short tap): Symmetric wire-swap negation (`+1 <-> -1`, `0 -> 0`) across all 7 trits.
     * Hold `BTN0 + BTN1` (`>= 800 ms`): Reset all 7 trits to `0` and return to Single Didactic Hexagon view.
   * **Active-Low LEDs (`O_led_n[5:0]`, pins 15..20):**
     * `LED0` (`pin 15`): Active when LSB `trit[0] == -1`.
     * `LED1` (`pin 16`): Active when LSB `trit[0] == 0`.
     * `LED2` (`pin 17`): Active when LSB `trit[0] == +1`.
     * `LED3` (`pin 18`): Button or UART command activity pulse.
     * `LED4` (`pin 19`): Active when `Tryte6` rosette mode or upper trits `trits[6:1]` are nonzero.
     * `LED5` (`pin 20`): PLL (Phase-Locked Loop, clock multiplier circuit) lock heartbeat (`~0.8 Hz`).

2. **UART Serial Bridge (`115200 8N1`, TX pin 69, RX pin 70)**:
   * `c` or `+`: Clockwise transition on `trit[0]`.
   * `a` or `-`: Counter-clockwise transition on `trit[0]`.
   * `i`: Symmetric negation across all 7 trits (`val -> -val`).
   * `r` or `0`: Reset all 7 trits to `0` and switch to single-cell mode.
   * `m`: Toggle HDMI display between `single` (didactic `-`, `0`, `+` hexagon) and `tryte6` (7-cell rosette).
   * `d<int>\n`: Convert signed integer in `[-1093, +1093]` to 7 balanced trits using a 7-cycle fixed-point `div3` hardware FSM (Finite-State Machine, sequential digital control circuit) and plot it across LEDs, UART telemetry, and HDMI.
   * `?`: Query current state formatted as ASCII (American Standard Code for Information Interchange, 7-bit character encoding): `TD dec=+0050 bt=00+-0-- mode=tryte6`.

3. **Direct 640x480@60Hz Procedural HDMI (`O_tmds_clk_p/n`, `O_tmds_data_p/n[2:0]`)**:
   * Driven directly from an internal `rPLL` (`126 MHz` TMDS clock) and `CLKDIV` (`/5` -> `25.2 MHz` pixel clock) using Gowin `OSER10` serializers and `TLVDS_OBUF` differential buffers.
   * Zero BRAM (Block Random-Access Memory, embedded FPGA memory blocks) framebuffers are used: the tripartite hexagon, 120-degree golden Y-junction, didactic `-` / `0` / `+` glyphs, 7-hexagon `Tryte6` rosette, and bottom 7-trit status strip are computed geometrically per pixel in real time.

## Open-Source Build and Flash

Requires `yosys`, `nextpnr-himbaechel` (built with `himbaechel-gowin`), `gowin_pack`, and `openFPGALoader`:

```sh
chmod +x fpga/build.sh
./fpga/build.sh --flash
```

Control the programmed FPGA over UART using Bun:

```sh
bun fpga/serial_ctrl.js /dev/ttyUSB1 ? d50 i r
```
