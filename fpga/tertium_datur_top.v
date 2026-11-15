`timescale 1ns/1ps

// Tertium Datur top-level for Sipeed Tang Nano 20K (Gowin GW2AR-18C).
// Bridges physical buttons & one-hot LEDs, 115200 8N1 UART, and procedural 640x480 HDMI.
// Balanced trit one-hot convention: 3'b001 = 0, 3'b010 = +1, 3'b100 = -1.
module tertium_datur_top #(
    parameter integer SIM_ONLY = 0
) (
    input  wire       I_clk,       // 27 MHz oscillator (pin 4)
    input  wire [1:0] I_btn,       // Active-high pushbuttons (pins 88, 87)
    output wire [5:0] O_led_n,     // Active-low LEDs (pins 15..20)
    output wire       O_uart_tx,   // UART TX (pin 69)
    input  wire       I_uart_rx,   // UART RX (pin 70)
    output wire       O_tmds_clk_p,
    output wire       O_tmds_clk_n,
    output wire [2:0] O_tmds_data_p,
    output wire [2:0] O_tmds_data_n
);
    // Clocks: 27 MHz system, 126 MHz TMDS serial, 25.2 MHz pixel clock
    wire clk_sys = I_clk;
    wire clk_tmds;
    wire clk_pix;
    wire pll_lock;

    generate
        if (SIM_ONLY == 0) begin : gen_gowin_clks
            rPLL #(
                .FCLKIN("27.0"),
                .IDIV_SEL(2),
                .FBDIV_SEL(13),
                .ODIV_SEL(4),
                .CLKOUTD_BYPASS("false"),
                .CLKOUTD_SRC("CLKOUT"),
                .DYN_SDIV_SEL(6)
            ) u_pll_hdmi (
                .CLKIN(I_clk),
                .CLKFB(1'b0),
                .RESET(1'b0),
                .RESET_P(1'b0),
                .FBDSEL(6'b0),
                .IDSEL(6'b0),
                .ODSEL(6'b0),
                .PSDA(4'b0),
                .DUTYDA(4'b0),
                .FDLY(4'b0),
                .CLKOUT(clk_tmds),
                .LOCK(pll_lock),
                .CLKOUTP(),
                .CLKOUTD(),
                .CLKOUTD3()
            );

            CLKDIV #(
                .DIV_MODE("5"),
                .GSREN("false")
            ) u_div5 (
                .HCLKIN(clk_tmds),
                .RESETN(pll_lock),
                .CALIB(1'b0),
                .CLKOUT(clk_pix)
            );
        end else begin : gen_sim_clks
            assign clk_tmds = I_clk;
            assign clk_pix  = I_clk;
            assign pll_lock = 1'b1;
        end
    endgenerate

    // Power-on reset stretcher (~2.4 ms on hardware, 8 cycles in simulation)
    reg [15:0] por_cnt = 16'd0;
    wire por_done = (SIM_ONLY != 0) ? (por_cnt >= 16'd8) : (&por_cnt);
    always @(posedge clk_sys) begin
        if (!por_done)
            por_cnt <= por_cnt + 16'd1;
    end
    wire rst_sys = ~por_done;

    reg rst_pix_s0 = 1'b1;
    reg rst_pix    = 1'b1;
    always @(posedge clk_pix) begin
        rst_pix_s0 <= (~por_done) | (~pll_lock);
        rst_pix    <= rst_pix_s0;
    end

    // One-hot state storage for 7 balanced trits (trits[0] = LSB weight 1 .. trits[6] = weight 729)
    reg [2:0] trits [0:6];
    reg       mode_rosette = 1'b0;

    integer init_i;
    initial begin
        for (init_i = 0; init_i < 7; init_i = init_i + 1)
            trits[init_i] = 3'b001;
    end

    wire [20:0] trits_flat = {
        trits[6], trits[5], trits[4], trits[3], trits[2], trits[1], trits[0]
    };

    // Combinational signed 12-bit decimal sum of the 7 balanced trits (range -1093..+1093)
    wire signed [11:0] w0 = trits[0][1] ? 12'sd1   : (trits[0][2] ? -12'sd1   : 12'sd0);
    wire signed [11:0] w1 = trits[1][1] ? 12'sd3   : (trits[1][2] ? -12'sd3   : 12'sd0);
    wire signed [11:0] w2 = trits[2][1] ? 12'sd9   : (trits[2][2] ? -12'sd9   : 12'sd0);
    wire signed [11:0] w3 = trits[3][1] ? 12'sd27  : (trits[3][2] ? -12'sd27  : 12'sd0);
    wire signed [11:0] w4 = trits[4][1] ? 12'sd81  : (trits[4][2] ? -12'sd81  : 12'sd0);
    wire signed [11:0] w5 = trits[5][1] ? 12'sd243 : (trits[5][2] ? -12'sd243 : 12'sd0);
    wire signed [11:0] w6 = trits[6][1] ? 12'sd729 : (trits[6][2] ? -12'sd729 : 12'sd0);
    wire signed [11:0] dec_sum = w0 + w1 + w2 + w3 + w4 + w5 + w6;

    wire [1:0] dec_sign = (dec_sum > 12'sd0) ? 2'b10 : ((dec_sum < 12'sd0) ? 2'b11 : 2'b01);
    wire       upper_nonzero = (trits[6] != 3'b001) || (trits[5] != 3'b001) ||
                               (trits[4] != 3'b001) || (trits[3] != 3'b001) ||
                               (trits[2] != 3'b001) || (trits[1] != 3'b001);

    // Button debouncer (15 ms at 27 MHz) + combo/hold controller
    localparam integer DB_LIMIT    = (SIM_ONLY != 0) ? 4 : 405000;
    localparam integer COMBO_WIN   = (SIM_ONLY != 0) ? 6 : 1080000;   // 40 ms
    localparam integer HOLD_RESET  = (SIM_ONLY != 0) ? 20 : 21600000; // 800 ms

    reg [1:0]  btn_s0 = 2'b00, btn_s1 = 2'b00, btn_db = 2'b00;
    reg [19:0] db_cnt0 = 20'd0, db_cnt1 = 20'd0;

    always @(posedge clk_sys) begin
        btn_s0 <= I_btn;
        btn_s1 <= btn_s0;

        if (btn_s1[0] == btn_db[0]) begin
            db_cnt0 <= 20'd0;
        end else if (db_cnt0 >= DB_LIMIT[19:0]) begin
            btn_db[0] <= btn_s1[0];
            db_cnt0   <= 20'd0;
        end else begin
            db_cnt0 <= db_cnt0 + 20'd1;
        end

        if (btn_s1[1] == btn_db[1]) begin
            db_cnt1 <= 20'd0;
        end else if (db_cnt1 >= DB_LIMIT[19:0]) begin
            btn_db[1] <= btn_s1[1];
            db_cnt1   <= 20'd0;
        end else begin
            db_cnt1 <= db_cnt1 + 20'd1;
        end
    end

    reg        btn_action_cw   = 1'b0;
    reg        btn_action_ccw  = 1'b0;
    reg        btn_action_inv  = 1'b0;
    reg        btn_action_rst  = 1'b0;

    localparam [1:0] B_IDLE  = 2'd0;
    localparam [1:0] B_WAIT  = 2'd1;
    localparam [1:0] B_COMBO = 2'd2;
    localparam [1:0] B_DONE  = 2'd3;

    reg [1:0]  b_state = B_IDLE;
    reg [25:0] b_timer = 26'd0;
    reg [1:0]  b_first = 2'b00;

    always @(posedge clk_sys) begin
        btn_action_cw  <= 1'b0;
        btn_action_ccw <= 1'b0;
        btn_action_inv <= 1'b0;
        btn_action_rst <= 1'b0;

        if (rst_sys) begin
            b_state <= B_IDLE;
            b_timer <= 26'd0;
            b_first <= 2'b00;
        end else begin
            case (b_state)
                B_IDLE: begin
                    if (btn_db == 2'b11) begin
                        b_state <= B_COMBO;
                        b_timer <= 26'd0;
                    end else if (btn_db != 2'b00) begin
                        b_first <= btn_db;
                        b_state <= B_WAIT;
                        b_timer <= 26'd0;
                    end
                end
                B_WAIT: begin
                    if (btn_db == 2'b11) begin
                        b_state <= B_COMBO;
                        b_timer <= 26'd0;
                    end else if (btn_db == 2'b00) begin
                        if (b_first[0]) btn_action_cw  <= 1'b1;
                        else            btn_action_ccw <= 1'b1;
                        b_state <= B_IDLE;
                    end else if (b_timer >= COMBO_WIN[25:0]) begin
                        if (b_first[0]) btn_action_cw  <= 1'b1;
                        else            btn_action_ccw <= 1'b1;
                        b_state <= B_DONE;
                    end else begin
                        b_timer <= b_timer + 26'd1;
                    end
                end
                B_COMBO: begin
                    if (btn_db == 2'b00) begin
                        btn_action_inv <= 1'b1;
                        b_state <= B_IDLE;
                    end else if (b_timer >= HOLD_RESET[25:0]) begin
                        btn_action_rst <= 1'b1;
                        b_state <= B_DONE;
                    end else begin
                        b_timer <= b_timer + 26'd1;
                    end
                end
                B_DONE: begin
                    if (btn_db == 2'b00)
                        b_state <= B_IDLE;
                end
            endcase
        end
    end

    // UART transceiver
    reg        tx_start = 1'b0;
    reg  [7:0] tx_data  = 8'd0;
    wire       tx_busy;
    wire       rx_valid;
    wire [7:0] rx_data;

    td_uart #(
        .CLK_FREQ(27000000),
        .BAUD(115200)
    ) u_uart (
        .clk(clk_sys),
        .rst(rst_sys),
        .rx(I_uart_rx),
        .tx(O_uart_tx),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .rx_valid(rx_valid),
        .rx_data(rx_data)
    );

    // UART RX parser & 7-cycle hardware div3 balanced-ternary converter
    localparam [1:0] CMD_IDLE       = 2'd0;
    localparam [1:0] CMD_DEC_SIGN   = 2'd1;
    localparam [1:0] CMD_DEC_DIGITS = 2'd2;

    reg [1:0]  cmd_state     = CMD_IDLE;
    reg        dec_neg_in    = 1'b0;
    reg        dec_has_digit = 1'b0;
    reg [11:0] dec_acc       = 12'd0;

    reg        conv_active   = 1'b0;
    reg        conv_neg      = 1'b0;
    reg [2:0]  conv_step     = 3'd0;
    reg [10:0] conv_mag      = 11'd0;
    reg        conv_set_mode = 1'b0;

    reg        report_req    = 1'b0;
    reg        por_boot_sent = 1'b0;
    reg [22:0] act_timer     = 23'd0;
    wire       act_pulse     = (act_timer != 23'd0);

    // Fixed-point unsigned div3 for [0..1093]: (conv_mag * 21846) >> 16 is exact
    wire [26:0] conv_mul = conv_mag * 16'd21846;
    wire [10:0] conv_q   = conv_mul[26:16];
    wire [10:0] conv_q3  = conv_q + (conv_q << 1);
    wire [1:0]  conv_rem = conv_mag - conv_q3;

    wire [15:0] next_acc_calc = ({4'd0, dec_acc} * 16'd10) + {12'd0, (rx_data - 8'd48)};

    integer k;
    always @(posedge clk_sys) begin
        report_req <= 1'b0;

        if (rst_sys) begin
            for (k = 0; k < 7; k = k + 1)
                trits[k] <= 3'b001;
            mode_rosette  <= 1'b0;
            cmd_state     <= CMD_IDLE;
            conv_active   <= 1'b0;
            dec_neg_in    <= 1'b0;
            dec_has_digit <= 1'b0;
            dec_acc       <= 12'd0;
            por_boot_sent <= 1'b0;
            act_timer     <= 23'd0;
        end else begin
            if (!por_boot_sent) begin
                por_boot_sent <= 1'b1;
                report_req    <= 1'b1;
            end

            if (act_timer != 23'd0)
                act_timer <= act_timer - 23'd1;

            // Priority 1: Hardware div3 decimal-to-balanced-ternary conversion steps
            if (conv_active) begin
                if (conv_rem == 2'd0) begin
                    trits[conv_step] <= 3'b001;
                    conv_mag         <= conv_q;
                end else if (conv_rem == 2'd1) begin
                    trits[conv_step] <= conv_neg ? 3'b100 : 3'b010;
                    conv_mag         <= conv_q;
                end else begin
                    trits[conv_step] <= conv_neg ? 3'b010 : 3'b100;
                    conv_mag         <= conv_q + 11'd1;
                end

                if (conv_step == 3'd6) begin
                    conv_active  <= 1'b0;
                    mode_rosette <= conv_set_mode;
                    act_timer    <= (SIM_ONLY != 0) ? 23'd20 : 23'd4050000;
                    report_req   <= 1'b1;
                end else begin
                    conv_step <= conv_step + 3'd1;
                end
            end else begin
                // Priority 2: Physical button actions
                if (btn_action_rst) begin
                    for (k = 0; k < 7; k = k + 1)
                        trits[k] <= 3'b001;
                    mode_rosette <= 1'b0;
                    act_timer    <= (SIM_ONLY != 0) ? 23'd20 : 23'd4050000;
                    report_req   <= 1'b1;
                end else if (btn_action_inv) begin
                    for (k = 0; k < 7; k = k + 1)
                        trits[k] <= {trits[k][1], trits[k][2], trits[k][0]};
                    act_timer  <= (SIM_ONLY != 0) ? 23'd20 : 23'd4050000;
                    report_req <= 1'b1;
                end else if (btn_action_cw) begin
                    trits[0]   <= {trits[0][1:0], trits[0][2]};
                    act_timer  <= (SIM_ONLY != 0) ? 23'd20 : 23'd4050000;
                    report_req <= 1'b1;
                end else if (btn_action_ccw) begin
                    trits[0]   <= {trits[0][0], trits[0][2:1]};
                    act_timer  <= (SIM_ONLY != 0) ? 23'd20 : 23'd4050000;
                    report_req <= 1'b1;
                end else if (rx_valid) begin
                    // Priority 3: UART ASCII commands
                    case (cmd_state)
                        CMD_IDLE: begin
                            case (rx_data)
                                "c", "C", "+": begin
                                    trits[0]   <= {trits[0][1:0], trits[0][2]};
                                    act_timer  <= (SIM_ONLY != 0) ? 23'd20 : 23'd4050000;
                                    report_req <= 1'b1;
                                end
                                "a", "A", "-": begin
                                    trits[0]   <= {trits[0][0], trits[0][2:1]};
                                    act_timer  <= (SIM_ONLY != 0) ? 23'd20 : 23'd4050000;
                                    report_req <= 1'b1;
                                end
                                "i", "I": begin
                                    for (k = 0; k < 7; k = k + 1)
                                        trits[k] <= {trits[k][1], trits[k][2], trits[k][0]};
                                    act_timer  <= (SIM_ONLY != 0) ? 23'd20 : 23'd4050000;
                                    report_req <= 1'b1;
                                end
                                "r", "R", "0": begin
                                    for (k = 0; k < 7; k = k + 1)
                                        trits[k] <= 3'b001;
                                    mode_rosette <= 1'b0;
                                    act_timer    <= (SIM_ONLY != 0) ? 23'd20 : 23'd4050000;
                                    report_req   <= 1'b1;
                                end
                                "m", "M": begin
                                    mode_rosette <= ~mode_rosette;
                                    act_timer    <= (SIM_ONLY != 0) ? 23'd20 : 23'd4050000;
                                    report_req   <= 1'b1;
                                end
                                "?": begin
                                    act_timer  <= (SIM_ONLY != 0) ? 23'd20 : 23'd2025000;
                                    report_req <= 1'b1;
                                end
                                "d", "D": begin
                                    cmd_state     <= CMD_DEC_SIGN;
                                    dec_neg_in    <= 1'b0;
                                    dec_has_digit <= 1'b0;
                                    dec_acc       <= 12'd0;
                                end
                                default: ;
                            endcase
                        end

                        CMD_DEC_SIGN: begin
                            if (rx_data == "-") begin
                                dec_neg_in <= 1'b1;
                                cmd_state  <= CMD_DEC_DIGITS;
                            end else if (rx_data == "+") begin
                                dec_neg_in <= 1'b0;
                                cmd_state  <= CMD_DEC_DIGITS;
                            end else if (rx_data >= "0" && rx_data <= "9") begin
                                dec_acc       <= {8'd0, (rx_data - 8'd48)};
                                dec_has_digit <= 1'b1;
                                cmd_state     <= CMD_DEC_DIGITS;
                            end else if (rx_data == " ") begin
                                // Stay waiting for sign/digits after optional space
                            end else begin
                                cmd_state <= CMD_IDLE;
                            end
                        end

                        CMD_DEC_DIGITS: begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                dec_acc       <= (next_acc_calc > 16'd2047) ? 12'd2047 : next_acc_calc[11:0];
                                dec_has_digit <= 1'b1;
                            end else if (rx_data == 8'h0D || rx_data == 8'h0A || rx_data == ";" || rx_data == " ") begin
                                if (dec_has_digit) begin
                                    conv_mag      <= (dec_acc > 12'd1093) ? 11'd1093 : dec_acc[10:0];
                                    conv_neg      <= dec_neg_in;
                                    conv_set_mode <= (dec_acc > 12'd1) ? 1'b1 : mode_rosette;
                                    conv_step     <= 3'd0;
                                    conv_active   <= 1'b1;
                                end
                                cmd_state <= CMD_IDLE;
                            end else begin
                                cmd_state <= CMD_IDLE;
                            end
                        end

                        default: cmd_state <= CMD_IDLE;
                    endcase
                end
            end
        end
    end

    // UART status formatter & transmitter:
    // "TD dec=+0050 bt=00+-0-- mode=tryte6\r\n" (37 bytes)
    localparam [2:0] FMT_IDLE = 3'd0;
    localparam [2:0] FMT_D3   = 3'd1;
    localparam [2:0] FMT_D2   = 3'd2;
    localparam [2:0] FMT_D1   = 3'd3;
    localparam [2:0] FMT_SEND = 3'd4;
    localparam [2:0] FMT_WAIT = 3'd5;

    reg [2:0]  fmt_state = FMT_IDLE;
    reg        pending_report = 1'b0;
    reg [10:0] fmt_rem   = 11'd0;
    reg        fmt_neg   = 1'b0;
    reg        fmt_pos   = 1'b0;
    reg [3:0]  d3 = 4'd0, d2 = 4'd0, d1 = 4'd0, d0 = 4'd0;
    reg [5:0]  tx_idx    = 6'd0;

    function [7:0] trit_to_ascii;
        input [2:0] t;
        begin
            if      (t[1]) trit_to_ascii = "+";
            else if (t[2]) trit_to_ascii = "-";
            else           trit_to_ascii = "0";
        end
    endfunction

    reg [7:0] msg_byte;
    always @(*) begin
        case (tx_idx)
            6'd0:  msg_byte = "T";
            6'd1:  msg_byte = "D";
            6'd2:  msg_byte = " ";
            6'd3:  msg_byte = "d";
            6'd4:  msg_byte = "e";
            6'd5:  msg_byte = "c";
            6'd6:  msg_byte = "=";
            6'd7:  msg_byte = fmt_neg ? "-" : (fmt_pos ? "+" : " ");
            6'd8:  msg_byte = 8'd48 + {4'd0, d3};
            6'd9:  msg_byte = 8'd48 + {4'd0, d2};
            6'd10: msg_byte = 8'd48 + {4'd0, d1};
            6'd11: msg_byte = 8'd48 + {4'd0, d0};
            6'd12: msg_byte = " ";
            6'd13: msg_byte = "b";
            6'd14: msg_byte = "t";
            6'd15: msg_byte = "=";
            6'd16: msg_byte = trit_to_ascii(trits[6]);
            6'd17: msg_byte = trit_to_ascii(trits[5]);
            6'd18: msg_byte = trit_to_ascii(trits[4]);
            6'd19: msg_byte = trit_to_ascii(trits[3]);
            6'd20: msg_byte = trit_to_ascii(trits[2]);
            6'd21: msg_byte = trit_to_ascii(trits[1]);
            6'd22: msg_byte = trit_to_ascii(trits[0]);
            6'd23: msg_byte = " ";
            6'd24: msg_byte = "m";
            6'd25: msg_byte = "o";
            6'd26: msg_byte = "d";
            6'd27: msg_byte = "e";
            6'd28: msg_byte = "=";
            6'd29: msg_byte = mode_rosette ? "t" : "s";
            6'd30: msg_byte = mode_rosette ? "r" : "i";
            6'd31: msg_byte = mode_rosette ? "y" : "n";
            6'd32: msg_byte = mode_rosette ? "t" : "g";
            6'd33: msg_byte = mode_rosette ? "e" : "l";
            6'd34: msg_byte = mode_rosette ? "6" : "e";
            6'd35: msg_byte = 8'h0D;
            6'd36: msg_byte = 8'h0A;
            default: msg_byte = 8'h0A;
        endcase
    end

    always @(posedge clk_sys) begin
        tx_start <= 1'b0;

        if (rst_sys) begin
            fmt_state      <= FMT_IDLE;
            pending_report <= 1'b0;
            tx_idx         <= 6'd0;
            tx_data        <= 8'd0;
        end else begin
            if (report_req)
                pending_report <= 1'b1;

            case (fmt_state)
                FMT_IDLE: begin
                    if (pending_report && !tx_busy) begin
                        pending_report <= 1'b0;
                        fmt_neg <= (dec_sum < 12'sd0);
                        fmt_pos <= (dec_sum > 12'sd0);
                        fmt_rem <= (dec_sum < 12'sd0) ? (-dec_sum) : dec_sum[10:0];
                        d3 <= 4'd0; d2 <= 4'd0; d1 <= 4'd0; d0 <= 4'd0;
                        fmt_state <= FMT_D3;
                    end
                end
                FMT_D3: begin
                    if (fmt_rem >= 11'd1000) begin
                        fmt_rem <= fmt_rem - 11'd1000;
                        d3      <= d3 + 4'd1;
                    end else begin
                        fmt_state <= FMT_D2;
                    end
                end
                FMT_D2: begin
                    if (fmt_rem >= 11'd100) begin
                        fmt_rem <= fmt_rem - 11'd100;
                        d2      <= d2 + 4'd1;
                    end else begin
                        fmt_state <= FMT_D1;
                    end
                end
                FMT_D1: begin
                    if (fmt_rem >= 11'd10) begin
                        fmt_rem <= fmt_rem - 11'd10;
                        d1      <= d1 + 4'd1;
                    end else begin
                        d0        <= fmt_rem[3:0];
                        tx_idx    <= 6'd0;
                        fmt_state <= FMT_SEND;
                    end
                end
                FMT_SEND: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data   <= msg_byte;
                        tx_start  <= 1'b1;
                        fmt_state <= FMT_WAIT;
                    end
                end
                FMT_WAIT: begin
                    if (!tx_busy && !tx_start) begin
                        if (tx_idx == 6'd36) begin
                            fmt_state <= FMT_IDLE;
                        end else begin
                            tx_idx    <= tx_idx + 6'd1;
                            fmt_state <= FMT_SEND;
                        end
                    end
                end
                default: fmt_state <= FMT_IDLE;
            endcase
        end
    end

    // Heartbeat counter + Active-low physical LEDs
    reg [24:0] hb_cnt = 25'd0;
    always @(posedge clk_sys) begin
        hb_cnt <= hb_cnt + 25'd1;
    end

    assign O_led_n[0] = ~trits[0][2];                // -1 state (LSB)
    assign O_led_n[1] = ~trits[0][0];                //  0 state (LSB)
    assign O_led_n[2] = ~trits[0][1];                // +1 state (LSB)
    assign O_led_n[3] = ~act_pulse;                  // UART/Button activity pulse
    assign O_led_n[4] = ~(mode_rosette | upper_nonzero); // Tryte6 / peripheral trits active
    assign O_led_n[5] = ~(pll_lock & hb_cnt[24]);    // PLL lock 0.8 Hz heartbeat

    // Direct 640x480@60Hz procedural HDMI output
    td_hdmi #(
        .SIM_ONLY(SIM_ONLY)
    ) u_hdmi (
        .clk_pix(clk_pix),
        .clk_tmds(clk_tmds),
        .rst_pix(rst_pix),
        .trits_oh_sys(trits_flat),
        .mode_rosette_sys(mode_rosette),
        .dec_sign_sys(dec_sign),
        .activity_sys(act_pulse),
        .O_tmds_clk_p(O_tmds_clk_p),
        .O_tmds_clk_n(O_tmds_clk_n),
        .O_tmds_data_p(O_tmds_data_p),
        .O_tmds_data_n(O_tmds_data_n)
    );
endmodule
