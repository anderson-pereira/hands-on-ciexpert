//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_aes_key_exp
// Description: Iterative pre-computed AES-128 Key Expansion unit generating
//              and storing the 11 128-bit Round Keys (RoundKey[0..10]) in 10
//              clock cycles (NIST FIPS PUB 197 Section 5.2, Figure 11).
//
// Architectural Choice & Justification (Pre-computed Iterative vs. On-the-Fly):
//   1. Area Efficiency (4 S-Boxes vs. 40 S-Boxes):
//      Instead of a fully unrolled combinational key schedule (which requires
//      40 S-Box instances and creates a 10-stage cascaded critical path), this
//      module reuses a single 32-bit SubWord stage (4x minisoc_aes_sbox) over
//      10 clock cycles.
//   2. Decryption & Multi-Block Efficiency vs. On-the-Fly:
//      In AES-128 Decryption (Inverse Cipher, FIPS-197 Fig. 12), round keys are
//      consumed in reverse order: RoundKey[10] down to RoundKey[0]. A forward
//      on-the-fly generator cannot immediately supply RoundKey[10] without
//      either pre-advancing 10 cycles per block or implementing an additional
//      inverse key schedule datapath. Furthermore, because MiniSoC AES
//      processes 1 to 256 blocks per START command under a constant 128-bit
//      key, computing and caching RoundKey[0..10] once at the start of the
//      operation (in 10 cycles) provides zero-latency random access in both
//      forward (0..10) and reverse (10..0) orders while completely freezing
//      key-schedule switching activity during block processing.
//=============================================================================

module minisoc_aes_key_exp import minisoc_aes_pkg::*; (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         i_start,
    input  logic [127:0] i_key,
    input  logic [3:0]   i_round_idx,
    output logic [127:0] o_round_key,
    output logic         o_busy,
    output logic         o_done,
    output logic         o_valid
);

    //-------------------------------------------------------------------------
    // Storage for 11 Round Keys: rk_mem[0] (Cipher Key) .. rk_mem[10]
    //-------------------------------------------------------------------------
    logic [127:0] rk_mem [0:10];

    logic [3:0]   round_q;
    logic         busy_q;
    logic         done_q;
    logic         valid_q;

    //-------------------------------------------------------------------------
    // Single-Round Combinational Key Schedule Step (FIPS-197 Section 5.2)
    //-------------------------------------------------------------------------
    logic [127:0] prev_rk;
    logic [31:0]  w0, w1, w2, w3;
    logic [31:0]  rot_w3;
    logic [31:0]  sub_w3;
    logic [31:0]  rcon_w;
    logic [31:0]  w0_next, w1_next, w2_next, w3_next;
    logic [127:0] next_rk;

    // Select previous round key rk_mem[round_q - 1] only when busy (operand isolation)
    always_comb begin
        if (busy_q && (round_q >= 4'd1) && (round_q <= 4'd10)) begin
            prev_rk = rk_mem[round_q - 4'd1];
        end else begin
            prev_rk = 128'd0;
        end

        w0     = prev_rk[127:96];
        w1     = prev_rk[95:64];
        w2     = prev_rk[63:32];
        w3     = prev_rk[31:0];

        // RotWord(w3): cyclic left byte shift [a0, a1, a2, a3] -> [a1, a2, a3, a0]
        rot_w3 = {w3[23:0], w3[31:24]};
        rcon_w = {aes_rcon(round_q), 24'h00_0000};

        // Word recurrence: w[i] = w[i-4] ^ temp
        w0_next = w0 ^ sub_w3 ^ rcon_w;
        w1_next = w1 ^ w0_next;
        w2_next = w2 ^ w1_next;
        w3_next = w3 ^ w2_next;

        next_rk = {w0_next, w1_next, w2_next, w3_next};
    end

    // SubWord(RotWord(w3)) using 4 parallel S-Box instances
    for (genvar b = 0; b < 4; b++) begin : g_subword
        minisoc_aes_sbox u_sbox_kw (
            .i_byte (rot_w3[8*b +: 8]),
            .o_byte (sub_w3[8*b +: 8])
        );
    end

    //-------------------------------------------------------------------------
    // Sequential Control & Round Key Register Bank (Synchronous Reset)
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int k = 0; k < 11; k++) begin
                rk_mem[k] <= 128'd0;
            end
            round_q <= 4'd0;
            busy_q  <= 1'b0;
            done_q  <= 1'b0;
            valid_q <= 1'b0;
        end else begin
            done_q <= 1'b0;

            if (i_start) begin
                rk_mem[0] <= i_key;
                round_q   <= 4'd1;
                busy_q    <= 1'b1;
                valid_q   <= 1'b0;
            end else if (busy_q) begin
                rk_mem[round_q] <= next_rk;

                if (round_q == 4'd10) begin
                    busy_q  <= 1'b0;
                    done_q  <= 1'b1;
                    valid_q <= 1'b1;
                end else begin
                    round_q <= round_q + 4'd1;
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // Combinational Read Port for RoundKey[0..10]
    //-------------------------------------------------------------------------
    always_comb begin
        if (i_round_idx <= 4'd10) begin
            o_round_key = rk_mem[i_round_idx];
        end else begin
            o_round_key = 128'd0;
        end
    end

    assign o_busy  = busy_q;
    assign o_done  = done_q;
    assign o_valid = valid_q;

endmodule : minisoc_aes_key_exp

