//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_aes_inv_shift_rows
// Description: Purely combinational AES InvShiftRows wire permutation on
//              128-bit column-major state (NIST FIPS-197 Section 5.3.1):
//                s'[r, (c + r) mod 4] = s[r, c]
//                <==> s'[r, c] = s[r, (c + 4 - r) mod 4]
//              With column-major aes_state_t (state[c][r] == s[r, c]):
//                s_out[c][r] = s_in[(c + 4 - r) mod 4][r]
//=============================================================================

module minisoc_aes_inv_shift_rows import minisoc_aes_pkg::*; (
    input  logic [127:0] i_state,
    output logic [127:0] o_state
);

    aes_state_t s_in;
    aes_state_t s_out;

    assign s_in    = aes_state_t'(i_state);
    assign o_state = s_out;

    for (genvar c = 0; c < 4; c++) begin : g_col
        assign s_out[c][0] = s_in[c][0];
        assign s_out[c][1] = s_in[(c + 3) % 4][1];
        assign s_out[c][2] = s_in[(c + 2) % 4][2];
        assign s_out[c][3] = s_in[(c + 1) % 4][3];
    end

endmodule : minisoc_aes_inv_shift_rows
