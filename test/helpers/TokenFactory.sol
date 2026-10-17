// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CoinbaseToken} from "../../src/CoinbaseToken.sol";

/// @dev Test fixture only; not a launch application contract.
contract TokenFactory {
    function deploy(bytes32 salt) external returns (CoinbaseToken) {
        return new CoinbaseToken{salt: salt}();
    }
}
