// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";

/// @notice Research prototype. Reactive fees do NOT measure or capture external LVR.
/// Exact-input only. Royalty is a fraction of actual output, paid in that currency.
contract CumulativeVolatilityHook is BaseHook, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint24 public constant BASE_FEE = 1500; // millionths: 0.15%
    uint24 public constant MAX_FEE = 10000; // 1%, experimental cap
    uint256 public constant DECAY_TICKS_PER_SECOND = 8;
    uint24 public constant MAX_SIGNAL = 455;
    address public immutable author;
    uint16 public immutable royaltyBps; // 0 for baseline; max 0.25% of output
    bool private claiming;

    struct Observation { int24 tick; uint64 time; uint24 signal; }
    mapping(PoolId => Observation) public observations;
    error InvalidConfiguration();
    error ExactOutputUnsupported();
    error NotInitialized();
    error UnauthorizedClaim();
    error ClaimInProgress();
    event FeeApplied(PoolId indexed id, uint24 fee);
    event RoyaltyAccrued(PoolId indexed id, address indexed currency, uint256 amount);
    event RoyaltyClaimed(address indexed currency, address indexed recipient, uint256 amount);

    constructor(IPoolManager manager, address recipient, uint16 bps) BaseHook(manager) {
        if (address(manager).code.length == 0 || recipient == address(0) || bps > 25) {
            revert InvalidConfiguration();
        }
        author = recipient;
        royaltyBps = bps;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.afterInitialize = true;
        p.beforeSwap = true;
        p.afterSwap = true;
        p.afterSwapReturnDelta = true;
    }

    function _afterInitialize(address, PoolKey calldata key, uint160, int24 tick)
        internal override returns (bytes4)
    {
        if (key.fee != LPFeeLibrary.DYNAMIC_FEE_FLAG) revert InvalidConfiguration();
        observations[key.toId()] = Observation(tick, uint64(block.timestamp), 0);
        return IHooks.afterInitialize.selector;
    }

    function decayedSignal(uint24 signal, uint256 elapsed) public pure returns (uint24) {
        if (elapsed >= (uint256(signal) + DECAY_TICKS_PER_SECOND - 1) / DECAY_TICKS_PER_SECOND) return 0;
        return uint24(uint256(signal) - elapsed * DECAY_TICKS_PER_SECOND);
    }

    function feeForSignal(uint24 signal) public pure returns (uint24) {
        // Saturate before narrowing. Thirty ticks is a noise threshold, not an oracle.
        uint256 fee = BASE_FEE + (signal > 30 ? uint256(signal - 30) * 20 : 0);
        return fee > MAX_FEE ? MAX_FEE : uint24(fee);
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal override returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (params.amountSpecified >= 0) revert ExactOutputUnsupported();
        Observation memory o = observations[key.toId()];
        if (o.time == 0) revert NotInitialized();
        uint24 fee = feeForSignal(decayedSignal(o.signal, block.timestamp - o.time));
        emit FeeApplied(key.toId(), fee);
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA,
            fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata params,
        BalanceDelta delta, bytes calldata) internal override returns (bytes4, int128)
    {
        PoolId id = key.toId();
        {
        Observation storage o = observations[id];
        (, int24 tick,,) = poolManager.getSlot0(id);
        int256 movement = int256(tick) - int256(o.tick);
        uint24 magnitude = uint24(uint256(movement < 0 ? -movement : movement));
        uint24 retained = decayedSignal(o.signal, block.timestamp - o.time);
        // Add absolute tick travel, so same-timestamp fragments accumulate.
        // Fixed-rate decay avoids resetting a proportional decay anchor on dust trades.
        uint256 combined = uint256(retained) + magnitude;
        o.signal = combined > MAX_SIGNAL ? MAX_SIGNAL : uint24(combined);
        o.time = uint64(block.timestamp);
        o.tick = tick;
        }

        int128 output = params.zeroForOne ? delta.amount1() : delta.amount0();
        if (output <= 0 || royaltyBps == 0) return (IHooks.afterSwap.selector, 0);
        uint256 cut = uint256(uint128(output)) * royaltyBps / 10000;
        if (cut != 0) {
            Currency currency = params.zeroForOne ? key.currency1 : key.currency0;
            // Mint manager-backed ERC-6909 claims instead of calling the author during a swap.
            // The positive hook delta offsets this mint; later redemption burns the claims.
            poolManager.mint(address(this), currency.toId(), cut);
            emit RoyaltyAccrued(id, Currency.unwrap(currency), cut);
        }
        return (IHooks.afterSwap.selector, int128(int256(cut)));
    }

    /// @notice Only the immutable author can redeem accrued fees, to any nonzero recipient.
    /// A failed withdrawal reverts atomically without affecting future swaps.
    function claim(Currency currency, address recipient, uint256 amount) external {
        if (msg.sender != author || recipient == address(0) || amount == 0) revert UnauthorizedClaim();
        if (claiming) revert ClaimInProgress();
        claiming = true;
        poolManager.unlock(abi.encode(currency, recipient, amount));
        claiming = false;
        emit RoyaltyClaimed(Currency.unwrap(currency), recipient, amount);
    }

    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        if (!claiming) revert UnauthorizedClaim();
        (Currency currency, address recipient, uint256 amount) = abi.decode(data, (Currency, address, uint256));
        poolManager.burn(address(this), currency.toId(), amount);
        poolManager.take(currency, recipient, amount);
        return "";
    }
}
