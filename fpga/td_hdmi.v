`timescale 1ns/1ps

// TMDS 8b/10b encoder per DVI 1.0 specification.
module td_tmds_encoder (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire [1:0] ctrl,
    input  wire       de,
    output reg  [9:0] dout
);
    wire [3:0] n1_d = data[0] + data[1] + data[2] + data[3] +
                      data[4] + data[5] + data[6] + data[7];
    wire use_xnor = (n1_d > 4'd4) || ((n1_d == 4'd4) && (data[0] == 1'b0));

    wire [8:0] q_m;
    assign q_m[0] = data[0];
    assign q_m[1] = use_xnor ? (q_m[0] ~^ data[1]) : (q_m[0] ^ data[1]);
    assign q_m[2] = use_xnor ? (q_m[1] ~^ data[2]) : (q_m[1] ^ data[2]);
    assign q_m[3] = use_xnor ? (q_m[2] ~^ data[3]) : (q_m[2] ^ data[3]);
    assign q_m[4] = use_xnor ? (q_m[3] ~^ data[4]) : (q_m[3] ^ data[4]);
    assign q_m[5] = use_xnor ? (q_m[4] ~^ data[5]) : (q_m[4] ^ data[5]);
    assign q_m[6] = use_xnor ? (q_m[5] ~^ data[6]) : (q_m[5] ^ data[6]);
    assign q_m[7] = use_xnor ? (q_m[6] ~^ data[7]) : (q_m[6] ^ data[7]);
    assign q_m[8] = ~use_xnor;

    wire [3:0] n1_qm = q_m[0] + q_m[1] + q_m[2] + q_m[3] +
                       q_m[4] + q_m[5] + q_m[6] + q_m[7];
    wire signed [4:0] balance_qm = $signed({1'b0, n1_qm}) - 5'sd4;

    reg signed [4:0] dc_bias = 5'sd0;

    always @(posedge clk) begin
        if (rst) begin
            dc_bias <= 5'sd0;
            dout    <= 10'b1101010100;
        end else if (!de) begin
            dc_bias <= 5'sd0;
            case (ctrl)
                2'b00: dout <= 10'b1101010100;
                2'b01: dout <= 10'b0010101011;
                2'b10: dout <= 10'b0101010100;
                2'b11: dout <= 10'b1010101011;
            endcase
        end else begin
            if ((dc_bias == 5'sd0) || (n1_qm == 4'd4)) begin
                dout[9]   <= ~q_m[8];
                dout[8]   <= q_m[8];
                dout[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                if (q_m[8] == 1'b0)
                    dc_bias <= dc_bias - (balance_qm <<< 1);
                else
                    dc_bias <= dc_bias + (balance_qm <<< 1);
            end else if (((dc_bias > 5'sd0) && (n1_qm > 4'd4)) ||
                         ((dc_bias < 5'sd0) && (n1_qm < 4'd4))) begin
                dout[9]   <= 1'b1;
                dout[8]   <= q_m[8];
                dout[7:0] <= ~q_m[7:0];
                dc_bias   <= dc_bias + (q_m[8] ? 5'sd2 : 5'sd0) - (balance_qm <<< 1);
            end else begin
                dout[9]   <= 1'b0;
                dout[8]   <= q_m[8];
                dout[7:0] <= q_m[7:0];
                dc_bias   <= dc_bias - (q_m[8] ? 5'sd0 : 5'sd2) + (balance_qm <<< 1);
            end
        end
    end
endmodule

// Procedural 640x480@60Hz HDMI generator for Tertium Datur (0 BRAM framebuffer).
// Visualizes Single Didactic Trit (with -, 0, + glyphs) or 7-cell Tryte6 Rosette
// plus a 7-slot balanced ternary status bar along the bottom.
module td_hdmi #(
    parameter integer SIM_ONLY = 0
) (
    input  wire        clk_pix,
    input  wire        clk_tmds,
    input  wire        rst_pix,
    input  wire [20:0] trits_oh_sys,
    input  wire        mode_rosette_sys,
    input  wire [1:0]  dec_sign_sys,     // 2'b01=0, 2'b10=pos, 2'b11=neg
    input  wire        activity_sys,
    output wire        O_tmds_clk_p,
    output wire        O_tmds_clk_n,
    output wire [2:0]  O_tmds_data_p,
    output wire [2:0]  O_tmds_data_n
);
    // 640x480 @ 60Hz timing (800x525 total)
    localparam [9:0] H_ACTIVE = 10'd640;
    localparam [9:0] H_FP     = 10'd16;
    localparam [9:0] H_SYNC   = 10'd96;
    localparam [9:0] H_TOTAL  = 10'd800;

    localparam [9:0] V_ACTIVE = 10'd480;
    localparam [9:0] V_FP     = 10'd10;
    localparam [9:0] V_SYNC   = 10'd2;
    localparam [9:0] V_TOTAL  = 10'd525;

    reg [9:0] hx = 10'd0;
    reg [9:0] vy = 10'd0;
    always @(posedge clk_pix) begin
        if (rst_pix) begin
            hx <= 10'd0;
            vy <= 10'd0;
        end else if (hx == H_TOTAL - 10'd1) begin
            hx <= 10'd0;
            vy <= (vy == V_TOTAL - 10'd1) ? 10'd0 : (vy + 10'd1);
        end else begin
            hx <= hx + 10'd1;
        end
    end

    wire de_raw = (hx < H_ACTIVE) && (vy < V_ACTIVE);
    wire hs_raw = ~((hx >= H_ACTIVE + H_FP) && (hx < H_ACTIVE + H_FP + H_SYNC));
    wire vs_raw = ~((vy >= V_ACTIVE + V_FP) && (vy < V_ACTIVE + V_FP + V_SYNC));

    // Synchronize state from clk_sys into clk_pix and latch cleanly at vertical blank
    reg [20:0] trits_sync0 = 21'b001_001_001_001_001_001_001;
    reg [20:0] trits_sync1 = 21'b001_001_001_001_001_001_001;
    reg [20:0] trits_pix   = 21'b001_001_001_001_001_001_001;
    reg        mode_sync0  = 1'b0, mode_sync1 = 1'b0, mode_pix = 1'b0;
    reg [1:0]  sign_sync0  = 2'b01, sign_sync1 = 2'b01, sign_pix = 2'b01;
    reg        act_sync0   = 1'b0, act_sync1  = 1'b0, act_pix  = 1'b0;

    always @(posedge clk_pix) begin
        trits_sync0 <= trits_oh_sys;
        trits_sync1 <= trits_sync0;
        mode_sync0  <= mode_rosette_sys;
        mode_sync1  <= mode_sync0;
        sign_sync0  <= dec_sign_sys;
        sign_sync1  <= sign_sync0;
        act_sync0   <= activity_sys;
        act_sync1   <= act_sync0;
        if (hx == 10'd0 && vy == V_ACTIVE) begin
            trits_pix <= trits_sync1;
            mode_pix  <= mode_sync1;
            sign_pix  <= sign_sync1;
            act_pix   <= act_sync1;
        end
    end

    // Stage 1: select target hexagon (single giant or one of 7 non-overlapping rosette hexes)
    reg [9:0]         s1_hx        = 10'd0;
    reg [9:0]         s1_vy        = 10'd0;
    reg               s1_de        = 1'b0;
    reg               s1_hs        = 1'b1;
    reg               s1_vs        = 1'b1;
    reg signed [10:0] s1_dx        = 11'sd0;
    reg signed [10:0] s1_dy        = 11'sd0;
    reg               s1_in_bbox   = 1'b0;
    reg [8:0]         s1_R         = 9'd148;
    reg [2:0]         s1_trit      = 3'b001;
    reg               s1_mode      = 1'b0;
    reg               s1_is_center = 1'b1;

    wire signed [10:0] shx = $signed({1'b0, hx});
    wire signed [10:0] svy = $signed({1'b0, vy});

    always @(posedge clk_pix) begin
        s1_hx   <= hx;
        s1_vy   <= vy;
        s1_de   <= de_raw;
        s1_hs   <= hs_raw;
        s1_vs   <= vs_raw;
        s1_mode <= mode_pix;

        if (!mode_pix) begin
            s1_dx        <= shx - 11'sd320;
            s1_dy        <= svy - 11'sd208;
            s1_in_bbox   <= (hx >= 10'd190 && hx <= 10'd450 && vy >= 10'd58 && vy <= 10'd358);
            s1_R         <= 9'd148;
            s1_trit      <= trits_pix[2:0];
            s1_is_center <= 1'b1;
        end else begin
            s1_R <= 9'd52;
            // Seven non-overlapping bounding boxes for pointy-top hexes of R=52 (W=45)
            if (hx >= 10'd274 && hx <= 10'd366 && vy >= 10'd155 && vy <= 10'd261) begin
                s1_dx <= shx - 11'sd320; s1_dy <= svy - 11'sd208;
                s1_trit <= trits_pix[2:0]; s1_in_bbox <= 1'b1; s1_is_center <= 1'b1;
            end else if (hx >= 10'd378 && hx <= 10'd470 && vy >= 10'd155 && vy <= 10'd261) begin
                s1_dx <= shx - 11'sd424; s1_dy <= svy - 11'sd208;
                s1_trit <= trits_pix[5:3]; s1_in_bbox <= 1'b1; s1_is_center <= 1'b0;
            end else if (hx >= 10'd326 && hx <= 10'd418 && vy >= 10'd65 && vy <= 10'd171) begin
                s1_dx <= shx - 11'sd372; s1_dy <= svy - 11'sd118;
                s1_trit <= trits_pix[8:6]; s1_in_bbox <= 1'b1; s1_is_center <= 1'b0;
            end else if (hx >= 10'd222 && hx <= 10'd314 && vy >= 10'd65 && vy <= 10'd171) begin
                s1_dx <= shx - 11'sd268; s1_dy <= svy - 11'sd118;
                s1_trit <= trits_pix[11:9]; s1_in_bbox <= 1'b1; s1_is_center <= 1'b0;
            end else if (hx >= 10'd170 && hx <= 10'd262 && vy >= 10'd155 && vy <= 10'd261) begin
                s1_dx <= shx - 11'sd216; s1_dy <= svy - 11'sd208;
                s1_trit <= trits_pix[14:12]; s1_in_bbox <= 1'b1; s1_is_center <= 1'b0;
            end else if (hx >= 10'd222 && hx <= 10'd314 && vy >= 10'd245 && vy <= 10'd351) begin
                s1_dx <= shx - 11'sd268; s1_dy <= svy - 11'sd298;
                s1_trit <= trits_pix[17:15]; s1_in_bbox <= 1'b1; s1_is_center <= 1'b0;
            end else if (hx >= 10'd326 && hx <= 10'd418 && vy >= 10'd245 && vy <= 10'd351) begin
                s1_dx <= shx - 11'sd372; s1_dy <= svy - 11'sd298;
                s1_trit <= trits_pix[20:18]; s1_in_bbox <= 1'b1; s1_is_center <= 1'b0;
            end else begin
                s1_dx <= 11'sd0; s1_dy <= 11'sd0;
                s1_trit <= 3'b001; s1_in_bbox <= 1'b0; s1_is_center <= 1'b0;
            end
        end
    end

    // Stage 2 combinational geometry evaluation for the selected hex + UI bars
    wire [10:0] ax = (s1_dx < 0) ? -s1_dx : s1_dx;
    wire [10:0] ay = (s1_dy < 0) ? -s1_dy : s1_dy;

    wire [17:0] ax18 = {7'd0, ax};
    wire [17:0] ay18 = {7'd0, ay};
    wire signed [17:0] sdx18 = {{7{s1_dx[10]}}, s1_dx};
    wire signed [17:0] sdy18 = {{7{s1_dy[10]}}, s1_dy};

    wire [17:0] m1 = ax18 * 18'd74;
    wire [17:0] m2 = (ay18 << 6) + (ax18 * 18'd37);
    wire [17:0] hex_metric = (m1 > m2) ? m1 : m2;

    wire [17:0] r_lim   = {3'd0, s1_R, 6'd0};
    wire [17:0] r_inner = r_lim - (s1_mode ? 18'd192 : 18'd320);
    wire [17:0] y_w     = s1_mode ? 18'd160 : 18'd320;

    wire in_hex = s1_in_bbox && (hex_metric <= r_lim);
    wire in_rim = in_hex && (hex_metric > r_inner);

    // 120-degree golden Y-junction rays
    wire signed [17:0] d_ul = (sdx18 <<< 5) - (sdy18 * 18'sd55);
    wire [17:0] abs_ul = (d_ul < 0) ? -d_ul : d_ul;
    wire signed [17:0] d_ur = (sdx18 <<< 5) + (sdy18 * 18'sd55);
    wire [17:0] abs_ur = (d_ur < 0) ? -d_ur : d_ur;

    wire in_y_down = (s1_dy >= 11'sd0) && ((ax18 << 6) <= y_w);
    wire in_y_ul   = (s1_dy <= 11'sd3) && (s1_dx <= 11'sd3)  && (abs_ul <= y_w);
    wire in_y_ur   = (s1_dy <= 11'sd3) && (s1_dx >= -11'sd3) && (abs_ur <= y_w);
    wire in_y_hub  = (hex_metric <= (y_w + 18'd64));
    wire in_y      = in_hex && (in_y_down || in_y_ul || in_y_ur || in_y_hub);

    // Rhombus partition: top wedge (0), bottom-left (-1), bottom-right (+1)
    wire sec_top = (sdy18 * 18'sd55) < -$signed(ax18 <<< 5);
    wire sec_neg = (!sec_top) && (s1_dx < 11'sd0);
    wire sec_pos = (!sec_top) && (s1_dx >= 11'sd0);

    // Didactic -, 0, + glyphs in single-hex mode
    wire signed [10:0] g0_dy = s1_dy + 11'sd74;
    wire [10:0] g0_ay = (g0_dy < 0) ? -g0_dy : g0_dy;
    wire glyph_0 = (!s1_mode) && in_hex && !in_y &&
                   (ax <= 11'd12 && g0_ay <= 11'd18) &&
                   !(ax <= 11'd5 && g0_ay <= 11'd11) &&
                   !((ax >= 11'd10) && (g0_ay >= 11'd16));

    wire signed [10:0] gm_dx = s1_dx + 11'sd64;
    wire signed [10:0] gm_dy = s1_dy - 11'sd37;
    wire [10:0] gm_ax = (gm_dx < 0) ? -gm_dx : gm_dx;
    wire [10:0] gm_ay = (gm_dy < 0) ? -gm_dy : gm_dy;
    wire glyph_neg = (!s1_mode) && in_hex && !in_y && (gm_ax <= 11'd15 && gm_ay <= 11'd4);

    wire signed [10:0] gp_dx = s1_dx - 11'sd64;
    wire signed [10:0] gp_dy = s1_dy - 11'sd37;
    wire [10:0] gp_ax = (gp_dx < 0) ? -gp_dx : gp_dx;
    wire [10:0] gp_ay = (gp_dy < 0) ? -gp_dy : gp_dy;
    wire glyph_pos = (!s1_mode) && in_hex && !in_y &&
                     ((gp_ax <= 11'd15 && gp_ay <= 11'd4) ||
                      (gp_ax <= 11'd4 && gp_ay <= 11'd15));

    // Bottom 7-slot balanced ternary tile bar (k=0..6 left-to-right displays trits[6..0])
    reg        tile_hit;
    reg        tile_border;
    reg        tile_glyph;
    reg        tile_lsb;
    reg [2:0]  tile_trit;
    reg signed [6:0] tile_dx;
    reg signed [6:0] tile_dy;
    reg [2:0]  tile_slot;
    always @(*) begin
        tile_hit    = 1'b0;
        tile_border = 1'b0;
        tile_glyph  = 1'b0;
        tile_lsb    = 1'b0;
        tile_trit   = 3'b001;
        tile_dx     = 7'sd0;
        tile_dy     = 7'sd0;
        tile_slot   = 3'd0;

        if (s1_vy >= 10'd404 && s1_vy <= 10'd444) begin
            if      (s1_hx >= 10'd144 && s1_hx <= 10'd184) begin tile_hit = 1'b1; tile_slot = 3'd6; tile_dx = $signed(s1_hx - 10'd164); tile_trit = trits_pix[20:18]; end
            else if (s1_hx >= 10'd196 && s1_hx <= 10'd236) begin tile_hit = 1'b1; tile_slot = 3'd5; tile_dx = $signed(s1_hx - 10'd216); tile_trit = trits_pix[17:15]; end
            else if (s1_hx >= 10'd248 && s1_hx <= 10'd288) begin tile_hit = 1'b1; tile_slot = 3'd4; tile_dx = $signed(s1_hx - 10'd268); tile_trit = trits_pix[14:12]; end
            else if (s1_hx >= 10'd300 && s1_hx <= 10'd340) begin tile_hit = 1'b1; tile_slot = 3'd3; tile_dx = $signed(s1_hx - 10'd320); tile_trit = trits_pix[11:9];  end
            else if (s1_hx >= 10'd352 && s1_hx <= 10'd392) begin tile_hit = 1'b1; tile_slot = 3'd2; tile_dx = $signed(s1_hx - 10'd372); tile_trit = trits_pix[8:6];   end
            else if (s1_hx >= 10'd404 && s1_hx <= 10'd444) begin tile_hit = 1'b1; tile_slot = 3'd1; tile_dx = $signed(s1_hx - 10'd424); tile_trit = trits_pix[5:3];   end
            else if (s1_hx >= 10'd456 && s1_hx <= 10'd496) begin tile_hit = 1'b1; tile_slot = 3'd0; tile_dx = $signed(s1_hx - 10'd476); tile_trit = trits_pix[2:0];   tile_lsb = 1'b1; end

            tile_dy = $signed(s1_vy - 10'd424);
            if (tile_hit) begin
                tile_border = (tile_dx <= -7'sd18 || tile_dx >= 7'sd18 || tile_dy <= -7'sd18 || tile_dy >= 7'sd18);
                if (tile_trit[2]) // -1: minus glyph
                    tile_glyph = (tile_dx >= -7'sd8 && tile_dx <= 7'sd8 && tile_dy >= -7'sd2 && tile_dy <= 7'sd2);
                else if (tile_trit[1]) // +1: plus glyph
                    tile_glyph = (tile_dx >= -7'sd8 && tile_dx <= 7'sd8 && tile_dy >= -7'sd2 && tile_dy <= 7'sd2) ||
                                 (tile_dx >= -7'sd2 && tile_dx <= 7'sd2 && tile_dy >= -7'sd8 && tile_dy <= 7'sd8);
                else // 0: zero ring
                    tile_glyph = (tile_dx >= -7'sd6 && tile_dx <= 7'sd6 && tile_dy >= -7'sd9 && tile_dy <= 7'sd9) &&
                                 !(tile_dx >= -7'sd2 && tile_dx <= 7'sd2 && tile_dy >= -7'sd5 && tile_dy <= 7'sd5);
            end
        end
    end

    // Top status header pills
    wire top_pill_mode = (s1_vy >= 10'd18 && s1_vy <= 10'd30 && s1_hx >= 10'd180 && s1_hx <= 10'd260);
    wire top_pill_sign = (s1_vy >= 10'd18 && s1_vy <= 10'd30 && s1_hx >= 10'd280 && s1_hx <= 10'd360);
    wire top_pill_act  = (s1_vy >= 10'd18 && s1_vy <= 10'd30 && s1_hx >= 10'd380 && s1_hx <= 10'd460);

    // Stage 2 RGB output registers + synced timing controls
    reg [7:0] pix_r = 8'd0;
    reg [7:0] pix_g = 8'd0;
    reg [7:0] pix_b = 8'd0;
    reg       s2_de = 1'b0;
    reg       s2_hs = 1'b1;
    reg       s2_vs = 1'b1;

    always @(posedge clk_pix) begin
        s2_de <= s1_de;
        s2_hs <= s1_hs;
        s2_vs <= s1_vs;

        if (!s1_de) begin
            pix_r <= 8'd0;
            pix_g <= 8'd0;
            pix_b <= 8'd0;
        end else if (in_hex) begin
            if (in_y || in_rim) begin
                // Golden Y-junction and perimeter trim (brighter gold on center/single hex)
                if (in_rim && s1_is_center && s1_mode) begin
                    pix_r <= 8'd244; pix_g <= 8'd202; pix_b <= 8'd84;
                end else begin
                    pix_r <= 8'd214; pix_g <= 8'd168; pix_b <= 8'd54;
                end
            end else if (sec_top) begin
                // Sector 0 (Top Rhombus, Ice White / Obsidian)
                if (s1_trit[0]) begin
                    if (glyph_0) begin pix_r <= 8'd18;  pix_g <= 8'd24;  pix_b <= 8'd36;  end
                    else         begin pix_r <= 8'd228; pix_g <= 8'd234; pix_b <= 8'd245; end
                end else begin
                    if (glyph_0) begin pix_r <= 8'd70; pix_g <= 8'd78; pix_b <= 8'd92; end
                    else         begin pix_r <= 8'd26; pix_g <= 8'd30; pix_b <= 8'd42; end
                end
            end else if (sec_neg) begin
                // Sector -1 (Bottom-Left Rhombus, Cobalt Sapphire Blue)
                if (s1_trit[2]) begin
                    if (glyph_neg) begin pix_r <= 8'd235; pix_g <= 8'd244; pix_b <= 8'd255; end
                    else           begin pix_r <= 8'd42;  pix_g <= 8'd128; pix_b <= 8'd245; end
                end else begin
                    if (glyph_neg) begin pix_r <= 8'd56; pix_g <= 8'd78; pix_b <= 8'd110; end
                    else           begin pix_r <= 8'd12; pix_g <= 8'd24; pix_b <= 8'd48;  end
                end
            end else begin
                // Sector +1 (Bottom-Right Rhombus, Crimson Coral Red)
                if (s1_trit[1]) begin
                    if (glyph_pos) begin pix_r <= 8'd255; pix_g <= 8'd240; pix_b <= 8'd236; end
                    else           begin pix_r <= 8'd230; pix_g <= 8'd56;  pix_b <= 8'd62;  end
                end else begin
                    if (glyph_pos) begin pix_r <= 8'd112; pix_g <= 8'd58; pix_b <= 8'd58; end
                    else           begin pix_r <= 8'd42;  pix_g <= 8'd16; pix_b <= 8'd20; end
                end
            end
        end else if (tile_hit) begin
            if (tile_border) begin
                if (tile_lsb) begin pix_r <= 8'd214; pix_g <= 8'd168; pix_b <= 8'd54;  end
                else          begin pix_r <= 8'd64;  pix_g <= 8'd76;  pix_b <= 8'd104; end
            end else if (tile_glyph) begin
                if (tile_trit[0]) begin pix_r <= 8'd16;  pix_g <= 8'd22;  pix_b <= 8'd34;  end
                else              begin pix_r <= 8'd245; pix_g <= 8'd248; pix_b <= 8'd255; end
            end else begin
                if      (tile_trit[2]) begin pix_r <= 8'd38;  pix_g <= 8'd114; pix_b <= 8'd228; end
                else if (tile_trit[1]) begin pix_r <= 8'd216; pix_g <= 8'd52;  pix_b <= 8'd58;  end
                else                   begin pix_r <= 8'd210; pix_g <= 8'd220; pix_b <= 8'd236; end
            end
        end else if (top_pill_mode) begin
            if (mode_pix) begin pix_r <= 8'd214; pix_g <= 8'd168; pix_b <= 8'd54; end
            else          begin pix_r <= 8'd58;  pix_g <= 8'd72;  pix_b <= 8'd98; end
        end else if (top_pill_sign) begin
            if      (sign_pix == 2'b11) begin pix_r <= 8'd42;  pix_g <= 8'd128; pix_b <= 8'd245; end
            else if (sign_pix == 2'b10) begin pix_r <= 8'd230; pix_g <= 8'd56;  pix_b <= 8'd62;  end
            else                        begin pix_r <= 8'd210; pix_g <= 8'd220; pix_b <= 8'd236; end
        end else if (top_pill_act) begin
            if (act_pix) begin pix_r <= 8'd52; pix_g <= 8'd211; pix_b <= 8'd153; end
            else         begin pix_r <= 8'd28; pix_g <= 8'd36;  pix_b <= 8'd52;  end
        end else begin
            // Deep obsidian radial-like backdrop with subtle grid ticks
            if ((s1_hx[4:0] == 5'd0) && (s1_vy[4:0] == 5'd0)) begin
                pix_r <= 8'd30; pix_g <= 8'd40; pix_b <= 8'd62;
            end else begin
                pix_r <= 8'd10; pix_g <= 8'd14; pix_b <= 8'd24;
            end
        end
    end

    // TMDS encoders (s2_de, s2_hs, s2_vs align strictly with pix_r/g/b)
    wire [9:0] tmds_blue, tmds_green, tmds_red;
    td_tmds_encoder u_enc_b (.clk(clk_pix), .rst(rst_pix), .data(pix_b), .ctrl({s2_vs, s2_hs}), .de(s2_de), .dout(tmds_blue));
    td_tmds_encoder u_enc_g (.clk(clk_pix), .rst(rst_pix), .data(pix_g), .ctrl(2'b00),          .de(s2_de), .dout(tmds_green));
    td_tmds_encoder u_enc_r (.clk(clk_pix), .rst(rst_pix), .data(pix_r), .ctrl(2'b00),          .de(s2_de), .dout(tmds_red));

    generate
        if (SIM_ONLY == 0) begin : gen_gowin_tmds
            wire ser_clk, ser_d0, ser_d1, ser_d2;

            OSER10 #(.GSREN("false"), .LSREN("true")) u_ser_clk (
                .Q(ser_clk),
                .D0(1'b1), .D1(1'b1), .D2(1'b1), .D3(1'b1), .D4(1'b1),
                .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0), .D9(1'b0),
                .PCLK(clk_pix), .FCLK(clk_tmds), .RESET(rst_pix)
            );
            TLVDS_OBUF u_obuf_clk (.I(ser_clk), .O(O_tmds_clk_p), .OB(O_tmds_clk_n));

            OSER10 #(.GSREN("false"), .LSREN("true")) u_ser_d0 (
                .Q(ser_d0),
                .D0(tmds_blue[0]), .D1(tmds_blue[1]), .D2(tmds_blue[2]), .D3(tmds_blue[3]), .D4(tmds_blue[4]),
                .D5(tmds_blue[5]), .D6(tmds_blue[6]), .D7(tmds_blue[7]), .D8(tmds_blue[8]), .D9(tmds_blue[9]),
                .PCLK(clk_pix), .FCLK(clk_tmds), .RESET(rst_pix)
            );
            TLVDS_OBUF u_obuf_d0 (.I(ser_d0), .O(O_tmds_data_p[0]), .OB(O_tmds_data_n[0]));

            OSER10 #(.GSREN("false"), .LSREN("true")) u_ser_d1 (
                .Q(ser_d1),
                .D0(tmds_green[0]), .D1(tmds_green[1]), .D2(tmds_green[2]), .D3(tmds_green[3]), .D4(tmds_green[4]),
                .D5(tmds_green[5]), .D6(tmds_green[6]), .D7(tmds_green[7]), .D8(tmds_green[8]), .D9(tmds_green[9]),
                .PCLK(clk_pix), .FCLK(clk_tmds), .RESET(rst_pix)
            );
            TLVDS_OBUF u_obuf_d1 (.I(ser_d1), .O(O_tmds_data_p[1]), .OB(O_tmds_data_n[1]));

            OSER10 #(.GSREN("false"), .LSREN("true")) u_ser_d2 (
                .Q(ser_d2),
                .D0(tmds_red[0]), .D1(tmds_red[1]), .D2(tmds_red[2]), .D3(tmds_red[3]), .D4(tmds_red[4]),
                .D5(tmds_red[5]), .D6(tmds_red[6]), .D7(tmds_red[7]), .D8(tmds_red[8]), .D9(tmds_red[9]),
                .PCLK(clk_pix), .FCLK(clk_tmds), .RESET(rst_pix)
            );
            TLVDS_OBUF u_obuf_d2 (.I(ser_d2), .O(O_tmds_data_p[2]), .OB(O_tmds_data_n[2]));
        end else begin : gen_sim_tmds
            assign O_tmds_clk_p  = 1'b0;
            assign O_tmds_clk_n  = 1'b1;
            assign O_tmds_data_p = 3'b000;
            assign O_tmds_data_n = 3'b111;
        end
    endgenerate
endmodule
