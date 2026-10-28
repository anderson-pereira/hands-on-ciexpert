# Backlog do Projeto - Acelerador AES com SPI (Trilha RTL)

Este backlog segue uma estrutura baseada em *User Stories* (US) alinhadas às fases e semanas do projeto, detalhando as tarefas de especificação, microarquitetura, implementação em SystemVerilog no nível de transferência entre registradores (RTL - *Register-Transfer Level*), síntese lógica, verificação formal de equivalência e aplicação de técnicas de baixo consumo.

> [!NOTE]
> O planejamento das tarefas reflete a microarquitetura prevista para o sistema e poderá ser ajustado dinamicamente conforme o andamento do projeto e as orientações fornecidas pelo instrutor.

---

## 📖 Glossário de Siglas e Abreviações Técnicas

Para assegurar clareza e precisão na documentação, a tabela abaixo consolida as siglas empregadas ao longo deste backlog:

| Sigla | Termo em Inglês | Significado / Contexto no Projeto |
| :--- | :--- | :--- |
| **AES** | *Advanced Encryption Standard* | Padrão de cifra de bloco criptográfica simétrica (128 bits) especificado na norma NIST FIPS-197. |
| **CDC** | *Clock Domain Crossing* | Travessia de sinais e dados entre domínios de clock assíncronos (`SCLK` e `clk_sys`). |
| **CS_N** | *Chip Select (Active-Low)* | Linha de seleção do periférico SPI, ativa em nível lógico baixo (`0`). |
| **CSR** | *Control and Status Registers* | Banco de registradores dedicados a comandos de controle, parâmetros e leitura de status do IP. |
| **DV** | *Design Verification* | Trilha parceira responsável pela verificação funcional e testes com testbench UVM. |
| **E2E** | *End-to-End* | Teste ou simulação de integração ponta a ponta, exercitando todo o caminho de dados. |
| **FSM** | *Finite State Machine* | Máquina de estados finitos que sequencia o controle de um bloco síncrono. |
| **ICG** | *Integrated Clock Gating* | Célula integrada da biblioteca padrão usada para desligar seletivamente o clock de lógica ociosa. |
| **IP** | *Intellectual Property* | Bloco funcional de hardware reutilizável (o acelerador criptográfico desenvolvido). |
| **I/O** | *Input / Output* | Portas de entrada e saída de dados e sinais do circuito. |
| **LUT** | *Look-Up Table* | Tabela estática de mapeamento em hardware (utilizada na substituição de bytes da S-Box). |
| **PDK** | *Process Design Kit* | Conjunto de modelos, regras e bibliotecas de células padrão fornecido para a tecnologia de fabricação. |
| **PICO** | *Peripheral In, Controller Out* | Linha serial de dados enviada do controlador (mestre) para o periférico (substitui a sigla MOSI). |
| **POCI** | *Peripheral Out, Controller In* | Linha serial de dados enviada do periférico para o controlador (substitui a sigla MISO). |
| **PLL** | *Phase-Locked Loop* | Bloco analógico/misto gerador do clock principal do sistema (`clk_sys`), instanciado como *mock* na fase RTL. |
| **PST** | *Power State Table* | Tabela em UPF que define combinações válidas de modos de operação e estados de tensão do circuito. |
| **RO / RW** | *Read-Only / Read-Write* | Modos de permissão de acesso a registradores (Apenas Leitura / Leitura e Escrita). |
| **RTL** | *Register-Transfer Level* | Nível de abstração de modelagem de hardware em SystemVerilog baseado em registradores e operações lógicas. |
| **S-Box** | *Substitution Box* | Matriz de substituição não linear de bytes fundamentada no corpo de Galois $\text{GF}(2^8)$. |
| **SCK / SCLK** | *Serial Clock* | Sinal de clock serial fornecido externamente pelo controlador do barramento SPI. |
| **SDC** | *Synopsys Design Constraints* | Formato padrão de especificação de restrições de temporização e temporização estática (STA). |
| **SPI** | *Serial Peripheral Interface* | Barramento serial síncrono de 4 vias adotado para controle e configuração do acelerador. |
| **SVF** | *Standard Verification Format* | Arquivo de orientações (*guidance*) gerado na síntese para acelerar a verificação formal no Formality. |
| **UPF** | *Unified Power Format* | Padrão IEEE 1801 para descrição da arquitetura de energia e técnicas de baixo consumo. |
| **US** | *User Story* | Unidade de planejamento que agrupa as tarefas e metas de uma etapa do projeto. |

---

## 📌 US1: Especificação e Arquitetura (Semanas 1 e 2)
**Objetivo:** Garantir a prontidão do ambiente de desenvolvimento, fluxo automatizado e mapear o contrato de hardware (interfaces, registradores e isolamento de domínios).

- [x] **Task 1.1:** Preparar ambiente base com estrutura de diretórios, automação via Makefile (checagem estática de *Lint*, simulação funcional, síntese lógica, equivalência formal e suporte a UPF) e relatório técnico da Semana 1.
- [x] **Task 1.2:** Desenhar o diagrama de blocos de alto nível mapeando as partições internas do sistema: `SPI IF` (*SPI Interface*), `CDC` (*Clock Domain Crossing*), `FSM SPI` (máquina de estados do protocolo SPI), `Controlador/CSR` (*Control and Status Registers*), núcleo criptográfico `AES`, subsistema de `Memória`, gerador de `RESET` e `PLL` (*Phase-Locked Loop*).
- [x] **Task 1.3:** Especificar a tabela de Mapa de Registradores CSR (*Control and Status Registers*) acessíveis via barramento SPI (endereçamento, bitfields, permissões RW/RO — *Read-Write / Read-Only*, flags de status e comandos de controle).
- [x] **Task 1.4:** Definir a estratégia e arquitetura de Clock/Reset, explicitando os mecanismos de travessia assíncrona CDC (*Clock Domain Crossing*) entre o domínio serial `SCLK` (SPI) e o domínio de sistema `clk_sys` gerado pelo PLL.
- [x] **Task 1.5:** Formalizar contratos e interfaces físicas de I/O (*Input/Output*, larguras de barramento, sinais de handshake) para os modelos de apoio em simulação (mock de Memória e mock de PLL com sinal de travamento `locked`).
- [x] **Task 1.6:** Definir a microarquitetura do núcleo AES (arquitetura iterativa por rodada, sub-rotinas de transformação criptográfica e interfaces de controle com CSR e transferência com memória).
- [x] **Task 1.7:** Consolidar e revisar o Documento de Arquitetura (v1.0).

---

## 📌 US2: Desenvolvimento RTL Sistêmico (Semanas 3 a 6)
**Objetivo:** Implementar e integrar a lógica funcional em SystemVerilog conforme a microarquitetura proposta, culminando na primeira versão estável do IP (RTL v1.0).

> **Fluxo Arquitetural do Sistema:**  
> `SPI IF` (Interface Serial) $\longrightarrow$ `CDC` (Sincronização de Domínios) $\longrightarrow$ `FSM SPI` (Controle de Quadro) $\longrightarrow$ `Controlador da Aplicação / CSR` (Registradores) $\longrightarrow$ `AES Core` (Datapath) $\longrightarrow$ `Memória`

- [ ] **Task 2.1 — Datapath do AES (`minisoc_aes_dp.sv`) — Cipher e Inverse Cipher (Semana 3):**
  - Implementar o datapath da matriz de estado do AES (128 bits) suportando cifragem (*Cipher*) e decifragem direta (*Inverse Cipher*):
    - `SubBytes` / `InvSubBytes`: substituição não linear byte a byte via S-Box e InvS-Box em $\text{GF}(2^8)$;
    - `ShiftRows` / `InvShiftRows`: deslocamento cíclico de linhas direto e inverso;
    - `MixColumns` / `InvMixColumns`: difusão linear matricial em $\text{GF}(2^8)$;
    - `AddRoundKey`: combinação XOR de 128 bits entre estado e subchave da rodada.
  - Implementar testbench unitário validando cada transformação isolada contra os valores intermediários de referência da norma NIST FIPS-197.

- [ ] **Task 2.2 — Expansão de Chave (`minisoc_aes_key_exp.sv`) e Engine Multi-Modo (`minisoc_aes_top.sv`) (Semana 4):**
  - Implementar a expansão de chave para 128 bits (`RotWord`, `SubWord`, `Rcon`) suportando acesso direto (`0..10`) e reverso (`10..0`);
  - Implementar o controlador de modos (`ECB`, `CBC`, `PCBC`, `CFB`, `OFB`, `CTR`), processamento *in-place* de `1..256` blocos (4 palavras de 32 bits por bloco), validação de parâmetros (`ERROR`) e indicação *sticky* de `DONE` e `BLOCKS_DONE`;
  - Validar o núcleo completo em testbench dirigido com vetores FIPS-197 e vetores multi-bloco para os 6 modos.

- [x] **Task 2.3 — Interface SPI de 40 bits e Sincronização CDC (`minisoc_spi_phy.sv`, `minisoc_spi_cdc.sv`) (Semana 5):**
  - Implementar a camada física SPI Mode 0 MSB-first (`spi_sclk` até 25 MHz) com quadro fixo de 40 bits (`{RWb, ADDR[5:0], RSV, DATA[31:0]}`) e leitura *Out-of-Frame* em duas transações;
  - Implementar a travessia CDC de evento/toggle de frame completo (`spi_sclk` $\leftrightarrow$ `clk` always-on de 2 GHz) com sincronizador 2-FF e retenção estática (*Data-Hold*).

- [x] **Task 2.4 — Banco CSR de 32 bits e Wrapper SPI (`minisoc_spi_csr.sv`, `minisoc_spi.sv`) (Semana 5):**
  - Implementar o banco CSR completo de 32 bits no domínio always-on `clk` (`KEY0..3`, `IV0..3`, `COUNTER_HI/LO`, `NUM_BLOCKS`, `AES_CONTROL`, `AES_STATUS`, `VERSION`, `SYSTEM_CONTROL`, `SYSTEM_STATUS` e `NOP = 0x3F`), atendendo à regra de *bootstrap* do PLL;
  - Encapsular PHY + CDC + CSR no módulo `rtl/minisoc_spi/minisoc_spi.sv` e validar em testbench dirigido (`tb/tb_minisoc_spi.sv`).

- [x] **Task 2.5 — Memória Compartilhada e Modelo RTL do PLL (`minisoc_memory.sv`, `minisoc_pll_mock.sv`) (Semanas 5 e 6):**
  - Implementar `rtl/minisoc_mem/minisoc_memory.sv` (SRAM single-port síncrona $1024 \times 32$ bits sem reset funcional no array);
  - Implementar `rtl/minisoc_pll/minisoc_pll_mock.sv` (referência de 2 GHz, `PLL_ENABLE`, divisores `/1, /2, /4, /8`, atraso pseudoaleatório por LFSR e liberação *glitch-free* de `o_sys_clk` pós-`o_locked`).

- [ ] **Task 2.6 — Integração do Top-Level (`minisoc_top.sv`) e Verificação Ponta a Ponta (Semana 6):**
  - Integrar `minisoc_spi`, `minisoc_pll_mock`, `minisoc_aes_top` e `minisoc_memory` em `rtl/minisoc_top.sv` (incluindo reset determinístico pós-lock `sys_rst_n`, CDC `clk` $\leftrightarrow$ `sys_clk` e mux de exclusão mútua `MEM_SEL_AES`);
  - Executar simulação E2E seguindo os 14 passos do Modelo de Programação do Block Guide;
  - Executar análise estática de *Lint* e *CDC* e emitir a **TAG RTL v1.0**.

---

## 📌 US3: Síntese Lógica e Baseline (Semana 7)
**Objetivo:** Definir restrições temporais (SDC) e sintetizar o RTL v1.0 para uma netlist base, avaliando área, temporização e potência de referência.

- [ ] **Task 3.1:** Desenvolver restrições temporais no formato SDC (*Synopsys Design Constraints*): declaração de clocks assíncronos `SCLK` e `CLK_SYS`, períodos nominais, atrasos de entrada/saída (I/O delays) e restrições dos caminhos de sincronização entre domínios.
- [ ] **Task 3.2:** Configurar caixas-pretas (*blackboxes*) no script de síntese para isolar os modelos comportamentais de memória e PLL durante o mapeamento tecnológico contra as células do PDK (*Process Design Kit*).
- [ ] **Task 3.3:** Executar a síntese lógica com as bibliotecas do PDK e extrair relatórios de área (contagem de células/portas equivalentes), temporização (análise de atraso de *setup* e *hold*) e potência estimada (estática e dinâmica).
- [ ] **Task 3.4:** Analisar relatórios para identificar latches não intencionais e caminhos críticos de temporização, consolidando o relatório de métricas de referência (*Baseline*).

---

## 📌 US4: Verificação Formal de Equivalência (Semanas 8 e 9)
**Objetivo:** Verificar a equivalência lógica entre o RTL de referência (Golden) e a netlist sintetizada (Implementation) utilizando o Synopsys Formality.

- [ ] **Task 4.1:** Configurar o fluxo de verificação formal de equivalência (*Match* e *Verify*) no Synopsys Formality comparando o RTL com a netlist, alimentando o arquivo de orientações SVF (*Standard Verification Format* / Guidance).
- [ ] **Task 4.2:** Depurar divergências e pontos não verificados, analisando registradores removidos por otimização da ferramenta de síntese, constantes propagadas ou ausência de guidance.
- [ ] **Task 4.3:** Executar teste de injeção intencional de falhas (*Fault Injection*) para validar a eficácia da ferramenta Formality na detecção de discrepâncias e não-equivalências lógicas.
- [ ] **Task 4.4:** Consolidar correções funcionais eventuais e emitir a **TAG RTL v1.1**.

---

## 📌 US5: Intenção de Potência com UPF (Semanas 10 e 11)
**Objetivo:** Definir a arquitetura de baixo consumo e descrever a intenção de potência utilizando o padrão IEEE 1801 (UPF).

- [ ] **Task 5.1:** Analisar o perfil de atividade dos blocos funcionais e definir a Tabela de Estados de Potência (PST — *Power State Table*), determinando os modos de operação (Ativo, Ocioso e *Power Gating*).
- [ ] **Task 5.2:** Definir as estratégias de gerenciamento de energia: domínios sempre energizados (*Always-On*: Reset, PLL, SPI), ilhas comutáveis com corte de alimentação (*Power Switching* para o núcleo AES), células de isolamento nas saídas e flip-flops com retenção de estado.
- [ ] **Task 5.3:** Escrever o arquivo de especificação de intenção de potência em UPF (*Unified Power Format*) e validar a sintaxe e a consistência estática contra a hierarquia RTL.
- [ ] **Task 5.4:** Executar simulação sensível à potência (*Power-Aware Simulation*), verificando a propagação de valores desconhecidos ('X') em domínios desenergizados e a correta atuação das células de isolamento e retenção de estado.

---

## 📌 US6: Técnicas de Baixo Consumo Aplicadas (Semanas 12 a 14)
**Objetivo:** Implementar os circuitos de gerenciamento de energia (Power Gating e Clock Gating) no RTL e sintetizar a netlist low-power.

- [ ] **Task 6.1:** Desenvolver o Controlador de Energia (FSM de *power gating*) para coordenar a sequência de isolamento, salvamento de estado, corte de alimentação (*shutdown*), religamento, restauração e liberação do isolamento.
- [ ] **Task 6.2:** Identificar oportunidades de economia dinâmica e inserir células integradas de chaveamento de clock (ICG — *Integrated Clock Gating*) na árvore de clock do datapath e em registradores de alta atividade.
- [ ] **Task 6.3:** Validar as transições dinâmicas entre modos de energia em simulação funcional e emitir a **TAG RTL v2.0 (Low Power)**.
- [ ] **Task 6.4:** Executar síntese lógica com o arquivo UPF e inserção automatizada de *Clock Gating*, reexecutando a verificação de equivalência formal no Formality considerando as regras de baixo consumo.
- [ ] **Task 6.5:** Comparar dados de área, temporização e potência da netlist *Low Power* contra o relatório *Baseline* da Semana 7 (US3), elaborando documento técnico comparativo com análise quantitativa de custos e benefícios.

---

## 📌 US7: Encerramento e Release Final (Semana 15)
**Objetivo:** Consolidar a documentação do projeto, garantir a reprodutibilidade do fluxo automatizado e finalizar a entrega técnica.

- [ ] **Task 7.1:** Limpar e organizar o repositório, garantindo a execução autônoma do fluxo completo de compilação, simulação, síntese e equivalência formal a partir do Makefile.
- [ ] **Task 7.2:** Responder e registrar a resolução das revisões técnicas e *issues* submetidas pelo parceiro da trilha de Verificação (DV — *Design Verification*).
- [ ] **Task 7.3:** Consolidar o pacote de entrega final (*Release*), englobando todos os relatórios e especificações de arquitetura, scripts, restrições SDC, arquivos UPF e o artigo técnico sumarizando a trilha.
