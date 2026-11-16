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
//      operation (10 cycles) provides zero-latency random access in both
//      forward (0..10) and reverse (10..0) orders while completely freezing
//      key-schedule switching activity during block processing.
//=============================================================================

module minisoc_aes_key_exp import minisoc_aes_pkg::*; (
    input  logic                   clk,
    input  logic                   rst_n,
    minisoc_aes_key_exp_if.key_exp ke_if
);

    //-------------------------------------------------------------------------
    // Storage for 11 Round Keys: rk_mem[0] (Cipher Key) .. rk_mem[10]
    //-------------------------------------------------------------------------
    aes_key_t   rk_mem [0:AES_NUM_RKEYS-1];

    aes_round_t round_q;
    logic       busy_q;
    logic       done_q;
    logic       valid_q;

    //-------------------------------------------------------------------------
    // Single-Round Combinational Key Schedule Step (FIPS-197 Section 5.2)
    // Uses structured packed types (aes_words128_t, aes_word_bytes_t) to avoid
    // manual bit-slice indexing.
    //-------------------------------------------------------------------------
    aes_key_t        prev_rk;
    aes_words128_t   prev_rk_w;
    aes_words128_t   next_rk_w;
    aes_word_bytes_t w3_bytes;
    aes_word_bytes_t rot_w3_bytes;
    aes_word_bytes_t sub_w3_bytes;
    aes_word_t       rcon_w;
    aes_key_t        next_rk;

    // Select previous round key rk_mem[round_q - 1] only when busy (operand isolation)
    always_comb begin
        if (busy_q && (round_q >= 4'd1) && (round_q <= AES_NUM_ROUNDS)) begin
            prev_rk = rk_mem[round_q - 4'd1];
        end else begin
            prev_rk = '0;
        end

        prev_rk_w = aes_words128_t'(prev_rk);
        w3_bytes  = aes_word_bytes_t'(prev_rk_w[3]);

        // RotWord(w3): cyclic left byte shift [a0, a1, a2, a3] -> [a1, a2, a3, a0]
        rot_w3_bytes = {w3_bytes[1], w3_bytes[2], w3_bytes[3], w3_bytes[0]};
        rcon_w       = {aes_rcon(round_q), 24'h00_0000};

        // Word recurrence: w[i] = w[i-4] ^ temp
        next_rk_w[0] = prev_rk_w[0] ^ aes_word_t'(sub_w3_bytes) ^ rcon_w;
        next_rk_w[1] = prev_rk_w[1] ^ next_rk_w[0];
        next_rk_w[2] = prev_rk_w[2] ^ next_rk_w[1];
        next_rk_w[3] = prev_rk_w[3] ^ next_rk_w[2];

        next_rk = aes_key_t'(next_rk_w);
    end

    // SubWord(RotWord(w3)) using 4 parallel S-Box instances
    for (genvar b = 0; b < 4; b++) begin : g_subword
        minisoc_aes_sbox u_sbox_kw (
            .i_byte (rot_w3_bytes[b]),
            .o_byte (sub_w3_bytes[b])
        );
    end

    //-------------------------------------------------------------------------
    // Sequential Control & Round Key Register Bank (Synchronous Reset)
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int k = 0; k < AES_NUM_RKEYS; k++) begin
                rk_mem[k] <= '0;
            end
            round_q <= '0;
            busy_q  <= 1'b0;
            done_q  <= 1'b0;
            valid_q <= 1'b0;
        end else begin
            done_q <= 1'b0;

            if (ke_if.start) begin
                rk_mem[0] <= ke_if.key;
                round_q   <= 4'd1;
                busy_q    <= 1'b1;
                valid_q   <= 1'b0;
            end else if (busy_q) begin
                rk_mem[round_q] <= next_rk;

                if (round_q == AES_NUM_ROUNDS) begin
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
        if (ke_if.round_idx <= AES_NUM_ROUNDS) begin
            ke_if.round_key = rk_mem[ke_if.round_idx];
        end else begin
            ke_if.round_key = '0;
        end
    end

    assign ke_if.busy  = busy_q;
    assign ke_if.done  = done_q;
    assign ke_if.valid = valid_q;

endmodule : minisoc_aes_key_exp
