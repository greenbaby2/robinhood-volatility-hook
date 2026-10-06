// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {CumulativeVolatilityHook} from "./CumulativeVolatilityHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract PilotHookFactory {
    event Deployed(address indexed hook, address indexed author, bytes32 salt);
    function deploy(bytes32 salt, IPoolManager manager, address author, uint16 bps)
        external returns (CumulativeVolatilityHook hook)
    {
        hook = new CumulativeVolatilityHook{salt: salt}(manager, author, bps);
        emit Deployed(address(hook), author, salt);
    }
}
