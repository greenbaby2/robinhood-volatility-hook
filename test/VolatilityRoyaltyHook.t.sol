// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {VolatilityRoyaltyHook} from "../src/VolatilityRoyaltyHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

interface Vm {
    function warp(uint256) external;
    function prank(address) external;
    function expectRevert() external;
}

/// Unit harness only: it does not reproduce PoolManager settlement.
contract VolatilityRoyaltyHookTest {
    using PoolIdLibrary for PoolKey;
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    VolatilityRoyaltyHook hook;
    PoolKey key;
    mapping(bytes32 => bytes32) slots;
    uint256 taken;
    address takenCurrency;
    address takenRecipient;

    function extsload(bytes32 slot) external view returns (bytes32) { return slots[slot]; }
    function mint(address recipient, uint256 currency, uint256 amount) external {
        require(msg.sender == address(hook));
        taken += amount;
        takenCurrency = address(uint160(currency));
        takenRecipient = recipient;
    }
    function setTick(int24 tick) internal {
        slots[keccak256(abi.encode(key.toId(), uint256(6)))] = bytes32(uint256(uint24(tick)) << 160);
    }
    function setUp() public {
        vm.warp(1000);
        bytes memory args = abi.encode(IPoolManager(address(this)), address(0xBEEF), uint16(10));
        bytes32 initHash = keccak256(abi.encodePacked(type(VolatilityRoyaltyHook).creationCode, args));
        for (uint256 i;; ++i) {
            address predicted = address(uint160(uint256(keccak256(abi.encodePacked(
                bytes1(0xff), address(this), bytes32(i), initHash)))));
            if ((uint160(predicted) & 0x3fff) == 0x10c4) {
                hook = new VolatilityRoyaltyHook{salt: bytes32(i)}(IPoolManager(address(this)), address(0xBEEF), 10);
                break;
            }
        }
        key = PoolKey(Currency.wrap(address(1)), Currency.wrap(address(2)), 0x800000, 60, IHooks(address(hook)));
        hook.afterInitialize(address(this), key, uint160(1 << 96), 0);
    }
    function fee() internal returns (uint24 f) {
        (,, f) = hook.beforeSwap(address(this), key, SwapParams(true, -1000000, 1), "");
        f &= 0x3fffff;
    }
    function move(int24 tick) internal {
        setTick(tick);
        hook.afterSwap(address(this), key, SwapParams(true, -1000000, 1), toBalanceDelta(-1000000, 900000), "");
    }
    function testBaseThenReactiveFee() public { require(fee() == 1500); move(100); require(fee() == 2900); }
    function testTinySwapDoesNotResetSignal() public { move(100); move(100); require(fee() == 2900); }
    function testDecayToBase() public { move(100); vm.warp(1060); require(fee() == 1500); }
    function testRoyaltyBothDirections() public {
        move(100); require(taken == 900 && takenCurrency == address(2) && takenRecipient == address(hook));
        (,int128 delta) = hook.afterSwap(address(this), key, SwapParams(false, -1000000, 1), toBalanceDelta(800000, -1000000), "");
        require(delta == 800 && taken == 1700 && takenCurrency == address(1));
    }
    function testExactOutputRejected() public {
        vm.expectRevert(); hook.beforeSwap(address(this), key, SwapParams(true, 1000, 1), "");
    }
    function testUnauthorizedCallerRejected() public {
        vm.prank(address(99)); vm.expectRevert();
        hook.beforeSwap(address(this), key, SwapParams(true, -1000, 1), "");
    }
    function testStaticFeeRejected() public {
        key.fee = 3000; vm.expectRevert(); hook.afterInitialize(address(this), key, uint160(1 << 96), 0);
    }
    function testPoolIsolation() public {
        move(100); key.tickSpacing = 10;
        hook.afterInitialize(address(this), key, uint160(1 << 96), 0); require(fee() == 1500);
    }
    function testExtremeTickMovementCaps() public { move(-887272); move(887272); require(fee() == 10000); }
    function testFuzzFeeBound(uint24 signal, uint32 elapsed) public view {
        uint24 f = hook.feeForSignal(hook.decayedSignal(signal, elapsed));
        require(f >= 1500 && f <= 10000);
    }
}
