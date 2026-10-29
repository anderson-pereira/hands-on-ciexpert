//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Testbench:   tb_minisoc_aes_s2
// Description: Self-checking testbench for Week 2 deliverable:
//              - Exhaustive 256-entry verification of minisoc_aes_sbox and
//                minisoc_aes_inv_sbox against both a 256-entry reference table
//                and an independent GF(2^8) + affine golden model;
//              - Verification of column-major state convention (Byte 0 at
//                [127:120], Byte 15 at [7:0], s[r][c] with r=n%4, c=n/4);
//              - Verification of minisoc_aes_sub_bytes and
//                minisoc_aes_shift_rows across all 10 rounds of NIST FIPS-197
//                Appendix B ("Start of Round" -> "After SubBytes" ->
//                "After ShiftRows");
//              - Optional verification of minisoc_aes_inv_sub_bytes and
//                minisoc_aes_inv_shift_rows as exact inverses and against all
//                10 rounds of NIST FIPS-197 Appendix C.1 Inverse Cipher.
//=============================================================================

`timescale 1ns/1ps

module tb_minisoc_aes_s2;
    import minisoc_aes_pkg::*;

    //-------------------------------------------------------------------------
    // DUT Signals & Combinational Instantiations
    //-------------------------------------------------------------------------
    logic [7:0]   sbox_in;
    wire  [7:0]   sbox_out;
    wire  [7:0]   inv_sbox_out;
    wire  [7:0]   inv_of_sbox_out;

    logic [127:0] state_in;
    wire  [127:0] sub_bytes_out;
    wire  [127:0] shift_rows_chain_out; // ShiftRows(SubBytes(state_in))
    wire  [127:0] shift_rows_direct_out;
    wire  [127:0] inv_sub_of_sub_out;   // InvSubBytes(SubBytes(state_in))
    wire  [127:0] inv_shift_of_shift_out;

    logic [127:0] inv_state_in;
    wire  [127:0] inv_shift_rows_out;
    wire  [127:0] inv_sub_bytes_chain_out; // InvSubBytes(InvShiftRows(inv_state_in))

    minisoc_aes_sbox u_sbox (
        .i_byte (sbox_in),
        .o_byte (sbox_out)
    );

    minisoc_aes_inv_sbox u_inv_sbox (
        .i_byte (sbox_in),
        .o_byte (inv_sbox_out)
    );

    minisoc_aes_inv_sbox u_inv_of_sbox (
        .i_byte (sbox_out),
        .o_byte (inv_of_sbox_out)
    );

    minisoc_aes_sub_bytes u_sub_bytes (
        .i_state (state_in),
        .o_state (sub_bytes_out)
    );

    minisoc_aes_shift_rows u_shift_rows_chain (
        .i_state (sub_bytes_out),
        .o_state (shift_rows_chain_out)
    );

    minisoc_aes_shift_rows u_shift_rows_direct (
        .i_state (state_in),
        .o_state (shift_rows_direct_out)
    );

    minisoc_aes_inv_sub_bytes u_inv_sub_of_sub (
        .i_state (sub_bytes_out),
        .o_state (inv_sub_of_sub_out)
    );

    minisoc_aes_inv_shift_rows u_inv_shift_of_shift (
        .i_state (shift_rows_direct_out),
        .o_state (inv_shift_of_shift_out)
    );

    minisoc_aes_inv_shift_rows u_inv_shift_rows (
        .i_state (inv_state_in),
        .o_state (inv_shift_rows_out)
    );

    minisoc_aes_inv_sub_bytes u_inv_sub_bytes_chain (
        .i_state (inv_shift_rows_out),
        .o_state (inv_sub_bytes_chain_out)
    );

    //-------------------------------------------------------------------------
    // Reference Table (NIST FIPS-197 Figure 7)
    //-------------------------------------------------------------------------
    localparam logic [7:0] REF_SBOX [0:255] = '{
        8'h63, 8'h7c, 8'h77, 8'h7b, 8'hf2, 8'h6b, 8'h6f, 8'hc5, 8'h30, 8'h01, 8'h67, 8'h2b, 8'hfe, 8'hd7, 8'hab, 8'h76,
        8'hca, 8'h82, 8'hc9, 8'h7d, 8'hfa, 8'h59, 8'h47, 8'hf0, 8'had, 8'hd4, 8'ha2, 8'haf, 8'h9c, 8'ha4, 8'h72, 8'hc0,
        8'hb7, 8'hfd, 8'h93, 8'h26, 8'h36, 8'h3f, 8'hf7, 8'hcc, 8'h34, 8'ha5, 8'he5, 8'hf1, 8'h71, 8'hd8, 8'h31, 8'h15,
        8'h04, 8'hc7, 8'h23, 8'hc3, 8'h18, 8'h96, 8'h05, 8'h9a, 8'h07, 8'h12, 8'h80, 8'he2, 8'heb, 8'h27, 8'hb2, 8'h75,
        8'h09, 8'h83, 8'h2c, 8'h1a, 8'h1b, 8'h6e, 8'h5a, 8'ha0, 8'h52, 8'h3b, 8'hd6, 8'hb3, 8'h29, 8'he3, 8'h2f, 8'h84,
        8'h53, 8'hd1, 8'h00, 8'hed, 8'h20, 8'hfc, 8'hb1, 8'h5b, 8'h6a, 8'hcb, 8'hbe, 8'h39, 8'h4a, 8'h4c, 8'h58, 8'hcf,
        8'hd0, 8'hef, 8'haa, 8'hfb, 8'h43, 8'h4d, 8'h33, 8'h85, 8'h45, 8'hf9, 8'h02, 8'h7f, 8'h50, 8'h3c, 8'h9f, 8'ha8,
        8'h51, 8'ha3, 8'h40, 8'h8f, 8'h92, 8'h9d, 8'h38, 8'hf5, 8'hbc, 8'hb6, 8'hda, 8'h21, 8'h10, 8'hff, 8'hf3, 8'hd2,
        8'hcd, 8'h0c, 8'h13, 8'hec, 8'h5f, 8'h97, 8'h44, 8'h17, 8'hc4, 8'ha7, 8'h7e, 8'h3d, 8'h64, 8'h5d, 8'h19, 8'h73,
        8'h60, 8'h81, 8'h4f, 8'hdc, 8'h22, 8'h2a, 8'h90, 8'h88, 8'h46, 8'hee, 8'hb8, 8'h14, 8'hde, 8'h5e, 8'h0b, 8'hdb,
        8'he0, 8'h32, 8'h3a, 8'h0a, 8'h49, 8'h06, 8'h24, 8'h5c, 8'hc2, 8'hd3, 8'hac, 8'h62, 8'h91, 8'h95, 8'he4, 8'h79,
        8'he7, 8'hc8, 8'h37, 8'h6d, 8'h8d, 8'hd5, 8'h4e, 8'ha9, 8'h6c, 8'h56, 8'hf4, 8'hea, 8'h65, 8'h7a, 8'hae, 8'h08,
        8'hba, 8'h78, 8'h25, 8'h2e, 8'h1c, 8'ha6, 8'hb4, 8'hc6, 8'he8, 8'hdd, 8'h74, 8'h1f, 8'h4b, 8'hbd, 8'h8b, 8'h8a,
        8'h70, 8'h3e, 8'hb5, 8'h66, 8'h48, 8'h03, 8'hf6, 8'h0e, 8'h61, 8'h35, 8'h57, 8'hb9, 8'h86, 8'hc1, 8'h1d, 8'h9e,
        8'he1, 8'hf8, 8'h98, 8'h11, 8'h69, 8'hd9, 8'h8e, 8'h94, 8'h9b, 8'h1e, 8'h87, 8'he9, 8'hce, 8'h55, 8'h28, 8'hdf,
        8'h8c, 8'ha1, 8'h89, 8'h0d, 8'hbf, 8'he6, 8'h42, 8'h68, 8'h41, 8'h99, 8'h2d, 8'h0f, 8'hb0, 8'h54, 8'hbb, 8'h16
    };

    //-------------------------------------------------------------------------
    // Independent Mathematical Golden Model in GF(2^8) (m(x) = x^8+x^4+x^3+x+1)
    //-------------------------------------------------------------------------
    function automatic logic [7:0] gf256_mul(input logic [7:0] a, input logic [7:0] b);
        logic [7:0] p;
        logic [7:0] cur_a;
        logic       hi_bit;
        begin
            p     = 8'h00;
            cur_a = a;
            for (int k = 0; k < 8; k++) begin
                if (b[k]) begin
                    p = p ^ cur_a;
                end
                hi_bit = cur_a[7];
                cur_a  = {cur_a[6:0], 1'b0};
                if (hi_bit) begin
                    cur_a = cur_a ^ 8'h1b;
                end
            end
            gf256_mul = p;
        end
    endfunction

    function automatic logic [7:0] gf256_inv(input logic [7:0] a);
        logic [7:0] acc;
        logic [7:0] sq;
        begin
            acc = 8'h01;
            sq  = a;
            for (int k = 0; k < 7; k++) begin
                sq  = gf256_mul(sq, sq);
                acc = gf256_mul(acc, sq);
            end
            gf256_inv = acc;
        end
    endfunction

    function automatic logic [7:0] golden_sbox_alg(input logic [7:0] x);
        logic [7:0] b;
        logic [7:0] out_b;
        begin
            b = gf256_inv(x);
            for (int i = 0; i < 8; i++) begin
                out_b[i] = b[i] ^ b[(i + 4) % 8] ^ b[(i + 5) % 8] ^ b[(i + 6) % 8] ^ b[(i + 7) % 8];
            end
            golden_sbox_alg = out_b ^ 8'h63;
        end
    endfunction

    //-------------------------------------------------------------------------
    // NIST FIPS-197 Appendix B Vectors (All 10 Rounds, Column-Major 128-bit)
    //-------------------------------------------------------------------------
    typedef struct packed {
        logic [127:0] start_of_round;
        logic [127:0] after_sub_bytes;
        logic [127:0] after_shift_rows;
    } round_vec_t;

    localparam round_vec_t APP_B_VECS [1:10] = '{
        // Round 1
        '{128'h193de3be_a0f4e22b_9ac68d2a_e9f84808,
          128'hd42711ae_e0bf98f1_b8b45de5_1e415230,
          128'hd4bf5d30_e0b452ae_b84111f1_1e2798e5},
        // Round 2
        '{128'ha49c7ff2_689f352b_6b5bea43_026a5049,
          128'h49ded289_45db96f1_7f39871a_7702533b,
          128'h49db873b_45395389_7f02d2f1_77de961a},
        // Round 3
        '{128'haa8f5f03_61dde3ef_82d24ad2_6832469a,
          128'hac73cf7b_efc111df_13b5d6b5_45235ab8,
          128'hacc1d6b8_efb55a7b_1323cfdf_457311b5},
        // Round 4
        '{128'h486c4eee_671d9d0d_4de3b138_d65f58e7,
          128'h52502f28_85a45ed7_e311c807_f6cf6a94,
          128'h52a4c894_85116a28_e3cf2fd7_f6505e07},
        // Round 5
        '{128'he0927fe8_c86363c0_d9b13550_85b8be01,
          128'he14fd29b_e8fbfbba_35c89653_976cae7c,
          128'he1fb967c_e8c8ae9b_356cd2ba_974ffb53},
        // Round 6
        '{128'hf1006f55_c1924cef_7cc88b32_5db5d50c,
          128'ha163a8fc_784f29df_10e83d23_4cd503fe,
          128'ha14f3dfe_78e803fc_10d5a8df_4c632923},
        // Round 7
        '{128'h260e2e17_3d41b77d_e86472a9_fdd28b25,
          128'hf7ab31f0_2783a9ff_9b4340d3_54b53d3f,
          128'hf783403f_27433df0_9bb531ff_54aba9d3},
        // Round 8
        '{128'h5a4142b1_1949dc1f_a3e01965_7a8c040c,
          128'hbe832cc8_d43b86c0_0ae1d44d_da64f2fe,
          128'hbe3bd4fe_d4e1f2c8_0a642cc0_da83864d},
        // Round 9
        '{128'hea835cf0_0445332d_655d98ad_8596b0c5,
          128'h87ec4a8c_f26ec3d8_4d4c4695_9790e7a6,
          128'h876e46a6_f24ce78c_4d904ad8_97ecc395},
        // Round 10
        '{128'heb40f21e_592e3884_8ba113e7_1bc342d2,
          128'he9098972_cb31075f_3d327d94_af2e2cb5,
          128'he9317db5_cb322c72_3d2e895f_af090794}
    };

    //-------------------------------------------------------------------------
    // NIST FIPS-197 Appendix C.1 Inverse Cipher Vectors (Rounds 1..10)
    //-------------------------------------------------------------------------
    typedef struct packed {
        logic [127:0] istart;
        logic [127:0] is_row;
        logic [127:0] is_box;
    } inv_round_vec_t;

    localparam inv_round_vec_t APP_C1_INV_VECS [1:10] = '{
        '{128'h7ad5fda7_89ef4e27_2bca100b_3d9ff59f,
          128'h7a9f1027_89d5f50b_2beffd9f_3dca4ea7,
          128'hbd6e7c3d_f2b5779e_0b61216e_8b10b689},
        '{128'h54d990a1_6ba09ab5_96bbf40e_a111702f,
          128'h5411f4b5_6bd9700e_96a0902f_a1bb9aa1,
          128'hfde3bad2_05e5d0d7_3547964e_f1fe37f1},
        '{128'h3e1c22c0_b6fcbf76_8da85067_f6170495,
          128'h3e175076_b61c0467_8dfc2295_f6a8bfc0,
          128'hd1876c0f_79c4300a_b45594ad_d66ff41f},
        '{128'hb458124c_68b68a01_4b99f82e_5f15554c,
          128'hb415f801_6858552e_4bb6124c_5f998a4c,
          128'hc62fe109_f75eedc3_cc79395d_84f9cf5d},
        '{128'he8dab690_1477d465_3ff7f5e2_e747dd4f,
          128'he847f565_14dadde2_3f77b64f_e7f7d490,
          128'hc81677bc_9b7ac93b_25027992_b0261996},
        '{128'h36339d50_f9b53926_9f2c092d_c4406d23,
          128'h36400926_f9336d2d_9fb59d23_c42c3950,
          128'h24724023_6966b3fa_6ed27532_88425b6c},
        '{128'h2d6d7ef0_3f33e334_093602dd_5bfb12c7,
          128'h2dfb0234_3f6d12dd_09337ec7_5b36e3f0,
          128'hfa636a28_25b339c9_40668a31_57244d17},
        '{128'h3bd92268_fc74fb73_5767cbe0_c0590e2d,
          128'h3b59cb73_fcd90ee0_5774222d_c067fb68,
          128'h4915598f_55e5d7a0_daca94fa_1f0a63f7},
        '{128'ha7be1a69_97ad739b_d8c9ca45_1f618b61,
          128'ha761ca9b_97be8b45_d8ad1a61_1fc97369,
          128'h89d810e8_855ace68_2d1843d8_cb128fe4},
        '{128'h6353e08c_0960e104_cd70b751_bacad0e7,
          128'h63cab704_0953d051_cd60e0e7_ba70e18c,
          128'h00102030_40506070_8090a0b0_c0d0e0f0}
    };

    //-------------------------------------------------------------------------
    // Main Self-Checking Verification Sequence
    //-------------------------------------------------------------------------
    logic [7:0]   alg_exp;
    logic [127:0] prng_state;

    initial begin
        sbox_in      = 8'h00;
        state_in     = 128'd0;
        inv_state_in = 128'd0;
        #1 begin end

        //=====================================================================
        // 1. Exhaustive 256-Entry S-box & InvS-box Verification
        //=====================================================================
        for (int idx = 0; idx < 256; idx++) begin
            sbox_in = idx[7:0];
            #1 alg_exp = golden_sbox_alg(idx[7:0]);

            if (sbox_out !== REF_SBOX[idx]) begin
                $fatal(1, "[TB ERROR] S-box table mismatch at 0x%02h: got 0x%02h, expected 0x%02h",
                       idx[7:0], sbox_out, REF_SBOX[idx]);
            end
            if (sbox_out !== alg_exp) begin
                $fatal(1, "[TB ERROR] S-box GF(2^8) mismatch at 0x%02h: got 0x%02h, alg 0x%02h",
                       idx[7:0], sbox_out, alg_exp);
            end
            if (inv_of_sbox_out !== idx[7:0]) begin
                $fatal(1, "[TB ERROR] InvSbox(Sbox(0x%02h)) = 0x%02h != 0x%02h",
                       idx[7:0], inv_of_sbox_out, idx[7:0]);
            end
            if (REF_SBOX[inv_sbox_out] !== idx[7:0]) begin
                $fatal(1, "[TB ERROR] Sbox(InvSbox(0x%02h)) = 0x%02h != 0x%02h",
                       idx[7:0], REF_SBOX[inv_sbox_out], idx[7:0]);
            end
        end

        // Explicit spot checks from Week 2 specification
        sbox_in = 8'h00;
        #1 if (sbox_out !== 8'h63) $fatal(1, "[TB ERROR] sbox(8'h00) != 8'h63");
        $display("     -> sbox(8'h00) = 8'h%02h (expected 8'h63)", sbox_out);
        sbox_in = 8'h53;
        #1 if (sbox_out !== 8'hed) $fatal(1, "[TB ERROR] sbox(8'h53) != 8'hed");
        $display("     -> sbox(8'h53) = 8'h%02h (expected 8'hed)", sbox_out);
        $display("[TB] 1. S-box & InvS-box verified across all 256 inputs (Table + GF(2^8) + Bijection)!");

        //=====================================================================
        // 2. State Bit-Ordering Convention Check (FIPS-197 Sec 3.4 & Block Guide)
        //=====================================================================
        state_in = APP_B_VECS[1].start_of_round;
        #1 begin end
        if (state_in[127:96] !== 32'h193d_e3be || state_in[127:120] !== 8'h19 || state_in[7:0] !== 8'h08) begin
            $fatal(1, "[TB ERROR] State slice convention mismatch!");
        end
        for (int n = 0; n < 16; n++) begin
            if (aes_get_byte(state_in, 2'(n % 4), 2'(n / 4)) !== state_in[127 - 8*n -: 8]) begin
                $fatal(1, "[TB ERROR] aes_get_byte(r=%0d, c=%0d) mismatch at byte %0d!", n % 4, n / 4, n);
            end
        end
        $display("[TB] 2. Column-major 128-bit state convention (Byte 0=[127:120], s[r][c]) verified!");

        //=====================================================================
        // 3. NIST FIPS-197 Appendix B: Rounds 1..10 (SubBytes & ShiftRows)
        //=====================================================================
        for (int rnd = 1; rnd <= 10; rnd++) begin
            state_in = APP_B_VECS[rnd].start_of_round;
            #1 begin end

            if (sub_bytes_out !== APP_B_VECS[rnd].after_sub_bytes) begin
                $fatal(1, "[TB ERROR] Appendix B Round %0d SubBytes mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                       rnd, sub_bytes_out, APP_B_VECS[rnd].after_sub_bytes);
            end
            if (shift_rows_chain_out !== APP_B_VECS[rnd].after_shift_rows) begin
                $fatal(1, "[TB ERROR] Appendix B Round %0d ShiftRows mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                       rnd, shift_rows_chain_out, APP_B_VECS[rnd].after_shift_rows);
            end
            if (inv_sub_of_sub_out !== state_in) begin
                $fatal(1, "[TB ERROR] Round %0d InvSubBytes(SubBytes(x)) != x!", rnd);
            end
            if (inv_shift_of_shift_out !== state_in) begin
                $fatal(1, "[TB ERROR] Round %0d InvShiftRows(ShiftRows(x)) != x!", rnd);
            end
            if (rnd == 1 || rnd == 10) begin
                $display("     [Round %2d] start of round  : %032h", rnd, state_in);
                $display("     [Round %2d] after SubBytes  : %032h", rnd, sub_bytes_out);
                $display("     [Round %2d] after ShiftRows : %032h", rnd, shift_rows_chain_out);
            end
        end
        $display("[TB] 3. NIST FIPS-197 Appendix B Rounds 1..10 (SubBytes -> ShiftRows) verified!");

        //=====================================================================
        // 4. Optional Inverse Transformations: Appendix C.1 + 256 Random Blocks
        //=====================================================================
        for (int rnd = 1; rnd <= 10; rnd++) begin
            inv_state_in = APP_C1_INV_VECS[rnd].istart;
            #1 begin end

            if (inv_shift_rows_out !== APP_C1_INV_VECS[rnd].is_row) begin
                $fatal(1, "[TB ERROR] Appendix C.1 Round %0d InvShiftRows mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                       rnd, inv_shift_rows_out, APP_C1_INV_VECS[rnd].is_row);
            end
            if (inv_sub_bytes_chain_out !== APP_C1_INV_VECS[rnd].is_box) begin
                $fatal(1, "[TB ERROR] Appendix C.1 Round %0d InvSubBytes mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                       rnd, inv_sub_bytes_chain_out, APP_C1_INV_VECS[rnd].is_box);
            end
        end

        prng_state = 128'h01234567_89ABCDEF_FEDCBA98_76543210;
        for (int t = 0; t < 256; t++) begin
            prng_state   = {prng_state[126:0], prng_state[127] ^ prng_state[125] ^ prng_state[100] ^ prng_state[98]};
            state_in     = prng_state;
            inv_state_in = shift_rows_chain_out;
            #1 inv_state_in = shift_rows_chain_out;
            #1 begin end

            if (inv_sub_of_sub_out !== state_in) begin
                $fatal(1, "[TB ERROR] Random trial %0d InvSubBytes(SubBytes(x)) != x!", t);
            end
            if (inv_shift_of_shift_out !== state_in) begin
                $fatal(1, "[TB ERROR] Random trial %0d InvShiftRows(ShiftRows(x)) != x!", t);
            end
            if (inv_sub_bytes_chain_out !== state_in) begin
                $fatal(1, "[TB ERROR] Random trial %0d InvSubBytes(InvShiftRows(ShiftRows(SubBytes(x)))) != x!", t);
            end
        end
        $display("[TB] 4. InvShiftRows & InvSubBytes verified (Appendix C.1 Rounds 1..10 + 256 random blocks)!");

        $display("===================================================================");
        $display("PASS: MiniSoC AES Week 2 (S-box, SubBytes, ShiftRows & Inverses)");
        $display("      passed 100%% of exhaustive and NIST FIPS-197 checks!");
        $display("===================================================================");
        $finish;
    end

endmodule : tb_minisoc_aes_s2
