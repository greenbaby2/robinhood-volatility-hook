// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @notice Valueless rehearsal token. Only deployable on local or Robinhood testnet.
contract TestToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_, 18) {
        require(block.chainid == 31337 || block.chainid == 46630, "Testnet only");
    }
    function faucet(address recipient, uint256 amount) external { _mint(recipient, amount); }
}
