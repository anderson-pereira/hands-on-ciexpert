//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_aes_mix_columns
// Description: Purely combinational AES MixColumns transformation on 128-bit
//              column-major state (NIST FIPS-197 Section 5.1.3, Eq. 5.6):
//                s'[0,c] = ({02} * s[0,c]) ^ ({03} * s[1,c]) ^ s[2,c] ^ s[3,c]
//                s'[1,c] = s[0,c] ^ ({02} * s[1,c]) ^ ({03} * s[2,c]) ^ s[3,c]
//                s'[2,c] = s[0,c] ^ s[1,c] ^ ({02} * s[2,c]) ^ ({03} * s[3,c])
//                s'[3,c] = ({03} * s[0,c]) ^ s[1,c] ^ s[2,c] ^ ({02} * s[3,c])
//=============================================================================

module minisoc_aes_mix_columns import minisoc_aes_pkg::*; (
    input  logic [127:0] i_state,
    output logic [127:0] o_state
);

    aes_state_t s_in;
    aes_state_t s_out;

    assign s_in    = aes_state_t'(i_state);
    assign o_state = s_out;

    for (genvar c = 0; c < 4; c++) begin : g_col
        always_comb begin
            s_out[c][0] = aes_xtime(s_in[c][0]) ^ aes_gf_mul3(s_in[c][1]) ^ s_in[c][2]            ^ s_in[c][3];
            s_out[c][1] = s_in[c][0]            ^ aes_xtime(s_in[c][1])   ^ aes_gf_mul3(s_in[c][2]) ^ s_in[c][3];
            s_out[c][2] = s_in[c][0]            ^ s_in[c][1]              ^ aes_xtime(s_in[c][2])   ^ aes_gf_mul3(s_in[c][3]);
            s_out[c][3] = aes_gf_mul3(s_in[c][0]) ^ s_in[c][1]            ^ s_in[c][2]              ^ aes_xtime(s_in[c][3]);
        end
    end

endmodule : minisoc_aes_mix_columns

