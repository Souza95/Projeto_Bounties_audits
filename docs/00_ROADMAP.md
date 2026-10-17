# Roadmap — Foundry → Immunefi

Status real do projeto. Data de referência: 16/10/2026.

## Visão geral

```
Fase 0  Diagnóstico .................. CONCLUÍDA
Fase 1  Drenagem + vocabulário ....... CONCLUÍDA
Fase 1  Exploit real com postmortem .. CONCLUÍDA (Euler)
Fase 2  Treinamento estruturado ...... PRÓXIMO
Fase 3  Auditoria real ............... A INICIAR
```

---

## Fase 0 — Diagnóstico ✅

Objetivo: confirmar que o toolchain funciona e que você entende fork.

- [x] Foundry instalado (`foundryup` → 1.8.5)
- [x] `forge init` na raiz, `forge-std` como lib
- [x] `foundry.toml` com `[rpc_endpoints]` apontando pro `.env`
- [x] Endpoint **archive** validado (7 endpoints testados; 2 servem estado
      histórico; os outros respondem `pruned history unavailable`)
- [x] Teste de fork da mainnet lendo saldo ETH e ERC-20 reais

**Ver [`01_FASE0_DIAGNOSTICO.md`](01_FASE0_DIAGNOSTICO.md)**

Critério de passagem do plano: *"se você entende o que `vm.createSelectFork`
faz sem googlear, pula pra Fase 2"*. Está documentado e testado.

---

## Fase 1 — Drenagem ✅

Objetivo do plano: **"fazer um script drenar dinheiro num fork e imprimir o
resultado"**.

- [x] `VaultVulneravel` — reentrância (a classe de bug que custou 60M à TheDAO)
- [x] `VaultCorrigido` — o patch, para metade do relatório de bug
- [x] `DrainReentrancia` — o atacante
- [x] Drain de 100 ETH, 3 voltas de reentrância, imprimindo o relatório
- [x] Versão `forge script` (`script/F1Drain.s.sol`)
- [x] Drain com saldo **real da mainnet** no fork (105k ETH lidos do bloco 19M)
- [x] Contra-teste provando que o patch fecha o buraco

**Ver [`02_FASE1_DRENAGEM.md`](02_FASE1_DRENAGEM.md)**

### Vocabulário ✅

13 testes, um por cheatcode, cada um com o que o cheatcode *mente* para o
contrato. Inclui as pegadinhas que custaram tempo real (ex.: `expectRevert`
com `require("texto")` precisa do envelope `Error(string)`).

**Ver [`03_CHEATCODES.md`](03_CHEATCODES.md)**

---

## Fase 1b — Exploit real ✅

Objetivo do plano: *"escolha um bug real com postmortem público e reproduza
num fork"*.

**Escolhido: Euler Finance, 13/03/2023, ~$197M.**

- [x] Endereços **verificados on-chain** antes de escrever qualquer linha
      (`script/verify_block.py`)
- [x] Fork no bloco `16818061`, no market wstETH
- [x] `donateToReserves` sem checagem de solvência → health < 1
- [x] Auto-liquidação com **desconto máximo de 20%**
- [x] Flashloan do Balancer Vault com capital de giro dimensionado
- [x] Lucro de **1.590 wstETH** extraído em fork, flashloan devolvido
- [x] Contra-teste: sem o `donate`, a liquidação reverte

**Ver [`04_EULER_POSTMORTEM.md`](04_EULER_POSTMORTEM.md)** — inclui os 8 erros
que cometi durante a engenharia reversa, porque foi aí que se aprendeu.

### Candidatos que ficaram de fora

| Alvo | Por que não agora |
|---|---|
| Curve (2023, jvEth) | mesma classe do Euler; implementar traz ganho baixo |
| Balancer V1 (2020) | exige token deflacionário + dYdX; bom 2º alvo |
| Sentiment/Balancer (2023) | reentrância *view-only* — leitura de oracle |

---

## Fase 2 — Treinamento estruturado (próxima)

Não depende de nada externo; é a sequência de desafios do plano.

- [ ] **Ethernaut** — 40 contratos, dificuldade crescente
      `git clone https://github.com/ConsenSys/smart-contract-security-game`
- [ ] **Damn Vulnerable DeFi (weth)** — 10 desafios, foco em DeFi
      `git clone https://github.com/w3fii/damn-vulnerable-defi`
- [ ] 12 desafios em ordem; documentar cada um em `labs/notas/`

Sugestão de ritmo: 2 desafios/dia, escrevendo o **contra-teste** de cada um
(o que prova que o patch fecha). Sem o contra-teste, metade do aprendizado some.

---

## Fase 3 — Auditoria real

- [ ] Escolher 3–5 protocolos Immunefi com bug bounty **ativo**
- [ ] Ler os relatórios públicos já pagos (Immunefi publica postmortem)
- [ ] Tentar repetir um achado antigo no fork — é o treino mais barato
- [ ] Escrever o relatório no formato do programa: impacto, PoC, patch

### Ferramentas que viram depois

| Ferramenta | Serve para |
|---|---|
| `forge test --debug` | depurar tx passo a passo no TUI |
| `forge coverage` | achar ramo nunca testado |
| Echidna / Foundry invariant tests | achar a quebra de invariante sem saber o bug |
| `cast run` / `cast call` | ler contrato real sem fork |
| Slither | triagem estática rápida |
| `forge script` + `anvil` | montar o PoC antes de rodar |

---

## Regra de ouro deste projeto

> Fork é para **aprender e provar**. Dinheiro real vem do **programa de bug
> bounty**, com relatório privado e payout pelo protocolo. Nenhum exploit
> deste repositório deve ser apontado para um contrato vivo.