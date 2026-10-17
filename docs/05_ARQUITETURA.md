# Arquitetura do projeto

```
Projeto_Bounties_audits/
├── foundry.toml              configuração: [rpc_endpoints], solc, fmt
├── .env / .env.example       endpoint archive (o .env está no .gitignore)
│
├── src/                      contratos
│   ├── F1_Drenagem/
│   │   ├── VaultVulneravel.sol    o alvo quebrado + o patch
│   │   └── DrainReentrancia.sol   o atacante
│   └── F2_Exploits/
│       ├── EulerExploit.sol       Violator, Liquidator, EulerAttacker
│       └── interfaces/Euler.sol   interfaces extraídas do bytecode on-chain
│
├── test/                     espelhando src/
│   ├── F0_Diagnostico/
│   │   └── F0ForkBalance.t.sol        4  — fork funciona, estado é histórico
│   ├── F1_Drenagem/
│   │   ├── F1Drenagem.t.sol           3  — o drain, com e sem patch
│   │   └── F1EscolaDeCheatcodes.t.sol 13 — o vocabulário
│   └── F2_Exploits/
│       ├── F2EulerExploit.t.sol       3  — o exploit real
│       └── F2EulerFerramenta.t.sol    1  — varredura de parâmetros
│
├── script/
│   ├── F1Drain.s.sol          versão `forge script` do drain
│   └── verify_block.py        verifica endereços on-chain antes do exploit
│
├── docs/                     a documentação (leia a partir de 00_ROADMAP.md)
├── labs/
│   ├── ethernaut/             ← Fase 2, vazio
│   ├── dvtd/                  ← Fase 2, vazio
│   └── notas/                 ← suas anotações dos desafios
│
├── lib/forge-std/            dependência (git submodule)
└── data/                     fixtures lidos por vm.readFile
```

## Por que `src/` e `test/` são espelhados

Convenção do Foundry. Facilita achar "o teste do contrato X" sem procurar. O
prefixo `F0_`/`F1_`/`F2_` marca a **fase do plano** — dá pra rodar só uma:

```bash
forge test --match-path 'test/F1_Drenagem/*'
```

## Convenções

| Regra | Por quê |
|---|---|
| Sem acento em **string literal** | Solidity só aceita ASCII — `error(8936)` |
| Comentário pode ter acento e UTF-8 | Commentários são descartados pelo compilador |
| Endereço hard-coded vai em `library` no topo do arquivo | Um lugar só pra atualizar |
| Toda constante mainnet tem `@dev` explicando como foi verificada | Endereço errado = PoC que "funciona" e não reproduz nada |
| Bug do lab fica ao lado da versão corrigida | Diff visual é o material do relatório |
| Toda vuln tem contra-teste | Prova que o patch fecha |

## Comandos

```bash
set -a && source .env && set +a

forge test                                              # tudo
forge test --match-contract F1Drenagem -vvvv           # o drain, passo a passo
forge test --match-contract F2EulerExploit -vv          # o exploit real
forge test --match-test test_exploitEuler -vvvv        # trace do exploit
forge test --match-contract F1Escola -vv               # só a escola de cheatcodes
forge test --rerun                                      # só o que falhou

forge script script/F1Drain.s.sol:F1Drain \
  --rpc-url "$ETHEREUM_RPC_URL" --fork-block-number 19000000 -vv

forge build --sizes                                     # tamanhos de bytecode
forge fmt
forge coverage

python3 script/verify_block.py 16818061                 # confere endereços
```

## Ao adicionar um exploit novo

1. **Verifique os endereços primeiro.** Escreva/estenda `script/verify_block.py`
   e rode. Nunca copie de blog.
2. Escreva a interface a partir do **bytecode on-chain**, não do ABI do
   explorador — o explorador mostra a *última* versão, e o bug pode ser de uma
   versão que já saiu do ar.
3. Fork no bloco **imediatamente anterior** à tx real.
4. Primeiro `test_estadoDoMercado` que só imprime saldos e supplies. Se os
   números não baterem com o postmortem, o fork está errado — pare aí.
5. Construa em passos, com `console.log` entre eles. Achar onde quebra é mais
   rápido do que tentar acertar de primeira.
6. Use **mensagem de erro como bússola.** Revert vazio = selector/param errado.
   Revert com string = você chegou na lógica.
7. Meça a **reserva do protocolo** antes e depois. É a métrica honesta.
8. Escreva o contra-teste.

**Anterior**: [Euler](04_EULER_POSTMORTEM.md) · **Início**: [Roadmap](00_ROADMAP.md)