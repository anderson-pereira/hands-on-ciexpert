//=============================================================================
// Project:     MiniSoC AES — RTL Design Track
// Interfaces:  minisoc_aes_key_exp_if, minisoc_aes_dp_if
// Description: SystemVerilog interfaces and modports connecting the AES-128
//              block controller (minisoc_aes_top), iterative key expansion
//              unit (minisoc_aes_key_exp), and bidirectional 128-bit datapath
//              (minisoc_aes_dp).
//=============================================================================

//-----------------------------------------------------------------------------
// 1. Key Expansion Control & Round-Key Readback Interface (sys_clk domain)
//-----------------------------------------------------------------------------
interface minisoc_aes_key_exp_if;
    import minisoc_aes_pkg::*;

    logic       start;     // 1-cycle pulse to load key and start 10-cycle expansion
    aes_key_t   key;       // 128-bit input cipher key (RoundKey[0])
    aes_round_t round_idx; // Requested round key index (0..10)
    aes_key_t   round_key; // Combinational 128-bit round key output (rk_mem[round_idx])
    logic       busy;      // High during cycles 1..10 of key expansion
    logic       done;      // 1-cycle completion pulse at the end of Round 10
    logic       valid;     // Sticky high once all 11 round keys are valid in rk_mem

    modport key_exp (
        input  start,
        input  key,
        input  round_idx,
        output round_key,
        output busy,
        output done,
        output valid
    );

    modport ctrl (
        output start,
        output key,
        output round_idx,
        input  round_key,
        input  busy,
        input  done,
        input  valid
    );
endinterface : minisoc_aes_key_exp_if


//-----------------------------------------------------------------------------
// 2. AES-128 Single-Block Datapath Interface (sys_clk domain)
//-----------------------------------------------------------------------------
interface minisoc_aes_dp_if;
    import minisoc_aes_pkg::*;

    logic       start;         // 1-cycle pulse to execute Round 0 and start Rounds 1..10
    logic       decrypt;       // 0 = Forward Cipher (E_K), 1 = Inverse Cipher (D_K)
    aes_block_t block_in;      // 128-bit input block (plaintext or ciphertext)
    aes_key_t   round_key;     // 128-bit active round key from minisoc_aes_key_exp
    aes_round_t round_key_idx; // Active round key index (0..10 or 10..0) requested by DP
    aes_block_t block_out;     // 128-bit processed output block (valid when done=1)
    logic       busy;          // High during Rounds 1..10
    logic       done;          // 1-cycle completion pulse at the end of Round 10

    modport dp (
        input  start,
        input  decrypt,
        input  block_in,
        input  round_key,
        output round_key_idx,
        output block_out,
        output busy,
        output done
    );

    modport ctrl (
        output start,
        output decrypt,
        output block_in,
        output round_key,
        input  round_key_idx,
        input  block_out,
        input  busy,
        input  done
    );
endinterface : minisoc_aes_dp_if

