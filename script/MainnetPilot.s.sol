// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {CumulativeVolatilityHook} from "../src/CumulativeVolatilityHook.sol";
import {PilotHookFactory} from "../src/PilotHookFactory.sol";
import "../src/mainnet/PilotActions.sol";

abstract contract PilotScript is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    function checkChain() internal view {
        require(block.chainid == PilotAddresses.CHAIN, "Robinhood mainnet only");
        require(PilotPositionManager(PilotAddresses.POSITION).poolManager() == PilotAddresses.MANAGER, "Manager mismatch");
        require(PilotToken(PilotAddresses.WETH).decimals() == 18 && PilotToken(PilotAddresses.USDG).decimals() == 6, "Decimals changed");
    }
    function checkedKey() internal returns (PoolKey memory key) {
        checkChain();
        address target = vm.envAddress("PILOT_HOOK");
        // Pin code after checking deployment receipt and locally compiled runtime/immutables.
        require(target.code.length > 0 && target.codehash == vm.envBytes32("PILOT_CODEHASH"), "Unverified runtime");
        CumulativeVolatilityHook hook = CumulativeVolatilityHook(target);
        require(address(hook.poolManager()) == PilotAddresses.MANAGER && hook.author() == PilotAddresses.WALLET, "Hook identity");
        require(hook.royaltyBps() == 10 && hook.MAX_SIGNAL() == 455 && hook.DECAY_TICKS_PER_SECOND() == 8, "Hook settings");
        require(uint160(target) & 0x3fff == 0x10c4, "Hook permissions");
        key = PoolKey(Currency.wrap(PilotAddresses.WETH), Currency.wrap(PilotAddresses.USDG), 0x800000, 60, IHooks(target));
    }
    function revoke() internal {
        for (uint256 i; i < 2; ++i) {
            address token = i == 0 ? PilotAddresses.WETH : PilotAddresses.USDG;
            PilotPermit2(PilotAddresses.PERMIT2).approve(token, PilotAddresses.POSITION, 0, 0);
            require(PilotToken(token).approve(PilotAddresses.PERMIT2, 0), "Revoke failed");
        }
    }
}

/// Run without --broadcast to prepare unsigned transactions. No pool funding in this stage.
contract DeployMainnetPilot is PilotScript {
    function run() external returns (CumulativeVolatilityHook hook) {
        checkChain();
        vm.startBroadcast(PilotAddresses.WALLET);
        PilotHookFactory factory = new PilotHookFactory();
        vm.stopBroadcast();
        IPoolManager manager = IPoolManager(PilotAddresses.MANAGER);
        bytes32 hash = keccak256(abi.encodePacked(type(CumulativeVolatilityHook).creationCode,
            abi.encode(manager, PilotAddresses.WALLET, uint16(10))));
        for (uint256 i; i < 1000000; ++i) {
            address predicted = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), bytes32(i), hash)))));
            if ((uint160(predicted) & 0x3fff) != 0x10c4 || predicted.code.length != 0) continue;
            vm.startBroadcast(PilotAddresses.WALLET);
            hook = factory.deploy(bytes32(i), manager, PilotAddresses.WALLET, 10);
            vm.stopBroadcast();
            require(address(hook) == predicted, "Address mismatch");
            console2.log("Predicted hook (not live unless broadcast)", predicted);
            console2.logBytes32(predicted.codehash);
            return hook;
        }
        revert("Salt search exhausted");
    }
}

/// Small pilot only: cap at 0.019 WETH + 50 USDG. No asset acquisition or wrapping.
contract FundMainnetPilot is PilotScript {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    function run() external {
        PoolKey memory key = checkedKey();
        IPoolManager manager = IPoolManager(PilotAddresses.MANAGER);
        (uint160 existing,,,) = manager.getSlot0(key.toId());
        require(existing == 0, "Pool exists; review separately");
        PilotReferencePool market = PilotReferencePool(PilotAddresses.REFERENCE);
        require(market.token0() == PilotAddresses.WETH && market.token1() == PilotAddresses.USDG, "Reference changed");
        (uint160 sqrtPrice, int24 tick,,,,,) = market.slot0();
        // The operator must independently review the reference against a fresh external market quote.
        int256 difference = int256(tick) - vm.envInt("REVIEWED_REFERENCE_TICK");
        require(difference >= -10 && difference <= 10, "Requote price");
        require(PilotToken(PilotAddresses.WETH).balanceOf(PilotAddresses.WALLET) >= 0.019 ether, "Need 0.019 WETH");
        require(PilotToken(PilotAddresses.USDG).balanceOf(PilotAddresses.WALLET) >= 50e6, "Need 50 USDG");
        int24 center = tick / 60 * 60;
        if (tick < 0 && tick % 60 != 0) center -= 60;
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtPrice,
            TickMath.getSqrtPriceAtTick(center - 600), TickMath.getSqrtPriceAtTick(center + 600), 0.019 ether, 50e6);
        liquidity = uint128(uint256(liquidity) * 995 / 1000); // 0.5% input headroom for fixed liquidity
        uint256 deadline = block.timestamp + 1200;
        vm.startBroadcast(PilotAddresses.WALLET);
        for (uint256 i; i < 2; ++i) {
            address token = i == 0 ? PilotAddresses.WETH : PilotAddresses.USDG;
            uint160 cap = uint160(i == 0 ? 0.019 ether : 50e6);
            require(PilotToken(token).approve(PilotAddresses.PERMIT2, cap));
            PilotPermit2(PilotAddresses.PERMIT2).approve(token, PilotAddresses.POSITION, cap, uint48(deadline));
        }
        PilotPositionManager position = PilotPositionManager(PilotAddresses.POSITION);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(position.initializePool, (key, sqrtPrice));
        calls[1] = abi.encodeCall(position.modifyLiquidities,
            (PilotActions.mint(key, center - 600, center + 600, liquidity, 0.019 ether, 50e6, PilotAddresses.WALLET), deadline));
        position.multicall(calls);
        revoke();
        vm.stopBroadcast();
        console2.log("Fixed liquidity", liquidity);
        console2.log("Lower tick", center - 600);
        console2.log("Upper tick", center + 600);
        console2.logBytes32(PoolId.unwrap(key.toId()));
        // Read the actual ERC721 Transfer receipt for tokenId; other users can mint between transactions.
    }
}

contract ExitMainnetPilot is PilotScript {
    function run() external {
        PoolKey memory key = checkedKey();
        uint256 tokenId = vm.envUint("PILOT_TOKEN_ID");
        require(PilotPositionManager(PilotAddresses.POSITION).ownerOf(tokenId) == PilotAddresses.WALLET, "Not your position");
        (PoolKey memory actual,) = PilotPositionManager(PilotAddresses.POSITION).getPoolAndPositionInfo(tokenId);
        require(keccak256(abi.encode(actual)) == keccak256(abi.encode(key)), "Wrong pool NFT");
        uint256 min0 = vm.envUint("EXIT_MIN_WETH");
        uint256 min1 = vm.envUint("EXIT_MIN_USDG");
        require(min0 <= type(uint128).max && min1 <= type(uint128).max && (min0 > 0 || min1 > 0), "Supply exit quote");
        vm.startBroadcast(PilotAddresses.WALLET);
        PilotPositionManager(PilotAddresses.POSITION).modifyLiquidities(
            PilotActions.burn(key, tokenId, uint128(min0), uint128(min1), PilotAddresses.WALLET), block.timestamp + 1200);
        revoke();
        vm.stopBroadcast();
    }
}
