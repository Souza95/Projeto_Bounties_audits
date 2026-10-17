# Fase 0 — Diagnóstico: o que `vm.createSelectFork` faz

## O problema que ele resolve

A EVM não tem estado próprio. Uma tx num nó real depende de todo o histórico
anterior: storage de milhares de contratos, saldos, código. Para testar, você
precisa de um mundo que já foi construído.

Foundry resolve isso baixando o **estado real** de um bloco específico da rede
e rodando a EVM em cima dele, localmente.

```
vm.createSelectFork("mainnet", 19_000_000)
        │                │           │
        │                │           └─ bloco: estado histórico exato
        │                └─ rede, resolvida via [rpc_endpoints] no foundry.toml
        └─ "create" = cria o fork · "Select" = deixa este fork como o ativo
```

Depois da linha seguinte, **tudo** que você consultar devolve o valor que tinha
naquele bloco:

```solidity
ALVO_ETH.balance;                       // ETH real, no bloco 19.000.000
IERC20(USDC).balanceOf(qualquer);       // ERC-20 real, com o bytecode real
enderecoDoPool.algumStorage();          // storage real do contrato real
```

Nada disso é simulado. O alvo pode ter 105.000 ETH de verdade.

## As três assinaturas

```solidity
vm.createSelectFork("mainnet");                  // mainnet, bloco "latest"
vm.createSelectFork("mainnet", 19_000_000);      // mainnet, bloco 19.000.000
vm.createSelectFork(urlDoRpc, 19_000_000);       // endpoint explícito
```

## Por que "select"

Você pode ter vários forks vivos ao mesmo tempo:

```solidity
vm.createSelectFork("mainnet", 19_000_000);   // fork A, agora ativo
vm.createSelectFork("mainnet", 26_200_000);   // fork B, agora ativo (A continua existindo)

// tudo daqui em diante fala com B
```

O que importa: `create` faz o fork, `select` aponta a EVM para ele. Depois do
`select`, **todo** o resto do teste — `balance`, `call`, `staticcall`,
`balanceOf` — vai para o fork selecionado.

## Archive vs. latest-only

Este é o detalhe que trava metade das pessoas. Endpoint RPC público de
gratuita quase sempre é **latest-only**: guarda o estado recente e descarta o
histórico. Fork em bloco antigo então falha:

```
Error: server returned an error response: error code 3
"pruned history unavailable: requested 19005600, earliest available 26198713"
```

Testamos sete endpoints neste projeto:

| Endpoint | Archive? |
|---|---|
| `eth-pokt.nodies.app` | **sim** (em uso) |
| `gateway.tenderly.co/public/mainnet` | **sim** |
| `ethereum-rpc.publicnode.com` | não — "pruned history" |
| `rpc.flashbots.net` | não — "state at block #… is pruned" |
| `rpc.ankr.com/eth` | não — exige API key |
| `eth.merkle.io` | rate limit agressivo |
| `rpc.blxrbdn.com` | indisponível |

Para trabalho sério: Alchemy, QuickNode, Infura ou Tenderly. Free tier resolve
pra começar. Troca em [`.env.example`](../.env.example).

---

## O que a suíte F0 prova

```bash
forge test --match-path 'test/F0_Diagnostico/*' -vv
```

| Teste | Prova |
|---|---|
| `test_forkEstaNoBlocoCerto` | `block.number == 19.000.000` e `chainid == 1` |
| `test_lerSaldoETH` | lê 105.627,38 ETH de um endereço real da mainnet |
| `test_lerSaldoERC20` | bytecode do USDC real responde; `0` para quem não tem, `673.729,85` para quem tem |
| `test_estadoEhHistorico` | o valor é congelado no bloco — rodar amanhã dá o mesmo número |

O último é o mais importante: prova que é estado **histórico**, não "latest".

### Saída real

```
saldo @19.000.000: 105627385179809479689008     (105.627,38 ETH)
ETH no bloco 19M:  105627385179809479689008
USDC do alvo:      673729857178891             (673.729,85 USDC)
bloco:             19000000
```

## Detalhe de configuração que morde

`eth_rpc_url` **está deprecado** no Foundry 1.8. O Foundry aceita a chave sem
erro e depois tenta abrir `${ETHEREUM_RPC_URL}` como nome de arquivo:

```
Error: failed to retrieve chain ID from fork endpoint
Internal transport error: No such file or directory (os error 2)
with .../${ETHEREUM_RPC_URL}
```

A forma correta é `[rpc_endpoints]`:

```toml
[rpc_endpoints]
mainnet = "${ETHEREUM_RPC_URL}"
```

E é esse nome — `"mainnet"` — que você escreve no `createSelectFork`.

## Fork vs. script: quem cria o fork

| | Quem faz o fork | Como |
|---|---|---|
| `forge test` | o código | `vm.createSelectFork(...)` no `setUp()` |
| `forge script` | a CLI | `--rpc-url` + `--fork-block-number` |

Mesma máquina, lados opostos. Detalhe importante para não ficar procurando
`createSelectFork` num script e achar que ele sumiu.

---

**Próximo**: [Fase 1 — Drenagem](02_FASE1_DRENAGEM.md)