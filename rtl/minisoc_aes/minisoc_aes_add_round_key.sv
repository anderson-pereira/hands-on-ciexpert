//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Module:      minisoc_aes_add_round_key
// Description: Purely combinational AES AddRoundKey transformation on 128-bit
//              column-major state (NIST FIPS-197 Section 5.1.4 & 5.3.4,
//              Eq. 5.7). AddRoundKey is its own inverse:
//                o_state = i_state ^ i_round_key
//=============================================================================

module minisoc_aes_add_round_key import minisoc_aes_pkg::*; (
    input  aes_block_t i_state,
    input  aes_key_t   i_round_key,
    output aes_block_t o_state
);

    assign o_state = i_state ^ i_round_key;

endmodule : minisoc_aes_add_round_key

