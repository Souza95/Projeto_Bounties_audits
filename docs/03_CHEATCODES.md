# Vocabulário — os cheatcodes que você precisa dominar

13 testes em `test/F1_Drenagem/F1EscolaDeCheatcodes.t.sol`, um por cheatcode.

O objetivo **não** é decorar assinatura. É internalizar *o que o cheatcode mente
para o contrato*.

> **Regra de ouro**: um cheatcode ajusta o estado do bloco como se algo tivesse
> acontecido, sem que nada tenha acontecido de fato. O contrato não sabe — ele
> só vê um mundo internamente consistente com a mentira.

```bash
forge test --match-contract F1Escola -vvvv
```

---

## `vm.prank` — falsifica `msg.sender` da próxima chamada

O mais usado em auditoria. Faz o **próximo call externo** sair da conta de outra
pessoa.

```solidity
sensor.quemChamou();          // sensor vê: address(this)
vm.prank(ALICE);
sensor.quemChamou();          // sensor vê: ALICE
```

**Pegadinha:** vale para **um** call só, e tem que estar **colada** no call.
Qualquer coisa no meio (outro contrato, um `staticcall`) consome a prank e o
teste mente. `test_prank_tem_que_ser_imediato` cobre isso.

## `vm.startPrank` / `vm.stopPrank` — vários calls, mesma identidade

Quando o ataque faz vários calls seguidos (reentrância), `prank` só aguentaria o
primeiro.

```solidity
vm.startPrank(BOB);
sensor.quemChamou();
sensor.quemChamou();
vm.stopPrank();               // sensor viu BOB, BOB
```

Também aceita valor: `vm.startPrank(CAROL); sensor.calha{value: 3 ether}();`
permite simular um depósito sem saldo real.

## `vm.deal` — forja saldo

```solidity
vm.deal(ALICE, 1000 ether);           // ETH
deal(address(token), BOB, 777 ether); // ERC-20 — SEM o prefixo vm.
```

O ERC-20 vem do `StdCheats`, não do cheatcode `Vm`. Ele detecta o padrão e
escreve no slot certo; token não-standard exige `stdstore` para achar o slot.

`deal` **não mexe no relógio** — para isso é `warp`. Existe também
`deal(..., adjust)` para ERC-20 que guardam `totalSupply`.

## `vm.expectRevert` — declara que o próximo call DEVE falhar

Sem argumento: só exige que reverta.

```solidity
vm.expectRevert();
guarda.apenasOwner();
```

Com motivo — o que importa em auditoria. Um reverter "pelo motivo errado"
esconde o bug real.

**Pegadinha que eu levei:** com `require("texto")`, o revert **não** é o seletor
puro, é o envelope `Error(string)`:

```solidity
// ERRADO — falha com "Error != expected error"
vm.expectRevert(abi.encodeWithSignature("only owner()"));

// CERTO
vm.expectRevert(abi.encodeWithSignature("Error(string)", "only owner"));
```

Com `revert CustomErr()` (custom error) aí sim é só `abi.encodeWithSelector(...)`.

## `vm.roll` / `vm.warp` — mexem no relógio

Erro clássico: usar `roll` quando queria `warp`.

```solidity
vm.roll(20_000_000);        // block.number = 20.000.000
// block.timestamp inalterado

vm.warp(tempo0 + 365 days); // block.timestamp + 1 ano
// block.number inalterado
```

| Quer mover | Use |
|---|---|
| número do bloco | `vm.roll` |
| timestamp / carência / unlock | `vm.warp` |
| os dois | `vm.roll` + `vm.warp` |

## `vm.label` — legibilidade

Não muda nada. Troca `0x104fBc01…` por `"alice"` nos logs de `-vvvv`. Parece
inútil, e é o que torna um trace de 500 linhas legível.

---

## Cheatcodes do dia a dia que ainda vão aparecer

| Cheatcode | Serve para |
|---|---|
| `vm.snapshotState()` / `vm.revertToState(id)` | tentar N cenários num teste só |
| `vm.expectEmit()` | exigir evento específico (reentrância, transfers) |
| `vm.expectCall()` | exigir que um certo método foi chamado |
| `vm.mockCallRevert(addr, data, revertReason)` | forçar um contrato externo a falhar |
| `vm.etch(addr, bytecode)` | trocar o código de um endereço (fork surgery) |
| `vm.store(addr, slot, value)` | escrever direto no storage |
| `vm.load(addr, slot)` | ler storage cru |
| `vm.coinbase(addr)` | quem recebe a recompensa de mineração |
| `vm.getBlockTimestamp()` | ler o tempo sem o lint reclamar |
| `deal(address,address,uint256,bool)` | ERC-20 com ajuste de supply |
| `makeAddr("alice")` | endereço legível a partir de string |

`vm.etch` merece atenção: é ele que permite "consertar" um market no fork para
reproduzir um exploit que dependia de um oráculo quebrado. Não abuse — um
`etch` grande demais deixa de ser um PoC do mundo real.

---

## Como ler um `-vvvv` (a skill que realmente importa)

```
├─ [0] VM::createSelectFork("mainnet", 19000000)
├─ [2534] wstETH::balanceOf(Euler) [staticcall]
│   └─ ← [Return] 0x0000…0eba396e168b16be3ec4a3
├─ [191] 0xd737eE2b::ec9d9e26(…) [delegatecall]
│   └─ ← [Revert] EvmError: Revert          ← HERE
```

Três coisas a ler:

1. **Gas baixo no frame que reverteu** (~191 gas) → o reverte aconteceu antes de
   qualquer `SLOAD`. É uma checagem de código puro, não de estado. Selector não
   registrado? Parâmetro errado?
2. **A string de erro.** `e/liq/violator-not-entered-underlying` diz exatamente
   qual invariante falhou. Revert vazio diz que você ainda nem chegou na
   lógica.
3. **Os `emit`.** Eventos show the state transitions. Ler os eventos de uma
   operação é mais rápido que ler o trace inteiro.

Foi exatamente assim que o exploit do Euler foi resolvido — ver
[`04_EULER_POSTMORTEM.md`](04_EULER_POSTMORTEM.md).

---

**Anterior**: [Fase 1 — Drenagem](02_FASE1_DRENAGEM.md) · **Próxima**: [Euler](04_EULER_POSTMORTEM.md)