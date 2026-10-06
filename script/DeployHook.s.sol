// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {VolatilityRoyaltyHook} from "../src/VolatilityRoyaltyHook.sol";
import {HookFactory} from "../src/HookFactory.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
interface DeployVm {
    function envAddress(string calldata) external returns (address);
    function envUint(string calldata) external returns (uint256);
    function startBroadcast() external;
    function stopBroadcast() external;
}
contract DeployHook {
    DeployVm constant vm = DeployVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    function run() external returns (VolatilityRoyaltyHook hook) {
        require(block.chainid == vm.envUint("EXPECTED_CHAIN_ID"), "Wrong chain");
        address factory = vm.envAddress("HOOK_FACTORY");
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address author = vm.envAddress("ROYALTY_RECIPIENT");
        uint256 bps = vm.envUint("ROYALTY_BPS");
        require(factory.code.length > 0 && bps <= 25, "Bad config");
        bytes32 initHash = keccak256(abi.encodePacked(type(VolatilityRoyaltyHook).creationCode,
            abi.encode(manager, author, uint16(bps))));
        bytes32 salt;
        address predicted;
        bool found;
        for (uint256 i; i < 1000000; ++i) {
            salt = bytes32(i);
            predicted = address(uint160(uint256(keccak256(abi.encodePacked(
                bytes1(0xff), factory, salt, initHash)))));
            if ((uint160(predicted) & 0x3fff) == 0x10c4 && predicted.code.length == 0) {
                found = true; break;
            }
        }
        require(found, "No salt found");
        vm.startBroadcast();
        hook = HookFactory(factory).deploy(salt, manager, author, uint16(bps));
        vm.stopBroadcast();
        require(address(hook) == predicted, "Address mismatch");
    }
}
