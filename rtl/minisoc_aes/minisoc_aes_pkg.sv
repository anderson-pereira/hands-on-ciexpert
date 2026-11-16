//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Package:     minisoc_aes_pkg
// Description: Common types, structured packed views, state-indexing helpers,
//              round constants, and GF(2^8) finite-field arithmetic functions
//              for the AES-128 block cipher datapath and key expander
//              (NIST FIPS PUB 197, Sections 3.4, 4.2, 5.1, 5.2, 5.3 &
//              DV_BlockGuide_MiniSoCAES_v1.0.0 Section 7.1).
//
// State & Word Bit-Ordering Convention (128-bit vector):
//   - Byte 0 is [127:120], ..., Byte 15 is [7:0].
//   - Word 0 (Column 0) is [127:96], ..., Word 3 (Column 3) is [31:0].
//   - Byte n (0..15) maps to FIPS-197 s[r][c] with r = n mod 4, c = n div 4.
//   - Consequently, in the 2D packed type aes_state_t, the outer dimension
//     indexes the column c (0..3) and the inner dimension indexes row r (0..3):
//       state_mat[c][r] <==> FIPS-197 s[r, c]
//=============================================================================

package minisoc_aes_pkg;

    //-------------------------------------------------------------------------
    // 1. Fundamental AES-128 Constants & Semantic Data Types
    //-------------------------------------------------------------------------
    localparam logic [3:0]  AES_NUM_ROUNDS = 4'd10;
    localparam int unsigned AES_NUM_RKEYS  = 11; // RoundKey[0..10]

    typedef logic [7:0]   aes_byte_t;    // Single byte in GF(2^8)
    typedef logic [31:0]  aes_word_t;    // 32-bit word (1 column / 1 key word)
    typedef logic [127:0] aes_block_t;   // 128-bit plaintext / ciphertext / state
    typedef logic [127:0] aes_key_t;     // 128-bit cipher key / round key
    typedef logic [63:0]  aes_counter_t; // 64-bit CTR mode block counter
    typedef logic [3:0]   aes_round_t;   // Round index (0..10)

    //-------------------------------------------------------------------------
    // 2. Structured Packed Views (Eliminates manual bit-slice indexing)
    //-------------------------------------------------------------------------
    // 32-bit word viewed as 4 big-endian bytes: w_bytes[0] = [31:24] .. w_bytes[3] = [7:0]
    typedef aes_byte_t [0:3] aes_word_bytes_t;

    // 128-bit block/key viewed as 4 32-bit words: words[0] = [127:96] .. words[3] = [31:0]
    typedef aes_word_t [0:3] aes_words128_t;

    // Column-major 4x4 byte matrix: state[c][r] == byte (4*c + r) <==> FIPS-197 s[r, c]
    typedef aes_byte_t [0:3][0:3] aes_state_t;

    // Extract byte s[r, c] using mathematical FIPS-197 (row, col) order
    function automatic aes_byte_t aes_get_byte(
        input aes_block_t state,
        input logic [1:0] r,
        input logic [1:0] c
    );
        aes_state_t mat;
        begin
            mat          = aes_state_t'(state);
            aes_get_byte = mat[c][r];
        end
    endfunction

    //-------------------------------------------------------------------------
    // 3. GF(2^8) Multiplication Helpers modulo m(x) = x^8 + x^4 + x^3 + x + 1
    //    Irreducible polynomial reduction byte: 8'h1b (FIPS-197 Section 4.2.1)
    //-------------------------------------------------------------------------

    // Multiply by {02} (xtime) in GF(2^8)
    function automatic aes_byte_t aes_xtime(input aes_byte_t b);
        begin
            aes_xtime = {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
        end
    endfunction

    // Multiply by {03} = {02} ^ {01} in GF(2^8)
    function automatic aes_byte_t aes_gf_mul3(input aes_byte_t b);
        begin
            aes_gf_mul3 = aes_xtime(b) ^ b;
        end
    endfunction

    // Multiply by {09} = {08} ^ {01} in GF(2^8)
    function automatic aes_byte_t aes_gf_mul9(input aes_byte_t b);
        aes_byte_t x2, x4, x8;
        begin
            x2          = aes_xtime(b);
            x4          = aes_xtime(x2);
            x8          = aes_xtime(x4);
            aes_gf_mul9 = x8 ^ b;
        end
    endfunction

    // Multiply by {0b} = {08} ^ {02} ^ {01} in GF(2^8)
    function automatic aes_byte_t aes_gf_mul11(input aes_byte_t b);
        aes_byte_t x2, x4, x8;
        begin
            x2           = aes_xtime(b);
            x4           = aes_xtime(x2);
            x8           = aes_xtime(x4);
            aes_gf_mul11 = x8 ^ x2 ^ b;
        end
    endfunction

    // Multiply by {0d} = {08} ^ {04} ^ {01} in GF(2^8)
    function automatic aes_byte_t aes_gf_mul13(input aes_byte_t b);
        aes_byte_t x2, x4, x8;
        begin
            x2           = aes_xtime(b);
            x4           = aes_xtime(x2);
            x8           = aes_xtime(x4);
            aes_gf_mul13 = x8 ^ x4 ^ b;
        end
    endfunction

    // Multiply by {0e} = {08} ^ {04} ^ {02} in GF(2^8)
    function automatic aes_byte_t aes_gf_mul14(input aes_byte_t b);
        aes_byte_t x2, x4, x8;
        begin
            x2           = aes_xtime(b);
            x4           = aes_xtime(x2);
            x8           = aes_xtime(x4);
            aes_gf_mul14 = x8 ^ x4 ^ x2;
        end
    endfunction

    //-------------------------------------------------------------------------
    // 4. AES-128 Key Expansion Round Constants Rcon[1..10] (FIPS-197 Sec. 5.2)
    //-------------------------------------------------------------------------
    function automatic aes_byte_t aes_rcon(input aes_round_t round);
        begin
            unique case (round)
                4'd1:    aes_rcon = 8'h01;
                4'd2:    aes_rcon = 8'h02;
                4'd3:    aes_rcon = 8'h04;
                4'd4:    aes_rcon = 8'h08;
                4'd5:    aes_rcon = 8'h10;
                4'd6:    aes_rcon = 8'h20;
                4'd7:    aes_rcon = 8'h40;
                4'd8:    aes_rcon = 8'h80;
                4'd9:    aes_rcon = 8'h1b;
                4'd10:   aes_rcon = 8'h36;
                default: aes_rcon = 8'h00;
            endcase
        end
    endfunction

endpackage : minisoc_aes_pkg
