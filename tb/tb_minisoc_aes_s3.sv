//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Testbench:   tb_minisoc_aes_s3
// Description: Self-checking unit testbench for Week 3 deliverable:
//              - Direct round transformations:
//                  * minisoc_aes_sub_bytes
//                  * minisoc_aes_shift_rows
//                  * minisoc_aes_mix_columns
//                  * minisoc_aes_add_round_key
//              - Inverse round transformations:
//                  * minisoc_aes_inv_shift_rows
//                  * minisoc_aes_inv_sub_bytes
//                  * minisoc_aes_inv_mix_columns
//              - Verification against all intermediate values of:
//                  1. NIST FIPS-197 Appendix B (Cipher Example, Rounds 0..10)
//                  2. NIST FIPS-197 Appendix C.1 (Cipher, Inverse Cipher, and
//                     Equivalent Inverse Cipher, Rounds 0..10)
//                  3. Independent GF(2^8) polynomial matrix golden model,
//                     bijection, and linearity across 256 random 128-bit states
//=============================================================================

`timescale 1ns/1ps

module tb_minisoc_aes_s3;
    import minisoc_aes_pkg::*;

    //-------------------------------------------------------------------------
    // DUT Signals & Combinational Instantiations
    //-------------------------------------------------------------------------
    logic [127:0] fwd_state_in;
    logic [127:0] fwd_round_key;
    wire  [127:0] fwd_sub_bytes_out;
    wire  [127:0] fwd_shift_rows_out;
    wire  [127:0] fwd_mix_columns_out;
    wire  [127:0] fwd_ark_after_mc_out;
    wire  [127:0] fwd_ark_after_sr_out;

    logic [127:0] mc_direct_in;
    wire  [127:0] mc_direct_out;
    wire  [127:0] imc_of_mc_out;

    logic [127:0] imc_direct_in;
    wire  [127:0] imc_direct_out;
    wire  [127:0] mc_of_imc_out;

    logic [127:0] ark_direct_in;
    logic [127:0] ark_direct_key;
    wire  [127:0] ark_direct_out;

    logic [127:0] inv_state_in;
    logic [127:0] inv_round_key;
    wire  [127:0] inv_shift_rows_out;
    wire  [127:0] inv_sub_bytes_out;
    wire  [127:0] inv_ark_out;
    wire  [127:0] inv_mix_columns_out;

    // Forward Round Chain: SubBytes -> ShiftRows -> MixColumns -> AddRoundKey
    minisoc_aes_sub_bytes u_fwd_sub_bytes (
        .i_state (fwd_state_in),
        .o_state (fwd_sub_bytes_out)
    );

    minisoc_aes_shift_rows u_fwd_shift_rows (
        .i_state (fwd_sub_bytes_out),
        .o_state (fwd_shift_rows_out)
    );

    minisoc_aes_mix_columns u_fwd_mix_columns (
        .i_state (fwd_shift_rows_out),
        .o_state (fwd_mix_columns_out)
    );

    minisoc_aes_add_round_key u_fwd_ark_mc (
        .i_state     (fwd_mix_columns_out),
        .i_round_key (fwd_round_key),
        .o_state     (fwd_ark_after_mc_out)
    );

    // Final Round Path (Round 10 omits MixColumns): ShiftRows -> AddRoundKey
    minisoc_aes_add_round_key u_fwd_ark_sr (
        .i_state     (fwd_shift_rows_out),
        .i_round_key (fwd_round_key),
        .o_state     (fwd_ark_after_sr_out)
    );

    // Standalone MixColumns / InvMixColumns / AddRoundKey instances
    minisoc_aes_mix_columns u_mc_direct (
        .i_state (mc_direct_in),
        .o_state (mc_direct_out)
    );

    minisoc_aes_inv_mix_columns u_imc_of_mc (
        .i_state (mc_direct_out),
        .o_state (imc_of_mc_out)
    );

    minisoc_aes_inv_mix_columns u_imc_direct (
        .i_state (imc_direct_in),
        .o_state (imc_direct_out)
    );

    minisoc_aes_mix_columns u_mc_of_imc (
        .i_state (imc_direct_out),
        .o_state (mc_of_imc_out)
    );

    minisoc_aes_add_round_key u_ark_direct (
        .i_state     (ark_direct_in),
        .i_round_key (ark_direct_key),
        .o_state     (ark_direct_out)
    );

    // Inverse Round Chain (FIPS-197 Fig. 12):
    // InvShiftRows -> InvSubBytes -> AddRoundKey -> InvMixColumns
    minisoc_aes_inv_shift_rows u_inv_shift_rows (
        .i_state (inv_state_in),
        .o_state (inv_shift_rows_out)
    );

    minisoc_aes_inv_sub_bytes u_inv_sub_bytes (
        .i_state (inv_shift_rows_out),
        .o_state (inv_sub_bytes_out)
    );

    minisoc_aes_add_round_key u_inv_ark (
        .i_state     (inv_sub_bytes_out),
        .i_round_key (inv_round_key),
        .o_state     (inv_ark_out)
    );

    minisoc_aes_inv_mix_columns u_inv_mix_columns (
        .i_state (inv_ark_out),
        .o_state (inv_mix_columns_out)
    );

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

    function automatic logic [127:0] golden_mix_columns(input logic [127:0] st);
        aes_state_t s_in;
        aes_state_t s_out;
        begin
            s_in = aes_state_t'(st);
            for (int c = 0; c < 4; c++) begin
                s_out[c][0] = gf256_mul(8'h02, s_in[c][0]) ^ gf256_mul(8'h03, s_in[c][1]) ^ s_in[c][2] ^ s_in[c][3];
                s_out[c][1] = s_in[c][0] ^ gf256_mul(8'h02, s_in[c][1]) ^ gf256_mul(8'h03, s_in[c][2]) ^ s_in[c][3];
                s_out[c][2] = s_in[c][0] ^ s_in[c][1] ^ gf256_mul(8'h02, s_in[c][2]) ^ gf256_mul(8'h03, s_in[c][3]);
                s_out[c][3] = gf256_mul(8'h03, s_in[c][0]) ^ s_in[c][1] ^ s_in[c][2] ^ gf256_mul(8'h02, s_in[c][3]);
            end
            golden_mix_columns = s_out;
        end
    endfunction

    function automatic logic [127:0] golden_inv_mix_columns(input logic [127:0] st);
        aes_state_t s_in;
        aes_state_t s_out;
        begin
            s_in = aes_state_t'(st);
            for (int c = 0; c < 4; c++) begin
                s_out[c][0] = gf256_mul(8'h0e, s_in[c][0]) ^ gf256_mul(8'h0b, s_in[c][1]) ^ gf256_mul(8'h0d, s_in[c][2]) ^ gf256_mul(8'h09, s_in[c][3]);
                s_out[c][1] = gf256_mul(8'h09, s_in[c][0]) ^ gf256_mul(8'h0e, s_in[c][1]) ^ gf256_mul(8'h0b, s_in[c][2]) ^ gf256_mul(8'h0d, s_in[c][3]);
                s_out[c][2] = gf256_mul(8'h0d, s_in[c][0]) ^ gf256_mul(8'h09, s_in[c][1]) ^ gf256_mul(8'h0e, s_in[c][2]) ^ gf256_mul(8'h0b, s_in[c][3]);
                s_out[c][3] = gf256_mul(8'h0b, s_in[c][0]) ^ gf256_mul(8'h0d, s_in[c][1]) ^ gf256_mul(8'h09, s_in[c][2]) ^ gf256_mul(8'h0e, s_in[c][3]);
            end
            golden_inv_mix_columns = s_out;
        end
    endfunction

    //-------------------------------------------------------------------------
    // 1. NIST FIPS-197 Appendix B Vectors (Cipher Example, Pages 33-34)
    //-------------------------------------------------------------------------
    localparam logic [127:0] APP_B_INPUT  = 128'h3243f6a8_885a308d_313198a2_e0370734;
    localparam logic [127:0] APP_B_KEY0   = 128'h2b7e1516_28aed2a6_abf71588_09cf4f3c;
    localparam logic [127:0] APP_B_OUTPUT = 128'h3925841d_02dc09fb_dc118597_196a0b32;

    typedef struct packed {
        logic [127:0] start_of_round;
        logic [127:0] after_sub_bytes;
        logic [127:0] after_shift_rows;
        logic [127:0] after_mix_columns;
        logic [127:0] round_key;
        logic [127:0] next_state;
    } cipher_round_vec_t;

    localparam cipher_round_vec_t APP_B_VECS [1:10] = '{
        // Round 1
        '{128'h193de3be_a0f4e22b_9ac68d2a_e9f84808,
          128'hd42711ae_e0bf98f1_b8b45de5_1e415230,
          128'hd4bf5d30_e0b452ae_b84111f1_1e2798e5,
          128'h046681e5_e0cb199a_48f8d37a_2806264c,
          128'ha0fafe17_88542cb1_23a33939_2a6c7605,
          128'ha49c7ff2_689f352b_6b5bea43_026a5049},
        // Round 2
        '{128'ha49c7ff2_689f352b_6b5bea43_026a5049,
          128'h49ded289_45db96f1_7f39871a_7702533b,
          128'h49db873b_45395389_7f02d2f1_77de961a,
          128'h584dcaf1_1b4b5aac_dbe7caa8_1b6bb0e5,
          128'hf2c295f2_7a96b943_5935807a_7359f67f,
          128'haa8f5f03_61dde3ef_82d24ad2_6832469a},
        // Round 3
        '{128'haa8f5f03_61dde3ef_82d24ad2_6832469a,
          128'hac73cf7b_efc111df_13b5d6b5_45235ab8,
          128'hacc1d6b8_efb55a7b_1323cfdf_457311b5,
          128'h75ec0993_200b6333_53c0cf7c_bb25d0dc,
          128'h3d80477d_4716fe3e_1e237e44_6d7a883b,
          128'h486c4eee_671d9d0d_4de3b138_d65f58e7},
        // Round 4
        '{128'h486c4eee_671d9d0d_4de3b138_d65f58e7,
          128'h52502f28_85a45ed7_e311c807_f6cf6a94,
          128'h52a4c894_85116a28_e3cf2fd7_f6505e07,
          128'h0fd6daa9_603138bf_6fc0106b_5eb31301,
          128'hef44a541_a8525b7f_b671253b_db0bad00,
          128'he0927fe8_c86363c0_d9b13550_85b8be01},
        // Round 5
        '{128'he0927fe8_c86363c0_d9b13550_85b8be01,
          128'he14fd29b_e8fbfbba_35c89653_976cae7c,
          128'he1fb967c_e8c8ae9b_356cd2ba_974ffb53,
          128'h25d1a9ad_bd11d168_b63a338e_4c4cc0b0,
          128'hd4d1c6f8_7c839d87_caf2b8bc_11f915bc,
          128'hf1006f55_c1924cef_7cc88b32_5db5d50c},
        // Round 6
        '{128'hf1006f55_c1924cef_7cc88b32_5db5d50c,
          128'ha163a8fc_784f29df_10e83d23_4cd503fe,
          128'ha14f3dfe_78e803fc_10d5a8df_4c632923,
          128'h4b868d6d_2c4a8980_339df4e8_37d218d8,
          128'h6d88a37a_110b3efd_dbf98641_ca0093fd,
          128'h260e2e17_3d41b77d_e86472a9_fdd28b25},
        // Round 7
        '{128'h260e2e17_3d41b77d_e86472a9_fdd28b25,
          128'hf7ab31f0_2783a9ff_9b4340d3_54b53d3f,
          128'hf783403f_27433df0_9bb531ff_54aba9d3,
          128'h1415b5bf_461615ec_274656d7_342ad843,
          128'h4e54f70e_5f5fc9f3_84a64fb2_4ea6dc4f,
          128'h5a4142b1_1949dc1f_a3e01965_7a8c040c},
        // Round 8
        '{128'h5a4142b1_1949dc1f_a3e01965_7a8c040c,
          128'hbe832cc8_d43b86c0_0ae1d44d_da64f2fe,
          128'hbe3bd4fe_d4e1f2c8_0a642cc0_da83864d,
          128'h00512fd1_b1c889ff_54766dcd_fa1b99ea,
          128'head27321_b58dbad2_312bf560_7f8d292f,
          128'hea835cf0_0445332d_655d98ad_8596b0c5},
        // Round 9
        '{128'hea835cf0_0445332d_655d98ad_8596b0c5,
          128'h87ec4a8c_f26ec3d8_4d4c4695_9790e7a6,
          128'h876e46a6_f24ce78c_4d904ad8_97ecc395,
          128'h473794ed_40d4e4a5_a3703aa6_4c9f42bc,
          128'hac7766f3_19fadc21_28d12941_575c006e,
          128'heb40f21e_592e3884_8ba113e7_1bc342d2},
        // Round 10 (MixColumns omitted in final round)
        '{128'heb40f21e_592e3884_8ba113e7_1bc342d2,
          128'he9098972_cb31075f_3d327d94_af2e2cb5,
          128'he9317db5_cb322c72_3d2e895f_af090794,
          128'h00000000_00000000_00000000_00000000,
          128'hd014f9a8_c9ee2589_e13f0cc8_b6630ca6,
          128'h3925841d_02dc09fb_dc118597_196a0b32}
    };

    //-------------------------------------------------------------------------
    // 2. NIST FIPS-197 Appendix C.1 Vectors (Cipher & Inverse Cipher, pp. 35-38)
    //-------------------------------------------------------------------------
    localparam logic [127:0] APP_C1_PLAINTEXT  = 128'h00112233_44556677_8899aabb_ccddeeff;
    localparam logic [127:0] APP_C1_KEY0       = 128'h00010203_04050607_08090a0b_0c0d0e0f;
    localparam logic [127:0] APP_C1_CIPHERTEXT = 128'h69c4e0d8_6a7b0430_d8cdb780_70b4c55a;

    localparam cipher_round_vec_t APP_C1_FWD_VECS [1:10] = '{
        // Round 1
        '{128'h00102030_40506070_8090a0b0_c0d0e0f0,
          128'h63cab704_0953d051_cd60e0e7_ba70e18c,
          128'h6353e08c_0960e104_cd70b751_bacad0e7,
          128'h5f726415_57f5bc92_f7be3b29_1db9f91a,
          128'hd6aa74fd_d2af72fa_daa678f1_d6ab76fe,
          128'h89d810e8_855ace68_2d1843d8_cb128fe4},
        // Round 2
        '{128'h89d810e8_855ace68_2d1843d8_cb128fe4,
          128'ha761ca9b_97be8b45_d8ad1a61_1fc97369,
          128'ha7be1a69_97ad739b_d8c9ca45_1f618b61,
          128'hff879684_31d86a51_645151fa_773ad009,
          128'hb692cf0b_643dbdf1_be9bc500_6830b3fe,
          128'h4915598f_55e5d7a0_daca94fa_1f0a63f7},
        // Round 3
        '{128'h4915598f_55e5d7a0_daca94fa_1f0a63f7,
          128'h3b59cb73_fcd90ee0_5774222d_c067fb68,
          128'h3bd92268_fc74fb73_5767cbe0_c0590e2d,
          128'h4c9c1e66_f771f076_2c3f868e_534df256,
          128'hb6ff744e_d2c2c9bf_6c590cbf_0469bf41,
          128'hfa636a28_25b339c9_40668a31_57244d17},
        // Round 4
        '{128'hfa636a28_25b339c9_40668a31_57244d17,
          128'h2dfb0234_3f6d12dd_09337ec7_5b36e3f0,
          128'h2d6d7ef0_3f33e334_093602dd_5bfb12c7,
          128'h6385b79f_fc538df9_97be478e_7547d691,
          128'h47f7f7bc_95353e03_f96c32bc_fd058dfd,
          128'h24724023_6966b3fa_6ed27532_88425b6c},
        // Round 5
        '{128'h24724023_6966b3fa_6ed27532_88425b6c,
          128'h36400926_f9336d2d_9fb59d23_c42c3950,
          128'h36339d50_f9b53926_9f2c092d_c4406d23,
          128'hf4bcd454_32e554d0_75f1d6c5_1dd03b3c,
          128'h3caaa3e8_a99f9deb_50f3af57_adf622aa,
          128'hc81677bc_9b7ac93b_25027992_b0261996},
        // Round 6
        '{128'hc81677bc_9b7ac93b_25027992_b0261996,
          128'he847f565_14dadde2_3f77b64f_e7f7d490,
          128'he8dab690_1477d465_3ff7f5e2_e747dd4f,
          128'h9816ee74_00f87f55_6b2c049c_8e5ad036,
          128'h5e390f7d_f7a69296_a7553dc1_0aa31f6b,
          128'hc62fe109_f75eedc3_cc79395d_84f9cf5d},
        // Round 7
        '{128'hc62fe109_f75eedc3_cc79395d_84f9cf5d,
          128'hb415f801_6858552e_4bb6124c_5f998a4c,
          128'hb458124c_68b68a01_4b99f82e_5f15554c,
          128'hc57e1c15_9a9bd286_f05f4be0_98c63439,
          128'h14f9701a_e35fe28c_440adf4d_4ea9c026,
          128'hd1876c0f_79c4300a_b45594ad_d66ff41f},
        // Round 8
        '{128'hd1876c0f_79c4300a_b45594ad_d66ff41f,
          128'h3e175076_b61c0467_8dfc2295_f6a8bfc0,
          128'h3e1c22c0_b6fcbf76_8da85067_f6170495,
          128'hbaa03de7_a1f9b56e_d5512cba_5f414d23,
          128'h47438735_a41c65b9_e016baf4_aebf7ad2,
          128'hfde3bad2_05e5d0d7_3547964e_f1fe37f1},
        // Round 9
        '{128'hfde3bad2_05e5d0d7_3547964e_f1fe37f1,
          128'h5411f4b5_6bd9700e_96a0902f_a1bb9aa1,
          128'h54d990a1_6ba09ab5_96bbf40e_a111702f,
          128'he9f74eec_023020f6_1bf2ccf2_353c21c7,
          128'h549932d1_f0855768_1093ed9c_be2c974e,
          128'hbd6e7c3d_f2b5779e_0b61216e_8b10b689},
        // Round 10
        '{128'hbd6e7c3d_f2b5779e_0b61216e_8b10b689,
          128'h7a9f1027_89d5f50b_2beffd9f_3dca4ea7,
          128'h7ad5fda7_89ef4e27_2bca100b_3d9ff59f,
          128'h00000000_00000000_00000000_00000000,
          128'h13111d7f_e3944a17_f307a78b_4d2b30c5,
          128'h69c4e0d8_6a7b0430_d8cdb780_70b4c55a}
    };

    typedef struct packed {
        logic [127:0] istart;
        logic [127:0] is_row;
        logic [127:0] is_box;
        logic [127:0] ik_sch;
        logic [127:0] ik_add;
        logic [127:0] next_istart;
        logic [127:0] eq_im_col;
        logic [127:0] eq_ik_sch;
    } inv_cipher_round_vec_t;

    localparam inv_cipher_round_vec_t APP_C1_INV_VECS [1:10] = '{
        // Inverse Round 1
        '{128'h7ad5fda7_89ef4e27_2bca100b_3d9ff59f,
          128'h7a9f1027_89d5f50b_2beffd9f_3dca4ea7,
          128'hbd6e7c3d_f2b5779e_0b61216e_8b10b689,
          128'h549932d1_f0855768_1093ed9c_be2c974e,
          128'he9f74eec_023020f6_1bf2ccf2_353c21c7,
          128'h54d990a1_6ba09ab5_96bbf40e_a111702f,
          128'h4773b91f_f72f3543_61cb018e_a1e6cf2c,
          128'h13aa29be_9c8faff6_f770f580_00f7bf03},
        // Inverse Round 2
        '{128'h54d990a1_6ba09ab5_96bbf40e_a111702f,
          128'h5411f4b5_6bd9700e_96a0902f_a1bb9aa1,
          128'hfde3bad2_05e5d0d7_3547964e_f1fe37f1,
          128'h47438735_a41c65b9_e016baf4_aebf7ad2,
          128'hbaa03de7_a1f9b56e_d5512cba_5f414d23,
          128'h3e1c22c0_b6fcbf76_8da85067_f6170495,
          128'h2d7e86a3_39d9393e_e6570a11_01904e16,
          128'h1362a463_8f258648_6bff5a76_f7874a83},
        // Inverse Round 3
        '{128'h3e1c22c0_b6fcbf76_8da85067_f6170495,
          128'h3e175076_b61c0467_8dfc2295_f6a8bfc0,
          128'hd1876c0f_79c4300a_b45594ad_d66ff41f,
          128'h14f9701a_e35fe28c_440adf4d_4ea9c026,
          128'hc57e1c15_9a9bd286_f05f4be0_98c63439,
          128'hb458124c_68b68a01_4b99f82e_5f15554c,
          128'h39daee38_f4f1a82a_af432410_c36d45b9,
          128'h8d82fc74_9c47222b_e4dadc3e_9c7810f5},
        // Inverse Round 4
        '{128'hb458124c_68b68a01_4b99f82e_5f15554c,
          128'hb415f801_6858552e_4bb6124c_5f998a4c,
          128'hc62fe109_f75eedc3_cc79395d_84f9cf5d,
          128'h5e390f7d_f7a69296_a7553dc1_0aa31f6b,
          128'h9816ee74_00f87f55_6b2c049c_8e5ad036,
          128'he8dab690_1477d465_3ff7f5e2_e747dd4f,
          128'h9a39bf1d_05b20a3a_476a0bf7_9fe51184,
          128'h72e3098d_11c5de5f_789dfe15_78a2cccb},
        // Inverse Round 5
        '{128'he8dab690_1477d465_3ff7f5e2_e747dd4f,
          128'he847f565_14dadde2_3f77b64f_e7f7d490,
          128'hc81677bc_9b7ac93b_25027992_b0261996,
          128'h3caaa3e8_a99f9deb_50f3af57_adf622aa,
          128'hf4bcd454_32e554d0_75f1d6c5_1dd03b3c,
          128'h36339d50_f9b53926_9f2c092d_c4406d23,
          128'h18f78d77_9a93eef4_f6742967_c47f5ffd,
          128'h2ec41027_6326d7d2_6958204a_003f32de},
        // Inverse Round 6
        '{128'h36339d50_f9b53926_9f2c092d_c4406d23,
          128'h36400926_f9336d2d_9fb59d23_c42c3950,
          128'h24724023_6966b3fa_6ed27532_88425b6c,
          128'h47f7f7bc_95353e03_f96c32bc_fd058dfd,
          128'h6385b79f_fc538df9_97be478e_7547d691,
          128'h2d6d7ef0_3f33e334_093602dd_5bfb12c7,
          128'h85cf8bf4_72d124c1_0348f545_329c0053,
          128'ha8a2f504_4de2c7f5_0a7ef798_69671294},
        // Inverse Round 7
        '{128'h2d6d7ef0_3f33e334_093602dd_5bfb12c7,
          128'h2dfb0234_3f6d12dd_09337ec7_5b36e3f0,
          128'hfa636a28_25b339c9_40668a31_57244d17,
          128'hb6ff744e_d2c2c9bf_6c590cbf_0469bf41,
          128'h4c9c1e66_f771f076_2c3f868e_534df256,
          128'h3bd92268_fc74fb73_5767cbe0_c0590e2d,
          128'hfc1fc1f9_1934c982_10fbfb8d_a340eb21,
          128'hc7c6e391_e54032f1_479c306d_6319e50c},
        // Inverse Round 8
        '{128'h3bd92268_fc74fb73_5767cbe0_c0590e2d,
          128'h3b59cb73_fcd90ee0_5774222d_c067fb68,
          128'h4915598f_55e5d7a0_daca94fa_1f0a63f7,
          128'hb692cf0b_643dbdf1_be9bc500_6830b3fe,
          128'hff879684_31d86a51_645151fa_773ad009,
          128'ha7be1a69_97ad739b_d8c9ca45_1f618b61,
          128'h076518f0_b52ba2fb_7a15c8d9_3be45e00,
          128'ha0db0299_2286d160_a2dc029c_2485d561},
        // Inverse Round 9
        '{128'ha7be1a69_97ad739b_d8c9ca45_1f618b61,
          128'ha761ca9b_97be8b45_d8ad1a61_1fc97369,
          128'h89d810e8_855ace68_2d1843d8_cb128fe4,
          128'hd6aa74fd_d2af72fa_daa678f1_d6ab76fe,
          128'h5f726415_57f5bc92_f7be3b29_1db9f91a,
          128'h6353e08c_0960e104_cd70b751_bacad0e7,
          128'hef053f7c_8b3d32fd_4d2a64ad_3c93071a,
          128'h8c56dff0_825dd3f9_805ad3fc_8659d7fd},
        // Inverse Round 10 (InvMixColumns omitted in final round)
        '{128'h6353e08c_0960e104_cd70b751_bacad0e7,
          128'h63cab704_0953d051_cd60e0e7_ba70e18c,
          128'h00102030_40506070_8090a0b0_c0d0e0f0,
          128'h00010203_04050607_08090a0b_0c0d0e0f,
          128'h00112233_44556677_8899aabb_ccddeeff,
          128'h00112233_44556677_8899aabb_ccddeeff,
          128'h00000000_00000000_00000000_00000000,
          128'h00010203_04050607_08090a0b_0c0d0e0f}
    };

    //-------------------------------------------------------------------------
    // Main Self-Checking Verification Sequence
    //-------------------------------------------------------------------------
    logic [127:0] prng_a;
    logic [127:0] prng_b;
    logic [127:0] mc_a_save;
    logic [127:0] mc_b_save;
    logic [127:0] imc_a_save;
    logic [127:0] imc_b_save;
    logic [127:0] cur_inv_state;

    initial begin
        fwd_state_in   = 128'd0;
        fwd_round_key  = 128'd0;
        mc_direct_in   = 128'd0;
        imc_direct_in  = 128'd0;
        ark_direct_in  = 128'd0;
        ark_direct_key = 128'd0;
        inv_state_in   = 128'd0;
        inv_round_key  = 128'd0;
        #1 begin end

        //=====================================================================
        // 1. NIST FIPS-197 Appendix B: Cipher Example (All 10 Rounds)
        //=====================================================================
        // Round 0: Initial AddRoundKey
        ark_direct_in  = APP_B_INPUT;
        ark_direct_key = APP_B_KEY0;
        #1 begin end
        if (ark_direct_out !== APP_B_VECS[1].start_of_round) begin
            $fatal(1, "[TB ERROR] Appendix B Round 0 AddRoundKey mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                   ark_direct_out, APP_B_VECS[1].start_of_round);
        end
        $display("     [App.B Rnd  0] input           : %032h", APP_B_INPUT);
        $display("     [App.B Rnd  0] after AddRndKey : %032h", ark_direct_out);

        for (int rnd = 1; rnd <= 10; rnd++) begin
            fwd_state_in  = APP_B_VECS[rnd].start_of_round;
            fwd_round_key = APP_B_VECS[rnd].round_key;
            #1 begin end

            if (fwd_sub_bytes_out !== APP_B_VECS[rnd].after_sub_bytes) begin
                $fatal(1, "[TB ERROR] Appendix B Round %0d SubBytes mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                       rnd, fwd_sub_bytes_out, APP_B_VECS[rnd].after_sub_bytes);
            end
            if (fwd_shift_rows_out !== APP_B_VECS[rnd].after_shift_rows) begin
                $fatal(1, "[TB ERROR] Appendix B Round %0d ShiftRows mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                       rnd, fwd_shift_rows_out, APP_B_VECS[rnd].after_shift_rows);
            end

            if (rnd < 10) begin
                if (fwd_mix_columns_out !== APP_B_VECS[rnd].after_mix_columns) begin
                    $fatal(1, "[TB ERROR] Appendix B Round %0d MixColumns mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                           rnd, fwd_mix_columns_out, APP_B_VECS[rnd].after_mix_columns);
                end
                if (fwd_ark_after_mc_out !== APP_B_VECS[rnd].next_state) begin
                    $fatal(1, "[TB ERROR] Appendix B Round %0d AddRoundKey mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                           rnd, fwd_ark_after_mc_out, APP_B_VECS[rnd].next_state);
                end

                // Verify InvMixColumns on Appendix B MixColumns output
                imc_direct_in = fwd_mix_columns_out;
                #1 begin end
                if (imc_direct_out !== APP_B_VECS[rnd].after_shift_rows) begin
                    $fatal(1, "[TB ERROR] Appendix B Round %0d InvMixColumns(MixColumns) mismatch!", rnd);
                end
            end else begin
                if (fwd_ark_after_sr_out !== APP_B_OUTPUT) begin
                    $fatal(1, "[TB ERROR] Appendix B Round 10 final AddRoundKey mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                           fwd_ark_after_sr_out, APP_B_OUTPUT);
                end
            end

            if (rnd == 1 || rnd == 9 || rnd == 10) begin
                $display("     [App.B Rnd %2d] start of round  : %032h", rnd, fwd_state_in);
                $display("     [App.B Rnd %2d] after SubBytes  : %032h", rnd, fwd_sub_bytes_out);
                $display("     [App.B Rnd %2d] after ShiftRows : %032h", rnd, fwd_shift_rows_out);
                if (rnd < 10) begin
                    $display("     [App.B Rnd %2d] after MixCols   : %032h", rnd, fwd_mix_columns_out);
                    $display("     [App.B Rnd %2d] after AddRndKey : %032h", rnd, fwd_ark_after_mc_out);
                end else begin
                    $display("     [App.B Rnd %2d] Cipher Output   : %032h", rnd, fwd_ark_after_sr_out);
                end
            end
        end

        // Full Inverse Cipher recovery of Appendix B ciphertext -> plaintext
        ark_direct_in  = APP_B_OUTPUT;
        ark_direct_key = APP_B_VECS[10].round_key;
        #1 cur_inv_state = ark_direct_out;
        for (int rnd = 9; rnd >= 1; rnd--) begin
            inv_state_in  = cur_inv_state;
            inv_round_key = APP_B_VECS[rnd].round_key;
            #1 cur_inv_state = inv_mix_columns_out;
            if (cur_inv_state !== APP_B_VECS[rnd].after_shift_rows) begin
                $fatal(1, "[TB ERROR] Appendix B Inverse recovery mismatch at round %0d!", rnd);
            end
        end
        inv_state_in  = cur_inv_state;
        inv_round_key = APP_B_KEY0;
        #1 begin end
        if (inv_ark_out !== APP_B_INPUT) begin
            $fatal(1, "[TB ERROR] Appendix B full Inverse Cipher did not recover plaintext!");
        end
        $display("[TB] 1. NIST FIPS-197 Appendix B (Rounds 0..10 + Inverse Recovery) verified!");

        //=====================================================================
        // 2. NIST FIPS-197 Appendix C.1: Cipher (Encrypt, Rounds 0..10)
        //=====================================================================
        ark_direct_in  = APP_C1_PLAINTEXT;
        ark_direct_key = APP_C1_KEY0;
        #1 begin end
        if (ark_direct_out !== APP_C1_FWD_VECS[1].start_of_round) begin
            $fatal(1, "[TB ERROR] Appendix C.1 Encrypt Round 0 AddRoundKey mismatch!");
        end

        for (int rnd = 1; rnd <= 10; rnd++) begin
            fwd_state_in  = APP_C1_FWD_VECS[rnd].start_of_round;
            fwd_round_key = APP_C1_FWD_VECS[rnd].round_key;
            #1 begin end

            if (fwd_sub_bytes_out !== APP_C1_FWD_VECS[rnd].after_sub_bytes) begin
                $fatal(1, "[TB ERROR] Appendix C.1 Encrypt Round %0d SubBytes mismatch!", rnd);
            end
            if (fwd_shift_rows_out !== APP_C1_FWD_VECS[rnd].after_shift_rows) begin
                $fatal(1, "[TB ERROR] Appendix C.1 Encrypt Round %0d ShiftRows mismatch!", rnd);
            end
            if (rnd < 10) begin
                if (fwd_mix_columns_out !== APP_C1_FWD_VECS[rnd].after_mix_columns) begin
                    $fatal(1, "[TB ERROR] Appendix C.1 Encrypt Round %0d MixColumns mismatch!", rnd);
                end
                if (fwd_ark_after_mc_out !== APP_C1_FWD_VECS[rnd].next_state) begin
                    $fatal(1, "[TB ERROR] Appendix C.1 Encrypt Round %0d AddRoundKey mismatch!", rnd);
                end
            end else begin
                if (fwd_ark_after_sr_out !== APP_C1_CIPHERTEXT) begin
                    $fatal(1, "[TB ERROR] Appendix C.1 Encrypt Round 10 final output mismatch!");
                end
            end
        end
        $display("[TB] 2. NIST FIPS-197 Appendix C.1 Cipher (Encrypt, Rounds 0..10) verified!");

        //=====================================================================
        // 3. NIST FIPS-197 Appendix C.1: Inverse Cipher (Decrypt, Rounds 0..10)
        //    and Equivalent Inverse Cipher InvMixColumns Vectors
        //=====================================================================
        ark_direct_in  = APP_C1_CIPHERTEXT;
        ark_direct_key = APP_C1_FWD_VECS[10].round_key;
        #1 begin end
        if (ark_direct_out !== APP_C1_INV_VECS[1].istart) begin
            $fatal(1, "[TB ERROR] Appendix C.1 Inverse Cipher Round 0 AddRoundKey mismatch!");
        end
        $display("     [App.C1 Inv  0] iinput          : %032h", APP_C1_CIPHERTEXT);
        $display("     [App.C1 Inv  0] istart[1]       : %032h", ark_direct_out);

        for (int rnd = 1; rnd <= 10; rnd++) begin
            inv_state_in  = APP_C1_INV_VECS[rnd].istart;
            inv_round_key = APP_C1_INV_VECS[rnd].ik_sch;
            #1 begin end

            if (inv_shift_rows_out !== APP_C1_INV_VECS[rnd].is_row) begin
                $fatal(1, "[TB ERROR] Appendix C.1 Inverse Round %0d InvShiftRows mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                       rnd, inv_shift_rows_out, APP_C1_INV_VECS[rnd].is_row);
            end
            if (inv_sub_bytes_out !== APP_C1_INV_VECS[rnd].is_box) begin
                $fatal(1, "[TB ERROR] Appendix C.1 Inverse Round %0d InvSubBytes mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                       rnd, inv_sub_bytes_out, APP_C1_INV_VECS[rnd].is_box);
            end
            if (inv_ark_out !== APP_C1_INV_VECS[rnd].ik_add) begin
                $fatal(1, "[TB ERROR] Appendix C.1 Inverse Round %0d AddRoundKey mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                       rnd, inv_ark_out, APP_C1_INV_VECS[rnd].ik_add);
            end

            if (rnd < 10) begin
                if (inv_mix_columns_out !== APP_C1_INV_VECS[rnd].next_istart) begin
                    $fatal(1, "[TB ERROR] Appendix C.1 Inverse Round %0d InvMixColumns mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                           rnd, inv_mix_columns_out, APP_C1_INV_VECS[rnd].next_istart);
                end

                // Also verify Equivalent Inverse Cipher im_col & dw=InvMixColumns(ik_sch)
                imc_direct_in = APP_C1_INV_VECS[rnd].is_box;
                #1 begin end
                if (imc_direct_out !== APP_C1_INV_VECS[rnd].eq_im_col) begin
                    $fatal(1, "[TB ERROR] Appendix C.1 EqInvCipher Round %0d im_col mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                           rnd, imc_direct_out, APP_C1_INV_VECS[rnd].eq_im_col);
                end

                imc_direct_in = APP_C1_INV_VECS[rnd].ik_sch;
                #1 begin end
                if (imc_direct_out !== APP_C1_INV_VECS[rnd].eq_ik_sch) begin
                    $fatal(1, "[TB ERROR] Appendix C.1 EqInvCipher Round %0d ik_sch mismatch:\n  got: 0x%032h\n  exp: 0x%032h",
                           rnd, imc_direct_out, APP_C1_INV_VECS[rnd].eq_ik_sch);
                end
            end else begin
                if (inv_ark_out !== APP_C1_PLAINTEXT) begin
                    $fatal(1, "[TB ERROR] Appendix C.1 Inverse Round 10 final output mismatch!");
                end
            end

            if (rnd == 1 || rnd == 9 || rnd == 10) begin
                $display("     [App.C1 Inv %2d] istart          : %032h", rnd, inv_state_in);
                $display("     [App.C1 Inv %2d] after InvShRows : %032h", rnd, inv_shift_rows_out);
                $display("     [App.C1 Inv %2d] after InvSubB   : %032h", rnd, inv_sub_bytes_out);
                $display("     [App.C1 Inv %2d] after AddRndKey : %032h", rnd, inv_ark_out);
                if (rnd < 10) begin
                    $display("     [App.C1 Inv %2d] after InvMixCol : %032h", rnd, inv_mix_columns_out);
                end
            end
        end
        $display("[TB] 3. NIST FIPS-197 Appendix C.1 Inverse & Equivalent Inverse Cipher (Rounds 0..10) verified!");

        //=====================================================================
        // 4. Independent GF(2^8) Golden Model, Bijection & Linearity (256 runs)
        //=====================================================================
        prng_a = 128'h01234567_89abcdef_fedcba98_76543210;
        prng_b = 128'h89abcdef_01234567_10325476_98badcfe;

        for (int t = 0; t < 256; t++) begin
            prng_a = {prng_a[126:0], prng_a[127] ^ prng_a[125] ^ prng_a[100] ^ prng_a[98]};
            prng_b = {prng_b[126:0], prng_b[127] ^ prng_b[120] ^ prng_b[85]  ^ prng_b[13]};

            mc_direct_in  = prng_a;
            imc_direct_in = prng_a;
            #1 begin end

            mc_a_save  = mc_direct_out;
            imc_a_save = imc_direct_out;

            // Golden model comparison
            if (mc_direct_out !== golden_mix_columns(prng_a)) begin
                $fatal(1, "[TB ERROR] Random trial %0d MixColumns != GF(2^8) golden model!", t);
            end
            if (imc_direct_out !== golden_inv_mix_columns(prng_a)) begin
                $fatal(1, "[TB ERROR] Random trial %0d InvMixColumns != GF(2^8) golden model!", t);
            end

            // Bijection: InvMixColumns(MixColumns(a)) == a & MixColumns(InvMixColumns(a)) == a
            if (imc_of_mc_out !== prng_a) begin
                $fatal(1, "[TB ERROR] Random trial %0d InvMixColumns(MixColumns(a)) != a!", t);
            end
            if (mc_of_imc_out !== prng_a) begin
                $fatal(1, "[TB ERROR] Random trial %0d MixColumns(InvMixColumns(a)) != a!", t);
            end

            // Linearity check: MixColumns(a ^ b) == MixColumns(a) ^ MixColumns(b)
            mc_direct_in  = prng_b;
            imc_direct_in = prng_b;
            #1 begin end
            mc_b_save  = mc_direct_out;
            imc_b_save = imc_direct_out;

            mc_direct_in  = prng_a ^ prng_b;
            imc_direct_in = prng_a ^ prng_b;
            #1 begin end
            if (mc_direct_out !== (mc_a_save ^ mc_b_save)) begin
                $fatal(1, "[TB ERROR] Random trial %0d MixColumns linearity failed!", t);
            end
            if (imc_direct_out !== (imc_a_save ^ imc_b_save)) begin
                $fatal(1, "[TB ERROR] Random trial %0d InvMixColumns linearity failed!", t);
            end
        end
        $display("[TB] 4. GF(2^8) Golden Model, Bijection, and Linearity verified across 256 random blocks!");

        $display("=========================================================================");
        $display("PASS: MiniSoC AES Week 3 (All Direct & Inverse Round Transformations)");
        $display("      passed 100%% of NIST FIPS-197 Appendix B, Appendix C.1 & GF(2^8)!");
        $display("=========================================================================");
        $finish;
    end

endmodule : tb_minisoc_aes_s3
