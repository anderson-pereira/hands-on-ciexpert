//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_aes_dp
// Description: Iterative AES-128 Block Cipher Datapath (1 round per clock
//              cycle) supporting both Forward Cipher (NIST FIPS-197 Fig. 5)
//              and Standard Inverse Cipher (NIST FIPS-197 Fig. 12).
//
// Microarchitecture & Timing:
//   - Cycle 0 (`dp_if.start = 1`):
//       Executes initial Round 0 `AddRoundKey` (`block_in ^ RoundKey[0]` for
//       Cipher, or `block_in ^ RoundKey[10]` for Inverse Cipher) and latches
//       the result into `state_q`, asserting `dp_if.busy = 1`.
//   - Cycles 1..9 (`round_q = 1..9`):
//       * Cipher (`dp_if.decrypt = 0`):
//           SubBytes -> ShiftRows -> MixColumns -> AddRoundKey(RoundKey[r])
//       * Inverse Cipher (`dp_if.decrypt = 1`):
//           InvShiftRows -> InvSubBytes -> AddRoundKey(RoundKey[10-r]) -> InvMixColumns
//   - Cycle 10 (`round_q = 10`):
//       * Cipher (`dp_if.decrypt = 0`):
//           SubBytes -> ShiftRows -> AddRoundKey(RoundKey[10])  (MixColumns bypassed)
//       * Inverse Cipher (`dp_if.decrypt = 1`):
//           InvShiftRows -> InvSubBytes -> AddRoundKey(RoundKey[0]) (InvMixColumns bypassed)
//       Deasserts `dp_if.busy` and asserts `dp_if.done = 1` with the final
//       128-bit processed block held stable on `dp_if.block_out`.
//   - Operand Isolation (Low-Power SAED 32nm QoR):
//       The inactive datapath branch (Cipher during decryption, or Inverse
//       Cipher during encryption, or both when idle) has its input forced to
//       zero, eliminating unnecessary switching across the 16 unused S-Boxes.
//=============================================================================

module minisoc_aes_dp import minisoc_aes_pkg::*; (
    input  logic            clk,
    input  logic            rst_n,
    minisoc_aes_dp_if.dp    dp_if
);

    //-------------------------------------------------------------------------
    // Datapath State & Control Registers
    //-------------------------------------------------------------------------
    aes_block_t state_q;
    aes_round_t round_q;
    logic       decrypt_q;
    logic       busy_q;
    logic       done_q;

    //-------------------------------------------------------------------------
    // Round Key Index Selection (0..10 for Cipher, 10..0 for Inverse Cipher)
    //-------------------------------------------------------------------------
    always_comb begin
        if (dp_if.start) begin
            dp_if.round_key_idx = dp_if.decrypt ? AES_NUM_ROUNDS : 4'd0;
        end else if (busy_q) begin
            dp_if.round_key_idx = decrypt_q ? (AES_NUM_ROUNDS - round_q) : round_q;
        end else begin
            dp_if.round_key_idx = 4'd0;
        end
    end

    //-------------------------------------------------------------------------
    // Initial Round 0 AddRoundKey (active on dp_if.start)
    //-------------------------------------------------------------------------
    aes_block_t init_ark_out;

    minisoc_aes_add_round_key u_ark_init (
        .i_state     (dp_if.block_in),
        .i_round_key (dp_if.round_key),
        .o_state     (init_ark_out)
    );

    //-------------------------------------------------------------------------
    // Forward Cipher Branch (FIPS-197 Section 5.1, Figure 5)
    //   SubBytes -> ShiftRows -> [MixColumns if round < 10] -> AddRoundKey
    //-------------------------------------------------------------------------
    aes_block_t enc_in_state;
    aes_block_t enc_sb_out;
    aes_block_t enc_sr_out;
    aes_block_t enc_mc_out;
    aes_block_t enc_pre_ark;
    aes_block_t enc_round_out;

    // Operand isolation: gate forward S-Boxes when idle or decrypting
    assign enc_in_state = (busy_q && !decrypt_q) ? state_q : '0;

    minisoc_aes_sub_bytes u_sub_bytes (
        .i_state (enc_in_state),
        .o_state (enc_sb_out)
    );

    minisoc_aes_shift_rows u_shift_rows (
        .i_state (enc_sb_out),
        .o_state (enc_sr_out)
    );

    minisoc_aes_mix_columns u_mix_columns (
        .i_state (enc_sr_out),
        .o_state (enc_mc_out)
    );

    assign enc_pre_ark = (round_q == AES_NUM_ROUNDS) ? enc_sr_out : enc_mc_out;

    minisoc_aes_add_round_key u_ark_enc (
        .i_state     (enc_pre_ark),
        .i_round_key (dp_if.round_key),
        .o_state     (enc_round_out)
    );

    //-------------------------------------------------------------------------
    // Inverse Cipher Branch (FIPS-197 Section 5.3, Figure 12)
    //   InvShiftRows -> InvSubBytes -> AddRoundKey -> [InvMixColumns if round < 10]
    //-------------------------------------------------------------------------
    aes_block_t dec_in_state;
    aes_block_t dec_isr_out;
    aes_block_t dec_isb_out;
    aes_block_t dec_ark_out;
    aes_block_t dec_imc_out;
    aes_block_t dec_round_out;

    // Operand isolation: gate inverse S-Boxes when idle or encrypting
    assign dec_in_state = (busy_q && decrypt_q) ? state_q : '0;

    minisoc_aes_inv_shift_rows u_inv_shift_rows (
        .i_state (dec_in_state),
        .o_state (dec_isr_out)
    );

    minisoc_aes_inv_sub_bytes u_inv_sub_bytes (
        .i_state (dec_isr_out),
        .o_state (dec_isb_out)
    );

    minisoc_aes_add_round_key u_ark_dec (
        .i_state     (dec_isb_out),
        .i_round_key (dp_if.round_key),
        .o_state     (dec_ark_out)
    );

    minisoc_aes_inv_mix_columns u_inv_mix_columns (
        .i_state (dec_ark_out),
        .o_state (dec_imc_out)
    );

    assign dec_round_out = (round_q == AES_NUM_ROUNDS) ? dec_ark_out : dec_imc_out;

    //-------------------------------------------------------------------------
    // Sequential State & Round Counter (Synchronous Reset)
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q   <= '0;
            round_q   <= '0;
            decrypt_q <= 1'b0;
            busy_q    <= 1'b0;
            done_q    <= 1'b0;
        end else begin
            done_q <= 1'b0;

            if (dp_if.start) begin
                state_q   <= init_ark_out;
                decrypt_q <= dp_if.decrypt;
                round_q   <= 4'd1;
                busy_q    <= 1'b1;
            end else if (busy_q) begin
                state_q <= decrypt_q ? dec_round_out : enc_round_out;

                if (round_q == AES_NUM_ROUNDS) begin
                    busy_q <= 1'b0;
                    done_q <= 1'b1;
                end else begin
                    round_q <= round_q + 4'd1;
                end
            end
        end
    end

    assign dp_if.block_out = state_q;
    assign dp_if.busy      = busy_q;
    assign dp_if.done      = done_q;

endmodule : minisoc_aes_dp
