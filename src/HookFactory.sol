// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {VolatilityRoyaltyHook} from "./VolatilityRoyaltyHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract HookFactory {
    event Deployed(address indexed hook, address indexed author, bytes32 salt);
    function deploy(bytes32 salt, IPoolManager manager, address author, uint16 bps)
        external returns (VolatilityRoyaltyHook hook)
    {
        hook = new VolatilityRoyaltyHook{salt: salt}(manager, author, bps);
        emit Deployed(address(hook), author, salt);
    }
}
