//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_aes_add_round_key
// Description: Purely combinational AES AddRoundKey transformation on 128-bit
//              column-major state (NIST FIPS-197 Section 5.1.4 & 5.3.4,
//              Eq. 5.7). AddRoundKey is its own inverse:
//                o_state = i_state ^ i_round_key
//=============================================================================

module minisoc_aes_add_round_key (
    input  logic [127:0] i_state,
    input  logic [127:0] i_round_key,
    output logic [127:0] o_state
);

    assign o_state = i_state ^ i_round_key;

endmodule : minisoc_aes_add_round_key

