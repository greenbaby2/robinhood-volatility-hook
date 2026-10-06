// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {PilotHookFactory} from "../src/PilotHookFactory.sol";
import {CumulativeVolatilityHook} from "../src/CumulativeVolatilityHook.sol";
import "../src/mainnet/PilotActions.sol";

contract MainnetForkTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    bool enabled;
    CumulativeVolatilityHook hook;
    PoolKey key;
    uint256 id;
    uint128 liquidity;
    IPoolManager manager = IPoolManager(PilotAddresses.MANAGER);
    PilotPositionManager position = PilotPositionManager(PilotAddresses.POSITION);
    PilotPermit2 permit2 = PilotPermit2(PilotAddresses.PERMIT2);
    address owner = PilotAddresses.WALLET;

    function setUp() public {
        enabled = vm.envOr("RUN_MAINNET_FORK", false);
        if (!enabled) return;
        vm.createSelectFork(vm.envOr("ROBINHOOD_RPC", string("https://rpc.mainnet.chain.robinhood.com")),
            vm.envOr("FORK_BLOCK", uint256(81389284)));
        require(block.chainid == PilotAddresses.CHAIN, "Wrong chain");
        require(position.poolManager() == address(manager), "Wrong periphery");
        require(PilotAddresses.ROUTER.code.length > 0 && PilotAddresses.PERMIT2.code.length > 0, "Missing periphery");
        require(PilotToken(PilotAddresses.WETH).decimals() == 18 && PilotToken(PilotAddresses.USDG).decimals() == 6, "Decimals");
        PilotReferencePool referencePool = PilotReferencePool(PilotAddresses.REFERENCE);
        require(referencePool.token0() == PilotAddresses.WETH && referencePool.token1() == PilotAddresses.USDG, "Reference order");
        (uint160 sqrtPrice, int24 tick,,,,,) = referencePool.slot0();
        PilotHookFactory factory = new PilotHookFactory();
        bytes32 hash = keccak256(abi.encodePacked(type(CumulativeVolatilityHook).creationCode, abi.encode(manager, owner, uint16(10))));
        for (uint256 salt;; ++salt) {
            address predicted = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), bytes32(salt), hash)))));
            if ((uint160(predicted) & 0x3fff) == 0x10c4) { hook = factory.deploy(bytes32(salt), manager, owner, 10); break; }
        }
        key = PoolKey(Currency.wrap(PilotAddresses.WETH), Currency.wrap(PilotAddresses.USDG), 0x800000, 60, IHooks(address(hook)));
        // These balances exist only in the local fork. They are not actual wallet funds.
        deal(PilotAddresses.WETH, owner, 0.02 ether);
        deal(PilotAddresses.USDG, owner, 100e6);
        vm.startPrank(owner);
        _approve(PilotAddresses.WETH);
        _approve(PilotAddresses.USDG);
        int24 center = tick / 60 * 60;
        if (tick < 0 && tick % 60 != 0) center -= 60;
        liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtPrice,
            TickMath.getSqrtPriceAtTick(center - 600), TickMath.getSqrtPriceAtTick(center + 600), 0.004 ether, 12e6);
        id = position.nextTokenId();
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(position.initializePool, (key, sqrtPrice));
        calls[1] = abi.encodeCall(position.modifyLiquidities,
            (PilotActions.mint(key, center - 600, center + 600, liquidity, 0.004 ether, 12e6, owner), block.timestamp + 600));
        position.multicall(calls);
        vm.stopPrank();
    }
    function _approve(address token) internal {
        require(PilotToken(token).approve(PilotAddresses.PERMIT2, token == PilotAddresses.WETH ? 0.02 ether : 100e6));
        permit2.approve(token, address(position), uint160(token == PilotAddresses.WETH ? 0.004 ether : 12e6), uint48(block.timestamp + 600));
        permit2.approve(token, PilotAddresses.ROUTER, uint160(token == PilotAddresses.WETH ? 0.001 ether : 3e6), uint48(block.timestamp + 600));
    }
    function testForkMintSwapClaimBurnRevoke() public {
        if (!enabled) { vm.skip(true); return; }
        assertEq(position.ownerOf(id), owner);
        assertEq(position.getPositionLiquidity(id), liquidity);
        vm.startPrank(owner);
        uint256 beforeUSDG = PilotToken(PilotAddresses.USDG).balanceOf(owner);
        PilotUniversalRouter(PilotAddresses.ROUTER).execute(hex"10", PilotActions.swap(key, true, 0.00001 ether, 10000), block.timestamp + 600);
        assertGt(PilotToken(PilotAddresses.USDG).balanceOf(owner), beforeUSDG);
        uint256 beforeWETH = PilotToken(PilotAddresses.WETH).balanceOf(owner);
        PilotUniversalRouter(PilotAddresses.ROUTER).execute(hex"10", PilotActions.swap(key, false, 20000, 1e12), block.timestamp + 600);
        assertGt(PilotToken(PilotAddresses.WETH).balanceOf(owner), beforeWETH);
        for (uint256 i; i < 2; ++i) {
            Currency currency = i == 0 ? key.currency0 : key.currency1;
            uint256 amount = manager.balanceOf(address(hook), currency.toId());
            assertGt(amount, 0);
            hook.claim(currency, owner, amount);
            assertEq(manager.balanceOf(address(hook), currency.toId()), 0);
        }
        position.modifyLiquidities(PilotActions.burn(key, id, 1e12, 10000, owner), block.timestamp + 600);
        assertEq(manager.getLiquidity(key.toId()), 0);
        for (uint256 i; i < 2; ++i) {
            address token = i == 0 ? PilotAddresses.WETH : PilotAddresses.USDG;
            permit2.approve(token, address(position), 0, 0);
            permit2.approve(token, PilotAddresses.ROUTER, 0, 0);
            require(PilotToken(token).approve(PilotAddresses.PERMIT2, 0));
            assertEq(PilotToken(token).allowance(owner, PilotAddresses.PERMIT2), 0);
        }
        vm.stopPrank();
        vm.expectRevert(); position.ownerOf(id);
    }
    function testForkMinOutRollbackAndOwnership() public {
        if (!enabled) { vm.skip(true); return; }
        uint256 balance = PilotToken(PilotAddresses.WETH).balanceOf(owner);
        vm.startPrank(owner);
        vm.expectRevert();
        PilotUniversalRouter(PilotAddresses.ROUTER).execute(hex"10", PilotActions.swap(key, true, 0.00001 ether, 100e6), block.timestamp + 600);
        assertEq(PilotToken(PilotAddresses.WETH).balanceOf(owner), balance);
        vm.expectRevert();
        position.modifyLiquidities(PilotActions.burn(key, id, type(uint128).max, type(uint128).max, owner), block.timestamp + 600);
        assertEq(position.getPositionLiquidity(id), liquidity);
        vm.stopPrank();
        vm.prank(address(123)); vm.expectRevert();
        position.modifyLiquidities(PilotActions.burn(key, id, 0, 0, address(123)), block.timestamp + 600);
        assertEq(position.ownerOf(id), owner);
    }
    function testForkFragmentedTradesBuildSignal() public {
        if (!enabled) { vm.skip(true); return; }
        (,int24 initial,,) = manager.getSlot0(key.toId());
        vm.startPrank(owner);
        for (uint256 i; i < 20; ++i) {
            PilotUniversalRouter(PilotAddresses.ROUTER).execute(hex"10", PilotActions.swap(key, true, 0.00002 ether, 10000), block.timestamp + 600);
        }
        vm.stopPrank();
        (int24 last,,uint24 signal) = hook.observations(key.toId());
        assertGt(signal, 30);
        assertEq(signal, uint24(initial - last));
        assertGt(hook.feeForSignal(signal), hook.BASE_FEE());
    }
    function testForkExpiredPermitAndDeadline() public {
        if (!enabled) { vm.skip(true); return; }
        vm.warp(block.timestamp + 601);
        vm.startPrank(owner);
        vm.expectRevert();
        PilotUniversalRouter(PilotAddresses.ROUTER).execute(hex"10", PilotActions.swap(key, true, 0.00001 ether, 10000), block.timestamp - 1);
        vm.expectRevert();
        PilotUniversalRouter(PilotAddresses.ROUTER).execute(hex"10", PilotActions.swap(key, true, 0.00001 ether, 10000), block.timestamp + 600);
        vm.stopPrank();
        assertEq(position.getPositionLiquidity(id), liquidity);
    }
}
