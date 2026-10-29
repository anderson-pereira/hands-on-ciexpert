# Relatório da Semana 2 — Desafio: `SubBytes` e `ShiftRows`

**Projeto:** Hands-on CIExpert — RTL Design Track (`MiniSoC AES`)  
**Autor:** Anderson Pereira  
**Data:** 29/10/2026  
**Referências:** [DV_BlockGuide_MiniSoCAES_v1.0.0.pdf](../references/DV_BlockGuide_MiniSoCAES_v1.0.0.pdf) | [nist.fips.197.pdf](../references/nist.fips.197.pdf)

---

## 1. Resumo da Implementação RTL (`rtl/minisoc_aes/`)

Foram implementadas as transformações puramente combinacionais de substituição não-linear e permutação de linhas do AES-128 (incluindo o escopo opcional das transformações inversas para o *Inverse Cipher*), preparadas para integração direta no `minisoc_aes_dp` a partir da Semana 3 e para a meta física de fechamento de *timing* a **2.0 GHz** no PDK **SAED 32nm**:

| Arquivo | Módulo / Pacote | Descrição |
| :--- | :--- | :--- |
| [`rtl/minisoc_aes/minisoc_aes_pkg.sv`](../../rtl/minisoc_aes/minisoc_aes_pkg.sv) | `minisoc_aes_pkg` | Define `aes_state_t` (`logic [0:3][0:3][7:0]`, *column-major*) e a função `aes_get_byte(state, r, c)`. |
| [`rtl/minisoc_aes/minisoc_aes_sbox.sv`](../../rtl/minisoc_aes/minisoc_aes_sbox.sv) | `minisoc_aes_sbox` | LUT combinacional (`8b -> 8b`) com as 256 entradas da Figura 7 da FIPS-197 (menor profundidade lógica para `500 ps`). |
| [`rtl/minisoc_aes/minisoc_aes_sub_bytes.sv`](../../rtl/minisoc_aes/minisoc_aes_sub_bytes.sv) | `minisoc_aes_sub_bytes` | Transformação de estado (`128b -> 128b`) com 16 instâncias paralelas de `minisoc_aes_sbox`. |
| [`rtl/minisoc_aes/minisoc_aes_shift_rows.sv`](../../rtl/minisoc_aes/minisoc_aes_shift_rows.sv) | `minisoc_aes_shift_rows` | Permutação puramente por reordenação de fios ($s'_{r,c} = s_{r,(c+r)\bmod 4}$). |
| [`rtl/minisoc_aes/minisoc_aes_inv_sbox.sv`](../../rtl/minisoc_aes/minisoc_aes_inv_sbox.sv) | `minisoc_aes_inv_sbox` | *(Opcional)* LUT combinacional inversa (`8b -> 8b`) da Figura 14 da FIPS-197. |
| [`rtl/minisoc_aes/minisoc_aes_inv_sub_bytes.sv`](../../rtl/minisoc_aes/minisoc_aes_inv_sub_bytes.sv) | `minisoc_aes_inv_sub_bytes` | *(Opcional)* Transformação inversa (`128b -> 128b`) com 16 instâncias de `minisoc_aes_inv_sbox`. |
| [`rtl/minisoc_aes/minisoc_aes_inv_shift_rows.sv`](../../rtl/minisoc_aes/minisoc_aes_inv_shift_rows.sv) | `minisoc_aes_inv_shift_rows` | *(Opcional)* Permutação inversa por fios ($s'_{r,c} = s_{r,(c+4-r)\bmod 4}$). |

### Convenção do Estado de 128 bits
Seguindo a Seção 3.4 da FIPS-197 e a Seção 7.1 do Block Guide:
- `Byte 0` ocupa `[127:120]` e `Byte 15` ocupa `[7:0]` (`Word 0 = [127:96]`, ..., `Word 3 = [31:0]`);
- O `byte n` (`0..15`) mapeia em $s[r][c]$ com $r = n \bmod 4$ e $c = \lfloor n / 4 \rfloor$;
- No tipo empacotado `aes_state_t` (`logic [0:3][0:3][7:0]`), o índice externo endereça a coluna `c` e o índice interno endereça a linha `r` (`state[c][r] == s[r, c]`).

---

## 2. Verificação e Resultados dos Testes (`tb/tb_minisoc_aes_s2.sv`)

O testbench autoverificável [`tb/tb_minisoc_aes_s2.sv`](../../tb/tb_minisoc_aes_s2.sv) é compilado com `vlogan +lint=all` (**0 erros e 0 avisos de lint**) e executado por um único comando:

```bash
make sim_aes_s2
```

### Escopo Validado e Resultado no Synopsys VCS (`X-2025.06-SP2_Full64`)
1. **Varredura exaustiva da S-box e InvS-box (`256` entradas `0x00..0xFF`):** Comparada simultaneamente contra uma tabela de referência explícita e contra um modelo algébrico independente em $\text{GF}(2^8)$ ($x^{254} \bmod \text{0x11B}$ + transformação afim), além da bijeção `InvSbox(Sbox(x)) == x` e `Sbox(InvSbox(x)) == x`.
2. **Convenção de fatiamento do estado (`Byte 0 = [127:120]` a `Byte 15 = [7:0]`):** Verificada nos 16 bytes contra `aes_get_byte(state, r, c)`.
3. **Exemplo de cifragem da FIPS-197 — Apêndice B (todas as Rodadas `1..10`):** Verificada a cadeia `Start of Round -> After SubBytes -> After ShiftRows` nas 10 rodadas.
4. **Transformações inversas opcionais:** Verificadas nas 10 rodadas do *Inverse Cipher* do **Apêndice C.1** da FIPS-197 (`istart -> InvShiftRows -> InvSubBytes`) e em 256 blocos pseudoaleatórios de 128 bits (`InvSubBytes(SubBytes(x)) == x` e `InvShiftRows(ShiftRows(x)) == x`).

```text
     -> sbox(8'h00) = 8'h63 (expected 8'h63)
     -> sbox(8'h53) = 8'hed (expected 8'hed)
[TB] 1. S-box & InvS-box verified across all 256 inputs (Table + GF(2^8) + Bijection)!
[TB] 2. Column-major 128-bit state convention (Byte 0=[127:120], s[r][c]) verified!
     [Round  1] start of round  : 193de3bea0f4e22b9ac68d2ae9f84808
     [Round  1] after SubBytes  : d42711aee0bf98f1b8b45de51e415230
     [Round  1] after ShiftRows : d4bf5d30e0b452aeb84111f11e2798e5
     [Round 10] start of round  : eb40f21e592e38848ba113e71bc342d2
     [Round 10] after SubBytes  : e9098972cb31075f3d327d94af2e2cb5
     [Round 10] after ShiftRows : e9317db5cb322c723d2e895faf090794
[TB] 3. NIST FIPS-197 Appendix B Rounds 1..10 (SubBytes -> ShiftRows) verified!
[TB] 4. InvShiftRows & InvSubBytes verified (Appendix C.1 Rounds 1..10 + 256 random blocks)!
===================================================================
PASS: MiniSoC AES Week 2 (S-box, SubBytes, ShiftRows & Inverses)
      passed 100% of exhaustive and NIST FIPS-197 checks!
===================================================================
```

---

## 3. Dúvidas e Ambiguidades Levantadas no Block Guide (Seções 1–3 e 8)

Como a norma **NIST FIPS-197** especifica apenas o primitivo de bloco AES (remetendo os modos de operação à *NIST SP 800-38A*, enquanto o PCBC origina-se do protocolo Kerberos v4), foram identificadas as seguintes dúvidas/ambiguidades nas Seções 1 a 3 e 8 do [`DV_BlockGuide_MiniSoCAES_v1.0.0.pdf`](../references/DV_BlockGuide_MiniSoCAES_v1.0.0.pdf) para alinhamento com a equipe de *Design Verification*:

1. **Comportamento conjunto de `ERROR`, `DONE` e `BLOCKS_DONE` em configuração inválida (Seções 8.2 e 8.4):**
   - Quando um `START` é disparado com `NUM_BLOCKS == 0`, `NUM_BLOCKS > 256` ou `MODE` reservado (`3'b110`, `3'b111`), o sinal `DONE` deve permanecer em `0` ou também deve subir para `1` junto com `ERROR = 1`? *(Observação: no Passo 12 da Seção 9 lê-se "Ler AES_STATUS até DONE=1; ERROR deve permanecer 0"; se `DONE` permanecer `0` em caso de erro, rotinas que façam polling apenas em `DONE` ficariam presas).* Além disso, confirma-se que `ERROR` é *sticky* até o próximo `START` aceito e que um `START` inválido zera `BLOCKS_DONE`?
2. **Modo `CTR` — Alinhamento da extensão com zeros e *wrap-around* do contador (Seção 8.2):**
   - A especificação descreve *"IV XOR contador de 64 bits zero-extendido; contador é incrementado por bloco"*. Confirma-se que os zeros ocupam os **64 MSBs** (`IV ^ {64'd0, cnt[63:0]}`) e que o incremento ocorre módulo $2^{64}$ (`cnt + 64'd1`, sem propagar *carry* para o bit 64 caso `cnt == 64'hFFFF_FFFF_FFFF_FFFF`)?
3. **Modo `CFB` — Largura do segmento e papel do bit `DECRYPT` (Seções 8.2 e 6.1):**
   - Confirma-se que o modo implementado é **CFB-128** (realimentação de bloco completo de 128 bits a cada 4 palavras lidas/escritas)? Além disso, embora o CFB utilize sempre o primitivo *AES encrypt* ($E_K$), confirma-se que o bit `DECRYPT` seleciona a fonte do encadeamento ($V_{i+1} = C_i$ calculado quando `DECRYPT = 0` vs. bloco cifrado de entrada lido da memória quando `DECRYPT = 1`), enquanto em `OFB` e `CTR` o campo `DECRYPT` é ignorado (*don't care*)?
4. **Modo `PCBC` — Equação formal de encadeamento (Seção 8.2):**
   - Como o PCBC não faz parte das normas NIST, confirma-se a equação clássica com $V_0 = \text{IV}$ e $V_{i+1} = P_i \oplus C_i$ (onde $C_i = E_K(P_i \oplus V_i)$ na criptografia e $P_i = D_K(C_i) \oplus V_i$ na decriptação)?
5. **Proteção contra `START` concorrente ou sem posse da memória (Seções 2.1, 8.3 e 8.4):**
   - Um pulso `START` enviado enquanto `BUSY == 1` deve ser ignorado silenciosamente sem alterar a operação em curso? E caso `START` seja emitido com `MEM_SEL_AES == 0` (memória ainda sob posse da interface externa `MEMORY DATA`), o engine deve sinalizar `ERROR = 1` ou assume-se que a exclusão mútua é garantida pelo protocolo de software?
6. **Liberdade de ciclos por rodada frente à meta física de `2.0 GHz` (Seções 1.2, 3 e 8.1):**
   - Como a referência `clk` é de `2.0 GHz` (`T = 500 ps` no divisor `/1` em SAED 32nm) e a Seção 8 não fixa um número rígido de ciclos de `sys_clk` por bloco, confirma-se que o modelo de referência do DV sincroniza pelo sinal `DONE`/`BUSY` (permitindo pipelining interno de meia-rodada no `minisoc_aes_dp`, se necessário para fechar STA a `2 GHz`)?

