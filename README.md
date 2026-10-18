# Immunefi Foundry — Do zero ao exploit

Laboratório de Foundry em Ethereum. Do diagnóstico à reprodução de um exploit
real de **~$197M** (Euler Finance, 13/03/2023) contra contratos reais da
mainnet, em fork histórico.

Mais uma metade: **caça em código de produção** — auditoria do código atual da
ENS, cinco hipóteses, cinco refutadas, nenhum report. Ver
[`docs/06_ENS_HUNT.md`](docs/06_ENS_HUNT.md).

```
24 testes · 5 suítes · todos passando
```

| Suíte | Testes | O que prova |
|---|---|---|
| `F0ForkBalance` | 4 | fork da mainnet funciona; o estado é histórico |
| `F1Drenagem` | 3 | drain completo em fork, com e sem o patch |
| `F1EscolaDeCheatcodes` | 13 | o vocabulário de auditoria |
| `F2EulerExploit` | 3 | exploit real, bloco 16818061 |
| `F2EulerFerramenta` | 1 | varredura do espaço de parâmetros |

---

## O que este repositório é — e o que não vale

**É.** Evidência de capacidade de ler EVM sob pressão: reconstruir a
arquitetura de delegatecall de um protocolo a partir do bytecode, decifrar
uma ABI que divergiu do esperado, calibrar limites experimenting, e chegar
num exploit que produz lucro contábil fechado.

**Também é.** Auditoria de código de produção em duas trilhas — TypeScript e
Solidity — começando pelo diff mais recente, formulando hipótese de falha,
identificando qual lado decide e procurando **refutar**. Cinco hipóteses no
código atual da ENS, cinco refutadas. Em auditoria real a maioria do que se
suspeita não é bug, e o que separa quem audita de quem lê diff é a disciplina
de procurar refutar antes de submeter — comprovada aqui em cima.

**Não é, e não deve ser lido como:**

- **Reprodução de bug de 2023 já corrigido.** O Euler v1 foi abandonado e
  relançado como v2. Este achado não é submissível a programa nenhum. Vale
  $0 como submissão, por construção.
- **"1.590 wstETH de lucro".** É extração dentro de um fork. Serve para provar
  que o encadeamento de chamadas funciona — não é receita, e nem de longe se
  aproxima dos $197M do incidente real (este PoC extrai ~1% disso, porque está
  dimensionado ao capital de giro escolhido para caber no teste).
- **"Já achei bug em produção".** Não. A caça na ENS rendeu zero reports
  subíveis, e o documento diz isso na primeira linha. A lacuna entre o que
  existe aqui e o que paga continua sendo **um report aceito** — e nenhum foi
  submetido até agora.

O ativo real é o raciocínio demonstrado — e isso é contratável como
competência, não como payout de bounty.

---

## Rodar

```bash
git clone --recurse-submodules <url>
cd Projeto_Bounties_audits
cp .env.example .env        # e ajuste ETHEREUM_RPC_URL
set -a && source .env && set +a

forge test                                              # 24 testes
forge test --match-contract F1Drenagem -vvvv            # o drain, passo a passo
forge test --match-contract F2EulerExploit -vv         # o exploit real
forge test --match-test test_exploitEuler -vvvv        # trace completo
```

Instalação (se já tiver Foundry 1.8.5, pule):

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
```

> **Precisa de endpoint ARCHIVE.** Endpoint "latest-only" falha com
> `pruned history unavailable`. Testados 7: só `eth-pokt.nodies.app` e
> `gateway.tenderly.co/public/mainnet` servem estado histórico. Alternativas
> em [`.env.example`](.env.example).

Sem `--broadcast`, nada toca a rede real. **Nunca use `--broadcast` num
exploit sem ler o contrato três vezes.**

---

## Documentação

| Arquivo | Assunto |
|---|---|
| [docs/00_ROADMAP.md](docs/00_ROADMAP.md) | plano, status, o que falta |
| [docs/01_FASE0_DIAGNOSTICO.md](docs/01_FASE0_DIAGNOSTICO.md) | o que `vm.createSelectFork` faz |
| [docs/02_FASE1_DRENAGEM.md](docs/02_FASE1_DRENAGEM.md) | o marco: drenar e imprimir |
| [docs/03_CHEATCODES.md](docs/03_CHEATCODES.md) | `prank`, `deal`, `expectRevert`, `roll`… |
| [docs/04_EULER_POSTMORTEM.md](docs/04_EULER_POSTMORTEM.md) | o exploit real + **os 8 erros que cometi** |
| [docs/05_ARQUITETURA.md](docs/05_ARQUITETURA.md) | estrutura de pastas |
| [docs/06_ENS_HUNT.md](docs/06_ENS_HUNT.md) | **Fase 3: caça em código de produção, 5 hipóteses, 0 reports** |
| [data/euler_incidente_referencias.md](data/euler_incidente_referencias.md) | tx, blocos, postmortems, invariante quebrada |

### Os três achados que mais custaram tempo

Detalhados em [`docs/04_EULER_POSTMORTEM.md`](docs/04_EULER_POSTMORTEM.md):

1. **O `approve` vai para o Dispatcher, não para o eToken.**
   `Violator → ewstETH(proxy) → Euler.dispatch → ETokenImpl`, com `DELEGATECALL`
   nos dois últimos saltos. Dentro da implementação, `msg.sender` ainda é o
   chamador mas `address(this)` é o Dispatcher — e é ele que aparece como
   `spender`.

2. **`liquidate` tem 5 argumentos, e `underlying` e `collateral` são ativos,
   não eTokens.**
   ```solidity
   liquidate(violator, wstETH, wstETH, repay, minYield)   // certo
   ```
   A variante de 6 args que aparece na maioria dos PoCs não existe nesta
   versão e reverte em silêncio. E o revert que vem ao passar o eToken
   (`e/liq/violator-not-entered-underlying`) **mente** — diz que a conta não
   entrou no mercado, quando o problema é o parâmetro.

3. **O endereço rotulado `EULER` em todo PoC publicado é o Dispatcher**, e é ele
   que custodia o subjacente. O eToken não tem saldo nenhum — procurar o saldo
   lá dá 0 e parece fork quebrado.

```
python3 script/verify_block.py --dump
```
regenera a prova on-chain disso em `data/euler_block_16818061.json`.

---

## O exploit em números

```
=============================================
     EULER EXPLOIT - 13/03/2023
=============================================
  flashloan pego         :  50.000,00 wstETH
  reserva do Euler ANTES :  66.271,50 wstETH
  reserva do Euler DEPOIS:  64.681,49 wstETH
  wstETH DRENADO         :   1.590,28 wstETH
  LUCRO LIQUIDO          :   1.590,28 wstETH
=============================================
```

| Métrica | Valor |
|---|---|
| `healthScore` do violador | 0,472 |
| `discount` da liquidação | 20% (teto) |
| `yield / repay` | 1,224 — o desconto em ação |

O bug: `donateToReserves` queima eTokens **sem checagem de solvência**, quebrando
a invariante "health score nunca cai abaixo de 1 sem mudança de valor de
mercado". A função havia sido adicionada como *remédio* de um bug anterior e
ficou fora do escopo da auditoria seguinte.

> **Ataque o diff, não o repositório inteiro.** Bug mora em código que o
> auditor anterior não viu. Este caso é a prova: o protocolo tinha auditoria.

---

## Ambiente

Foundry 1.8.5 · solc 0.8.24 · `lib/forge-std` como submodule (pinado).

---

## Licença e escopo

MIT — ver [`LICENSE`](LICENSE).

Laboratório educacional em fork local. Nenhum código aqui é apontado para
contrato vivo, e nenhum teste movimenta ativo de terceiros.

Bug encontrado em programa com bounty → o caminho é o programa: relatório
privado, payout pelo protocolo. Escrever o PoC num fork, como neste repositório,
é o trabalho de pesquisa — e é isso que os programas pagam.