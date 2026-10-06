// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {DeployMainnetPilot, FundMainnetPilot, ExitMainnetPilot} from "../script/MainnetPilot.s.sol";
import {CumulativeVolatilityHook} from "../src/CumulativeVolatilityHook.sol";
import "../src/mainnet/PilotActions.sol";

contract MainnetPilotScriptTest is Test {
    function testForkExactScriptsDeployFundExit() public {
        if (!vm.envOr("RUN_MAINNET_FORK", false)) { vm.skip(true); return; }
        vm.createSelectFork(vm.envOr("ROBINHOOD_RPC", string("https://rpc.mainnet.chain.robinhood.com")),
            vm.envOr("FORK_BLOCK", uint256(81389284)));
        vm.deal(PilotAddresses.WALLET, 1 ether);
        CumulativeVolatilityHook hook = (new DeployMainnetPilot()).run();
        vm.setEnv("PILOT_HOOK", vm.toString(address(hook)));
        vm.setEnv("PILOT_CODEHASH", vm.toString(address(hook).codehash));
        (,int24 tick,,,,,) = PilotReferencePool(PilotAddresses.REFERENCE).slot0();
        vm.setEnv("REVIEWED_REFERENCE_TICK", vm.toString(int256(tick)));
        deal(PilotAddresses.WETH, PilotAddresses.WALLET, 0.004 ether);
        deal(PilotAddresses.USDG, PilotAddresses.WALLET, 12e6);
        PilotPositionManager pm = PilotPositionManager(PilotAddresses.POSITION);
        uint256 tokenId = pm.nextTokenId();
        (new FundMainnetPilot()).run();
        assertEq(pm.ownerOf(tokenId), PilotAddresses.WALLET);
        assertGt(pm.getPositionLiquidity(tokenId), 0);
        _assertRevoked();
        vm.setEnv("PILOT_TOKEN_ID", vm.toString(tokenId));
        vm.setEnv("EXIT_MIN_WETH", "1");
        vm.setEnv("EXIT_MIN_USDG", "1");
        (new ExitMainnetPilot()).run();
        vm.expectRevert(); pm.ownerOf(tokenId);
        assertGe(PilotToken(PilotAddresses.WETH).balanceOf(PilotAddresses.WALLET), 0.004 ether - 2);
        assertGe(PilotToken(PilotAddresses.USDG).balanceOf(PilotAddresses.WALLET), 12e6 - 2);
        _assertRevoked();
    }
    function _assertRevoked() internal view {
        for (uint256 i; i < 2; ++i) {
            address token = i == 0 ? PilotAddresses.WETH : PilotAddresses.USDG;
            assertEq(PilotToken(token).allowance(PilotAddresses.WALLET, PilotAddresses.PERMIT2), 0);
            (uint160 remaining,,) = PilotPermit2(PilotAddresses.PERMIT2).allowance(PilotAddresses.WALLET, token, PilotAddresses.POSITION);
            assertEq(remaining, 0);
        }
    }
    function testWrongChainRejected() public {
        vm.chainId(46630);
        DeployMainnetPilot deployer = new DeployMainnetPilot();
        vm.expectRevert("Robinhood mainnet only"); deployer.run();
    }
}
