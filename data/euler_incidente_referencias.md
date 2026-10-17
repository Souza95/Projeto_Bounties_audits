# Referências do incidente — Euler Finance

Arquivo de índice. Os links e hashes abaixo foram conferidos durante a
reprodução. Nenhum PoC publicado foi copiado sem verificação on-chain.

---

## Transação doataque

| Campo | Valor |
|---|---|
| Hash | `0xc310a0affe2169d1f6feec1c63dbc7f7c62a887fa48795d327d4d2da2d6b111d` |
| Bloco | **16817996** |
| Data | 2023-03-13 |
| Market | eDAI (o primeiro dos cinco mercados drenados) |
| Bloco do fork **deste repo** | **16818061** |

> **Atenção:** a tx está no bloco `16817996`, **65 blocos ANTES** do bloco que
> este projeto forka (`16818061`). O repo forka o market de **wstETH**, um
> dos Attacks seguintes na mesma sequência — por isso os blocos não batem.
> Para caçar o hash da tx, procure a partir de `16817996`, não de `16818061`.

Verificado por `eth_getTransactionByHash` durante a construção do PoC.

---

## Perdas

| Métrica | Valor |
|---|---|
| Total drenado | ~$197M |
| Mercados atingidos | eDAI, eUSDC, eWETH, ewstETH, eWBTC |
| Tx doataque | `0xc310a0af…e6b111d` (bloco 16817996) |

---

## Postmortems públicos

| Fonte | URL | O que traz |
|---|---|---|
| rekt.news | `https://rekt.news/euler-rekt/` | narrativa do incidente, timeline |
| Cyfrin | `https://www.cyfrin.io/blog/how-did-the-euler-finance-hack-happen-hack-analysis` | análise técnica + PoC em Foundry |
| ImmuneBytes | `github.com/ImmuneBytes-Security-Audit/The-HackersDiary` | PoC em Foundry, teste equivalente ao deste repo |
| Zellic | `github.com/Zellic/poc-hacks` | PoC enxuto no market wstETH (base deste repo) |
| Slow Mist / PeckShield | relatórios de PSE | análise da vulnerabilidade |
| Euler (oficial) | `github.com/euler-xyz/euler-contracts` | código-fonte, postmortem, `docs/invariants.md` |

---

## Código-fonte usado para decifrar a interface

Extraído do repositório oficial `euler-xyz/euler-contracts` (branch `master`):

| Arquivo | Uso |
|---|---|
| `contracts/modules/Liquidation.sol` | assinatura real de `liquidate`/`checkLiquidation`; `require` da linha 57 é o `e/liq/violator-not-entered-underlying` |
| `contracts/modules/EToken.sol` | `donateToReserves`, `deposit`, `mint`, `withdraw`; linha 191 tem `e/insufficient-pool-size` |
| `docs/invariants.md` | a invariante que o bug quebra |

### Erro que o código-fonte desmentiu

A avaliação interna Affordable esperava `e/insufficient-liquidity`. A string
real no Euler v1 é:

```solidity
// contracts/modules/EToken.sol:191
require(assetCache.poolSize >= amount, "e/insufficient-pool-size");
```

Não existe `e/insufficient-liquidity` neste code path — e o próprio output do
teste reproduz a string `e/insufficient-pool-size`. **Ler o código-fonte vale
mais que confiar no padrão.** O mesmo princípio que vale para endereços vale
para mensagens de erro.

---

## A invariante quebrada

> O health score de uma conta nunca pode cair abaixo de 1 a menos que o valor
> de mercado do subjacente tenha mudado.

`donateToReserves` aumenta o passivo sem alterar valor de mercado.
Detalhamento em [`../docs/04_EULER_POSTMORTEM.md`](../docs/04_EULER_POSTMORTEM.md).