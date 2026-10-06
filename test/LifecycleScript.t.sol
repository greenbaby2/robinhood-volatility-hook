// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {TestnetLifecycle} from "../script/TestnetLifecycle.s.sol";
import {VolatilityRoyaltyHook} from "../src/VolatilityRoyaltyHook.sol";
import {TestToken} from "../src/testnet/TestToken.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
contract LifecycleScriptTest is Test {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    address constant WALLET = 0xfE6Fac6620c89f7DDa96d1B3c34300C75aBBe6b8;
    function testCompleteDeploymentScript() public {
        vm.chainId(46630); vm.deal(WALLET, 0.01 ether);
        TestnetLifecycle script = new TestnetLifecycle();
        (address hook, address manager, address router, address token) = script.run();
        assertEq(VolatilityRoyaltyHook(hook).author(), WALLET);
        assertEq(uint160(hook) & 0x3fff, 0x10c4);
        assertEq(IPoolManager(manager).balanceOf(hook, 0), 0);
        assertEq(IPoolManager(manager).balanceOf(hook, uint160(token)), 0);
        PoolKey memory key = PoolKey(Currency.wrap(address(0)), Currency.wrap(token), 0x800000, 60, IHooks(hook));
        assertEq(IPoolManager(manager).getLiquidity(key.toId()), 0);
        assertEq(TestToken(token).allowance(WALLET, router), 0);
        assertGt(WALLET.balance, 0.00999 ether);
    }
    function testDeploymentScriptRejectsMainnet() public {
        vm.chainId(4663);
        TestnetLifecycle script = new TestnetLifecycle();
        vm.expectRevert("Robinhood testnet only"); script.run();
    }
}
