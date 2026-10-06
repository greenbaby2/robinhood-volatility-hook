// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// @notice Owner-only testnet lifecycle router. Not a public production trading integration.
contract RehearsalRouter is IUnlockCallback {
    IPoolManager public immutable manager;
    address public immutable owner;
    bool private entered;
    modifier ownerOnly() { require(msg.sender == owner, "Owner only"); _; }
    modifier locked() { require(!entered, "Reentrant"); entered = true; _; entered = false; }

    constructor(IPoolManager manager_, address owner_) {
        require(block.chainid == 31337 || block.chainid == 46630, "Testnet only");
        require(address(manager_).code.length > 0 && owner_ != address(0), "Bad configuration");
        manager = manager_; owner = owner_;
    }
    receive() external payable {}

    function swap(PoolKey calldata key, SwapParams calldata params, uint256 minOutput, uint256 deadline)
        external payable ownerOnly locked returns (BalanceDelta delta)
    {
        require(block.timestamp <= deadline, "Expired");
        require(params.amountSpecified < 0, "Exact input only");
        delta = abi.decode(manager.unlock(abi.encode(uint8(0), key, abi.encode(params), minOutput, uint256(0))), (BalanceDelta));
        _refund();
    }

    /// @param bound0 Maximum input on add, minimum output on remove/collect (raw units).
    /// @param bound1 Maximum input on add, minimum output on remove/collect (raw units).
    function liquidity(PoolKey calldata key, ModifyLiquidityParams calldata params,
        uint256 bound0, uint256 bound1, uint256 deadline)
        external payable ownerOnly locked returns (BalanceDelta delta)
    {
        require(block.timestamp <= deadline, "Expired");
        delta = abi.decode(manager.unlock(abi.encode(uint8(1), key, abi.encode(params), bound0, bound1)), (BalanceDelta));
        _refund();
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager) && entered, "Invalid callback");
        (uint8 operation, PoolKey memory key, bytes memory params, uint256 bound0, uint256 bound1) =
            abi.decode(data, (uint8, PoolKey, bytes, uint256, uint256));
        BalanceDelta delta;
        if (operation == 0) {
            SwapParams memory p = abi.decode(params, (SwapParams));
            delta = manager.swap(key, p, "");
            int128 output = p.zeroForOne ? delta.amount1() : delta.amount0();
            require(output >= 0 && uint128(output) >= bound0, "Too little output");
        } else {
            ModifyLiquidityParams memory p = abi.decode(params, (ModifyLiquidityParams));
            (delta,) = manager.modifyLiquidity(key, p, "");
            if (p.liquidityDelta > 0) {
                require(_debt(delta.amount0()) <= bound0 && _debt(delta.amount1()) <= bound1, "Too much input");
            } else {
                require(delta.amount0() >= 0 && delta.amount1() >= 0, "Unexpected debt");
                require(uint128(delta.amount0()) >= bound0 && uint128(delta.amount1()) >= bound1, "Too little liquidity output");
            }
        }
        _settle(key.currency0, delta.amount0());
        _settle(key.currency1, delta.amount1());
        return abi.encode(delta);
    }

    function _debt(int128 value) private pure returns (uint256) {
        return value < 0 ? uint256(-int256(value)) : 0;
    }
    function _settle(Currency currency, int128 delta) private {
        if (delta < 0) {
            uint256 amount = _debt(delta);
            if (currency.isAddressZero()) manager.settle{value: amount}();
            else {
                manager.sync(currency);
                require(IERC20Minimal(Currency.unwrap(currency)).transferFrom(owner, address(manager), amount), "Transfer failed");
                manager.settle();
            }
        } else if (delta > 0) manager.take(currency, owner, uint128(delta));
    }
    function _refund() private {
        if (address(this).balance != 0) {
            (bool ok,) = owner.call{value: address(this).balance}("");
            require(ok, "Refund failed");
        }
    }
}
