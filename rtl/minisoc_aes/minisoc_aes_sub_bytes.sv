//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_aes_sub_bytes
// Description: Purely combinational AES SubBytes transformation (128-bit state)
//              instantiating 16 parallel minisoc_aes_sbox modules (NIST
//              FIPS-197 Section 5.1.1).
//=============================================================================

module minisoc_aes_sub_bytes import minisoc_aes_pkg::*; (
    input  logic [127:0] i_state,
    output logic [127:0] o_state
);

    aes_state_t s_in;
    aes_state_t s_out;

    assign s_in    = aes_state_t'(i_state);
    assign o_state = s_out;

    for (genvar c = 0; c < 4; c++) begin : g_col
        for (genvar r = 0; r < 4; r++) begin : g_row
            minisoc_aes_sbox u_sbox (
                .i_byte (s_in[c][r]),
                .o_byte (s_out[c][r])
            );
        end
    end

endmodule : minisoc_aes_sub_bytes
