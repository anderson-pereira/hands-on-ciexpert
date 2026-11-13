# Relatório da Semana 3 — Microarquitetura e Transformações de Rodada (Diretas e Inversas)

**Projeto:** Hands-on CIExpert — RTL Design Track (`MiniSoC AES`)  
**Autor:** Anderson Pereira  
**Data:** 06/11/2026  
**Referências:** [DV_BlockGuide_MiniSoCAES_v1.0.0.pdf](../references/DV_BlockGuide_MiniSoCAES_v1.0.0.pdf) | [nist.fips.197.pdf](../references/nist.fips.197.pdf) | [arquitetura_v1.0.md](../architecture/arquitetura_v1.0.md)

---

## 1. Documento de Microarquitetura v1.0 ([`docs/architecture/arquitetura_v1.0.md`](../architecture/arquitetura_v1.0.md))

O documento de microarquitetura foi consolidado cobrindo todos os aspectos de implementação interna do `MiniSoC AES`:
1. **Diagrama de blocos interno** detalhando `minisoc_top`, `minisoc_spi` (`phy`, `cdc`, `csr`), `minisoc_pll_mock`, `minisoc_aes_top` (`dp`, `key_exp`), o multiplexador de propriedade da memória (`MEM_SEL_AES`) e a SRAM `minisoc_memory` ($1024 \times 32$ bits).
2. **Microarquitetura do AES (`minisoc_aes_dp.sv`)**: escolha e justificativa técnica da **arquitetura iterativa de 1 rodada por ciclo de `sys_clk`** (11 ciclos/bloco no datapath), frente à interface single-port de 32 bits da memória compartilhada e às metas de área, potência e fechamento de *timing* no PDK **Synopsys SAED 32nm**.
3. **Máquina de estados (FSM) do `minisoc_aes_top.sv`**: diagrama de estados e tabela de transições (`ST_IDLE`, `ST_ERR`, `ST_KEY_EXP`, `ST_RD_REQ`/`ST_RD_CAP`, `ST_BLK_PREP`, `ST_AES_RUN`, `ST_BLK_POST`, `ST_WR_WORD`, `ST_NEXT_BLK`, `ST_DONE`), cobrindo a leitura de 4 palavras, o encadeamento dos 6 modos (`ECB`, `CBC`, `PCBC`, `CFB`, `OFB`, `CTR`), a escrita *in-place* e a sinalização de `BUSY`, `DONE`, `ERROR` e `BLOCKS_DONE`.
4. **Estratégia de CDC (Seção 5.3)**: sincronização por inversão de nível (*toggle*) + *Data-Hold* de 40 bits entre `spi_sclk` ($\le 25\text{ MHz}$) e `clk` (`2 GHz` always-on), além da travessia de `START` e sinais de status entre `clk` e `sys_clk` (`/1, /2, /4, /8`).
5. **Sequência de reset do domínio do sistema (Seção 4.2)**: adoção de **reset síncrono** em todos os domínios com clock ativo para maximizar QoR no Design Compiler, mantendo `sys_rst_n = 0` enquanto `!rst_n || !pll_locked` e liberando-o após 4 ciclos ativos de `sys_clk` pós-lock.

---

## 2. Implementação RTL Completa das Transformações de Rodada (`rtl/minisoc_aes/`)

Todas as transformações de rodada diretas (*Cipher*) e inversas (*Inverse Cipher*, necessárias à decriptação nos modos `ECB`, `CBC` e `PCBC`) encontram-se implementadas em SystemVerilog sintetizável:

| Arquivo | Módulo / Pacote | Seção FIPS-197 | Descrição Funcional |
| :--- | :--- | :---: | :--- |
| [`rtl/minisoc_aes/minisoc_aes_pkg.sv`](../../rtl/minisoc_aes/minisoc_aes_pkg.sv) | `minisoc_aes_pkg` | Seções 3.4 e 4.2 | Tipo `aes_state_t` (*column-major*) e funções em $\text{GF}(2^8)$: `aes_xtime` (`{02}`), `aes_gf_mul3` (`{03}`), `aes_gf_mul9` (`{09}`), `aes_gf_mul11` (`{0b}`), `aes_gf_mul13` (`{0d}`) e `aes_gf_mul14` (`{0e}`). |
| [`rtl/minisoc_aes/minisoc_aes_sbox.sv`](../../rtl/minisoc_aes/minisoc_aes_sbox.sv) | `minisoc_aes_sbox` | Seção 5.1.1 (Fig. 7) | S-Box combinacional (`8b -> 8b`). |
| [`rtl/minisoc_aes/minisoc_aes_inv_sbox.sv`](../../rtl/minisoc_aes/minisoc_aes_inv_sbox.sv) | `minisoc_aes_inv_sbox` | Seção 5.3.2 (Fig. 14) | Inverse S-Box combinacional (`8b -> 8b`). |
| [`rtl/minisoc_aes/minisoc_aes_sub_bytes.sv`](../../rtl/minisoc_aes/minisoc_aes_sub_bytes.sv) | `minisoc_aes_sub_bytes` | Seção 5.1.1 | `SubBytes` (`128b -> 128b`, 16 instâncias de `minisoc_aes_sbox`). |
| [`rtl/minisoc_aes/minisoc_aes_inv_sub_bytes.sv`](../../rtl/minisoc_aes/minisoc_aes_inv_sub_bytes.sv) | `minisoc_aes_inv_sub_bytes` | Seção 5.3.2 | `InvSubBytes` (`128b -> 128b`, 16 instâncias de `minisoc_aes_inv_sbox`). |
| [`rtl/minisoc_aes/minisoc_aes_shift_rows.sv`](../../rtl/minisoc_aes/minisoc_aes_shift_rows.sv) | `minisoc_aes_shift_rows` | Seção 5.1.2 (Eq. 5.3) | `ShiftRows` por permutação pura de fios ($s'_{r,c} = s_{r,(c+r)\bmod 4}$). |
| [`rtl/minisoc_aes/minisoc_aes_inv_shift_rows.sv`](../../rtl/minisoc_aes/minisoc_aes_inv_shift_rows.sv) | `minisoc_aes_inv_shift_rows` | Seção 5.3.1 (Eq. 5.8) | `InvShiftRows` por permutação pura de fios ($s'_{r,c} = s_{r,(c+4-r)\bmod 4}$). |
| [`rtl/minisoc_aes/minisoc_aes_mix_columns.sv`](../../rtl/minisoc_aes/minisoc_aes_mix_columns.sv) | `minisoc_aes_mix_columns` | Seção 5.1.3 (Eq. 5.6) | `MixColumns` combinacional nas 4 colunas pela matriz circulante $\{02, 03, 01, 01\}$ sobre $\text{GF}(2^8)$. |
| [`rtl/minisoc_aes/minisoc_aes_inv_mix_columns.sv`](../../rtl/minisoc_aes/minisoc_aes_inv_mix_columns.sv) | `minisoc_aes_inv_mix_columns` | Seção 5.3.3 (Eq. 5.10) | `InvMixColumns` combinacional nas 4 colunas pela matriz inversa $\{0\text{e}, 0\text{b}, 0\text{d}, 09\}$ sobre $\text{GF}(2^8)$. |
| [`rtl/minisoc_aes/minisoc_aes_add_round_key.sv`](../../rtl/minisoc_aes/minisoc_aes_add_round_key.sv) | `minisoc_aes_add_round_key` | Seções 5.1.4 e 5.3.4 | `AddRoundKey` (`o_state = i_state ^ i_round_key`, autoinversa). |

---

## 3. Verificação Unitária com Vetores da FIPS-197 (`tb/tb_minisoc_aes_s3.sv`)

O testbench autoverificável [`tb/tb_minisoc_aes_s3.sv`](../../tb/tb_minisoc_aes_s3.sv) é executado via:

```bash
make sim_aes_s3
```

### Escopo Validado
1. **NIST FIPS-197 — Apêndice B (Exemplo de Cifragem, Rodadas `0..10`):**
   - Verifica o `AddRoundKey` inicial (Round 0) e todos os estados intermediários (`start_of_round`, `after_sub_bytes`, `after_shift_rows`, `after_mix_columns`, `after_add_round_key`) ao longo das 10 rodadas até o ciphertext `3925841d_02dc09fb_dc118597_196a0b32`, seguido da recuperação completa do plaintext pelo caminho inverso.
2. **NIST FIPS-197 — Apêndice C.1 (`AES-128`, Cifragem, Cifragem Inversa e *Equivalent Inverse Cipher*, Rodadas `0..10`):**
   - Verifica todas as 10 rodadas da cifragem direta (`s_box`, `s_row`, `m_col`, `k_sch`, `output = 69c4e0d8_6a7b0430_d8cdb780_70b4c55a`);
   - Verifica todas as 10 rodadas do *Inverse Cipher* (`istart` $\xrightarrow{\text{InvShiftRows}}$ `is_row` $\xrightarrow{\text{InvSubBytes}}$ `is_box` $\xrightarrow{\text{AddRoundKey}}$ `ik_add` $\xrightarrow{\text{InvMixColumns}}$ `istart[r+1]` até `ioutput = 00112233_44556677_8899aabb_ccddeeff`);
   - Verifica ainda os vetores `im_col` e `ik_sch` transformados por `InvMixColumns` do *Equivalent Inverse Cipher* do Apêndice C.1.
3. **Modelo de Referência Polinomial em $\text{GF}(2^8)$, Bijeção e Linearidade (`256` blocos aleatórios):**
   - Confirma $\text{InvMixColumns}(\text{MixColumns}(x)) = x$, $\text{MixColumns}(\text{InvMixColumns}(x)) = x$ e a linearidade $\text{MixColumns}(a \oplus b) = \text{MixColumns}(a) \oplus \text{MixColumns}(b)$ e $\text{InvMixColumns}(a \oplus b) = \text{InvMixColumns}(a) \oplus \text{InvMixColumns}(b)$.

