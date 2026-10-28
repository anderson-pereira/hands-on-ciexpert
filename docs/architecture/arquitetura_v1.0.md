# Documento de Arquitetura e Microarquitetura — MiniSoC AES (v1.0.0)

**Projeto:** Hands-on CIExpert — RTL Design Track  
**Autor:** Anderson Pereira  
**Documentos de Referência:**
- [DV_BlockGuide_MiniSoCAES_v1.0.0.pdf](../references/DV_BlockGuide_MiniSoCAES_v1.0.0.pdf) *(System Architecture and RTL Specification)*
- [Planejamento-Projeto-Hands-on.pdf](../references/Planejamento-Projeto-Hands-on.pdf)
- [NIST FIPS PUB 197 (AES Standard)](../references/nist.fips.197.pdf)

---

## 1. Visão Geral do Sistema (`MiniSoC AES`)

O **`MiniSoC AES`** (`minisoc_top`) é um sistema digital integrado em SystemVerilog que reúne, em um único *top-level*, um **Front-End SPI** de configuração e monitoramento, um **gerador/divisor de clock PLL (`minisoc_pll_mock`)**, um **Engine Criptográfico AES-128 multi-modo** e uma **memória física compartilhada de $1024 \times 32$ bits (`minisoc_memory`)** com processamento *in-place*.

O circuito atende integralmente às especificações do ambiente de verificação parceiro (*Design Verification Track*) e aos fluxos industriais Synopsys (VCS/Vlogan, Design Compiler, Formality, PrimeTime e VC Static / UPF IEEE 1801) sobre o PDK **Synopsys SAED 32nm**.

### 1.1 Arquitetura de Blocos do Sistema

```text
========================================================================================================================
                                        MINISOC AES TOP-LEVEL SYSTEM (minisoc_top)
========================================================================================================================

  INTERFACES DE TOPO
  ==================
  • CLK            : clk (Referência always-on de 2 GHz)
  • RESET          : rst_n (Reset global ativo em nível baixo)
  • SPI            : spi_sclk (<= 25 MHz), spi_cs_n, spi_mosi, spi_miso
  • MEMORY DATA IF : mem_clk (<= 200 MHz), mem_i_data[31:0], mem_i_wr_en, mem_i_addr[9:0], mem_o_data[31:0]

                 clk (2 GHz Always-On)                        rst_n (Global Reset)
                           │                                           │
           ┌───────────────┼───────────────────────────────────────────┼──────────────────────┐
           │               ▼                                           ▼                      │
           │    ┌──────────────────────┐                    ┌────────────────────┐            │
           │    │   minisoc_pll_mock   │                    │  Reset Sequencer   │            │
           │    │ • Enable & Div (/1..8)├───── o_locked ────►│ • Gera sys_rst_n   │            │
           │    │ • LFSR Lock Delay    │      (status)      │   pós-lock determ. │            │
           │    └──────────┬───────────┘                    └──────────┬─────────┘            │
           │               │ sys_clk (2GHz/1GHz/500MHz/250MHz)         │ sys_rst_n            │
           ▼               │                                           │                      ▼
  ┌─────────────────────────┐                                          │           ┌────────────────────┐
  │      minisoc_spi        │◄── spi_sclk, spi_cs_n, spi_mosi, spi_miso│           │                    │
  │  ┌───────────────────┐  │                                          │           │                    │
  │  │ minisoc_spi_phy   │  │ (Domínio spi_sclk: Frame 40b Mode 0)     │           │                    │
  │  ├───────────────────┤  │                                          │           │                    │
  │  │ minisoc_spi_cdc   │  │ (Toggle de Frame Completo + Data-Hold)   │           │                    │
  │  ├───────────────────┤  │                                          ▼           │                    │
  │  │ minisoc_spi_csr   │  │ (Domínio clk 2 GHz Always-On: CSRs 32b) ┌───────────────────────┐         │
  │  └─────────┬─────────┘  │                                         │    minisoc_aes_top    │         │
  └────────────┼────────────┘                                         │  • Controlador Blocos │         │
               │ KEY, IV, COUNTER, NUM_BLOCKS, MODE, DECRYPT, START   │    (ECB,CBC,PCBC,     │         │
               ├─────────────────────────────────────────────────────►│     CFB,OFB,CTR)      │         │
               │◄─────────────────────────────────────────────────────┤  • minisoc_aes_dp     │         │
               │ BUSY, DONE, ERROR, BLOCKS_DONE (CDC clk <-> sys_clk) │  • minisoc_aes_key_exp│         │
               │                                                      └───────────┬───────────┘         │
               │ MEM_SEL_AES (Ownership Select)                                   │ Porta AES (sys_clk) │
               │                                                                  ▼                     │
               │      Porta Externa MEMORY DATA IF (mem_clk) ────────► ┌─────────────────────┐          │
               └─────────────────────────────────────────────────────► │   Mux de Memória    │          │
                                                                       │ (Exclusão Mútua)    │          │
                                                                       └──────────┬──────────┘          │
                                                                                  ▼                     │
                                                                       ┌─────────────────────┐          │
                                                                       │   minisoc_memory    │          │
                                                                       │  SRAM 1024 x 32 bits│          │
                                                                       └─────────────────────┘          │
```

### 1.2 Convenções de Módulos e Organização RTL (Seções 1.3 e 10)

| Arquivo / Módulo | Papel Funcional no Sistema |
| :--- | :--- |
| `rtl/minisoc_top.sv` | Top-level de integração do sistema completo (expõe apenas as 4 interfaces de topo). |
| `rtl/minisoc_spi/minisoc_spi.sv` | Wrapper do Front-End SPI integrando `minisoc_spi_phy`, `minisoc_spi_cdc` e `minisoc_spi_csr`. |
| `rtl/minisoc_aes/minisoc_aes_top.sv` | Engine AES, validação de parâmetros, encadeamento de modos, CDC de comando/status e acesso à memória. |
| `rtl/minisoc_aes/minisoc_aes_dp.sv` | Datapath AES-128 iterativo com suporte a *Cipher* e *Inverse Cipher*. |
| `rtl/minisoc_aes/minisoc_aes_key_exp.sv` | Expansor de chaves AES-128 (geração das 11 *round keys*). |
| `rtl/minisoc_mem/minisoc_memory.sv` | Modelo RTL da memória física compartilhada single-port $1024 \times 32$ bits. |
| `rtl/minisoc_pll/minisoc_pll_mock.sv` | Modelo RTL sintetizável do PLL (referência de 2 GHz, divisores `/1, /2, /4, /8`). |

---

## 2. Interfaces de Topo (`minisoc_top.sv` — Seção 3)

O top-level expõe estritamente quatro grupos de sinais externos:

| Grupo | Sinal | Direção | Largura | Domínio | Descrição Funcional |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **CLK** | `clk` | Input | 1 | `clk` (2 GHz) | Clock de referência de **2 GHz**. Alimenta o PLL mock e o domínio always-on de controle/SPI. |
| **RESET** | `rst_n` | Input | 1 | Assíncrono | Reset global ativo em nível baixo (`0`). Não apaga o conteúdo da memória de dados. |
| **SPI** | `spi_sclk` | Input | 1 | `spi_sclk` | Clock serial SPI Mode 0. Frequência máxima especificada: **25 MHz**. |
| | `spi_cs_n` | Input | 1 | `spi_sclk` | *Chip Select* ativo em nível baixo (`0`). Delimita cada frame de 40 bits. |
| | `spi_mosi` | Input | 1 | `spi_sclk` | Linha de dados serializados Mestre $\to$ Escravo (amostrada em `posedge spi_sclk`). |
| | `spi_miso` | Output | 1 | `spi_sclk` | Linha de dados serializados Escravo $\to$ Mestre (atualizada em `negedge spi_sclk`). |
| **MEMORY DATA** | `mem_clk` | Input | 1 | `mem_clk` | Clock externo da interface de memória (até **200 MHz**). |
| | `mem_i_data` | Input | 32 | `mem_clk` | Palavra de 32 bits para escrita externa na memória. |
| | `mem_i_wr_en` | Input | 1 | `mem_clk` | Controle de operação (`1 = write`, `0 = read`). |
| | `mem_i_addr` | Input | 10 | `mem_clk` | Endereço de palavra de 32 bits na memória (`0..1023`). |
| | `mem_o_data` | Output | 32 | `mem_clk` | Dado de 32 bits retornado em leituras síncronas da memória. |

---

## 3. Estratégia de Clock, PLL, Reset e Travessia de Domínios (CDC)

### 3.1 Relação de Clocks e Regra de Bootstrap (Seções 2.2 e 4)
O sistema opera com quatro domínios de clock:
1. **`clk` (2.000 GHz Always-On):** Alimenta o `minisoc_pll_mock` e o banco CSR do `minisoc_spi`. **Regra de Bootstrap:** como o SPI utiliza `clk` e independe de `sys_clk`, o software consegue programar `PLL_DIV_SEL`, habilitar `PLL_ENABLE = 1` e monitorar `PLL_LOCKED` mesmo enquanto `sys_clk` está totalmente bloqueado em `0`.
2. **`sys_clk` (2 GHz / 1 GHz / 500 MHz / 250 MHz):** Gerado pelo `minisoc_pll_mock` e liberado de forma *glitch-free* somente após `PLL_LOCKED = 1` (`REQ-PLL-01`):

| `PLL_DIV_SEL` | Divisor | Frequência de `sys_clk` | Período |
| :---: | :---: | :---: | :---: |
| `2'b00` | `/1` | `2.000 GHz` | `0.5 ns` |
| `2'b01` | `/2` | `1.000 GHz` | `1.0 ns` |
| `2'b10` | `/4` | `  500 MHz` | `2.0 ns` |
| `2'b11` | `/8` | `  250 MHz` | `4.0 ns` |

3. **`spi_sclk` ($\le 25\text{ MHz}$):** Clock serial externo assíncrono, ativo apenas durante janelas `spi_cs_n = 0`.
4. **`mem_clk` ($\le 200\text{ MHz}$):** Clock externo encaminhado à SRAM quando `MEM_SEL_AES = 0`.

### 3.2 Estratégia de Reset Síncrono e Sequência Interna (Seção 4.2 — Foco em QoR)
Para maximizar a qualidade de resultados (*QoR*) nas ferramentas Synopsys (eliminando arcos críticos de *recovery/removal* a `2 GHz`, facilitando *Clock Gating* automático em células `DFFX1_RVT` / `DFFSSRX1_RVT` do PDK SAED 32nm e evitando *Reset Domain Crossings* no Formality e VC Static), o sistema adota **Reset Síncrono** em todos os domínios com clock garantido, mantendo reset assíncrono estritamente onde o clock serial encontra-se parado durante o reset:

- **Domínio Always-On (`clk`, 2 GHz — Reset Síncrono):** `minisoc_spi_csr`, o estágio destino de `minisoc_spi_cdc`, `minisoc_pll_mock` e o sequenciador de reset interno utilizam `always_ff @(posedge clk) if (!rst_n)` (inicializando deterministicamente no 1º ciclo de `0.5 ns`).
- **Domínio do Sistema (`sys_clk` / AES — Reset Síncrono Pós-Lock, Seção 4.2):** Como `sys_clk` permanece bloqueado enquanto `PLL_LOCKED == 0`, o `minisoc_top` mantém `sys_rst_n = 0` enquanto `!rst_n || !pll_locked` e, após a liberação de `sys_clk`, aguarda um número determinístico de ciclos de `sys_clk` antes de elevar `sys_rst_n = 1`, garantindo inicialização síncrona limpa de todo o `minisoc_aes_*`.
- **Domínio Serial (`spi_sclk` — Exceção Assíncrona Necessária):** Como `spi_sclk` está parado em `0` fora das janelas de transação e durante o boot, `minisoc_spi_phy` usa reset local assíncrono por `spi_cs_n = 1` e os 2 registradores fonte de `minisoc_spi_cdc` (`req_toggle` e `rx_frame_hold`) mantêm `negedge rst_n` assíncrono para impedir injeção de `'X'` no domínio `clk`.
- **Memória Física (`minisoc_memory`):** Não possui reset funcional no array (Seções 3 e 7.3).

### 3.3 Fronteira CDC 1: `spi_sclk` $\longleftrightarrow$ `clk` Always-On (Seção 5.3)
- **Recepção (`spi_sclk` $\to$ `clk`):** O submódulo [`minisoc_spi_phy.sv`](../../rtl/minisoc_spi/minisoc_spi_phy.sv) acumula 40 bits em `posedge spi_sclk` com contador módulo-40 (`0..39 -> 0`), suportando tanto transações individuais delimitadas por `spi_cs_n` quanto *streaming* contínuo de múltiplos frames de 40 bits com `spi_cs_n = 0` (abortando qualquer *runt frame* incompleto caso `spi_cs_n` retorne a `1` antes do 40º clock). Na 40ª borda de subida (`bit_cnt == 39`), [`minisoc_spi_cdc.sv`](../../rtl/minisoc_spi/minisoc_spi_cdc.sv) captura o quadro completo em `rx_frame_hold` (*Data-Hold*) e alterna `req_toggle`. Um sincronizador **2-FF** em `clk` detecta a transição e emite `frame_valid` por 1 ciclo de `clk`.
- **Transmissão *Out-of-Frame* (`clk` $\to$ `spi_sclk`):** Em um `READ request` (Frame 1), `minisoc_spi_csr` atualiza `rd_data_hold[31:0]` em ~`1.5 ns` (3 ciclos de `clk` a 2 GHz) e o mantém estático. No Frame 2 subsequente (`NOP` `0x3F` ou novo comando em *pipeline*, com ou sem pulso intermediário de `spi_cs_n`), `minisoc_spi_phy` carrega `tx_shift <= rd_data_hold` em `negedge spi_sclk` quando `bit_cnt == 1` (~`60 ns` após o término do Frame 1 a 25 MHz) e desloca `DATA[31:0]` nas bordas de descida `8..39`.

### 3.4 Fronteira CDC 2: `clk` (2 GHz) $\longleftrightarrow$ `sys_clk` (`/1, /2, /4, /8`)
Como um pulso `o_aes_start` de 1 ciclo de `clk` (`0.5 ns`) é mais curto que o período de `sys_clk` nos divisores `/2`, `/4` e `/8` (até `4.0 ns`), a travessia de comando e status entre `minisoc_spi` (`clk`) e `minisoc_aes_top` (`sys_clk`) utiliza:
1. **Disparo `START` (`clk` $\to$ `sys_clk`):** Conversão do pulso `o_aes_start` em inversão de nível (`start_toggle_clk`), sincronizada por 2-FF em `sys_clk` para gerar `start_pulse_sys` de exatamente 1 ciclo de `sys_clk` sem risco de perda de pulso.
2. **Parâmetros de Configuração (`KEY`, `IV`, `COUNTER`, `NUM_BLOCKS`, `MODE`, `DECRYPT`):** Mantidos estáveis pelo software antes do envio de `START` (Modelo de Programação, passos 3–7 e 11) e amostrados nos registradores internos do AES no ciclo de `start_pulse_sys` (*Data-Hold*).
3. **Sinais de Estado (`sys_clk` $\to$ `clk`):** `BUSY`, `DONE` e `ERROR` (1 bit cada) atravessam sincronizadores 2-FF para `clk`; `BLOCKS_DONE[8:0]` é amostrado de forma coerente no domínio `clk` (ou codificado/qualificado quando estável após cada bloco concluído e ao asserir `DONE`).

---

## 4. Mapa de Registradores CSR (32 bits — Seção 6)

Todos os registradores possuem largura de **32 bits** e endereçamento de **6 bits** (`0x00..0x3F`):

| Addr | Registro | Acesso | Reset | Descrição e Mapeamento de Bits |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | `KEY0` | R/W | `32'h0` | `cfg_key[127:96]` |
| `0x01` | `KEY1` | R/W | `32'h0` | `cfg_key[95:64]` |
| `0x02` | `KEY2` | R/W | `32'h0` | `cfg_key[63:32]` |
| `0x03` | `KEY3` | R/W | `32'h0` | `cfg_key[31:0]` |
| `0x04` | `IV0` | R/W | `32'h0` | `cfg_iv[127:96]` |
| `0x05` | `IV1` | R/W | `32'h0` | `cfg_iv[95:64]` |
| `0x06` | `IV2` | R/W | `32'h0` | `cfg_iv[63:32]` |
| `0x07` | `IV3` | R/W | `32'h0` | `cfg_iv[31:0]` |
| `0x08` | `COUNTER_HI` | R/W | `32'h0` | `cfg_counter[63:32]` |
| `0x09` | `COUNTER_LO` | R/W | `32'h0` | `cfg_counter[31:0]` |
| `0x0A` | `NUM_BLOCKS` | R/W | `32'h0` | Quantidade de blocos AES de 128 bits a processar (`1..256`). |
| `0x0B` | `AES_CONTROL` | R/W | `32'h0` | • `[0]` `START`: *write-one-pulse* (solicita nova operação; lê `0`).<br>• `[1]` `DECRYPT`: `0 = criptografia`, `1 = decriptação`.<br>• `[4:2]` `MODE`: modo de operação (`000`..`101`).<br>• `[31:5]` `reserved` (`0`). |
| `0x0C` | `AES_STATUS` | R | `32'h0` | • `[0]` `BUSY`: `1` enquanto o engine processa.<br>• `[1]` `DONE`: *sticky* após término até novo `START` válido.<br>• `[2]` `ERROR`: configuração inválida no início da operação.<br>• `[11:3]` `BLOCKS_DONE`: blocos concluídos (`0..256`).<br>• `[31:12]` `reserved` (`0`). |
| `0x0D` | `VERSION` | R | `32'h0001_0000` | Identificação da versão do front-end SPI (`v1.0.0`). |
| `0x0E` | `SYSTEM_CONTROL`| R/W | `32'h0` | • `[0]` `MEM_SEL_AES`: `0 = MEMORY DATA`, `1 = AES Engine`.<br>• `[1]` `PLL_ENABLE`: habilita o `minisoc_pll_mock`.<br>• `[3:2]` `PLL_DIV_SEL`: seleciona `/1, /2, /4, /8`.<br>• `[31:4]` `reserved` (`0`). |
| `0x0F` | `SYSTEM_STATUS` | R | `32'h0` | • `[0]` `PLL_LOCKED`: `1` quando o PLL travou e liberou `sys_clk`.<br>• `[31:1]` `reserved` (`0`). |
| `0x3F` | `NOP` | - | - | Endereço reservado para a 2ª transação de retorno de uma leitura SPI. |

---

## 5. Memória Compartilhada e Arbitragem (Seção 7)

### 5.1 Organização Física (`1024 x 32` bits, *In-Place*)
A memória física [`minisoc_memory.sv`](../../rtl/minisoc_mem/minisoc_memory.sv) possui **1024 palavras de 32 bits** (`0..1023`), comportando até **256 blocos AES de 128 bits** armazenados em ordem *big-endian* de palavras a partir da base `0` (`base = block_idx * 4`):

| Palavra do Bloco AES | Endereço na SRAM | Fatia do Bloco de 128 bits | Exemplo (`00112233_44556677_8899AABB_CCDDEEFF`) |
| :--- | :--- | :---: | :---: |
| `Word 0` | `base + 0` | `[127:96]` | `0x00112233` |
| `Word 1` | `base + 1` | `[95:64]` | `0x44556677` |
| `Word 2` | `base + 2` | `[63:32]` | `0x8899AABB` |
| `Word 3` | `base + 3` | `[31:0]` | `0xCCDDEEFF` |

### 5.2 Arbitragem de Ownership (`MEM_SEL_AES`)
Como o recurso físico é *single-port* (`LIM-MEM-01`), um multiplexador controlado por `SYSTEM_CONTROL.MEM_SEL_AES` seleciona todos os sinais do porto (`i_clk`, `i_wr_en`, `i_addr`, `i_data`):
- `MEM_SEL_AES = 0`: a interface externa `MEMORY DATA` controla a SRAM com `mem_clk`.
- `MEM_SEL_AES = 1`: o `minisoc_aes_top` controla a SRAM com `sys_clk`, lendo 4 palavras, cifrando/decifrando o bloco e gravando as 4 palavras resultantes **in-place** nos mesmos endereços (`REQ-AES-02`).
- **Regra de exclusão mútua:** a comutação de `MEM_SEL_AES` é realizada pelo software apenas com o AES ocioso (`BUSY = 0`) e sem acesso externo em andamento.

---

## 6. Microarquitetura do Engine Criptográfico AES-128 (Seção 8)

### 6.1 Primitive Criptográfico (*Cipher* e *Inverse Cipher*)
O datapath iterativo (`minisoc_aes_dp.sv`, 1 rodada por ciclo) implementa **AES-128** conforme o padrão **NIST FIPS-197**, suportando tanto o caminho direto (*Cipher*) quanto o caminho inverso (*Inverse Cipher*, necessário para decriptação em ECB, CBC e PCBC):
- **Caminho Direto (*Encrypt*):** `AddRoundKey` inicial (Round 0) $\to$ 9 rodadas de `SubBytes` (16 S-Boxes em $\text{GF}(2^8)$) + `ShiftRows` + `MixColumns` (matriz $\{02, 03, 01, 01\}$ via `xtime`) + `AddRoundKey` $\to$ Round 10 final sem `MixColumns`.
- **Caminho Inverso (*Decrypt*):** `AddRoundKey` inicial com `RoundKey[10]` $\to$ 9 rodadas de `InvShiftRows` + `InvSubBytes` (16 S-Boxes inversas) + `AddRoundKey` + `InvMixColumns` (matriz $\{0e, 0b, 0d, 09\}$ em $\text{GF}(2^8)$) $\to$ rodada final sem `InvMixColumns` com `RoundKey[0]`.
- **Expansão de Chaves (`minisoc_aes_key_exp.sv`):** Calcula as 11 *round keys* (`RoundKey[0..10]`) a partir de `cfg_key[127:0]` usando `RotWord`, `SubWord` e `Rcon[1..10]`, fornecendo subchaves na ordem `0..10` (encrypt) ou `10..0` (decrypt).

### 6.2 Modos de Operação e Equações de Encadeamento (`minisoc_aes_top.sv`)

Seja $P_i$ o bloco de entrada lido da memória (`128 bits`), $C_i$ o bloco de saída escrito *in-place*, $E_K(\cdot)$ o primitive de *Cipher* e $D_K(\cdot)$ o primitive de *Inverse Cipher*:

| `MODE` | Modo | Primitive Usado | Equação de Criptografia (`DECRYPT = 0`) | Equação de Decriptação (`DECRYPT = 1`) |
| :---: | :--- | :---: | :--- | :--- |
| `000` | **ECB** | $E_K$ / $D_K$ | $C_i = E_K(P_i)$ | $P_i = D_K(C_i)$ |
| `001` | **CBC** | $E_K$ / $D_K$ | $C_i = E_K(P_i \oplus V_i),\; V_{i+1} = C_i$ | $P_i = D_K(C_i) \oplus V_i,\; V_{i+1} = C_i$ |
| `010` | **PCBC** | $E_K$ / $D_K$ | $C_i = E_K(P_i \oplus V_i),\; V_{i+1} = P_i \oplus C_i$ | $P_i = D_K(C_i) \oplus V_i,\; V_{i+1} = P_i \oplus C_i$ |
| `011` | **CFB** | Sempre $E_K$ | $C_i = P_i \oplus E_K(V_i),\; V_{i+1} = C_i$ | $P_i = C_i \oplus E_K(V_i),\; V_{i+1} = C_i$ |
| `100` | **OFB** | Sempre $E_K$ | $O_i = E_K(V_i),\; C_i = P_i \oplus O_i,\; V_{i+1} = O_i$ | $O_i = E_K(V_i),\; P_i = C_i \oplus O_i,\; V_{i+1} = O_i$ |
| `101` | **CTR** | Sempre $E_K$ | $T_i = \text{IV} \oplus \{64\text{'d0}, \text{cnt}_i\},\; C_i = P_i \oplus E_K(T_i)$ | $T_i = \text{IV} \oplus \{64\text{'d0}, \text{cnt}_i\},\; P_i = C_i \oplus E_K(T_i)$ |

*(Onde $V_0 = \text{cfg\_iv}$ e, no modo CTR, $\text{cnt}_0 = \text{cfg\_counter}[63:0]$ com $\text{cnt}_{i+1} = \text{cnt}_i + 1$ por bloco).*

### 6.3 Validação de Configuração e Tratamento de `ERROR` (Seções 8.2 e 8.4)
No início de cada `START`:
- Se `NUM_BLOCKS == 0`, `NUM_BLOCKS > 256` ou `MODE > 3'b101` (`3'b110` ou `3'b111`), a configuração é inválida: o engine **não modifica a memória**, zera `BLOCKS_DONE`, eleva `ERROR = 1` (e encerra sem processamento normal).
- Caso contrário, o comando é um `START` válido: limpa `DONE` e `ERROR`, eleva `BUSY = 1`, processa `0..NUM_BLOCKS-1` incrementando `BLOCKS_DONE` a cada bloco gravado e, ao terminar, limpa `BUSY = 0` e mantém `DONE = 1` (*sticky* até o próximo `START` válido).

---

## 7. Modelo de Programação (Seção 9)

Fluxo operacional completo esperado pelo software ou testbench UVM:
1. Selecionar `MEM_SEL_AES = 0` em `SYSTEM_CONTROL` (`0x0E`) para manter a memória sob posse externa.
2. Escrever os blocos de entrada (`4` palavras de 32 bits por bloco) usando `MEMORY DATA`.
3. Programar a chave de 128 bits em `KEY0..KEY3` (`0x00..0x03`).
4. Programar o vetor de inicialização em `IV0..IV3` (`0x04..0x07`) quando o modo utilizar IV.
5. Programar o contador inicial em `COUNTER_HI` / `COUNTER_LO` (`0x08..0x09`) quando em modo `CTR`.
6. Programar `NUM_BLOCKS` (`0x0A`) com valor entre `1` e `256`.
7. Programar `MODE` e `DECRYPT` em `AES_CONTROL` (`0x0B`), com `START = 0`.
8. Programar `PLL_DIV_SEL` e `PLL_ENABLE = 1` em `SYSTEM_CONTROL` (`0x0E`).
9. Ler `SYSTEM_STATUS` (`0x0F`, em 2 transações SPI) até `PLL_LOCKED == 1`.
10. Transferir a posse da memória ao AES escrevendo `MEM_SEL_AES = 1` em `SYSTEM_CONTROL` (`0x0E`).
11. Escrever `START = 1` (junto a `MODE` e `DECRYPT`) em `AES_CONTROL` (`0x0B`).
12. Ler `AES_STATUS` (`0x0C`) até `DONE == 1`, verificando `ERROR == 0` e `BLOCKS_DONE == NUM_BLOCKS`.
13. Retornar a memória ao usuário escrevendo `MEM_SEL_AES = 0` em `SYSTEM_CONTROL` (`0x0E`).
14. Ler os blocos processados *in-place* através da interface `MEMORY DATA`.
