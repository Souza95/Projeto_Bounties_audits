# Euler Finance — 13 de março de 2023, ~$197M

O primeiro exploit real reproduzido neste projeto: **contratos reais da
mainnet**, **bloco histórico real**, fork no `16818061`.

```
=============================================
     EULER EXPLOIT - 13/03/2023
=============================================
  flashloan pego         : 50000000000000000000000
  reserva do Euler ANTES : 66271498175683316786271
  reserva do Euler DEPOIS: 64681216742798570810584
  wstETH DRENADO         : 1590281432884745975687
  LUCRO LIQUIDO          : 1590281432884745975687
=============================================
```

Lucro: **1.590,28 wstETH** com 50.000 de capital de giro. Flashloan devolvido.

---

## O bug

`EToken.donateToReserves(account, amount)` queima eTokens do chamador e manda o
valor para as reservas — **sem verificar se a conta continua solvente**.

A propriedade que deveria valer:

> O health score de uma conta nunca pode cair abaixo de 1 a menos que o valor
> de mercado do colateral tenha mudado.

`donateToReserves` quebra isso: altera o passivo sem alterar o valor de mercado.

**E aqui está a lição de auditoria que o caso ensina.** A função foi adicionada
como *remédio* de um bug anterior — resolvia um depósito que falhava quando a
reserva era pequena. Ou seja: um patch virou superfície de ataque nova. O Euler
passou por auditorias; `donateToReserves` foi added depois e ficou fora do
escopo da revisão seguinte.

> Achado em código novo é o mais provável. Patch é código novo.

## O ataque

```
1. flashloan de 50.000 wstETH no Balancer Vault      → capital zero
2. deposita 33.333, minta 15x (alavancagem auto)
3. donateToReserves 8x o aporte                     → health 0,47  ← o BUG
4. auto-liquida a própria conta
   repayAsset == collateral                           → desconto MÁXIMO de 20%
5. saca o colateral, devolve o flashloan com lucro
```

### Por que a auto-liquidação é lucrativa

Liquidação é "-1, +1": o liquidador paga a dívida e recebe o colateral. Isso
nunca é lucrativo sozinho. O que muda o jogo é o `discount`:

```
baseDiscount = UNDERLYING_RESERVES_FEE + (1 - healthScore)
```

Com health em 0,47, o desconto trava no teto de **20%**. O liquidador recebe
**1,25×** em colateral pelo que quita. Como o atacante é ao mesmo tempo o
violador e o liquidador, ele recolhe o prêmio inteiro — e o prêmio sai do
bolso do protocolo.

### Saída real do `checkLiquidation`

| campo | valor | 1e18 = |
|---|---|---|
| `healthScore` | 471.763.141.674.090.067 | **0,472** |
| `discount` | 200.000.000.000.000.000 | **20%** (teto) |
| `repay` | 453.824.480.524.200.957 | 453.824 wstETH |
| `yield` | 556.157.451.622.795.290 | 556.157 ewstETH apreendidos |

`yield / repay = 1,224` — é o desconto em ação.

---

## Endereços (todos verificados on-chain)

Verificados por `script/verify_block.py` **antes** de escrever uma linha de
exploit. Ver [Euler.sol](../src/F2_Exploits/EulerExploit.sol).

| Papel | Endereço | Verificado |
|---|---|---|
| wstETH (subjacente) | `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0` | "Wrapped liquid staked Ether 2.0" |
| ewstETH (eToken) | `0xbd1bd5C956684f7EB79DA40f582cbE1373A1D593` | "Euler Pool: Wrapped liquid staked Ether 2.0" |
| dwstETH (dToken) | `0x436548baAb5Ec4D79F669D1b9506D67e98927aF7` | "Euler Debt: …" |
| Euler (Dispatcher) | `0x27182842E098f60e3D576794A5bFFb0777E025d3` | "Euler Protocol", **custódia o subjacente** |
| Módulo Liquidation | `0xf43ce1d09050BAfd6980dD43Cde2aB9F18C85b34` | moduleId 500002 |
| Balancer Vault | `0xBA12222222228d8Ba445958a75a0704d566BF2C8` | flashloan |

Bloco do fork: **16818061** (market **wstETH**).

A tx real doataque `0xc310a0af…e6b111d` está no bloco **16817996** — 65 blocos
*antes* do fork, e no market **eDAI**. A sequência de ataque do atacante passou
por cinco mercados em blocos consecutivos; este repo reproduz a mesma classe
de bug no wstETH. Por isso os blocos não batem, e o hash não aparece na janela
`16818061–16818110`.

Detalhes em [`../data/euler_incidente_referencias.md`](../data/euler_incidente_referencias.md).

> **Confirme antes de confiar em qualquer PoC — inclusive nos de blog.** O
> endereço `0x27182842…` érotulado como `EULER` em quase todo PoC publicado,
> e isso está certo — mas ele **não** é o eToken. É o Dispatcher, e é ele que
> guarda o DAI/wstETH. Procurar o saldo no eToken dá 0 e parece que o fork
> quebrou.

---

## Os 8 erros que cometi (e como sair deles)

Esta seção vale mais que o código. Cada um custou tempo real.

### 1. Copiei endereço de blog sem verificar
Assumi que o eToken segurava o ativo. Não segura — o Dispatcher segura.
**Como sair:** um script de verificação on-chain antes do exploit. 5 minutos.

### 2. Aprovei para o contrato errado
```
Violator → ewstETH(proxy) → Euler.dispatch → ETokenImpl
             └────────────── DELEGATECALL ──────────┘
```
Dentro da implementação, `msg.sender` ainda é o chamador, mas **`address(this)`
é o Dispatcher** — e é ele que aparece como `spender`. O `approve` tem que ir
para o Dispatcher.
**Erro:** `ERC20: transfer amount exceeds allowance`.
**Como sair:** ler o `-vvvv`. O trace mostra o `transferFrom` com o remetente
exato.

### 3. Chamei o módulo errado
`Euler.liquidate(...)` reverte em 170 gas. O Dispatcher **não tem contexto de
módulo**. A entrada correta é o *proxy* do módulo.
**Como sair:** gas baixo no frame = reverteu antes de qualquer storage read.

### 4. Assinatura errada — o inimigo silencioso
A variante de 6 argumentos (`liquidator, violator, …`), que aparece na maioria
dos PoCs, **não existe** nesta versão. Reverte sem mensagem nenhuma.
**Como sair:** testar candidatos com `cast call` até um devolver string de
erro em vez de revert vazio.

### 5. `underlying` e `collateral` são ATIVOS, não eTokens
```solidity
// ERRADO — e/liq/violator-not-entered-underlying
liquidate(violator, eToken, eToken, repay, minYield)

// CERTO
liquidate(violator, wstETH, wstETH, repay, minYield)
```
O erro aqui **mente**: diz "não entrou no mercado", quando na verdade você
passou o token errado. É o tipo de revert que joga você para o lado oposto do
problema.
**Como sair:** mensagem de erro enganosa = leia o código-fonte do módulo, não o
trace. `Liquidation.sol` tem a `require` na linha 57.

### 6. Liquidei sem capital próprio
Sem colateral próprio, o liquidador absorve a dívida e o Euler **ganha** — a
reserva sobe em vez de descer. Não há exploit.
**Como sair:** meça a reserva do protocolo antes e depois. É a métrica honesta,
não o saldo do atacante.

### 7. Loop guloso de saque → OutOfGas
Buscar o valor correto de saque por divisão sucessiva até dar certo: cada
`withdraw` do Euler custa **~48k de gas** (rechama `requireLiquidity`, que relê
o preço na Chainlink). Busca binária fina mata a transação — **sem erro
legível**, só `OutOfGas`.
**Como sair:** busca geométrica (×0,85) com teto de 10 tentativas ≈ 480k de
gas, folga de sobra.

### 8. Dimensionei o flashloan pelo saldo do vault
Peguei os 105.487 wstETH que o vault tinha. Só dá pra extrair o que o **pool**
do market tem (66.271). Extraí 85k, investi 105k — prejuízo.
**Como sair:** dimensione o flashloan ao **capital de giro**, não ao
disponível. Com 50.000 de giro, o desconto de 20% multiplica o suficiente para
sugar o pool e devolver o empréstimo com folga.

---

## Contra-teste

Metade de qualquer relatório de bug é provar que o patch fecha. Aqui:

```solidity
function test_semDonate_naoFunciona() public {
    violator.armar(qtd, alavanc, 0);   // SEM o donateToReserves
    vm.expectRevert();                  // conta sadia: liquidar reverte
    EulerMainnet.LIQUIDATION.liquidate(violator, wstETH, wstETH, repay, 0);
}
```

Sem a linha 3 do ataque, não há insolvência, não há o que liquidar. **O bug é
a linha `donateToReserves`, não a alavancagem.**

---

## Ferramenta de laboratório

`test/F2_Exploits/F2EulerFerramenta.t.sol` varre o espaço de parâmetros e
imprime health/discount para cada combinação. Foi ela que achou os limites
usados no PoC:

| Descoberta | Valor |
|---|---|
| `mint` acima de ~15x o aporte | reverte (`requireLiquidity`) |
| com 15x, doar < 3x | conta continua sadia (health > 1) |
| doar 8x | health ≈ 0,47 → desconto trava em 20% |
| repay / underlying / collateral | todos o **ativo subjacente** |

---

## Reproduzir

```bash
set -a && source .env && set +a
forge test --match-contract F2EulerExploit -vv
forge test --match-test test_exploitEuler -vvvv    # trace completo
forge test --match-contract F2EulerFerramenta -vv  # varrer parâmetros
```

## Referências

- Tx doataque: `0xc310a0affe2169d1f6feec1c63dbc7f7c62a887fa48795d327d4d2da2d6b111d`
- rekt.news · Cyfrin: *How did the Euler Finance hack happen*
- Código: `euler-xyz/euler-contracts`, `contracts/modules/Liquidation.sol:57`
- Invariante quebrada: `euler-xyz/euler-contracts`, `docs/invariants.md`

**Anterior**: [Cheatcodes](03_CHEATCODES.md) · **Próxima**: [Arquitetura](05_ARQUITETURA.md)