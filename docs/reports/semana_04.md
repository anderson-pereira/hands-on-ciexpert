# Relatório da Semana 4 — Expansão de Chave e Datapath AES-128

**Projeto:** Hands-on CIExpert — RTL Design Track (`MiniSoC AES`)  
**Autor:** Anderson Pereira  
**Data:** 13/11/2026  
**Referências:** [DV_BlockGuide_MiniSoCAES_v1.0.0.pdf](../references/DV_BlockGuide_MiniSoCAES_v1.0.0.pdf) | [nist.fips.197.pdf](../references/nist.fips.197.pdf) | [arquitetura_v1.0.md](../architecture/arquitetura_v1.0.md) | [README_AES_DATAPATH_KEYEXP.md](../architecture/README_AES_DATAPATH_KEYEXP.md)

---

## 1. Expansão de Chave AES-128 (`minisoc_aes_key_exp.sv`)

O módulo [`rtl/minisoc_aes/minisoc_aes_key_exp.sv`](../../rtl/minisoc_aes/minisoc_aes_key_exp.sv) implementa o algoritmo `KeyExpansion` da NIST FIPS-197 (Seção 5.2, Figura 11 para $N_k = 4$, $N_r = 10$), gerando e armazenando as 11 *round keys* de 128 bits (`rk_mem[0:10]`, onde `rk_mem[0] = i_key`).

### 1.1 Escolha Arquitetural e Justificativa Técnica: Pré-Computada Iterativa vs. *On-the-Fly*

| Critério | Expansão Desenrolada (Combinacional) | Expansão *On-the-Fly* por Rodada | **Expansão Iterativa Pré-Computada (`rk_mem[0:10]`) — Escolhida** |
| :--- | :--- | :--- | :--- |
| **Instâncias de S-Box** | $40\times$ `minisoc_aes_sbox` | $4\times$ `minisoc_aes_sbox` (+ lógica inversa para decriptação) | **$4\times$ `minisoc_aes_sbox`** (reutilizadas ao longo de 10 ciclos) |
| **Impacto na Decriptação (`InvCipher`)** | Acesso direto a `RoundKey[10..0]`, porém com alto custo de área e caminho crítico de 10 estágios em cascata | **Desfavorável:** Como a decriptação consome as subchaves em **ordem inversa** (`RoundKey[10]` $\to$ `RoundKey[0]`), exige avançar 10 ciclos antes de cada bloco ou duplicar hardware com expansão reversa | **Ideal:** Acesso combinacional imediato (`o_round_key = rk_mem[i_round_idx]`) tanto na ordem direta (`0..10`) quanto na **ordem inversa (`10..0`)** com **0 ciclos de penalidade por bloco** |
| **Operação Multi-Bloco (`1..256` blocos)** | Recomputa ou mantém rede combinacional ativa | Recomputa as 10 subchaves em **todos os blocos** ($256 \times 10 = 2560$ transições de S-Box) | **Calcula uma única vez por comando `START` (10 ciclos)** e congela o expansor (`prev_rk = 0`) durante todos os `1..256` blocos |

### 1.2 Interface e Operação de `minisoc_aes_key_exp`
- **Reset Síncrono (`always_ff @(posedge clk) if (!rst_n)`):** Inicializa `rk_mem[0:10]`, `round_q`, `busy_q`, `done_q` e `valid_q`.
- **Pulso `i_start`:** Captura `rk_mem[0] <= i_key`, posiciona `round_q <= 4'd1`, eleva `o_busy = 1` e limpa `o_valid = 0`.
- **Ciclos `1..10` (`round_q = 1..10`):** A partir de `prev_rk = rk_mem[round_q - 1] = {w0, w1, w2, w3}`, aplica `RotWord(w3)`, `SubWord` (4 instâncias de `minisoc_aes_sbox`), XOR com `{aes_rcon(round_q), 24'h000000}` e calcula `{w0_next, w1_next, w2_next, w3_next}`, gravando `rk_mem[round_q]`. Ao término da rodada 10, baixa `o_busy <= 0` e sinaliza `o_done <= 1` (pulso) e `o_valid <= 1` (nível).
- **Isolamento de Operandos:** Fora do estado `busy_q`, `prev_rk` é forçado a `128'd0`, eliminando consumo dinâmico nas 4 S-Boxes do expansor durante o processamento de dados.

---

## 2. Datapath AES-128 Iterativo (`minisoc_aes_dp.sv`)

O módulo [`rtl/minisoc_aes/minisoc_aes_dp.sv`](../../rtl/minisoc_aes/minisoc_aes_dp.sv) implementa o datapath iterativo de **1 rodada por ciclo** para um bloco de 128 bits, suportando tanto o **Cipher** direto (FIPS-197 Seção 5.1, Figura 5) quanto o **Inverse Cipher** (FIPS-197 Seção 5.3, Figura 12).

### 2.1 Interface de Controle e Temporização (11 Ciclos por Bloco)
- **Ciclo 0 (`i_start = 1`):**
  - Solicita combinacionalmente `o_round_key_idx = i_decrypt ? 4'd10 : 4'd0` ao `minisoc_aes_key_exp`;
  - Executa o `AddRoundKey` inicial (`state_q <= i_block ^ i_round_key`), registra `decrypt_q <= i_decrypt`, inicia `round_q <= 4'd1` e eleva `o_busy <= 1'b1`.
- **Ciclos 1 a 9 (`round_q = 1..9`):**
  - **Cifragem (`decrypt_q = 0`):** Solicita `o_round_key_idx = round_q` (`1..9`) e executa `SubBytes` $\to$ `ShiftRows` $\to$ `MixColumns` $\to$ `AddRoundKey`.
  - **Decriptação (`decrypt_q = 1`):** Solicita `o_round_key_idx = 4'd10 - round_q` (`9..1`) e executa `InvShiftRows` $\to$ `InvSubBytes` $\to$ `AddRoundKey` $\to$ `InvMixColumns`.
- **Ciclo 10 (`round_q = 10`):**
  - **Cifragem (`decrypt_q = 0`):** Solicita `RoundKey[10]` e executa `SubBytes` $\to$ `ShiftRows` $\to$ `AddRoundKey` (com bypass de `MixColumns`).
  - **Decriptação (`decrypt_q = 1`):** Solicita `RoundKey[0]` e executa `InvShiftRows` $\to$ `InvSubBytes` $\to$ `AddRoundKey` (com bypass de `InvMixColumns`).
  - Registra o bloco final em `state_q` (`o_block`), baixa `o_busy <= 1'b0` e gera um pulso de 1 ciclo em `o_done <= 1'b1`.
- **Isolamento de Operandos (*Low-Power QoR*):**
  - `enc_in_state = (busy_q && !decrypt_q) ? state_q : 128'd0` e `dec_in_state = (busy_q && decrypt_q) ? state_q : 128'd0` garantem que o ramo inativo permaneça com entradas estáticas em zero.

---

## 3. Verificação nos Dois Sentidos (`tb/tb_minisoc_aes_s4.sv`)

O testbench autoverificável [`tb/tb_minisoc_aes_s4.sv`](../../tb/tb_minisoc_aes_s4.sv) é compilado e executado via:

```bash
make sim_aes_s4
```

### Resultados Obtidos
1. **Apêndice B / A.1 da FIPS-197 (`key = 2b7e151628aed2a6abf7158809cf4f3c`):**
   - Verificação das 11 *round keys* (`RoundKey[0..10]`) lidas em ordem direta e inversa;
   - Cifragem de `pt = 3243f6a8885a308d313198a2e0370734` conferindo o estado de `state_q` ciclo a ciclo (`Round 0..10`) até `ct = 3925841d02dc09fbdc118597196a0b32`;
   - Decriptação de `ct` reutilizando as subchaves pré-computadas e recuperando exatamente `pt`.
2. **Apêndice C.1 da FIPS-197 (`key = 000102030405060708090a0b0c0d0e0f`):**
   - Verificação das 11 *round keys* (`RoundKey[0..10]`);
   - Cifragem de `pt = 00112233445566778899aabbccddeeff` conferindo todas as rodadas `0..10` até `ct = 69c4e0d86a7b0430d8cdb78070b4c55a`;
   - Decriptação de `ct` conferindo todas as rodadas `0..10` do *Inverse Cipher* até `pt = 00112233445566778899aabbccddeeff`.
3. **Multi-Bloco NIST SP 800-38A F.1.1 (4 blocos ECB-AES128) e 32 Testes Aleatórios ($D_K(E_K(P)) = P$):**
   - **218 verificações executadas, 0 erros** ([`tb/aes_s4_simulation.log`](../../tb/aes_s4_simulation.log)) e **0 warnings / 0 errors** no Synopsys Vlogan com `+lint=all` ([`tb/compile_aes_s4.log`](../../tb/compile_aes_s4.log)).

