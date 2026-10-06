// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {VolatilityRoyaltyHook} from "../src/VolatilityRoyaltyHook.sol";
import {HookFactory} from "../src/HookFactory.sol";
import {RehearsalRouter} from "../src/testnet/RehearsalRouter.sol";
import {TestToken} from "../src/testnet/TestToken.sol";

contract RejectETH { receive() external payable { revert("No ETH"); } }

contract IntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    IPoolManager manager;
    HookFactory factory;
    VolatilityRoyaltyHook hook;
    RehearsalRouter router;
    TestToken token;
    PoolKey key;
    uint256 constant LIQUIDITY = 100 ether;
    receive() external payable {}

    function setUp() public virtual {
        vm.chainId(31337);
        vm.warp(1000);
        vm.deal(address(this), 1000 ether);
        manager = IPoolManager(address(new PoolManager(address(this))));
        factory = new HookFactory();
        hook = _deployHook(10, address(this));
        router = new RehearsalRouter(manager, address(this));
        token = new TestToken("Rehearsal Token", "TEST");
        token.faucet(address(this), 10000 ether);
        token.approve(address(router), type(uint256).max);
        key = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), 0x800000, 60, IHooks(address(hook)));
        manager.initialize(key, uint160(1 << 96));
        router.liquidity{value: 10 ether}(key, _position(int256(LIQUIDITY)), 10 ether, 10 ether, block.timestamp);
    }
    function _position(int256 amount) internal pure returns (ModifyLiquidityParams memory) {
        return ModifyLiquidityParams(-600, 600, amount, bytes32(0));
    }
    function _deployHook(uint16 bps, address author) internal returns (VolatilityRoyaltyHook deployed) {
        bytes32 hash = keccak256(abi.encodePacked(type(VolatilityRoyaltyHook).creationCode, abi.encode(manager, author, bps)));
        for (uint256 i;; ++i) {
            address predicted = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), bytes32(i), hash)))));
            if ((uint160(predicted) & 0x3fff) == 0x10c4) {
                deployed = factory.deploy(bytes32(i), manager, author, bps);
                assertEq(address(deployed), predicted); return deployed;
            }
        }
    }
    function _swap(bool buy, uint256 amount, uint256 minOut, uint160 priceLimit) internal returns (BalanceDelta) {
        return router.swap{value: buy ? amount : 0}(key,
            SwapParams(buy, -int256(amount), priceLimit), minOut, block.timestamp);
    }
    function _swap(bool buy, uint256 amount) internal returns (BalanceDelta) {
        return _swap(buy, amount, 0, buy ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1);
    }
    function _assertSettled() internal view {
        assertEq(manager.getNonzeroDeltaCount(), 0);
        assertEq(manager.currencyDelta(address(hook), key.currency0), 0);
        assertEq(manager.currencyDelta(address(hook), key.currency1), 0);
        assertEq(manager.currencyDelta(address(router), key.currency0), 0);
        assertEq(manager.currencyDelta(address(router), key.currency1), 0);
        assertFalse(manager.isUnlocked());
    }
    function _assertRoyalty(uint256 net, uint256 claim) internal pure {
        assertEq(claim, (net + claim) * 10 / 10000);
    }
    function testNativeBuySettlesRoyaltyAndTokenClaim() public {
        uint256 beforeTokens = token.balanceOf(address(this));
        uint256 beforeETH = address(this).balance;
        BalanceDelta d = _swap(true, 0.1 ether);
        assertEq(beforeETH - address(this).balance, uint128(-d.amount0()));
        assertEq(token.balanceOf(address(this)) - beforeTokens, uint128(d.amount1()));
        uint256 claim = manager.balanceOf(address(hook), key.currency1.toId());
        _assertRoyalty(uint128(d.amount1()), claim);
        assertGt(claim, 0);
        hook.claim(key.currency1, address(123), claim);
        assertEq(token.balanceOf(address(123)), claim);
        assertEq(manager.balanceOf(address(hook), key.currency1.toId()), 0);
        _assertSettled();
    }
    function testTokenSellSettlesNativeClaim() public {
        uint256 beforeETH = address(this).balance;
        BalanceDelta d = _swap(false, 0.1 ether);
        assertEq(address(this).balance - beforeETH, uint128(d.amount0()));
        uint256 claim = manager.balanceOf(address(hook), 0);
        _assertRoyalty(uint128(d.amount0()), claim);
        hook.claim(key.currency0, address(123), claim);
        assertEq(address(123).balance, claim);
        _assertSettled();
    }
    function testRejectedNativeClaimDoesNotBlockTrading() public {
        _swap(false, 0.1 ether);
        uint256 claim = manager.balanceOf(address(hook), 0);
        RejectETH rejector = new RejectETH();
        vm.expectRevert(); hook.claim(key.currency0, address(rejector), claim);
        assertEq(manager.balanceOf(address(hook), 0), claim);
        _swap(false, 0.1 ether);
        hook.claim(key.currency0, address(this), manager.balanceOf(address(hook), 0));
        _assertSettled();
    }
    function testUnauthorizedAndExcessClaimRevert() public {
        _swap(true, 0.1 ether);
        uint256 claim = manager.balanceOf(address(hook), key.currency1.toId());
        vm.prank(address(123)); vm.expectRevert(); hook.claim(key.currency1, address(123), claim);
        vm.expectRevert(); hook.claim(key.currency1, address(this), claim + 1);
        assertEq(manager.balanceOf(address(hook), key.currency1.toId()), claim);
        _assertSettled();
    }
    function testMinOutputIncludesRoyaltyAndRevertsAtomically() public {
        uint256 snapshot = vm.snapshotState();
        BalanceDelta d = _swap(true, 0.1 ether);
        uint256 net = uint128(d.amount1());
        assertTrue(vm.revertToState(snapshot));
        vm.expectRevert("Too little output");
        router.swap{value: 0.1 ether}(key, SwapParams(true, -0.1 ether, TickMath.MIN_SQRT_PRICE + 1), net + 1, block.timestamp);
        assertEq(manager.balanceOf(address(hook), key.currency1.toId()), 0);
        _assertSettled();
    }
    function testPartialFillChargesActualOutputAndRefundsETH() public {
        uint256 beforeETH = address(this).balance;
        BalanceDelta d = _swap(true, 1 ether, 0, TickMath.getSqrtPriceAtTick(-10));
        uint256 spent = beforeETH - address(this).balance;
        assertGt(spent, 0); assertLt(spent, 1 ether);
        assertEq(spent, uint128(-d.amount0()));
        _assertRoyalty(uint128(d.amount1()), manager.balanceOf(address(hook), key.currency1.toId()));
        assertEq(address(router).balance, 0);
        _assertSettled();
    }
    function testCollectFeesAndRemoveAllLiquidity() public {
        _swap(true, 0.1 ether); _swap(false, 0.1 ether);
        BalanceDelta fees = router.liquidity(key, _position(0), 0, 0, block.timestamp);
        assertTrue(fees.amount0() > 0 || fees.amount1() > 0);
        router.liquidity(key, _position(-int256(LIQUIDITY)), 0, 0, block.timestamp);
        assertEq(manager.getLiquidity(key.toId()), 0);
        _assertSettled();
    }
    function testPositionCannotBeRemovedByOtherWallet() public {
        vm.prank(address(123)); vm.expectRevert("Owner only");
        router.liquidity(key, _position(-int256(LIQUIDITY)), 0, 0, block.timestamp);
    }
    function testExpiredSwapAndLiquidityBoundsRevert() public {
        vm.expectRevert("Expired"); router.swap(key, SwapParams(true, -1000, TickMath.MIN_SQRT_PRICE + 1), 0, block.timestamp - 1);
        vm.expectRevert("Too much input"); router.liquidity(key, _position(1 ether), 0, 0, block.timestamp);
    }
    function testERC20PairBothDirections() public {
        TestToken other = new TestToken("Other", "OTHER");
        other.faucet(address(this), 10000 ether); other.approve(address(router), type(uint256).max);
        (address a, address b) = address(token) < address(other) ? (address(token), address(other)) : (address(other), address(token));
        key = PoolKey(Currency.wrap(a), Currency.wrap(b), 0x800000, 60, IHooks(address(hook)));
        manager.initialize(key, uint160(1 << 96));
        router.liquidity(key, _position(int256(LIQUIDITY)), 10 ether, 10 ether, block.timestamp);
        router.swap(key, SwapParams(true, -0.1 ether, TickMath.MIN_SQRT_PRICE + 1), 1, block.timestamp);
        router.swap(key, SwapParams(false, -0.1 ether, TickMath.MAX_SQRT_PRICE - 1), 1, block.timestamp);
        assertGt(manager.balanceOf(address(hook), key.currency0.toId()), 0);
        assertGt(manager.balanceOf(address(hook), key.currency1.toId()), 0);
        _assertSettled();
    }
    function testDecayAnchorSurvivesDustObservations() public {
        _swap(true, 1 ether);
        (, uint64 anchor, uint24 initial) = hook.observations(key.toId());
        assertGt(initial, 30);
        for (uint256 i = 1; i <= 60; ++i) {
            vm.warp(uint256(anchor) + i);
            _swap(true, 1000);
        }
        (,uint64 finalAnchor,uint24 signal) = hook.observations(key.toId());
        assertEq(finalAnchor, anchor);
        assertEq(hook.decayedSignal(signal, block.timestamp - finalAnchor), 0);
    }
    function testFuzzRoundTripSettlement(uint96 amountSeed, uint16 waitSeed) public {
        uint256 amount = bound(uint256(amountSeed), 1e9, 1 ether);
        _swap(true, amount);
        vm.warp(block.timestamp + bound(uint256(waitSeed), 0, 120));
        _swap(false, amount);
        _assertSettled();
    }
    function testMainnetRehearsalContractsRejected() public {
        vm.chainId(4663);
        vm.expectRevert("Testnet only"); new TestToken("No", "NO");
        vm.expectRevert("Testnet only"); new RehearsalRouter(manager, address(this));
    }

    // Economic limitation regression: many individually small trades can move the
    // pool materially without ever producing a large per-trade volatility signal.
    function testSplitTradesAvoidSurgeSignal() public {
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < 100; ++i) _swap(true, 0.01 ether);
        (, int24 splitTick,,) = manager.getSlot0(key.toId());
        (,, uint24 splitSignal) = hook.observations(key.toId());
        assertLt(splitTick, -100);
        assertLe(splitSignal, 30);
        assertEq(hook.feeForSignal(splitSignal), 1500);
        assertTrue(vm.revertToState(snapshot));
        _swap(true, 1 ether);
        (,, uint24 singleSignal) = hook.observations(key.toId());
        assertGt(singleSignal, 30);
        emit log_named_uint("Split trade signal", splitSignal);
        emit log_named_uint("Single trade signal", singleSignal);
        emit log_named_uint("Next fee after split trades (millionths)", hook.feeForSignal(splitSignal));
        emit log_named_uint("Next fee after one trade (millionths)", hook.feeForSignal(singleSignal));
    }
}
