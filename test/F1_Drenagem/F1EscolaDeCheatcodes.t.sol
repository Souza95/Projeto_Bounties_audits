// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

/// @notice Alvo genérico: registra quem chamou e qual msg.sender o
///         contrato enxergou. Serve para provar `prank` / `startPrank`.
contract Sensor {
    address public ultimoRemetente;
    uint256 public contador;

    function quemChamou() external returns (address) {
        ultimoRemetente = msg.sender;
        contador += 1;
        return msg.sender;
    }

    function calha() external payable {}
}

/// @notice Alvo com require, para `expectRevert`.
contract ComGuarda {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function apenasOwner() external view {
        require(msg.sender == owner, "only owner");
    }

    function valorExato(uint256 x) external pure returns (uint256) {
        require(x > 0, "valor zero");
        return x * 2;
    }
}

contract ERC20Falso {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 qty) external {
        balanceOf[to] += qty;
    }
}

/// @title F1EscolaDeCheatcodes — o vocabulário que você precisa dominar
/// @notice Um teste por cheatcode. O objetivo NÃO é decorar a assinatura;
///         é internalizar *o que o cheatcode mente para o contrato*.
///
/// A regra de ouro do Foundry: um cheatcode ajusta o estado do bloco como
/// se algo tivesse acontecido, sem que nada tenha acontecido de fato.
/// O contrato não sabe. Ele só vê um mundo consistente com a mentira.
///
/// Como ler isso na prática:
///     forge test --match-contract F1Escola -vvvv
/// Cada teste tem o log mostrando o valor antes/depois.
contract F1EscolaDeCheatcodes is Test {
    Sensor sensor;
    ComGuarda guarda;
    ERC20Falso token;

    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant CAROL = address(0xCA401);

    function setUp() public {
        sensor = new Sensor();
        guarda = new ComGuarda();
        token = new ERC20Falso();
    }

    // ══════════════════════════════════════════════════════════════════
    // vm.prank — falsifica msg.sender da PRÓXIMA chamada externa
    // ══════════════════════════════════════════════════════════════════

    /// @dev Sem prank, quem chamou foi o próprio contrato de teste.
    function test_prank_sem() public {
        sensor.quemChamou();
        console.log("sem prank, o sensor viu :", sensor.ultimoRemetente());
        assertEq(sensor.ultimoRemetente(), address(this));
    }

    /// @dev `vm.prank(ALICE)` faz o *próximo* call externo sair da conta
    /// da ALICE. O truque: a prank tem que vir JUSTO antes do call, e
    /// vale para UM call só.
    function test_prank_com() public {
        vm.prank(ALICE);
        sensor.quemChamou();

        console.log("com prank, o sensor viu :", sensor.ultimoRemetente());
        assertEq(sensor.ultimoRemetente(), ALICE);
    }

    /// @dev O erro clássico: colocar o prank longe demais do call.
    /// A prank é consumida pela PRÓXIMA chamada externa — se um `console.log`
    /// ou outro contrato entrar no meio, ela se perde e o teste mente.
    function test_prank_tem_que_ser_imediato() public {
        // ERRADO: esta prank seria consumida pela próxima chamada.
        // vm.prank(ALICE);

        // Certo: colada no call.
        vm.prank(ALICE);
        sensor.quemChamou();
        assertEq(sensor.ultimoRemetente(), ALICE);

        // E a prank já foi: esta chamada NÃO usa ALICE.
        sensor.quemChamou();
        assertEq(sensor.ultimoRemetente(), address(this));
    }

    // ══════════════════════════════════════════════════════════════════
    // vm.startPrank / vm.stopPrank — vários calls com o mesmo remetente
    // ══════════════════════════════════════════════════════════════════

    /// @dev Quando o ataque faz vários calls seguidos (o caso da
    /// reentrância), `prank` só aguentaria o primeiro. `startPrank` segura
    /// a identidade até `stopPrank`.
    function test_startPrank_holdAIdentidade() public {
        vm.startPrank(BOB);
        sensor.quemChamou();
        sensor.quemChamou();
        sensor.quemChamou();
        vm.stopPrank();

        assertEq(sensor.ultimoRemetente(), BOB, "todos os calls vieram do BOB");
        assertEq(sensor.contador(), 3, "3 chamadas registradas");
    }

    /// @dev `startPrank` também pode definir o valor de msg.value, para
    /// simular um depósito sem precisar de saldo real.
    function test_startPrank_comValor() public {
        vm.deal(CAROL, 10 ether);

        vm.deal(address(sensor), 0);
        vm.startPrank(CAROL);
        sensor.calha{value: 3 ether}();
        vm.stopPrank();

        assertEq(address(sensor).balance, 3 ether);
        console.log("CAROL depositou 3 ETH via prank com valor");
    }

    // ══════════════════════════════════════════════════════════════════
    // vm.deal — forja saldo ETH
    // ══════════════════════════════════════════════════════════════════

    /// @dev `deal` é a forma mais direta: escreve no saldo de um endereço.
    /// Existe também `deal(token, to, amount)` para ERC-20 (o snippet
    /// do plano menciona isso) — e `deal` com `adjust` para ERC-20
    /// que também guardam o totalSupply.
    function test_deal_ETH() public {
        assertEq(ALICE.balance, 0, "comeca zerado");

        vm.deal(ALICE, 1000 ether);

        assertEq(ALICE.balance, 1000 ether);
        console.log("ALICE forjado para:", ALICE.balance);
    }

    /// @dev A variante ERC-20. O Foundry detecta o padrão e escreve no
    /// slot certo — mas se o token for não-standard (slot manual, proxy),
    /// você precisa de `stdstore` para achar o slot na mão.
    function test_deal_ERC20() public {
        token.mint(ALICE, 5 ether);
        assertEq(token.balanceOf(ALICE), 5 ether);

        // `deal(token, to, amount)` NÃO tem o prefixo vm.: vem do StdCheats.
        deal(address(token), BOB, 777 ether);
        assertEq(token.balanceOf(BOB), 777 ether);

        console.log("BOB tem", token.balanceOf(BOB), "de token falso");
    }

    /// @dev `deal` não mexe em timestamp. Para isso existe `warp`.
    function test_deal_nao_mexe_no_tempo() public {
        uint256 t0 = block.timestamp;
        vm.deal(ALICE, 1 ether);
        assertEq(block.timestamp, t0, "deal nao altera o relogio");
    }

    // ══════════════════════════════════════════════════════════════════
    // vm.expectRevert — declara que o próximo call DEVE falhar
    // ══════════════════════════════════════════════════════════════════

    function test_expectRevert_simples() public {
        vm.prank(ALICE);
        vm.expectRevert();
        guarda.apenasOwner(); // ALICE não é o owner → reverte
    }

    /// @dev `expectRevert` com seletor: garante que a falha foi pelo MOTIVO
    /// certo, não por qualquer outra razão. Numa auditoria isso é
    /// essencial — um reverter "pelo motivo errado" esconde o bug real.
    ///
    /// PEGADINHA: quando o contrato usa `require("texto")`, o revert
    /// NÃO é o seletor puro — é o envelope `Error(string)`. Precisa:
    ///
    ///     vm.expectRevert(abi.encodeWithSignature("Error(string)", "only owner"));
    ///
    /// Se o contrato usasse `revert OnlyOwner()` (custom error), aí sim
    /// seria só `vm.expectRevert(ComGuarda.OnlyOwner.selector)`.
    /// Assertion failed com "Error != expected error" = este envelope
    /// faltando.
    function test_expectRevert_comMotivo() public {
        bytes4 seletor = bytes4(keccak256("Error(string)"));
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "only owner"));

        guarda.apenasOwner();

        console.log("reverteu pelo motivo certo (Error(string) 'only owner')");
        assertEq(seletor, bytes4(keccak256("Error(string)")));
    }

    /// @dev Variante com `require` numérico, para ver o motivo exato.
    function test_expectRevert_outroMotivo() public {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "valor zero"));
        guarda.valorExato(0);

        // E o caminho feliz, com o MESMO contrato:
        assertEq(guarda.valorExato(21), 42);
    }

    // ══════════════════════════════════════════════════════════════════
    // vm.roll / vm.warp — mexe no relógio
    // ══════════════════════════════════════════════════════════════════

    /// @dev `roll` move o BLOCK NUMBER. `warp` move o TIMESTAMP.
    /// Erro clássico: usar `roll` quando queria `warp`.
    function test_roll_vs_warp() public {
        uint256 bloco0 = block.number;
        uint256 tempo0 = block.timestamp;

        vm.roll(20_000_000);
        assertEq(block.number, 20_000_000, "roll mexe no numero do bloco");
        assertEq(block.timestamp, tempo0, "roll NAO mexe no tempo");

        vm.warp(tempo0 + 365 days);
        assertEq(block.timestamp, tempo0 + 365 days, "warp mexe no relogio");
        assertEq(block.number, 20_000_000, "warp NAO mexe no bloco");

        console.log("bloco  :", bloco0, "->", block.number);
        console.log("tempo  :", tempo0, "->", block.timestamp);
    }

    // ══════════════════════════════════════════════════════════════════
    // vm.label / vm.assume — legibilidade e sanidade
    // ══════════════════════════════════════════════════════════════════

    /// @dev `label` não muda nada — só troca o endereço por um nome nos
    /// logs. Parece inútil, e é o que torna um trace de 500 linhas legível.
    function test_label_deixaTraceLegivel() public {
        vm.label(ALICE, "alice");
        vm.label(BOB, "bob");

        vm.startPrank(ALICE);
        sensor.quemChamou();
        vm.stopPrank();

        // nos logs de -vvvv isso aparece como "alice" em vez do 0x...
        assertEq(sensor.ultimoRemetente(), ALICE);
    }
}
