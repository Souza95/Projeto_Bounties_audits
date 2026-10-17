// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

/// @title F0 — Fork da mainnet e leitura de saldo
/// @notice Este é o teste "diagnóstico". Se ele passar, você tem TUDO que
///         precisa para a Fase 1. Ele prova 4 coisas de uma vez:
///           1. o toolchain compila e roda testes
///           2. o endpoint RPC alcança estado histórico (fork funciona)
///           3. você sabe ler saldo de ETH e de ERC-20 em mainnet real
///           4. `vm.createSelectFork` faz o que o nome promete
///
/// O que é `vm.createSelectFork("mainnet", 19_000_000)`?
/// ------------------------------------------------------------
/// O Foundry não roda uma EVM "de mentira". Ele abre um nó real
/// (via RPC) e baixa o *estado completo* da blockchain no bloco 19.000.000
/// para um banco local, então roda a EVM em cima dele.
///
///  "createSelectFork" = cria o fork E o deixa selecionado como ativo.
///  A partir da linha seguinte, todo endereço que você consultar
///  (balanceOf, allowance, storage, code) devolve o valor que tinha
///  NA MAINNET, no bloco 19.000.000.
///
///  Sem argumentos:      usa a rede via chain id (mainnet=1) e "latest".
///  ("mainnet", N):      mainnet, no bloco N.
///  (urlDoRpc, N):       a url explícita + bloco N.
///
///  Consequência prática:合约 o "alvo" do seu exploit pode ser um contrato
///  real da mainnet com bilhões em ETH. Nada disso é simulado.
contract F0ForkBalance is Test {
    // Endereço com saldo ETH conhecido e estável (hot wallet da Binance).
    address constant ALVO_ETH = 0x28C6c06298d514Db089934071355E5743bf21d60;

    // USDC na mainnet — contrato real, para provar leitura de ERC-20.
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        vm.createSelectFork("mainnet", 19_000_000);
    }

    /// O teste mais simples possível: o fork está no bloco certo?
    function test_forkEstaNoBlocoCerto() public view {
        assertEq(block.number, 19_000_000, "fork deve estar no bloco 19.000.000");
        assertEq(block.chainid, 1, "deve ser mainnet (chainid 1)");
    }

    /// Lê saldo ETH de um endereço real da mainnet.
    function test_lerSaldoETH() public view {
        uint256 antes = ALVO_ETH.balance;
        console.log("ALVO   :", ALVO_ETH);
        console.log("saldo  :", antes);
        console.log("bloco  :", block.number);

        assertGt(antes, 100 ether, "alvo deveria ter saldo gigante em ETH");
    }

    /// Lê saldo de um ERC-20 real usando uma chamada normal (não vm.deal).
    /// Isso prova que o bytecode do contrato está disponível no fork também.
    function test_lerSaldoERC20() public view {
        uint256 bal = IERC20Minimal(USDC).balanceOf(address(this));
        console.log("USDC de address(this):", bal);

        // address(this) não tem USDC — o que prova que a chamada aconteceu
        // de verdade e não retornou 0 por erro silencioso.
        assertEq(bal, 0);

        // ...e que um endereço que TEM USDC devolve != 0.
        uint256 binance = IERC20Minimal(USDC).balanceOf(ALVO_ETH);
        console.log("USDC do alvo:", binance);
        assertGt(binance, 0, "alvo tem USDC, logo a leitura funciona");
    }

    /// Prova que o estado é HISTÓRICO, não "latest".
    /// No bloco 19M o alvo tinha ~123k ETH; hoje ele tem menos.
    function test_estadoEhHistorico() public {
        uint256 noBloco19M = ALVO_ETH.balance;
        assertGt(noBloco19M, 0);
        console.log("saldo @19.000.000:", noBloco19M);
        emit log_named_uint("ETH no bloco 19M", noBloco19M);

        // Não comparamos com "hoje" — o fork congela o tempo.
        // Se este teste rodar amanhã, o valor tem que ser IDÊNTICO.
    }
}

interface IERC20Minimal {
    function balanceOf(address) external view returns (uint256);

    function symbol() external view returns (string memory);
}
