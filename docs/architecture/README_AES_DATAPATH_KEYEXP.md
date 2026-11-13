# Guia Arquitetural e Investigativo — Datapath AES-128 (`minisoc_aes_dp`) e Expansão de Chaves (`minisoc_aes_key_exp`)

**Projeto:** Hands-on CIExpert — RTL Design Track (`MiniSoC AES`)  
**Autor:** Anderson Pereira  
**Arquivos RTL de Referência:**
- [`rtl/minisoc_aes/minisoc_aes_pkg.sv`](../../rtl/minisoc_aes/minisoc_aes_pkg.sv)
- [`rtl/minisoc_aes/minisoc_aes_key_exp.sv`](../../rtl/minisoc_aes/minisoc_aes_key_exp.sv)
- [`rtl/minisoc_aes/minisoc_aes_dp.sv`](../../rtl/minisoc_aes/minisoc_aes_dp.sv)
- [`tb/tb_minisoc_aes_s4.sv`](../../tb/tb_minisoc_aes_s4.sv)

---

## Sumário
1. [Visão Executiva das Semanas 3 e 4 (Pontos de Destaque)](#1-visão-executiva-das-semanas-3-e-4-pontos-de-destaque)
2. [Temporização: "1 Rodada por Ciclo" = 11 Ciclos de Clock por Bloco](#2-temporização-1-rodada-por-ciclo--11-ciclos-de-clock-por-bloco)
3. [Como o Datapath (`minisoc_aes_dp`) Funciona e Por Que Separar do `minisoc_aes_top`](#3-como-o-datapath-minisoc_aes_dp-funciona-e-por-que-separar-do-minisoc_aes_top)
4. [Como o Expansor de Chaves (`minisoc_aes_key_exp`) Opera a Nível de RTL e Arquitetura](#4-como-o-expansor-de-chaves-minisoc_aes_key_exp-opera-a-nível-de-rtl-e-arquitetura)
5. [A Matemática e o Papel Criptográfico do `Rcon` (*Round Constant*)](#5-a-matemática-e-o-papel-criptográfico-do-rcon-round-constant)
6. [Como o `sub_w3` (`SubWord`) é Gerado no RTL (Passo a Passo Numérico)](#6-como-o-sub_w3-subword-é-gerado-no-rtl-passo-a-passo-numérico)
7. [Decifragem (*Inverse Cipher*): Ordem Reversa das Chaves e Por Que a Sequência de Rodada é `InvSR -> InvSB -> ARK -> InvMC`](#7-decifragem-inverse-cipher-ordem-reversa-das-chaves-e-por-que-a-sequência-de-rodada-é-invsr---invsb---ark---invmc)

---

## 1. Visão Executiva das Semanas 3 e 4 (Pontos de Destaque)

Nas Semanas 3 e 4 evoluímos dos blocos isolados da Semana 2 (`SubBytes`/`ShiftRows`) para consolidar **toda a microarquitetura do MiniSoC** e entregar o **núcleo criptográfico AES-128 completo e funcional ponta a ponta** (expansão de chaves + datapath de cifragem e decriptação), 100% validado contra o padrão NIST FIPS-197 e com zero avisos de lint.

### 1.1 Semana 3 — Microarquitetura do Sistema e Transformações em $\text{GF}(2^8)$
1. **Definição da Microarquitetura ([`arquitetura_v1.0.md`](arquitetura_v1.0.md)):**
   - **Escolha do Datapath Iterativo (1 rodada/ciclo — 11 ciclos/bloco):** Justificada pelo gargalo físico da memória SRAM compartilhada (*single-port* de 32 bits, que exige 4 ciclos de leitura + 4 de escrita por bloco). Uma arquitetura desenrolada gastaria ~10x mais área (~320 S-Boxes) sem ganho real de vazão.
   - **Estratégia de Reset Síncrono Pós-Lock (Foco em QoR SAED 32nm):** Como `sys_clk` fica parado enquanto `PLL_LOCKED = 0`, foi definido um sequenciador que mantém `sys_rst_n = 0` pelos primeiros **4 ciclos ativos de `sys_clk`** após o lock do PLL. Isso permite usar **reset síncrono** em todo o AES, eliminando arcos críticos de *recovery/removal* a 2 GHz no Design Compiler.
   - **Travessia de Domínios de Clock (CDC):** Sincronização por **Toggle + 2-FF + Data-Hold** tanto na fronteira `spi_sclk` ($\le 25\text{ MHz}$) $\to$ `clk` ($2\text{ GHz}$) quanto no disparo de `START` e retorno de status entre `clk` e `sys_clk`.
2. **Transformações Polinomiais Diretas e Inversas:**
   - **Aritmética em $\text{GF}(2^8)$ ([`minisoc_aes_pkg.sv`](../../rtl/minisoc_aes/minisoc_aes_pkg.sv)):** Implementação dos multiplicadores modulares pelo polinômio irredutível `0x11B` (`{02}` e `{03}` para cifragem; `{09}`, `{0b}`, `{0d}` e `{0e}` para decriptação).
   - **Fechamento dos Blocos Combinacionais:** Implementação de [`minisoc_aes_mix_columns.sv`](../../rtl/minisoc_aes/minisoc_aes_mix_columns.sv), [`minisoc_aes_inv_mix_columns.sv`](../../rtl/minisoc_aes/minisoc_aes_inv_mix_columns.sv) e [`minisoc_aes_add_round_key.sv`](../../rtl/minisoc_aes/minisoc_aes_add_round_key.sv), além da visão matricial $4\times 4$ interativa no [`aes_hardware_explorer.html`](aes_hardware_explorer.html).

### 1.2 Semana 4 — Expansão de Chave e Datapath AES-128 Completo
1. **Expansor de Chave Iterativo Pré-Computado ([`minisoc_aes_key_exp.sv`](../../rtl/minisoc_aes/minisoc_aes_key_exp.sv)):**
   - Em vez de calcular subchaves *on-the-fly* a cada bloco ou desenrolar 40 S-Boxes, o módulo usa **apenas 4 S-Boxes** (`SubWord` de 32 bits) para gerar e armazenar as 11 subchaves (`rk_mem[0:10]`) em **10 ciclos**.
   - **Decriptação sem penalidade:** O *Inverse Cipher* consome as chaves de trás para frente (`RoundKey[10]` $\to$ `RoundKey[0]`); com `rk_mem[0:10]` armazenado, o acesso reverso tem **latência zero**.
   - **Eficiência Multi-Bloco (`1..256` blocos):** A chave é expandida **uma única vez** no início do comando `START` e o expansor fica totalmente congelado durante o processamento dos blocos.
2. **Datapath AES-128 Bidirecional ([`minisoc_aes_dp.sv`](../../rtl/minisoc_aes/minisoc_aes_dp.sv)):**
   - Integra o *Cipher* direto (FIPS-197 Fig. 5) e o *Inverse Cipher* (FIPS-197 Fig. 12) com handshake `i_start` / `o_busy` / `o_done`.
   - **Isolamento de Operandos (*Low-Power*):** Quando está cifrando, a entrada do ramo de decriptação é forçada a `0` (e vice-versa), evitando chaveamento inútil nas 16 S-Boxes do caminho inativo.

---

## 2. Temporização: "1 Rodada por Ciclo" = 11 Ciclos de Clock por Bloco

**"1 rodada por ciclo"** significa **1 rodada por ciclo de clock** (`sys_clk`).

Para o **AES-128**, o padrão FIPS-197 possui **1 etapa inicial ("Rodada 0") + 10 rodadas de transformação (`Rodadas 1..10`)**, totalizando exatamente **11 ciclos de clock** por bloco de 128 bits no [`minisoc_aes_dp.sv`](../../rtl/minisoc_aes/minisoc_aes_dp.sv):

| Ciclo de Clock | Rodada AES | O que acontece na borda de subida do clock (`posedge clk`) |
| :---: | :---: | :--- |
| **1º ciclo** (`i_start = 1`) | **Rodada 0** *(Inicial)* | Aplica o `AddRoundKey` inicial (`i_block ^ RoundKey[0]` na cifragem, ou `RoundKey[10]` na decriptação) e guarda em `state_q`. |
| **2º ao 10º ciclo** (`9 ciclos`) | **Rodadas 1 a 9** | Executa 1 rodada completa por ciclo (`SubBytes` $\to$ `ShiftRows` $\to$ `MixColumns` $\to$ `AddRoundKey`). |
| **11º ciclo** (`1 ciclo`) | **Rodada 10** *(Final)* | Executa a rodada final (sem `MixColumns` / `InvMixColumns`), registra o bloco pronto em `o_block` e pulsa `o_done = 1`. |

Ou seja: **$1\text{ (Rodada 0)} + 9\text{ (Rodadas 1..9)} + 1\text{ (Rodada 10)} = 11\text{ ciclos de clock}$** para cifrar ou decriptar um bloco de 128 bits.

---

## 3. Como o Datapath (`minisoc_aes_dp`) Funciona e Por Que Separar do `minisoc_aes_top`

A lógica adotada foi projetar o [`minisoc_aes_dp.sv`](../../rtl/minisoc_aes/minisoc_aes_dp.sv) como um **motor puro de 1 bloco de 128 bits** ($E_K(X)$ e $D_K(X)$), separando o **cálculo criptográfico da rodada** da **expansão de chaves** e do **encadeamento dos modos de operação / acesso à memória**.

### 3.1 Funcionamento Interno do `minisoc_aes_dp`

O `minisoc_aes_dp` gira em torno de dois elementos: um **registrador de estado de 128 bits (`state_q`)** que é realimentado a cada ciclo de clock e um **contador de rodadas (`round_q` de `1` a `10`)**.

```text
                       ┌─────────────────────────────────────────────┐
                       │          minisoc_aes_key_exp                │
                       │   Armazena rk_mem[0..10] (11 Round Keys)    │
                       └──────▲───────────────────────────────┬──────┘
                              │ o_round_key_idx [3:0]         │ i_round_key [127:0]
                              │ (Pede chave 0..10 ou 10..0)   ▼ (Devolve no mesmo ciclo)
   ┌──────────────────────────┴───────────────────────────────┴──────────────────────────┐
   │                                  minisoc_aes_dp                                     │
   │                                                                                     │
   │  Ciclo 0 (i_start=1):  i_block ──►(^ i_round_key)───────────────────┐               │
   │                                                                     ▼               │
   │  Ciclos 1..10 (busy=1): ┌──► [Ramo Cipher: SB->SR->(MC)->ARK] ───►[MUX]──► state_q  ├──► o_block[127:0]
   │                         │                                           ▲        │      │
   │                         └──► [Ramo InvCipher: ISR->ISB->ARK->(IMC)]─┘        │      │
   │                              ▲                                               │      │
   │                              └─────────────────(Realimentação a cada clock)──┘      │
   └─────────────────────────────────────────────────────────────────────────────────────┘
```

#### Passo a passo das portas e sinais:
1. **Por que `o_round_key_idx` é uma saída do datapath?**
   - Quem sabe em qual rodada o bloco está (`0..10`) e em qual sentido está operando (`i_decrypt`) é o próprio datapath.
   - Por isso, em cada ciclo o datapath calcula combinacionalmente **qual índice de chave (`0..10`) ele precisa naquele instante**:
     - **Se `i_decrypt = 0` (Cifragem):** no pulso `i_start` pede `0` (`RoundKey[0]`); nos ciclos `1..10` pede `round_q` (`1, 2, ..., 10`).
     - **Se `i_decrypt = 1` (Decriptação):** no pulso `i_start` pede `10` (`RoundKey[10]`); nos ciclos `1..10` pede `10 - round_q` (`9, 8, ..., 0`).
   - O `minisoc_aes_key_exp` recebe esse índice e devolve `i_round_key = rk_mem[idx]` **imediatamente no mesmo ciclo** (leitura combinacional).
2. **O que acontece a cada ciclo no registrador `state_q`:**
   - **No pulso `i_start = 1` (Rodada 0):**
     - `u_ark_init` calcula `i_block ^ i_round_key` e grava em `state_q`;
     - Salva a direção em `decrypt_q <= i_decrypt`, coloca `round_q <= 4'd1` e levanta `o_busy <= 1`.
   - **Durante `round_q = 1..9` (Rodadas intermediárias):**
     - `state_q` entra no ramo ativo (*Cipher* ou *Inverse Cipher*), passa pelas 4 transformações combinacionais em série e o resultado volta para `state_q` na borda de subida do clock, incrementando `round_q <= round_q + 1`.
   - **Quando `round_q == 10` (Rodada final):**
     - Os multiplexadores `enc_pre_ark` e `dec_round_out` desviam (*bypass*) de `MixColumns` / `InvMixColumns`, conforme exige a FIPS-197 na 10ª rodada.
     - O resultado final é registrado em `state_q` (que alimenta diretamente `o_block`), `o_busy` cai para `0` e `o_done` pulsa em `1` por 1 ciclo.

### 3.2 Por que manter `minisoc_aes_dp` minimalista e criar `minisoc_aes_top` ao redor dele?

`minisoc_aes_key_exp` + `minisoc_aes_dp` já formam um **núcleo AES-128 completo de bloco único (modo ECB puro de 128 bits)**. A razão de separar o `minisoc_aes_dp` do controlador `minisoc_aes_top` é isolar **o primitivo matemático ($E_K / D_K$)** das **três tarefas de sistema** exigidas pelo Block Guide:

1. **Adaptação com a Memória SRAM de 32 bits (`minisoc_memory`):**
   - O `minisoc_aes_dp` enxerga 128 bits de uma vez (`i_block[127:0]` $\to$ `o_block[127:0]`), mas a memória física do SoC é *single-port* de **32 bits**.
   - O `minisoc_aes_top` busca **4 palavras de 32 bits** na SRAM para montar os 128 bits de `i_block`, dispara o `minisoc_aes_dp`, e depois grava `o_block` de volta em **4 escritas de 32 bits** (*in-place*).
2. **Encadeamento dos 6 Modos de Operação (`ECB`, `CBC`, `PCBC`, `CFB`, `OFB`, `CTR`):**
   - Graças a essa separação, o `minisoc_aes_dp` **não precisa mudar nenhuma linha de código** para suportar os 6 modos.
   - Quem decide o que entra em `i_block`, o que faz XOR com `o_block` (ex.: `IV`, `ciphertext` anterior, `counter`) e se chama o datapath com `i_decrypt = 0` ou `1` (já que `CFB`, `OFB` e `CTR` usam sempre `i_decrypt = 0` mesmo na decriptação) é apenas a lógica de pré/pós-processamento do `minisoc_aes_top`.
3. **Execução em Lote (`1..256` blocos) com Expansão Única de Chave:**
   - Quando o SPI envia `START` para processar $N$ blocos, o `minisoc_aes_top` pulsa `ke_start` **uma única vez** (gastando 10 ciclos) e depois aciona `dp_start` $N$ vezes seguidas, lendo as chaves prontas de `minisoc_aes_key_exp` sem nunca recalcular a expansão de chave.

---

## 4. Como o Expansor de Chaves (`minisoc_aes_key_exp`) Opera a Nível de RTL e Arquitetura

O [`minisoc_aes_key_exp.sv`](../../rtl/minisoc_aes/minisoc_aes_key_exp.sv) combina duas estruturas clássicas de hardware:
1. **Na escrita (durante 10 ciclos):** um **gerador iterativo síncrono** que calcula uma nova subchave de 128 bits por ciclo de clock e preenche a tabela `rk_mem[0:10]`.
2. **Na leitura (durante a cifragem/decriptação):** um **banco de registradores (*Register File*) com porta de leitura puramente combinacional** (um multiplexador 11:1 de 128 bits).

### 4.1 Diagrama Interno do `minisoc_aes_key_exp`

```text
                       ┌────────────────────────────────────────────────────────────┐
                       │                 Banco de Registradores                     │
          i_key ──────►│  rk_mem[0]  rk_mem[1]  rk_mem[2]  ...  rk_mem[9] rk_mem[10]│
      (em i_start=1)   └──────┬──────────┬──────────┬───────────────┬─────────┬─────┘
                              │          │          │               │         │
                              ▼          ▼          ▼               ▼         ▼
                       ┌────────────────────────────────────────────────────────────┐
   i_round_idx [3:0] ─►│       MUX Combinacional de Leitura (11:1 de 128 bits)      ├──► o_round_key [127:0]
   (vindo do Datapath) └────────────────────────────────────────────────────────────┘    (Disponível em 0 ciclos)
                                                     │
                (Enquanto busy_q=1: seleciona prev_rk = rk_mem[round_q - 1])
                                                     ▼
                       ┌────────────────────────────────────────────────────────────┐
                       │     Lógica Combinacional de 1 Rodada de Chave (next_rk)    │
                       │  • Separa prev_rk em 4 palavras de 32b: {w0, w1, w2, w3}   │
                       │  • w3 ──► RotWord (fios) ──► SubWord (4x S-Box) ──► ^ Rcon │
                       │  • w0_next = w0 ^ SubWord(RotWord(w3)) ^ Rcon[round_q]     │
                       │  • w1_next = w1 ^ w0_next                                  │
                       │  • w2_next = w2 ^ w1_next                                  │
                       │  • w3_next = w3 ^ w2_next                                  │
                       └─────────────────────────────┬──────────────────────────────┘
                                                     │ Grava rk_mem[round_q] <= next_rk
                                                     └────► (em posedge clk, round_q = 1..10)
```

### 4.2 Operação de Cada Bloco do Código RTL

1. **Cálculo Combinacional de 1 Subchave:**
   - Na FIPS-197 (Seção 5.2), cada *RoundKey* de 128 bits é formada por 4 palavras de 32 bits (`w0, w1, w2, w3`). Para gerar a chave da rodada `round_q` (`1..10`) a partir da chave anterior `prev_rk = rk_mem[round_q - 1]`:
     ```systemverilog
     w0 = prev_rk[127:96];
     w1 = prev_rk[95:64];
     w2 = prev_rk[63:32];
     w3 = prev_rk[31:0];

     rot_w3 = {w3[23:0], w3[31:24]};
     rcon_w = {aes_rcon(round_q), 24'h00_0000};

     w0_next = w0 ^ sub_w3 ^ rcon_w;
     w1_next = w1 ^ w0_next;
     w2_next = w2 ^ w1_next;
     w3_next = w3 ^ w2_next;
     next_rk = {w0_next, w1_next, w2_next, w3_next};
     ```
   - Na mesma rodada, `w1_next` depende de `w0_next`, `w2_next` depende de `w1_next` e `w3_next` depende de `w2_next`. Como isso representa apenas **3 portas XOR em série após 1 S-Box**, o atraso combinacional é mínimo e fecha *timing* com folga em SAED 32nm.
2. **Máquina Sequencial de Preenchimento:**
   - Quando chega `i_start = 1`, grava `rk_mem[0] <= i_key` e prepara `round_q <= 4'd1`, `busy_q <= 1'b1`.
   - Nos 10 ciclos seguintes (`round_q = 1..10`), grava `rk_mem[round_q] <= next_rk`. Ao chegar em `round_q == 4'd10`, desliga `busy_q <= 0`, pulsa `done_q <= 1` e levanta `valid_q <= 1`.
3. **Leitura Combinacional para o Datapath:**
   ```systemverilog
   always_comb begin
       if (i_round_idx <= 4'd10) begin
           o_round_key = rk_mem[i_round_idx];
       end else begin
           o_round_key = 128'd0;
       end
   end
   ```
   - Como `rk_mem[0:10]` são flip-flops, suas saídas `Q` já estão estáveis. O bloco `always_comb` sintetiza um multiplexador 11:1 controlado por `i_round_idx`, entregando qualquer chave no mesmo ciclo sem estados de espera.
4. **Isolamento de Operandos (*Low-Power*):**
   ```systemverilog
   if (busy_q && (round_q >= 4'd1) && (round_q <= 4'd10)) begin
       prev_rk = rk_mem[round_q - 4'd1];
   end else begin
       prev_rk = 128'd0;
   end
   ```
   - Assim que os 10 ciclos de expansão terminam (`busy_q == 0`), `prev_rk` é forçado a `0`. Com isso, as 4 S-Boxes e a árvore de XORs de `next_rk` ficam completamente paradas durante todo o processamento dos blocos no datapath.

---

## 5. A Matemática e o Papel Criptográfico do `Rcon` (*Round Constant*)

O **`Rcon`** conecta-se diretamente com a função **`aes_xtime` (multiplicação por `{02}` em $\text{GF}(2^8)$)** usada no `MixColumns`.

### 5.1 Qual é a matemática do `Rcon`?

Na rodada $r$ ($r = 1, 2, \dots, 10$), o byte `Rcon[r]` é **a potência de $x$ (isto é, $\{02\}^{r-1}$) dentro do corpo finito $\text{GF}(2^8)$** reduzida pelo polinômio irredutível do AES ($\text{0x11B}$):

$$\text{Rcon}[r] = x^{r-1} \bmod (x^8 + x^4 + x^3 + x + 1)$$

- Começa em **`8'h01`** na Rodada 1 ($x^0 = 1$).
- Para achar o `Rcon` da próxima rodada, basta aplicar **`aes_xtime` (deslocar 1 bit para a esquerda; e se o bit 7 que saiu era `1`, fazer XOR com `8'h1b`)**:

| Rodada ($r$) | Potência em $\text{GF}(2^8)$ | Cálculo a partir do anterior (`aes_xtime`) | Valor Hex (`aes_rcon(r)`) | Valor Binário |
| :---: | :---: | :--- | :---: | :---: |
| **1** | $x^0$ | Valor inicial | **`8'h01`** | `0000_0001` |
| **2** | $x^1$ | `01 << 1` | **`8'h02`** | `0000_0010` |
| **3** | $x^2$ | `02 << 1` | **`8'h04`** | `0000_0100` |
| **4** | $x^3$ | `04 << 1` | **`8'h08`** | `0000_1000` |
| **5** | $x^4$ | `08 << 1` | **`8'h10`** | `0001_0000` |
| **6** | $x^5$ | `10 << 1` | **`8'h20`** | `0010_0000` |
| **7** | $x^6$ | `20 << 1` | **`8'h40`** | `0100_0000` |
| **8** | $x^7$ | `40 << 1` | **`8'h80`** | `1000_0000` |
| **9** | $x^8 \bmod m(x)$ | `80 << 1` estoura o bit 7! Então faz `00 ^ 1b` | **`8'h1b`** | `0001_1011` |
| **10** | $x^9 \bmod m(x)$ | `1b << 1` (sem estouro no bit 7) | **`8'h36`** | `0011_0110` |

> **Por que na Rodada 9 vira `1b` e na 10 vira `36`?**  
> Até a Rodada 8 (`0x80 = 1000_0000`), dobrar o valor apenas desloca o bit `1` para a esquerda (`01 -> 02 -> 04 -> 08 -> 10 -> 20 -> 40 -> 80`).  
> Na passagem da Rodada 8 para a 9, deslocar `1000_0000` para a esquerda geraria $x^8$ (9º bit), que não cabe em 1 byte. Pela regra de redução de $\text{GF}(2^8)$, $x^8 \equiv x^4 + x^3 + x + 1 = \text{8'h1b}$. E na Rodada 10, `8'h1b << 1` resulta em `8'h36`.

### 5.2 Por que concatenar com `24'h00_0000` no RTL?

```systemverilog
rcon_w = {aes_rcon(round_q), 24'h00_0000};
```
Pela definição da FIPS-197 (Seção 5.2), a palavra constante de 32 bits `Rcon[r]` tem o byte $x^{r-1}$ **apenas no byte mais significativo (MSB)** e zero nos outros 3 bytes:

$$\text{Rcon\_word}[r] = \big[\,\text{Rcon}[r],\;\text{8'h00},\;\text{8'h00},\;\text{8'h00}\,\big]$$

Como $A \oplus 0 = A$, o `Rcon` modifica diretamente o primeiro byte de `w0_next` e se propaga em cascata para `w1_next`, `w2_next` e `w3_next`.

### 5.3 Para que serve o `Rcon` na segurança do AES?
Sem o `Rcon`, uma chave com bytes repetidos produziria subchaves simétricas em todas as rodadas, abrindo brecha para **ataques de chave relacionada (*related-key attacks*)** e **ataques por deslize (*slide attacks*)**. Ao injetar um valor distinto em cada rodada (`Rcon[1..10]`), o AES **quebra a simetria entre as rodadas**.

---

## 6. Como o `sub_w3` (`SubWord`) é Gerado no RTL (Passo a Passo Numérico)

O **`sub_w3`** é o resultado da função **`SubWord(rot_w3)`** da FIPS-197: ela aplica a mesma substituição não-linear do `SubBytes`, mas sobre **1 palavra de 32 bits (4 bytes)** em vez do bloco de 128 bits (16 bytes).

### 6.1 Instanciação no RTL

```systemverilog
// SubWord(RotWord(w3)) using 4 parallel S-Box instances
for (genvar b = 0; b < 4; b++) begin : g_subword
    minisoc_aes_sbox u_sbox_kw (
        .i_byte (rot_w3[8*b +: 8]),
        .o_byte (sub_w3[8*b +: 8])
    );
end
```

Esse laço `generate` instancia **4 tabelas S-Box em paralelo**, uma para cada byte de `rot_w3[31:0]`:

| Iteração (`b`) | Fatia `rot_w3[8*b +: 8]` | Instância S-Box | Saída `sub_w3[8*b +: 8]` |
| :---: | :---: | :--- | :---: |
| **`b = 3`** | `rot_w3[31:24]` *(Byte 0 — MSB)* | `g_subword[3].u_sbox_kw` | `sub_w3[31:24] = SBox(rot_w3[31:24])` |
| **`b = 2`** | `rot_w3[23:16]` *(Byte 1)* | `g_subword[2].u_sbox_kw` | `sub_w3[23:16] = SBox(rot_w3[23:16])` |
| **`b = 1`** | `rot_w3[15:8]` *(Byte 2)* | `g_subword[1].u_sbox_kw` | `sub_w3[15:8]  = SBox(rot_w3[15:8])` |
| **`b = 0`** | `rot_w3[7:0]` *(Byte 3 — LSB)* | `g_subword[0].u_sbox_kw` | `sub_w3[7:0]   = SBox(rot_w3[7:0])` |

### 6.2 Exemplo Prático Passo a Passo (Rodada 1 do Apêndice A.1 da FIPS-197)

Considere a chave inicial do Apêndice B / A.1:
- `w0 = 32'h2b7e1516`
- `w3 = 32'h09cf4f3c`

1. **`RotWord(w3)`:**
   - Gira 1 byte para a esquerda: `rot_w3 = 32'hcf_4f_3c_09`
2. **`SubWord(rot_w3)` $\to$ `sub_w3`:**
   - `SBox(8'hcf) = 8'h8a`
   - `SBox(8'h4f) = 8'h84`
   - `SBox(8'h3c) = 8'hfb`
   - `SBox(8'h09) = 8'h01`
   - Juntando os 4 bytes: **`sub_w3 = 32'h8a_84_fb_01`**
3. **XOR com `rcon_w` (`32'h01_00_00_00` na Rodada 1):**
   - `sub_w3 ^ rcon_w = 32'h8b_84_fb_01`
4. **XOR com `w0` (`32'h2b_7e_15_16`):**
   - `w0_next = 32'h2b_7e_15_16 ^ 32'h8b_84_fb_01 = 32'ha0_fa_fe_17` (primeira palavra da `RoundKey[1]`).

> **Importante:** A expansão de chaves usa **sempre a S-Box direta (`minisoc_aes_sbox`)**, mesmo quando o circuito vai executar uma **decriptação**.

---

## 7. Decifragem (*Inverse Cipher*): Ordem Reversa das Chaves e Por Que a Sequência de Rodada é `InvSR -> InvSB -> ARK -> InvMC`

Na decifragem do AES:
1. **As 11 chaves (`RoundKey[0]` a `RoundKey[10]`) são 100% idênticas** às da cifragem. O `minisoc_aes_key_exp` executa exatamente a mesma expansão; o que muda é apenas a **ordem de leitura** (`0 -> 10` na cifragem vs. `10 -> 0` na decifragem).
2. **No datapath (`minisoc_aes_dp`), o bloco passa pelas transformações inversas** (`InvShiftRows`, `InvSubBytes` com `InvSBox`, e `InvMixColumns`), enquanto o `AddRoundKey` permanece um `XOR` (pois $(A \oplus K) \oplus K = A$).

### 7.1 Comparação Lado a Lado: Cifragem vs. Decifragem

| Etapa | Cifragem (*Cipher* — FIPS-197 Fig. 5) | Decifragem (*Inverse Cipher* — FIPS-197 Fig. 12) |
| :--- | :--- | :--- |
| **Chaves usadas** | Lê na ordem direta: **`RK[0]` $\to$ `RK[10]`** | Lê na ordem inversa: **`RK[10]` $\to$ `RK[0]`** |
| **Ciclo 0** (`i_start=1`) | `AddRoundKey(RK[0])` | `AddRoundKey(RK[10])` *(desfaz o último XOR da Rodada 10 da cifragem)* |
| **Ciclos 1..9** (`r = 1..9`) | 1. `SubBytes` *(S-Box)*<br>2. `ShiftRows`<br>3. `MixColumns`<br>4. `AddRoundKey(RK[r])` | 1. **`InvShiftRows`** *(desfaz o ShiftRows)*<br>2. **`InvSubBytes`** *(InvS-Box: desfaz o SubBytes)*<br>3. **`AddRoundKey(RK[10-r])`** *(desfaz o XOR da rodada)*<br>4. **`InvMixColumns`** *(desfaz o MixColumns)* |
| **Ciclo 10** (`r = 10`) | 1. `SubBytes`<br>2. `ShiftRows`<br>3. `AddRoundKey(RK[10])` | 1. **`InvShiftRows`**<br>2. **`InvSubBytes`**<br>3. **`AddRoundKey(RK[0])`** *(desfaz o primeiro XOR do Ciclo 0 da cifragem)* |

### 7.2 Por que a sequência das Rodadas `1..9` na decifragem é `InvSR -> InvSB -> ARK -> InvMC` (e não `ARK -> InvMC -> InvSR -> InvSB`)?

Na verdade, **ela É exatamente a sequência inversa passo a passo**! O motivo do deslocamento visual está no fato de que **a Rodada 10 da cifragem não tem `MixColumns`**, o que desloca o agrupamento dos parênteses quando desfazemos a cadeia da direita para a esquerda:

```text
CIFRAGEM (indo para a frente ──►):

... ──► [SB ──► SR ──► MC ──► ARK(K9)] ──► [SB ──► SR ──► ARK(K10)] ──► Ciphertext
        └───────── Rodada 9 ─────────┘     └── Rodada 10 (sem MC) ─┘
```

Agora, desfazendo **passo a passo da direita para a esquerda ($\leftarrow$)** a partir do `Ciphertext`:

```text
DECIFRAGEM (voltando de trás para frente ◄──):

Ciphertext
   │
   ├──► 0) Desfaz ARK(K10) ──► [ ARK(K10) ]                                 (Ciclo 0 da Decifragem)
   │
   ├──► 1) Desfaz SR  (da R10) ─┐
   ├──► 2) Desfaz SB  (da R10)  ├──► [ InvSR ──► InvSB ──► ARK(K9) ──► InvMC ] (Rodada 1 da Decifragem!)
   ├──► 3) Desfaz ARK (da R9)   │
   ├──► 4) Desfaz MC  (da R9)  ─┘
   │
   ├──► 5) Desfaz SR  (da R9)  ─┐
   ├──► 6) Desfaz SB  (da R9)   ├──► [ InvSR ──► InvSB ──► ARK(K8) ──► InvMC ] (Rodada 2 da Decifragem!)
   ├──► 7) Desfaz ARK (da R8)   │
   ├──► 8) Desfaz MC  (da R8)  ─┘
   ...
   └──► No final (Rodada 10 da Decifragem), sobram apenas o SR e o SB da Rodada 1
        original e o ARK(K0) inicial:
                                ──► [ InvSR ──► InvSB ──► ARK(K0) ]         (Rodada 10 da Decifragem!)
```

1. Como a **Rodada 10 da cifragem** terminou com `SB -> SR -> ARK(K10)` (sem `MixColumns`), após removermos o `ARK(K10)` no Ciclo 0 da decifragem, a primeira operação que aparece à frente para ser desfeita **não é um `MixColumns`**, e sim o **`SR` e o `SB` da Rodada 10** (`InvShiftRows -> InvSubBytes`).
2. Só depois de desfazer esse `SR` e esse `SB` é que alcançamos o `ARK(K9)` e o `MC` da Rodada 9 (`AddRoundKey(K9) -> InvMixColumns`).
3. Ao agrupar esses 4 passos em cada ciclo de clock (`InvShiftRows -> InvSubBytes -> AddRoundKey -> InvMixColumns`), todas as rodadas `1..9` da decifragem ficam com a **mesma estrutura**, e na rodada 10 da decifragem basta pular o `InvMixColumns` — exatamente espelhado com a cifragem.

