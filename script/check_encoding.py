#!/usr/bin/env python3
"""Verifica que nenhum arquivo versionado tem lixo de encoding.

Nao e paranoia: CJK/texto corrompido ja entrou no LICENSE, na descricao
do repo no GitHub e em um comentario Solidity ja versionado - e em todos
os casos passou por review so olhando diff de codigo. Auditoria de encoding
e o tipo de coisa que pega a gente desprevenido.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent

EXTENSOES = {".sol", ".py", ".md", ".toml", ".json", ".sh"}
IGNORAR_DIRS = {".git", "lib", "out", "cache", "node_modules", "broadcast"}

# Faixas nao-latinhas que nao deveriam aparecer em nenhum arquivo daqui.
# Comparacao por nome de bloco Unicode, nao por faixa literal.
PADROES = {
    "CJK (ideogramas)": re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]"),
    "hiragana/katakana": re.compile(r"[\u3040-\u30ff]"),
    "hangul": re.compile(r"[\uac00-\ud7af]"),
    "cirilico": re.compile(r"[\u0400-\u04ff]"),
    "caixa alta fullwidth": re.compile(r"[\uff21-\uff3a]"),
    "substituicao U+FFFD": re.compile(r"\ufffd"),
}


def arquivos_do_git():
    r = subprocess.run(
        ["git", "-C", str(RAIZ), "ls-files"],
        capture_output=True, text=True, check=True,
    )
    return [RAIZ / l for l in r.stdout.splitlines() if l]


def arquivos_do_disco():
    achados = []
    for caminho in RAIZ.rglob("*"):
        if not caminho.is_file():
            continue
        if any(parte in IGNORAR_DIRS for parte in caminho.parts):
            continue
        if caminho.suffix in EXTENSOES or caminho.name in {"LICENSE", "README"}:
            achados.append(caminho)
    return achados


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--git", action="store_true",
                    help="verificar apenas arquivos versionados em HEAD")
    args = ap.parse_args()

    alvos = arquivos_do_git() if args.git else arquivos_do_disco()
    problemas = []

    for caminho in alvos:
        try:
            texto = caminho.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        rel = caminho.relative_to(RAIZ)
        for numero, linha in enumerate(texto.splitlines(), 1):
            for nome, padrao in PADROES.items():
                achado = padrao.search(linha)
                if achado:
                    problemas.append((rel, numero, nome, achado.group(0)))

    if problemas:
        print(f"FALHA: {len(problemas)} trecho(s) com encoding suspeito\n")
        for rel, num, nome, ch in problemas:
            print(f"  {rel}:{num}  [{nome}] -> {ch!r}")
        print("\nNormalize para latin/ASCII antes de commitar.")
        return 1

    print(f"ok: {len(alvos)} arquivo(s) verificado(s), nenhum lixo de encoding.")
    return 0


if __name__ == "__main__":
    sys.exit(main())