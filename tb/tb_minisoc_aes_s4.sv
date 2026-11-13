//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Testbench:   tb_minisoc_aes_s4
// Description: Self-checking testbench for Week 4 deliverable:
//              - minisoc_aes_key_exp: 128-bit Key Expansion (11 Round Keys)
//              - minisoc_aes_dp: 128-bit Iterative AES Datapath (Cipher &
//                Inverse Cipher, 1 round/cycle)
//              - Verification against:
//                  1. NIST FIPS-197 Appendix A.1 / Appendix B (Key Schedule,
//                     Cipher & Inverse Cipher, including per-round states)
//                  2. NIST FIPS-197 Appendix C.1 (Key Schedule, Cipher &
//                     Inverse Cipher, including per-round states)
//                  3. NIST SP 800-38A Section F.1.1 (Multi-block ECB-AES128
//                     vectors in both directions reusing pre-computed keys)
//                  4. Random key/block round-trip bijection D_K(E_K(P)) == P
//=============================================================================

`timescale 1ns/1ps

module tb_minisoc_aes_s4;
    import minisoc_aes_pkg::*;

    //-------------------------------------------------------------------------
    // Clock & Reset Generation (500 MHz / 2.0 ns period)
    //-------------------------------------------------------------------------
    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    always #1.0 clk = ~clk;

    //-------------------------------------------------------------------------
    // DUT Signals & Interconnect between minisoc_aes_key_exp and minisoc_aes_dp
    //-------------------------------------------------------------------------
    logic         ke_start;
    logic [127:0] ke_key;
    logic [3:0]   ke_round_idx;
    wire  [127:0] ke_round_key;
    wire          ke_busy;
    wire          ke_done;
    wire          ke_valid;

    logic         dp_start;
    logic         dp_decrypt;
    logic [127:0] dp_block_in;
    wire  [3:0]   dp_round_key_idx;
    wire  [127:0] dp_block_out;
    wire          dp_busy;
    wire          dp_done;

    // Allow TB to override round key index during standalone key schedule readback
    logic         tb_override_rk_idx;
    logic [3:0]   tb_rk_idx;

    assign ke_round_idx = tb_override_rk_idx ? tb_rk_idx : dp_round_key_idx;

    minisoc_aes_key_exp u_key_exp (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_start     (ke_start),
        .i_key       (ke_key),
        .i_round_idx (ke_round_idx),
        .o_round_key (ke_round_key),
        .o_busy      (ke_busy),
        .o_done      (ke_done),
        .o_valid     (ke_valid)
    );

    minisoc_aes_dp u_dp (
        .clk             (clk),
        .rst_n           (rst_n),
        .i_start         (dp_start),
        .i_decrypt       (dp_decrypt),
        .i_block         (dp_block_in),
        .i_round_key     (ke_round_key),
        .o_round_key_idx (dp_round_key_idx),
        .o_block         (dp_block_out),
        .o_busy          (dp_busy),
        .o_done          (dp_done)
    );

    //-------------------------------------------------------------------------
    // Reference Vectors — NIST FIPS-197 Appendix B & Appendix A.1
    //-------------------------------------------------------------------------
    localparam logic [127:0] APP_B_KEY = 128'h2b7e1516_28aed2a6_abf71588_09cf4f3c;
    localparam logic [127:0] APP_B_PT  = 128'h3243f6a8_885a308d_313198a2_e0370734;
    localparam logic [127:0] APP_B_CT  = 128'h3925841d_02dc09fb_dc118597_196a0b32;

    localparam logic [127:0] APP_B_RK [0:10] = '{
        128'h2b7e1516_28aed2a6_abf71588_09cf4f3c, // RoundKey[0]
        128'ha0fafe17_88542cb1_23a33939_2a6c7605, // RoundKey[1]
        128'hf2c295f2_7a96b943_5935807a_7359f67f, // RoundKey[2]
        128'h3d80477d_4716fe3e_1e237e44_6d7a883b, // RoundKey[3]
        128'hef44a541_a8525b7f_b671253b_db0bad00, // RoundKey[4]
        128'hd4d1c6f8_7c839d87_caf2b8bc_11f915bc, // RoundKey[5]
        128'h6d88a37a_110b3efd_dbf98641_ca0093fd, // RoundKey[6]
        128'h4e54f70e_5f5fc9f3_84a64fb2_4ea6dc4f, // RoundKey[7]
        128'head27321_b58dbad2_312bf560_7f8d292f, // RoundKey[8]
        128'hac7766f3_19fadc21_28d12941_575c006e, // RoundKey[9]
        128'hd014f9a8_c9ee2589_e13f0cc8_b6630ca6  // RoundKey[10]
    };

    // State after AddRoundKey at end of Round 0..10 (FIPS-197 Appendix B)
    localparam logic [127:0] APP_B_ENC_STATE [0:10] = '{
        128'h193de3be_a0f4e22b_9ac68d2a_e9f84808, // After Round 0 AddRoundKey
        128'ha49c7ff2_689f352b_6b5bea43_026a5049, // After Round 1
        128'haa8f5f03_61dde3ef_82d24ad2_6832469a, // After Round 2
        128'h486c4eee_671d9d0d_4de3b138_d65f58e7, // After Round 3
        128'he0927fe8_c86363c0_d9b13550_85b8be01, // After Round 4
        128'hf1006f55_c1924cef_7cc88b32_5db5d50c, // After Round 5
        128'h260e2e17_3d41b77d_e86472a9_fdd28b25, // After Round 6
        128'h5a4142b1_1949dc1f_a3e01965_7a8c040c, // After Round 7
        128'hea835cf0_0445332d_655d98ad_8596b0c5, // After Round 8
        128'heb40f21e_592e3884_8ba113e7_1bc342d2, // After Round 9
        128'h3925841d_02dc09fb_dc118597_196a0b32  // After Round 10 (Ciphertext)
    };

    //-------------------------------------------------------------------------
    // Reference Vectors — NIST FIPS-197 Appendix C.1 (AES-128)
    //-------------------------------------------------------------------------
    localparam logic [127:0] APP_C1_KEY = 128'h00010203_04050607_08090a0b_0c0d0e0f;
    localparam logic [127:0] APP_C1_PT  = 128'h00112233_44556677_8899aabb_ccddeeff;
    localparam logic [127:0] APP_C1_CT  = 128'h69c4e0d8_6a7b0430_d8cdb780_70b4c55a;

    localparam logic [127:0] APP_C1_RK [0:10] = '{
        128'h00010203_04050607_08090a0b_0c0d0e0f, // RoundKey[0]
        128'hd6aa74fd_d2af72fa_daa678f1_d6ab76fe, // RoundKey[1]
        128'hb692cf0b_643dbdf1_be9bc500_6830b3fe, // RoundKey[2]
        128'hb6ff744e_d2c2c9bf_6c590cbf_0469bf41, // RoundKey[3]
        128'h47f7f7bc_95353e03_f96c32bc_fd058dfd, // RoundKey[4]
        128'h3caaa3e8_a99f9deb_50f3af57_adf622aa, // RoundKey[5]
        128'h5e390f7d_f7a69296_a7553dc1_0aa31f6b, // RoundKey[6]
        128'h14f9701a_e35fe28c_440adf4d_4ea9c026, // RoundKey[7]
        128'h47438735_a41c65b9_e016baf4_aebf7ad2, // RoundKey[8]
        128'h549932d1_f0855768_1093ed9c_be2c974e, // RoundKey[9]
        128'h13111d7f_e3944a17_f307a78b_4d2b30c5  // RoundKey[10]
    };

    // Cipher state at end of Round 0..10 (FIPS-197 Appendix C.1, pp. 35-36)
    localparam logic [127:0] APP_C1_ENC_STATE [0:10] = '{
        128'h00102030_40506070_8090a0b0_c0d0e0f0, // After Round 0
        128'h89d810e8_855ace68_2d1843d8_cb128fe4, // After Round 1
        128'h4915598f_55e5d7a0_daca94fa_1f0a63f7, // After Round 2
        128'hfa636a28_25b339c9_40668a31_57244d17, // After Round 3
        128'h24724023_6966b3fa_6ed27532_88425b6c, // After Round 4
        128'hc81677bc_9b7ac93b_25027992_b0261996, // After Round 5
        128'hc62fe109_f75eedc3_cc79395d_84f9cf5d, // After Round 6
        128'hd1876c0f_79c4300a_b45594ad_d66ff41f, // After Round 7
        128'hfde3bad2_05e5d0d7_3547964e_f1fe37f1, // After Round 8
        128'hbd6e7c3d_f2b5779e_0b61216e_8b10b689, // After Round 9
        128'h69c4e0d8_6a7b0430_d8cdb780_70b4c55a  // After Round 10 (Ciphertext)
    };

    // Inverse Cipher state at end of Round 0..10 (FIPS-197 Appendix C.1, pp. 36-37)
    localparam logic [127:0] APP_C1_DEC_STATE [0:10] = '{
        128'h7ad5fda7_89ef4e27_2bca100b_3d9ff59f, // After InvRound 0 (ct ^ RK[10])
        128'h54d990a1_6ba09ab5_96bbf40e_a111702f, // After InvRound 1
        128'h3e1c22c0_b6fcbf76_8da85067_f6170495, // After InvRound 2
        128'hb458124c_68b68a01_4b99f82e_5f15554c, // After InvRound 3
        128'he8dab690_1477d465_3ff7f5e2_e747dd4f, // After InvRound 4
        128'h36339d50_f9b53926_9f2c092d_c4406d23, // After InvRound 5
        128'h2d6d7ef0_3f33e334_093602dd_5bfb12c7, // After InvRound 6
        128'h3bd92268_fc74fb73_5767cbe0_c0590e2d, // After InvRound 7
        128'ha7be1a69_97ad739b_d8c9ca45_1f618b61, // After InvRound 8
        128'h6353e08c_0960e104_cd70b751_bacad0e7, // After InvRound 9
        128'h00112233_44556677_8899aabb_ccddeeff  // After InvRound 10 (Plaintext)
    };

    //-------------------------------------------------------------------------
    // NIST SP 800-38A Section F.1.1 ECB-AES128 Multi-Block Vectors
    //-------------------------------------------------------------------------
    localparam logic [127:0] SP800_PT [0:3] = '{
        128'h6bc1bee2_2e409f96_e93d7e11_7393172a,
        128'hae2d8a57_1e03ac9c_9eb76fac_45af8e51,
        128'h30c81c46_a35ce411_e5fbc119_1a0a52ef,
        128'hf69f2445_df4f9b17_ad2b417b_e66c3710
    };

    localparam logic [127:0] SP800_CT [0:3] = '{
        128'h3ad77bb4_0d7a3660_a89ecaf3_2466ef97,
        128'hf5d3d585_03b9699d_e785895a_96fdbaaf,
        128'h43b1cd7f_598ece23_881b00e3_ed030688,
        128'h7b0c785e_27e8ad3f_82232071_04725dd4
    };

    //-------------------------------------------------------------------------
    // Helper Tasks
    //-------------------------------------------------------------------------
    int total_checks;
    int error_count;

    task automatic check_128(
        input string        label,
        input logic [127:0] got,
        input logic [127:0] expected
    );
        begin
            total_checks++;
            if (got !== expected) begin
                $display("[ERROR] %s: got=%032h expected=%032h", label, got, expected);
                error_count++;
            end
        end
    endtask

    task automatic run_key_expansion(input logic [127:0] key_val);
        int cyc;
        begin
            @(negedge clk) begin
                ke_key   = key_val;
                ke_start = 1'b1;
            end
            @(negedge clk) begin
                ke_start = 1'b0;
            end

            cyc = 0;
            while (!ke_done && (cyc < 20)) begin
                @(posedge clk) begin end
                #0.1 cyc++;
            end

            total_checks++;
            if (!ke_done || !ke_valid || ke_busy || (cyc != 10)) begin
                $display("[ERROR] KeyExpansion timing mismatch: cyc=%0d done=%0b valid=%0b busy=%0b",
                         cyc, ke_done, ke_valid, ke_busy);
                error_count++;
            end
        end
    endtask

    task automatic run_dp_block(
        input  logic         is_decrypt,
        input  logic [127:0] blk_in,
        output logic [127:0] blk_out
    );
        int cyc;
        begin
            @(negedge clk) begin
                dp_decrypt  = is_decrypt;
                dp_block_in = blk_in;
                dp_start    = 1'b1;
            end
            @(negedge clk) begin
                dp_start = 1'b0;
            end

            cyc = 0;
            while (!dp_done && (cyc < 20)) begin
                @(posedge clk) begin end
                #0.1 cyc++;
            end

            blk_out = dp_block_out;

            total_checks++;
            if (!dp_done || dp_busy || (cyc != 10)) begin
                $display("[ERROR] Datapath timing mismatch (decrypt=%0b): cyc=%0d done=%0b busy=%0b",
                         is_decrypt, cyc, dp_done, dp_busy);
                error_count++;
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Main Verification Stimulus
    //-------------------------------------------------------------------------
    initial begin
        logic [127:0] res_block;
        logic [127:0] enc_block;
        logic [127:0] dec_block;
        logic [127:0] rand_key;
        logic [127:0] rand_pt;

        total_checks       = 0;
        error_count        = 0;
        rst_n              = 1'b0;
        ke_start           = 1'b0;
        ke_key             = 128'd0;
        dp_start           = 1'b0;
        dp_decrypt         = 1'b0;
        dp_block_in        = 128'd0;
        tb_override_rk_idx = 1'b0;
        tb_rk_idx          = 4'd0;

        repeat (4) @(posedge clk) begin end
        @(negedge clk) rst_n = 1'b1;

        $display("=======================================================================");
        $display("  MiniSoC AES Week 4 Testbench — Key Expansion & AES-128 Datapath");
        $display("=======================================================================");

        //=====================================================================
        // 1. NIST FIPS-197 Appendix A.1 / Appendix B Key Schedule & Datapath
        //=====================================================================
        $display("[TEST 1] NIST FIPS-197 Appendix B: Key Expansion, Cipher & Inverse Cipher...");
        run_key_expansion(APP_B_KEY);

        // Verify all 11 Round Keys in forward (0..10) and reverse (10..0) order
        tb_override_rk_idx = 1'b1;
        for (int r = 0; r <= 10; r++) begin
            tb_rk_idx = 4'(r);
            #0.1 check_128($sformatf("App.B RoundKey[%0d] (fwd)", r), ke_round_key, APP_B_RK[r]);
        end
        for (int r = 10; r >= 0; r--) begin
            tb_rk_idx = 4'(r);
            #0.1 check_128($sformatf("App.B RoundKey[%0d] (rev)", r), ke_round_key, APP_B_RK[r]);
        end
        tb_override_rk_idx = 1'b0;

        // Run Appendix B Forward Cipher and verify intermediate state at every cycle
        @(negedge clk) begin
            dp_decrypt  = 1'b0;
            dp_block_in = APP_B_PT;
            dp_start    = 1'b1;
        end
        @(posedge clk) begin end
        #0.1 check_128("App.B Cipher Round 0 state", dp_block_out, APP_B_ENC_STATE[0]);
        @(negedge clk) dp_start = 1'b0;

        for (int r = 1; r <= 10; r++) begin
            @(posedge clk) begin end
            #0.1 check_128($sformatf("App.B Cipher Round %0d state", r), dp_block_out, APP_B_ENC_STATE[r]);
        end
        check_128("App.B Cipher Final Ciphertext", dp_block_out, APP_B_CT);

        // Run Appendix B Inverse Cipher reusing the pre-computed RoundKeys
        run_dp_block(1'b1, APP_B_CT, res_block);
        check_128("App.B Inverse Cipher Recovered Plaintext", res_block, APP_B_PT);

        //=====================================================================
        // 2. NIST FIPS-197 Appendix C.1 Key Schedule, Cipher & Inverse Cipher
        //=====================================================================
        $display("[TEST 2] NIST FIPS-197 Appendix C.1: Key Expansion, Cipher & Inverse Cipher...");
        run_key_expansion(APP_C1_KEY);

        tb_override_rk_idx = 1'b1;
        for (int r = 0; r <= 10; r++) begin
            tb_rk_idx = 4'(r);
            #0.1 check_128($sformatf("App.C1 RoundKey[%0d]", r), ke_round_key, APP_C1_RK[r]);
        end
        tb_override_rk_idx = 1'b0;

        // Run Appendix C.1 Forward Cipher and check every round state (0..10)
        @(negedge clk) begin
            dp_decrypt  = 1'b0;
            dp_block_in = APP_C1_PT;
            dp_start    = 1'b1;
        end
        @(posedge clk) begin end
        #0.1 check_128("App.C1 Cipher Round 0 state", dp_block_out, APP_C1_ENC_STATE[0]);
        @(negedge clk) dp_start = 1'b0;

        for (int r = 1; r <= 10; r++) begin
            @(posedge clk) begin end
            #0.1 check_128($sformatf("App.C1 Cipher Round %0d state", r), dp_block_out, APP_C1_ENC_STATE[r]);
        end
        check_128("App.C1 Cipher Final Ciphertext", dp_block_out, APP_C1_CT);

        // Run Appendix C.1 Inverse Cipher and check every round state (0..10)
        @(negedge clk) begin
            dp_decrypt  = 1'b1;
            dp_block_in = APP_C1_CT;
            dp_start    = 1'b1;
        end
        @(posedge clk) begin end
        #0.1 check_128("App.C1 InvCipher Round 0 state", dp_block_out, APP_C1_DEC_STATE[0]);
        @(negedge clk) dp_start = 1'b0;

        for (int r = 1; r <= 10; r++) begin
            @(posedge clk) begin end
            #0.1 check_128($sformatf("App.C1 InvCipher Round %0d state", r), dp_block_out, APP_C1_DEC_STATE[r]);
        end
        check_128("App.C1 InvCipher Final Plaintext", dp_block_out, APP_C1_PT);

        //=====================================================================
        // 3. NIST SP 800-38A F.1.1 Multi-Block ECB Encryption & Decryption
        //=====================================================================
        $display("[TEST 3] NIST SP 800-38A F.1.1 Multi-Block (4 blocks, single KeyExpansion)...");
        run_key_expansion(APP_B_KEY);

        for (int b = 0; b < 4; b++) begin
            run_dp_block(1'b0, SP800_PT[b], enc_block);
            check_128($sformatf("SP800-38A Block[%0d] Encrypt", b), enc_block, SP800_CT[b]);

            run_dp_block(1'b1, SP800_CT[b], dec_block);
            check_128($sformatf("SP800-38A Block[%0d] Decrypt", b), dec_block, SP800_PT[b]);
        end

        //=====================================================================
        // 4. Random Key & Block Round-Trip Bijection Test (32 vectors)
        //=====================================================================
        $display("[TEST 4] Random Key/Block Round-Trip Bijection (32 vectors)...");
        for (int t = 0; t < 32; t++) begin
            rand_key = {$urandom(32'hA500_0000 + t), $urandom(32'hB600_0000 + t),
                        $urandom(32'hC700_0000 + t), $urandom(32'hD800_0000 + t)};
            rand_pt  = {$urandom(32'h1100_0000 + t), $urandom(32'h2200_0000 + t),
                        $urandom(32'h3300_0000 + t), $urandom(32'h4400_0000 + t)};

            run_key_expansion(rand_key);
            run_dp_block(1'b0, rand_pt, enc_block);
            run_dp_block(1'b1, enc_block, dec_block);
            check_128($sformatf("Random Round-Trip [%0d] D_K(E_K(P)) == P", t), dec_block, rand_pt);
        end

        //=====================================================================
        // Final Summary
        //=====================================================================
        $display("=======================================================================");
        $display("  SUMMARY: %0d checks executed, %0d errors.", total_checks, error_count);
        if (error_count == 0) begin
            $display("  STATUS : PASS — All AES-128 Key Expansion & Datapath checks passed!");
        end else begin
            $display("  STATUS : FAIL — %0d errors detected!", error_count);
        end
        $display("=======================================================================");
        $finish;
    end

endmodule : tb_minisoc_aes_s4
