`timescale 1ns/1ps

// Minimal 115200 bps 8N1 UART transceiver for 27 MHz Tang Nano 20K clock.
module td_uart #(
    parameter integer CLK_FREQ = 27000000,
    parameter integer BAUD     = 115200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg        tx,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx_busy,
    output reg        rx_valid,
    output reg  [7:0] rx_data
);
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD;
    localparam integer HALF_BIT     = CLKS_PER_BIT / 2;

    // RX synchronizer
    reg rx_s0 = 1'b1;
    reg rx_s1 = 1'b1;
    reg rx_prev = 1'b1;
    always @(posedge clk) begin
        rx_s0 <= rx;
        rx_s1 <= rx_s0;
        rx_prev <= rx_s1;
    end

    // RX FSM
    localparam [1:0] RX_IDLE  = 2'd0;
    localparam [1:0] RX_START = 2'd1;
    localparam [1:0] RX_DATA  = 2'd2;
    localparam [1:0] RX_STOP  = 2'd3;

    reg [1:0] rx_state = RX_IDLE;
    reg [9:0] rx_cnt   = 10'd0;
    reg [2:0] rx_bit   = 3'd0;
    reg [7:0] rx_shift = 8'd0;

    always @(posedge clk) begin
        rx_valid <= 1'b0;
        if (rst) begin
            rx_state <= RX_IDLE;
            rx_cnt   <= 10'd0;
            rx_bit   <= 3'd0;
            rx_shift <= 8'd0;
            rx_data  <= 8'd0;
        end else begin
            case (rx_state)
                RX_IDLE: begin
                    if (rx_prev == 1'b1 && rx_s1 == 1'b0) begin
                        rx_state <= RX_START;
                        rx_cnt   <= HALF_BIT[9:0];
                    end
                end
                RX_START: begin
                    if (rx_cnt == 10'd0) begin
                        if (rx_s1 == 1'b0) begin
                            rx_state <= RX_DATA;
                            rx_cnt   <= CLKS_PER_BIT[9:0] - 10'd1;
                            rx_bit   <= 3'd0;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_cnt <= rx_cnt - 10'd1;
                    end
                end
                RX_DATA: begin
                    if (rx_cnt == 10'd0) begin
                        rx_shift[rx_bit] <= rx_s1;
                        rx_cnt <= CLKS_PER_BIT[9:0] - 10'd1;
                        if (rx_bit == 3'd7)
                            rx_state <= RX_STOP;
                        else
                            rx_bit <= rx_bit + 3'd1;
                    end else begin
                        rx_cnt <= rx_cnt - 10'd1;
                    end
                end
                RX_STOP: begin
                    if (rx_cnt == 10'd0) begin
                        if (rx_s1 == 1'b1) begin
                            rx_data  <= rx_shift;
                            rx_valid <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_cnt <= rx_cnt - 10'd1;
                    end
                end
            endcase
        end
    end

    // TX FSM
    reg [9:0] tx_shift = 10'h3FF;
    reg [9:0] tx_cnt   = 10'd0;
    reg [3:0] tx_bits  = 4'd0;

    always @(posedge clk) begin
        if (rst) begin
            tx       <= 1'b1;
            tx_busy  <= 1'b0;
            tx_shift <= 10'h3FF;
            tx_cnt   <= 10'd0;
            tx_bits  <= 4'd0;
        end else if (!tx_busy) begin
            tx <= 1'b1;
            if (tx_start) begin
                tx_shift <= {1'b1, tx_data, 1'b0};
                tx_busy  <= 1'b1;
                tx_cnt   <= CLKS_PER_BIT[9:0] - 10'd1;
                tx_bits  <= 4'd10;
            end
        end else begin
            tx <= tx_shift[0];
            if (tx_cnt == 10'd0) begin
                tx_cnt   <= CLKS_PER_BIT[9:0] - 10'd1;
                tx_shift <= {1'b1, tx_shift[9:1]};
                if (tx_bits == 4'd1) begin
                    tx_busy <= 1'b0;
                    tx_bits <= 4'd0;
                end else begin
                    tx_bits <= tx_bits - 4'd1;
                end
            end else begin
                tx_cnt <= tx_cnt - 10'd1;
            end
        end
    end
endmodule
