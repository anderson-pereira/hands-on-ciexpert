//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_pll_mock
// Description: Synthesizable RTL PLL integration model aligned with Section 4.1
//              and REQ-PLL-01 of DV_BlockGuide_MiniSoCAES_v1.0.0:
//              - Reference input clock: 2 GHz (i_clk).
//              - Supports dividers /1 (00), /2 (01), /4 (10), /8 (11).
//              - When disabled (i_enable == 0), o_locked = 0 and o_sys_clk = 0.
//              - Upon enable (or divider change), waits a pseudo-random number
//                of reference cycles (LFSR) before asserting o_locked and
//                releasing glitch-free o_sys_clk.
//=============================================================================

module minisoc_pll_mock (
    input  logic       i_clk,
    input  logic       i_rst_n,
    input  logic       i_enable,
    input  logic [1:0] i_div_sel,
    output logic       o_sys_clk,
    output logic       o_locked
);

    logic [7:0] lfsr_q;
    logic [7:0] lock_cnt;
    logic [7:0] lock_target;
    logic [1:0] div_sel_q;
    logic [2:0] div_cnt;
    logic       div_clk_mux;
    logic       en_div1;
    logic       en_divn;

    //-------------------------------------------------------------------------
    // 8-bit Maximal-Length LFSR (x^8 + x^6 + x^5 + x^4 + 1) for Lock Delay
    //-------------------------------------------------------------------------
    wire lfsr_fb = lfsr_q[7] ^ lfsr_q[5] ^ lfsr_q[4] ^ lfsr_q[3];

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            lfsr_q      <= 8'hA5;
            lock_cnt    <= 8'd0;
            lock_target <= 8'd24;
            div_sel_q   <= 2'b00;
            o_locked    <= 1'b0;
        end else begin
            lfsr_q <= {lfsr_q[6:0], lfsr_fb};

            if (!i_enable) begin
                o_locked    <= 1'b0;
                lock_cnt    <= 8'd0;
                lock_target <= {2'b00, lfsr_q[5:0]} + 8'd16; // 16..79 ref cycles
                div_sel_q   <= i_div_sel;
            end else if (i_div_sel != div_sel_q) begin
                // Re-acquire lock cleanly if divider changes while enabled
                o_locked    <= 1'b0;
                lock_cnt    <= 8'd0;
                lock_target <= {2'b00, lfsr_q[5:0]} + 8'd16;
                div_sel_q   <= i_div_sel;
            end else if (lock_cnt < lock_target) begin
                lock_cnt <= lock_cnt + 8'd1;
                o_locked <= 1'b0;
            end else begin
                o_locked <= 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Synchronous Clock Divider (/2, /4, /8)
    //-------------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (!i_rst_n || !o_locked) begin
            div_cnt <= 3'd0;
        end else begin
            div_cnt <= div_cnt + 3'd1;
        end
    end

    always_comb begin
        case (div_sel_q)
            2'b01:   div_clk_mux = div_cnt[0]; // /2 (1.000 GHz)
            2'b10:   div_clk_mux = div_cnt[1]; // /4 (  500 MHz)
            2'b11:   div_clk_mux = div_cnt[2]; // /8 (  250 MHz)
            default: div_clk_mux = 1'b0;
        endcase
    end

    //-------------------------------------------------------------------------
    // Glitch-Free Clock Release Post-Lock (Updated synchronously on negedge i_clk)
    //-------------------------------------------------------------------------
    always_ff @(negedge i_clk) begin
        if (!i_rst_n) begin
            en_div1 <= 1'b0;
            en_divn <= 1'b0;
        end else begin
            en_div1 <= o_locked;
            if (!div_clk_mux) begin
                en_divn <= o_locked;
            end
        end
    end

    assign o_sys_clk = (div_sel_q == 2'b00) ? (i_clk & en_div1)
                                            : (div_clk_mux & en_divn);

endmodule : minisoc_pll_mock

