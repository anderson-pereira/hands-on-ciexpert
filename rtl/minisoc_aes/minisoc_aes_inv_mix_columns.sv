//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_aes_inv_mix_columns
// Description: Purely combinational AES InvMixColumns transformation on
//              128-bit column-major state (NIST FIPS-197 Section 5.3.3,
//              Eq. 5.10):
//                s'[0,c] = ({0e}*s[0,c]) ^ ({0b}*s[1,c]) ^ ({0d}*s[2,c]) ^ ({09}*s[3,c])
//                s'[1,c] = ({09}*s[0,c]) ^ ({0e}*s[1,c]) ^ ({0b}*s[2,c]) ^ ({0d}*s[3,c])
//                s'[2,c] = ({0d}*s[0,c]) ^ ({09}*s[1,c]) ^ ({0e}*s[2,c]) ^ ({0b}*s[3,c])
//                s'[3,c] = ({0b}*s[0,c]) ^ ({0d}*s[1,c]) ^ ({09}*s[2,c]) ^ ({0e}*s[3,c])
//=============================================================================

module minisoc_aes_inv_mix_columns import minisoc_aes_pkg::*; (
    input  aes_block_t i_state,
    output aes_block_t o_state
);

    aes_state_t s_in;
    aes_state_t s_out;

    assign s_in    = aes_state_t'(i_state);
    assign o_state = s_out;

    for (genvar c = 0; c < 4; c++) begin : g_col
        always_comb begin
            s_out[c][0] = aes_gf_mul14(s_in[c][0]) ^ aes_gf_mul11(s_in[c][1]) ^ aes_gf_mul13(s_in[c][2]) ^ aes_gf_mul9(s_in[c][3]);
            s_out[c][1] = aes_gf_mul9(s_in[c][0])  ^ aes_gf_mul14(s_in[c][1]) ^ aes_gf_mul11(s_in[c][2]) ^ aes_gf_mul13(s_in[c][3]);
            s_out[c][2] = aes_gf_mul13(s_in[c][0]) ^ aes_gf_mul9(s_in[c][1])  ^ aes_gf_mul14(s_in[c][2]) ^ aes_gf_mul11(s_in[c][3]);
            s_out[c][3] = aes_gf_mul11(s_in[c][0]) ^ aes_gf_mul13(s_in[c][1]) ^ aes_gf_mul9(s_in[c][2])  ^ aes_gf_mul14(s_in[c][3]);
        end
    end

endmodule : minisoc_aes_inv_mix_columns

