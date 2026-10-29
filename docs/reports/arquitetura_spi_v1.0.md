# Projeto Hands-on — RTL Design Track

## Relatório da Semana 2: Definição da Arquitetura e Microarquitetura do MiniSoC AES (v1.0.0)

**Autor:** Anderson Pereira  
**Documentos de Apoio:** [DV_BlockGuide_MiniSoCAES_v1.0.0.pdf](../references/DV_BlockGuide_MiniSoCAES_v1.0.0.pdf) | [Planejamento-Projeto-Hands-on.pdf](../references/Planejamento-Projeto-Hands-on.pdf) | [arquitetura_v1.0.md](../architecture/arquitetura_v1.0.md) | [BACKLOG.md](BACKLOG.md)

---

## 1. Escopo e Objetivos da Semana 2

A segunda semana consolidou o **Documento de Arquitetura e Microarquitetura v1.0.0** do sistema **`MiniSoC AES`** (`minisoc_top`), alinhado integralmente à especificação oficial compartilhada com a trilha parceira de *Design Verification (DV)* (`DV_BlockGuide_MiniSoCAES_v1.0.0.pdf`):

1. **Diagrama de Blocos e Hierarquia Padronizada (`rtl/minisoc_*/`)**: Particionamento em quatro blocos funcionais (`minisoc_spi`, `minisoc_pll_mock`, `minisoc_aes_top` e `minisoc_memory`) integrados em `minisoc_top.sv`.
2. **Interfaces de Topo Compatíveis com DV**: Assinaturas exatas para `CLK` (`clk` de 2 GHz), `RESET` (`rst_n`), `SPI` (`spi_sclk`, `spi_cs_n`, `spi_mosi`, `spi_miso` até 25 MHz) e `MEMORY DATA` (`mem_clk`, `mem_i_data[31:0]`, `mem_i_wr_en`, `mem_i_addr[9:0]`, `mem_o_data[31:0]` até 200 MHz).
3. **Regra de Bootstrap, Clock/PLL e Dupla Fronteira CDC**:
   - Banco CSR do SPI operando no clock de referência always-on `clk` (2 GHz), permitindo configurar e habilitar o PLL enquanto `sys_clk` está bloqueado;
   - Travessia `spi_sclk` $\leftrightarrow$ `clk` via toggle de evento de **frame completo (40 bits)** e *Data-Hold*;
   - Travessia `clk` $\leftrightarrow$ `sys_clk` (`/1, /2, /4, /8`) para pulso `START` e indicadores de status do AES.
4. **Mapa de Registradores CSR de 32 bits (`0x00..0x0F`, `0x3F NOP`)**: Suporte a `KEY0..3`, `IV0..3`, `COUNTER_HI/LO`, `NUM_BLOCKS` (`1..256`), `AES_CONTROL`, `AES_STATUS` (`BLOCKS_DONE`), `VERSION`, `SYSTEM_CONTROL` (`MEM_SEL_AES`, `PLL_ENABLE`, `PLL_DIV_SEL`) e `SYSTEM_STATUS` (`PLL_LOCKED`).
5. **Microarquitetura do AES-128 Multi-Modo e Memória *In-Place***: Suporte a *Cipher* e *Inverse Cipher* nos 6 modos (`ECB, CBC, PCBC, CFB, OFB, CTR`) operando *in-place* sobre a SRAM compartilhada single-port de $1024 \times 32$ bits.
6. **Subsistema SPI e Modelos RTL Validados**: Implementação sintetizável e livre de avisos de lint (`+lint=all`) do `minisoc_spi` modular (`phy + cdc + csr`), `minisoc_pll_mock` e `minisoc_memory`, verificados em simulação no VCS (`tb_minisoc_spi.sv`).

---

## 2. Interfaces de Topo (`minisoc_top.sv`)

| Grupo | Sinal | Direção | Largura | Descrição |
| :--- | :--- | :---: | :---: | :--- |
| **CLK** | `clk` | `input` | 1 | Clock de referência always-on de **2 GHz**. |
| **RESET** | `rst_n` | `input` | 1 | Reset global ativo em nível baixo (`0`). |
| **SPI** | `spi_sclk` | `input` | 1 | Clock serial SPI Mode 0 ($\le 25\text{ MHz}$). |
| | `spi_cs_n` | `input` | 1 | *Chip Select* ativo em nível baixo (`0`). |
| | `spi_mosi` | `input` | 1 | Dados serializados Mestre $\to$ Escravo. |
| | `spi_miso` | `output` | 1 | Dados serializados Escravo $\to$ Mestre. |
| **MEMORY DATA** | `mem_clk` | `input` | 1 | Clock externo da interface de memória ($\le 200\text{ MHz}$). |
| | `mem_i_data` | `input` | 32 | Palavra de escrita externa na memória. |
| | `mem_i_wr_en` | `input` | 1 | `1 = write`, `0 = read`. |
| | `mem_i_addr` | `input` | 10 | Endereço de palavra de 32 bits (`0..1023`). |
| | `mem_o_data` | `output` | 32 | Palavra lida sincronamente da memória. |

---

## 3. Subsistema SPI Out-of-Frame, Bootstrap e Modelos RTL

1. **Protocolo SPI de 40 bits (*Out-of-Frame Read*)**:
   - Quadro fixo `{RWb[39], ADDR[38:33], RSV[32], DATA[31:0]}` sem *burst*.
   - **Write:** 1 transação (`RWb = 0`).
   - **Read:** 2 transações (`1ª = READ request` selecionando o endereço; `2ª = NOP 0x3F` deslocando os 32 bits lidos em `spi_miso`, suportando inclusive leituras encadeadas em *pipeline*).
2. **Módulos Implementados e Simulados (`make sim_spi`)**:
   - [`rtl/minisoc_spi/`](../../rtl/minisoc_spi/): `minisoc_spi_pkg.sv`, `minisoc_spi_if.sv`, `minisoc_spi_phy.sv`, `minisoc_spi_cdc.sv`, `minisoc_spi_csr.sv` e wrapper `minisoc_spi.sv`.
   - [`rtl/minisoc_pll/minisoc_pll_mock.sv`](../../rtl/minisoc_pll/minisoc_pll_mock.sv): Divisor `/1, /2, /4, /8` a partir de `2 GHz` com tempo de aquisição pseudoaleatório via LFSR e liberação *glitch-free* de `o_sys_clk` pós-`o_locked`.
   - [`rtl/minisoc_mem/minisoc_memory.sv`](../../rtl/minisoc_mem/minisoc_memory.sv): SRAM single-port síncrona $1024 \times 32$ bits sem reset funcional no array.

---

## 4. Próximos Passos (Semanas 3 e 4)

- Implementar `rtl/minisoc_aes/minisoc_aes_dp.sv` contemplando *Cipher* (`SubBytes`, `ShiftRows`, `MixColumns`, `AddRoundKey`) e *Inverse Cipher* (`InvShiftRows`, `InvSubBytes`, `InvMixColumns`), validado contra os vetores intermediários do **NIST FIPS-197**;
- Implementar `rtl/minisoc_aes/minisoc_aes_key_exp.sv` e o controlador multi-bloco/multi-modo `rtl/minisoc_aes/minisoc_aes_top.sv` (`ECB, CBC, PCBC, CFB, OFB, CTR`, `1..256` blocos *in-place* e detecção de `ERROR`).
