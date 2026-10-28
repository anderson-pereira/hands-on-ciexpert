# Subsistema SPI Front-End — MiniSoC AES (`rtl/minisoc_spi/`)

Implementação modular em SystemVerilog do **SPI Front-End + CDC + Banco de Registradores CSR de 32 bits**, 100% alinhada à especificação oficial [`DV_BlockGuide_MiniSoCAES_v1.0.0.pdf`](../references/DV_BlockGuide_MiniSoCAES_v1.0.0.pdf) (Seções 2.2, 5, 6 e 10).

> **Nota sobre o histórico:** A implementação preliminar anterior (baseada em protocolo *In-Frame* de 8 bits com *dummy byte* e *burst* auto-incrementado) foi preservada integralmente junto ao seu testbench e esquemático em [`backups/spi_inframe_burst_backup.zip`](../../backups/spi_inframe_burst_backup.zip) para eventual reutilização futura.

---

## 1. Características do Protocolo SPI (Seções 5.1 e 5.2)

- **Modo de Operação:** SPI Mode 0 (`CPOL = 0`, `CPHA = 0`), ordem **MSB-first**, seleção ativa em nível baixo (`spi_cs_n = 0`).
- **Temporização Serial:**
  - `spi_mosi` amostrado na **borda de subida** (`posedge spi_sclk`);
  - `spi_miso` atualizado na **borda de descida** (`negedge spi_sclk`), mantido em `0` quando `spi_cs_n = 1`;
  - Frequência máxima de `spi_sclk`: **25 MHz** (`REQ-SPI-01`).
- **Formato Fixo de Frame (40 bits, sem burst):**
  ```text
    39       38:33       32              31:0
  +-----+-------------+-----+-----------------------------+
  | RWb |  ADDR[5:0]  | RSV |         DATA[31:0]          |
  +-----+-------------+-----+-----------------------------+
   1 bit     6 bits    1 bit            32 bits
  ```
  - `RWb` (`[39]`): `0 = WRITE`, `1 = READ request`.
  - `ADDR` (`[38:33]`): Endereço de 6 bits do registrador CSR (`0x00..0x3F`).
  - `RSV` (`[32]`): Reservado (enviado como `0`).
  - `DATA` (`[31:0]`): Payload de 32 bits para escrita; ignorado na recepção durante um `READ request`.

### Modo de Uso: Escrita vs. Leitura *Out-of-Frame*
- **Escrita (`WRITE`):** Realizada em **1 frame** de 40 bits (`RWb = 0`, `ADDR`, `RSV = 0`, `DATA[31:0]`).
- **Leitura (`READ`):** Realizada em **2 frames** de 40 bits (padrão industrial *Out-of-Frame Response*):
  1. **1º Frame (`READ request`):** O mestre envia `{1'b1, ADDR[5:0], 1'b0, 32'h0}`. Ao final do 40º pulso de `spi_sclk`, o evento de frame completo cruza o CDC para o domínio `clk` always-on e carrega o valor de 32 bits do registrador em `rd_data_hold[31:0]`.
  2. **2º Frame (Fase de retorno):** O mestre envia um novo frame com o endereço reservado `ADDR = 6'h3F` (`NOP`) — ou já um próximo comando `READ`/`WRITE` encadeado em *pipeline* — enquanto o escravo desloca `8'h00` nos bits `[39:32]` e o valor lido nos bits `[31:0]` através de `spi_miso`.
- **Enquadramento Flexível de `spi_cs_n` (Pulsado ou Contínuo Módulo-40):** O contador `bit_cnt` em `minisoc_spi_phy` opera em **módulo-40** (`0..39 -> 0`), suportando transparentemente tanto transações delimitadas por pulso de `spi_cs_n` (`1 -> 0 -> 1` a cada 40 bits) quanto *streaming* contínuo de múltiplos frames de 40 bits mantendo `spi_cs_n = 0` (ex.: 80 pulsos contínuos para `READ + NOP`, facilitando a interface com controladores SPI padrão), preservando o aborto seguro de *runt frames* incompletos (`< 40` bits) ao subir `spi_cs_n = 1`.

---

## 2. Regra de Bootstrap e Clock-Domain Crossing (Seções 2.2 e 5.3)

- **Domínio Always-On (`clk`, 2 GHz):** Diferente do domínio do AES (`sys_clk`, que permanece bloqueado enquanto `PLL_LOCKED = 0`), todo o banco CSR opera no clock de referência always-on `clk`. Isso permite configurar `PLL_DIV_SEL`, escrever `PLL_ENABLE = 1` e monitorar `PLL_LOCKED` por SPI antes da liberação do clock do sistema.
- **CDC de Frame Completo (`spi_sclk` $\to$ `clk`) e Estratégia de Reset:** No 40º `posedge spi_sclk` (`bit_cnt == 39`), a palavra de 40 bits é travada em `rx_frame_hold` (*Data-Hold*) e `req_toggle` inverte de estado, atravessando um sincronizador **2-FF** no domínio `clk`. Para maximizar o QoR na síntese SAED 32nm (sem arcos de *recovery/removal*), o lado `clk` (`minisoc_spi_csr` e estágio destino de `minisoc_spi_cdc`) utiliza **reset síncrono** (`posedge clk`), mantendo reset assíncrono estritamente onde `spi_sclk` permanece parado: `spi_cs_n = 1` na PHY e `negedge rst_n` nos registradores fonte `rx_frame_hold` / `req_toggle` (evitando propagação de `'X'` no boot).
- **Retorno de Leitura (`clk` $\to$ `spi_sclk`):** Como `clk` (`2 GHz`, `T = 0.5 ns`) é 80× mais rápido que `spi_sclk` ($\le 25\text{ MHz}$, `T >= 40 ns`), `rd_data_hold[31:0]` estabiliza em ~`1.5 ns` após o término da 1ª transação e é capturado em `tx_shift[31:0]` na 1ª borda de descida da 2ª transação, garantindo ausência total de corrida mesmo em leituras em *pipeline*.

---

## 3. Mapa de Registradores CSR (32 bits — Seção 6)

| Endereço | Registro | Acesso | Descrição / Campos |
| :---: | :--- | :---: | :--- |
| `0x00..0x03` | `KEY0..KEY3` | R/W | `cfg_key[127:0]` (`KEY0 = [127:96]`, ..., `KEY3 = [31:0]`) |
| `0x04..0x07` | `IV0..IV3` | R/W | `cfg_iv[127:0]` (`IV0 = [127:96]`, ..., `IV3 = [31:0]`) |
| `0x08..0x09` | `COUNTER_HI / LO` | R/W | `cfg_counter[63:0]` (`HI = [63:32]`, `LO = [31:0]`) |
| `0x0A` | `NUM_BLOCKS` | R/W | Quantidade de blocos AES de 128 bits (`1..256`) |
| `0x0B` | `AES_CONTROL` | R/W | `[0]` `START` (*write-1-pulse*, lê `0`), `[1]` `DECRYPT`, `[4:2]` `MODE` |
| `0x0C` | `AES_STATUS` | R | `[0]` `BUSY`, `[1]` `DONE` (*sticky*), `[2]` `ERROR`, `[11:3]` `BLOCKS_DONE` |
| `0x0D` | `VERSION` | R | Identificação da versão do front-end (`32'h0001_0000`) |
| `0x0E` | `SYSTEM_CONTROL` | R/W | `[0]` `MEM_SEL_AES`, `[1]` `PLL_ENABLE`, `[3:2]` `PLL_DIV_SEL` |
| `0x0F` | `SYSTEM_STATUS` | R | `[0]` `PLL_LOCKED` |
| `0x3F` | `NOP` | - | Reservado para a 2ª transação (retorno) de leituras SPI |

---

## 4. Organização Modular dos Arquivos (`rtl/minisoc_spi/`)

Seguindo a árvore da Seção 10 do Block Guide com separação interna limpa entre PHY, CDC e CSR:

- [`rtl/minisoc_spi/minisoc_spi_pkg.sv`](../../rtl/minisoc_spi/minisoc_spi_pkg.sv): Endereços CSR de 6 bits, struct empacotada `spi_frame_t` (40 bits), enums `aes_mode_e` e `pll_div_sel_e`.
- [`rtl/minisoc_spi/minisoc_spi_if.sv`](../../rtl/minisoc_spi/minisoc_spi_if.sv): Interfaces SystemVerilog com `modports` (`minisoc_spi_phy_if`, `minisoc_spi_cdc_if`, `minisoc_spi_csr_if`).
- [`rtl/minisoc_spi/minisoc_spi_phy.sv`](../../rtl/minisoc_spi/minisoc_spi_phy.sv): Deserializador RX de 40 bits (`posedge spi_sclk`) e serializador TX de 32 bits (`negedge spi_sclk`).
- [`rtl/minisoc_spi/minisoc_spi_cdc.sv`](../../rtl/minisoc_spi/minisoc_spi_cdc.sv): Sincronizador de evento/toggle de frame completo (`spi_sclk` $\leftrightarrow$ `clk`).
- [`rtl/minisoc_spi/minisoc_spi_csr.sv`](../../rtl/minisoc_spi/minisoc_spi_csr.sv): Banco completo de registradores de 32 bits no domínio `clk`.
- [`rtl/minisoc_spi/minisoc_spi.sv`](../../rtl/minisoc_spi/minisoc_spi.sv): Wrapper de integração do bloco SPI para conexão direta no `minisoc_top`.
- [`tb/tb_minisoc_spi.sv`](../../tb/tb_minisoc_spi.sv): Testbench auto-verificante integrando `minisoc_spi`, `minisoc_pll_mock` e `minisoc_memory`.

---

## 5. Compilação, Lint e Simulação

```bash
# Checagem estrita de sintaxe e lint (+lint=all no Synopsys Vlogan)
make lint

# Compilação e simulação completa do subsistema SPI + PLL Bootstrap + Memória (Synopsys VCS)
make sim_spi
```
