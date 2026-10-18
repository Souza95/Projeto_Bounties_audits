# Fase 3 — Caça em código de produção: cinco hipóteses, zero reports

Alvo: **ENS** — `immunefi.com/bug-bounty/ens/`
Data: 16–17 de outubro de 2026.
Repos: [`ensdomains/ens-app-v3`](https://github.com/ensdomains/ens-app-v3) ·
[`ensdomains/ens-contracts`](https://github.com/ensdomains/ens-contracts)

**Resultado: nenhum report subível.** Cinco hipóteses testadas, cinco refutadas.
Este documento é o registro do método e da evidência — não um achado.

---

## Por que ENS e não outro

| | |
|---|---|
| Recompensa | Critical até $250k · High $25k–$100k · **Medium $10k flat** · **Low $2.5k flat** |
| Paga em | **USDC on Ethereum** |
| Escopo amended | `docs.ens.domains` e `basics.ensdao.org` entraram em **8 Out 2026** |
| Princípio | Primacy of **Impact** (não *Rules*) — mais flexível na severidade |
| Tracks | **A:** smart contracts · **B:** web/apps (NextJS, TypeScript) |

Dois fatos decidiram: os tetos de Medium/Low são **flat**, não "até" — isso muda o
cálculo de EV. E a Track B é TypeScript, a mesma linguagem dos três repos, onde
praticamente nenhum auditor de blockchain concorre.

---

## Método

Caça por diferença, não leitura linear. Bug mora em código que o auditor
anterior não viu. O commit mais suspeito do recorte:

```
2026-10-01  Only unwrap official ENS composite resolvers
2026-10-12  Merge pull request #1166 from ensdomains/fix/untrusted-composite-resolver
2026-10-15  fix: bridge DNS root key rollover for imports
2026-10-15  fix: update dnsprovejs root trust anchors
```

Lógica nova de **confiança** escrita em semanas, validação de **âncora raiz DNSSEC**
em dias. Duas superfícies onde a hipótese de bypass é plausível por construção.

Para cada hipótese o mesmo ciclo: formular a falha → localizar a fronteira de
segurança → verificar qual lado decide → **procurar refutar**.

---

## Hipótese 1 — o unwrap de composite resolver confia em valor forjável

> *Se a checagem "é um composite resolver oficial" lê um valor controlado pelo
> atacante, o cliente desembrulha um resolver malicioso.*

A allowlist é a fronteira:

```ts
// src/constants/resolverAddressData.ts:307
export const OFFICIAL_COMPOSITE_RESOLVERS: Record<string, Address[] | undefined> = {
  '1': [],                                    // ← mainnet: VAZIO
  '11155111': ['0xae66c62AcAE72098BdAc57d8E8AED53EF000b2Ba'],   // Sepolia
  '1337': [],
}
```

**Refutada.** Mainnet com lista vazia ⇒ `isOfficialCompositeResolver()` retorna
`false` sempre ⇒ `enabled` falso em `useEffectiveResolverAddress.ts:53` ⇒ o
caminho inteiro está **desligado em produção**. Não há superfície a atacar na
mainnet hoje.

O resto do caminho está bem escrito: `decodeUnderlyingResolver` faz shape-check
estrito do returndata (`isPaddedAddressWord`, `isBoolWord`, `TRUE_WORD`) para que
um contrato auto-reportando ERC-165 não injete endereço lixo.

**Oportunidade real aqui não é hoje.** `OFFICIAL_COMPOSITE_RESOLVERS['1']` vazio
é placeholder esperando endereço — quando a ENS popular a mainnet, a lista vira
superfície nova e ninguém vai ter lido esse diff.

---

## Hipótese 2 — a ponte enfraquece a checagem de inception

> *A ponte reimplementa a comparação de inception do ENSJS. Reimplementação é
> onde validação costuma afrouxar.*

A ponte não chama o helper do ENSJS, ela reimplementa:

```ts
// src/utils/dns/rootKeyRollover/index.ts:72
if (
  (inception < dnsInception && dnsInception - inception > 0x7fffffff) ||
  (inception > dnsInception && inception - dnsInception  < 0x7fffffff)
)
  throw new DnsNewerRecordTypeAvailableError({...})
```

Contra o original:

```ts
// ensjs getDnsImportData.ts:29
const serialNumberGt = (i1, i2) =>
  (i1 < i2 && i2 - i1 > 0x7fffffff) || (i1 > i2 && i1 - i2 < 0x7fffffff)
// usado como: serialNumberGt(inception, lastProof.signature.data.inception)
```

Substituindo `i1 = inception`, `i2 = dnsInception`: **as duas cláusulas batem
termo a termo**. É a mesma aritmética unsigned de 32 bits de RFC1982, na mesma
direção, com o mesmo predicado.

**Refutada.** Reimplementação fiel.

> Nota de método: uma verificação de igualdade de string entre as duas versões
> acusou divergência porque os nomes das variáveis diferem. O falso positivo foi
> do checker, não do código. Comparar lógica exige normalizar nomes, senão o
> instrumento mente sobre o objeto.

---

## Hipótese 3 — o endpoint DoH configurável permite forjar a cadeia de proofs

> *`parameters.endpoint` alimenta um resolver DoH. Um DoH malicioso entrega a
> proof inteira, e a app não deveria CONSEguir distinguir.*

```ts
// index.ts:41
const prover = DNSProver.create(parameters.endpoint ?? 'https://cloudflare-dns.com/dns-query')
```

À primeira vista, toda a confiança vira do endpoint. **Refutada em duas
camadas:**

**a) A raiz é trocada por constante local, não pelo DoH.**

```ts
// index.ts:46
const root = result.proofs[0]
if (
  root?.signature.name !== '.' ||
  root.signature.data.typeCovered !== 'DNSKEY' ||
  root.signature.data.keyTag !== 38696
) throw error

const proofs = [
  { rrset: historicalRoot.rrset as Hex, sig: historicalRoot.sig as Hex },   // ← do bundle
  ...
]
```

O que o DoH devolve é **validado e descartado**. O que entra na cadeia é o
fixture `root-dnskey-ksk20326-20261001.json`, versionado no repo.

**b) A autoridade final é o contrato.**

```ts
// index.ts:64
const [onchainRrData, inception] = await readContract(client, {
  abi: dnssecImplVerifyRrSetSnippet,
  address: getChainContractAddress({ client, contract: 'ensDnssecImpl' }),
  functionName: 'verifyRRSet',
  args: [proofs],
})
```

E a âncora de confiança **não é constante no código** — é estado on-chain:

```solidity
// ens-contracts/contracts/dnssec-oracle/DNSSECImpl.sol:41,49
/// @param _anchors The binary format RR entries for the root DS records.
/// @notice Sets the root anchors.
```

Consequência: o `keyTag !== 38696` do cliente é **filtro heurístico**, não
fronteira. A fronteira é o que o `ensDnssecImpl` *deployado* tem em âncoras.
O `DNSSECImpl` valida de verdade — owner name do DNSKEY contra o signer do
RRSIG (`:217`), Zone Flag bit obrigatório (`:268`), REVOKE bit checado (`:277`).

Cliente propõe, contrato decide. O check da linha 82
(`toHex(lastProof.toWire(false)) !== onchainRrData`) fecha o circuito.

---

## Hipótese 4 — o guard de expiração compara hex sem normalizar

Único lugar do codebase que compara endereço/hex com `===` cru:

```ts
// index.ts:15
export const assertDnsImportProofNotExpired = (proofs) => {
  if (proofs[0]?.rrset === historicalRoot.rrset && isExpired())
    throw new Error('The temporary DNS root proof expired...')
}
```

Todo o resto normaliza — `isOfficialCompositeResolver` e `getKnownResolverData`
usam `.toLowerCase()` nos dois lados.

**Verifiquei se é bug hoje: não.** O fixture é minúsculo, e `toHex()` do viem
também produz minúsculo. Bate.

**Mas é fragilidade latente**, por dois motivos que o `===` esconde:

- o valor vem de **cache do react-query**, que sobrevive à sessão;
- um `===` de hex que falha aberto não dá erro de tipo — falha em silêncio,
  que é o pior modo de falha para um guard de segurança.

O conserto é uma linha: `proofs[0]?.rrset?.toLowerCase() === historicalRoot.rrset.toLowerCase()`.

---

## Hipótese 5 — o relógio do cliente decide a expiração

`isExpired()` é `Date.now() >= ROOT_KEY_ROLLOVER_EXPIRY`, no browser. O usuário
muda o clock e pula o gate.

**Refutada, e com um achado embutido.** O guard não é controle de segurança —
porque a transação é julgada on-chain de qualquer forma:

```ts
// ensjs importDnsName.ts:96
data: encodeFunctionData({
  functionName: 'proveAndClaim',
  args: [hexEncodedName, dnsImportData],   // ← só codifica, não verifica
})
```

`makeFunctionData` **não chama `verifyRRSet`**. Nenhuma verificação client-side
na montagem da transação. Logo `assertDnsImportProofNotExpired` existe
exatamente para o que o README diz: **poupar gas**, falhar rápido em vez de
deixar a chain rejeitar. O `Date.now()` é aceitável porque o objetivo não é
segurança.

Consequência derivada: nos três call sites de transação
(`importDnsName.ts:26`, `claimDnsName.ts:26`, `syncManager.ts:40`) esse guard é
o **único** gate entre uma proof cacheada e uma transação enviada.

---

## Observação operacional (não é vulnerabilidade)

Não encontrei bug, mas achei uma data:

```ts
// index.ts:11
export const ROOT_KEY_ROLLOVER_EXPIRY = Date.parse('2026-10-22T00:00:00Z')
```

Depois de 22/10 00:00 UTC a linha 37 passa a relançar a exceção original:

```ts
if (![1, 11155111].includes(client.chain.id) || isExpired() || !isMissingTrustAnchor(error))
  throw error
```

Ou seja, todo import de nome DNS na mainnet que caia nesse fallback passa a
falhar. É deliberado — o README do módulo documenta o plano de remoção em 4
passos, e a checagem de expiração aparece duas vezes (linhas 61 e 84) como
rede de segurança. Registrado aqui porque o fuse tem prazo, não porque seja
falha.

Menor, e do mesmo tipo: o allowlist de chain-id do bridge é `[1, 11155111]`
hardcoded, enquanto `resolverAddressData.ts` registra `'1337'`. Duas listas de
redes diferentes no mesmo app.

---

## Reproduzir

```bash
git clone --recurse-submodules <este repo>
cd ens-app-v3
git log --since="2026-09-25" --oneline            # o recorte
git show ae1ac7d9 --stat                            # hipótese 1
git show 6b312f9c:src/utils/dns/rootKeyRollover/index.ts | cat -n
```

Contratos (para a hipótese 3):
```bash
git clone https://github.com/ensdomains/ens-contracts
grep -n "Sets the root anchors" contracts/dnssec-oracle/DNSSECImpl.sol
```

Referência do ENSJS para a hipótese 2:
`packages/ensjs/src/actions/dns/getDnsImportData.ts:29` em
[`ensdomains/ensjs`](https://github.com/ensdomains/ensjs).

---

## O que isto demonstra

Cinco hipóteses. Cinco refutadas. **Zero reports.**

E é esse o ponto. Em auditoria de produção, a taxa de hipóteses erradas é alta
por construção — a maioria do que se suspeita não é bug. O que separa auditor
de quem lê diff é a **disciplina de procurar refutar antes de submeter**, e a
capacidade de dizer "aqui está o porquê de não ser".

Dois erros meus aparecem registrados porque foram os pontos mais fáceis de
reportar errado:

- **A hipótese 1 passou a parecer o melhor lead** antes de eu ler a allowlist. Era
  código de três semanas, parecendo superfície fresca — e estava desligado em produção.
- **O checker de comparação acusou divergência** onde não havia nenhuma,
  por comparar nomes de variáveis em vez de lógica.

Os dois são o mesmo erro: confiar na aparência antes de verificar a fronteira.

Nenhuma submissão foi feita ao Immunefi. Nenhum achado foi divulgado. Todo o
material aqui é leitura de código público.

**Anterior**: [Arquitetura](05_ARQUITETURA.md) · **Início**: [Roadmap](00_ROADMAP.md)