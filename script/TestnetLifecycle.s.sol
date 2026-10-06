// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {VolatilityRoyaltyHook} from "../src/VolatilityRoyaltyHook.sol";
import {HookFactory} from "../src/HookFactory.sol";
import {TestToken} from "../src/testnet/TestToken.sol";
import {RehearsalRouter} from "../src/testnet/RehearsalRouter.sol";

/// @notice Deploy an isolated test stack, trade, redeem, and remove all liquidity.
/// Does not publish to Hookr or use a claimed canonical testnet Uniswap deployment.
contract TestnetLifecycle is Script {
    address constant WALLET = 0xfE6Fac6620c89f7DDa96d1B3c34300C75aBBe6b8;
    uint256 constant LIQUIDITY = 0.01 ether;
    function run() public returns (address hookAddress, address managerAddress, address routerAddress, address tokenAddress) {
        require(block.chainid == 46630, "Robinhood testnet only");
        vm.startBroadcast(WALLET);
        IPoolManager manager = IPoolManager(address(new PoolManager(WALLET)));
        TestToken token = new TestToken("Hook Research Test Token", "HRTT");
        HookFactory factory = new HookFactory();
        vm.stopBroadcast();

        (bytes32 salt, address predicted) = _mine(manager, factory);
        vm.startBroadcast(WALLET);
        VolatilityRoyaltyHook hook = factory.deploy(salt, manager, WALLET, 10);
        require(address(hook) == predicted, "Wrong hook address");
        RehearsalRouter router = new RehearsalRouter(manager, WALLET);
        vm.stopBroadcast();
        _exercise(manager, token, hook, router);
        console2.log("TESTNET ONLY - isolated PoolManager, not a Hookr listing");
        console2.log("Wallet", WALLET);
        console2.log("PoolManager", address(manager));
        console2.log("Factory", address(factory));
        console2.log("Hook", address(hook));
        console2.log("Router", address(router));
        console2.log("Test token", address(token));
        return (address(hook), address(manager), address(router), address(token));
    }

    function _mine(IPoolManager manager, HookFactory factory) private pure returns (bytes32 salt, address predicted) {
        bytes32 initHash = keccak256(abi.encodePacked(type(VolatilityRoyaltyHook).creationCode,
            abi.encode(manager, WALLET, uint16(10))));
        bool found;
        for (uint256 i; i < 1000000; ++i) {
            salt = bytes32(i);
            predicted = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, initHash)))));
            if ((uint160(predicted) & 0x3fff) == 0x10c4) { found = true; break; }
        }
        require(found, "Salt search failed");
    }
    function _exercise(IPoolManager manager, TestToken token, VolatilityRoyaltyHook hook, RehearsalRouter router) private {
        vm.startBroadcast(WALLET);
        PoolKey memory key = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)),
            0x800000, 60, IHooks(address(hook)));
        manager.initialize(key, uint160(1 << 96));
        token.faucet(WALLET, 1 ether);
        token.approve(address(router), 1 ether);
        uint256 deadline = block.timestamp + 1 hours;
        router.liquidity{value: 0.0004 ether}(key, ModifyLiquidityParams(-600, 600, int256(LIQUIDITY), 0),
            0.0004 ether, 0.0004 ether, deadline);
        router.swap{value: 0.00001 ether}(key, SwapParams(true, -0.00001 ether, TickMath.MIN_SQRT_PRICE + 1),
            0.000009 ether, deadline);
        router.swap(key, SwapParams(false, -0.00001 ether, TickMath.MAX_SQRT_PRICE - 1), 0.000009 ether, deadline);
        uint256 nativeClaim = manager.balanceOf(address(hook), 0);
        uint256 tokenClaim = manager.balanceOf(address(hook), key.currency1.toId());
        require(nativeClaim > 0 && tokenClaim > 0, "Missing royalty");
        hook.claim(key.currency0, WALLET, nativeClaim);
        hook.claim(key.currency1, WALLET, tokenClaim);
        router.liquidity(key, ModifyLiquidityParams(-600, 600, 0, 0), 0, 0, deadline);
        router.liquidity(key, ModifyLiquidityParams(-600, 600, -int256(LIQUIDITY), 0),
            0.00028 ether, 0.00028 ether, deadline);
        token.approve(address(router), 0);
        vm.stopBroadcast();
        console2.log("Native royalty redeemed (wei)", nativeClaim);
        console2.log("Token royalty redeemed (raw units)", tokenClaim);
    }
}
