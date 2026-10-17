// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title VaultVulneravel — o alvo
/// @notice Vault de staking propositalmente quebrado. Reproduz a classe de
///         bug mais cara da história: **reentrância** (TheDAO, 2016).
///
/// O QUE ESTÁ ERRADO
/// ─────────────────
/// Em `withdraw()` o contrato faz a INTERAÇÃO EXTERNA (`msg.sender.call`)
/// ANTES de atualizar o estado (`balances[msg.sender] = 0`).
///
/// A EVM permite que o destinatário da chamada reconecte de volta ao
/// `withdraw()` enquanto ele ainda não terminou de executar. Como o saldo
/// ainda consta cheio no storage, o atacante volta a sacar o mesmo ETH
/// quantas vezes quiser.
///
/// O ataque funciona porque a ordem está invertida. A ordem correta é
/// "checks → effects → interactions" (CEI):
///     1. checks    : valida saldo, exige require
///     2. effects   : escreve no storage  <-- ANTES de chamar fora
///     3. interactions: chama o outro contrato
contract VaultVulneravel {
    mapping(address => uint256) public balances;

    event Deposit(address indexed who, uint256 amount);
    event Withdraw(address indexed who, uint256 amount);

    function deposit() external payable {
        require(msg.value > 0, "valor zero");
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /// @dev BUG: interação (linha 1) antes do efeito (linha 2).
    function withdraw() external {
        require(balances[msg.sender] > 0, "sem deposito");
        uint256 valor = balances[msg.sender]; // checks

        (bool ok,) = msg.sender.call{value: valor}(""); // interactions  <-- aqui
        require(ok, "falha no envio");

        balances[msg.sender] = 0; // effects  <-- tarde demais
        emit Withdraw(msg.sender, valor);
    }

    function saldoDe(address conta) external view returns (uint256) {
        return balances[conta];
    }

    receive() external payable {}
}

/// @title VaultCorrigido — a mesma coisa, escrita direito
/// @notice Serve de referência. Compare linha a linha com o de cima.
///         Este é o exercício nº 1 de qualquer relatório de bug real:
///         "o patch mínimo é mover esta linha para cá".
contract VaultCorrigido {
    mapping(address => uint256) public balances;

    event Withdraw(address indexed who, uint256 amount);

    function deposit() external payable {
        require(msg.value > 0, "valor zero");
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 valor = balances[msg.sender];
        require(valor > 0, "sem deposito");

        balances[msg.sender] = 0; // effects  <-- ANTES de interagir
        (bool ok,) = msg.sender.call{value: valor}("");
        require(ok, "falha no envio");

        emit Withdraw(msg.sender, valor);
    }

    receive() external payable {}
}
