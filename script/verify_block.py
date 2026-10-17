#!/usr/bin/env python3
"""Verifica enderecos de um exploit contra o estado on-chain e grava um dump.

Uso:
    python3 script/verify_block.py [BLOCO] [--dump]

BLOCO padrao: 16818061 (market wstETH do Euler).

Por que isso existe: enderecos publicados em PoC de terceiros quase sempre
trocam de papel. Verificar ANTES de escrever o exploit evita horas de
confusao depois -- em especial o caso do Euler, em que o endereco rotulado
"EULER" em quase todo PoC e o Dispatcher (que custodia o subjacente), e nao
o eToken. Procurar o saldo no eToken da 0 e parece fork quebrado.

Sem argumentos extras, so imprime. Com --dump, grava
data/euler_block_<BLOCO>.json.
"""
import json
import os
import sys
import time
import urllib.request

RPC = ""
for _line in open(os.path.join(os.path.dirname(__file__), "..", ".env")):
    if _line.startswith("ETHEREUM_RPC_URL="):
        RPC = _line.strip().split("=", 1)[1]
if not RPC:
    RPC = os.environ.get("ETHEREUM_RPC_URL", "")
if not RPC:
    sys.exit("defina ETHEREUM_RPC_URL no .env ou no ambiente")

BLOCO = 16818061
DUMP = "--dump" in sys.argv
for arg in sys.argv[1:]:
    if arg != "--dump":
        BLOCO = int(arg, 0)
H = hex(BLOCO)

# Papel -> endereco. Verificado em 2026-10-16 no bloco 16818061.
ENDERECOS = {
    "wstETH": "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
    "eToken_ewstETH": "0xbd1bd5C956684f7EB79DA40f582cbE1373A1D593",
    "dToken_dwstETH": "0x436548baAb5Ec4D79F669D1b9506D67e98927aF7",
    "Euler_Dispatcher": "0x27182842E098f60e3D576794A5bFFb0777E025d3",
    "mod_Liquidation": "0xf43ce1d09050BAfd6980dD43Cde2aB9F18C85b34",
    "mod_Markets": "0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3",
    "Balancer_Vault": "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
}
WSTETH = ENDERECOS["wstETH"]

SELETORES = {
    "name()": "0x06fdde03",
    "symbol()": "0x95d89b41",
    "totalSupply()": "0x18160ddd",
    "moduleId()": "0x097b1c69",
}


def rpc(metodo, params):
    corpo = json.dumps({"jsonrpc": "2.0", "method": metodo, "params": params, "id": 1}).encode()
    req = urllib.request.Request(
        str(RPC), data=corpo, headers={"Content-Type": "application/json"}
    )
    return json.loads(urllib.request.urlopen(req, timeout=45).read())


def call(destino, dados):
    return rpc("eth_call", [{"to": destino, "data": dados}, H])


def como_str(res):
    try:
        x = res["result"][2:]
        n = int(x[64:128], 16)
        return bytes.fromhex(x[128 : 128 + n * 2]).decode()
    except (KeyError, ValueError, TypeError):
        return None


def como_int(res):
    try:
        return int(res["result"], 16)
    except (KeyError, ValueError, TypeError):
        return None


def saldo_de(token, dono):
    return como_int(call(token, "0x70a08231" + dono[2:].rjust(64, "0"))) or 0


def main():
    print(f"RPC    : {RPC}")
    print(f"bloco  : {BLOCO} ({H})\n")
    print(f"{'papel':<20}{'endereco':<44}{'code':>7}  nome")
    print("-" * 100)

    dump = {
        "_meta": {
            "descricao": (
                "Dump de estado on-chain verificado. Gerado por "
                "script/verify_block.py. Nao edite a mao - regenere."
            ),
            "fork_block": BLOCO,
            "rpc": RPC,
            "gerado_em": time.strftime("%Y-%m-%d"),
            "aviso": (
                "Dump confere ESTADO, naoSeed. Nenhum valor aqui e dinheiro real."
            ),
        },
        "enderecos": {},
        "saldos_wstETH": {},
    }

    for papel, addr in ENDERECOS.items():
        try:
            code = rpc("eth_getCode", [addr, H]).get("result", "")
            tam = (len(code) - 2) // 2
            nome = como_str(call(addr, SELETORES["name()"]))
            linha = f"{papel:<20}{addr:<44}{tam:>7}  {nome or '-'}"
            print(linha)

            ent = {"endereco": addr, "code_bytes": tam}
            if nome:
                ent["name"] = nome
            sim = como_str(call(addr, SELETORES["symbol()"]))
            if sim:
                ent["symbol"] = sim
            ts = como_int(call(addr, SELETORES["totalSupply()"]))
            if ts:
                ent["totalSupply"] = str(ts)
            mid = como_int(call(addr, SELETORES["moduleId()"]))
            if mid is not None:
                ent["moduleId"] = mid
            dump["enderecos"][papel] = ent
            dump["saldos_wstETH"][papel] = str(saldo_de(WSTETH, addr))
        except Exception as exc:  # noqa: BLE001
            print(f"{papel:<20}{addr:<44}  FALHA: {exc}")

    reserva = int(dump["saldos_wstETH"]["Euler_Dispatcher"])
    ebal = int(dump["saldos_wstETH"]["eToken_ewstETH"])

    print()
    print("=" * 72)
    print("  PONTO QUE MAIS CONFUNDE QUEM COPIA PGC DE TERCEIROS")
    print("=" * 72)
    print(f"  wstETH no Euler_Dispatcher : {reserva / 1e18:>15,.2f}")
    print(f"  wstETH no eToken          : {ebal / 1e18:>15,.2f}")
    print()
    print("  O endereco rotulado 'EULER' em quase todo PoC publicado e o")
    print("  DISPATCHER -- e ele quem custodia o subjacente. O eToken nao tem")
    print("  saldo nenhum. Procurar o saldo no eToken da 0 e parece fork quebrado.")
    print("=" * 72)

    dump["saldos_wstETH"]["_nota"] = (
        "Euler_Dispatcher e quem custodia o subjacente; o eToken nao tem saldo."
    )

    if DUMP:
        rel = os.path.join("data", f"euler_block_{BLOCO}.json")
        os.makedirs("data", exist_ok=True)
        with open(rel, "w") as fh:
            json.dump(dump, fh, indent=2, ensure_ascii=False)
        print(f"\ndump gravado em {rel}")


if __name__ == "__main__":
    main()