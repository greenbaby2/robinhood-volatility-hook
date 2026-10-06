// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

// Minimal ABIs for the specific deployed periphery, validated by the fork tests.
interface PilotPositionManager {
    function poolManager() external view returns (address);
    function nextTokenId() external view returns (uint256);
    function ownerOf(uint256) external view returns (address);
    function getPositionLiquidity(uint256) external view returns (uint128);
    function getPoolAndPositionInfo(uint256) external view returns (PoolKey memory, uint256);
    function modifyLiquidities(bytes calldata, uint256 deadline) external payable;
    function multicall(bytes[] calldata) external payable returns (bytes[] memory);
    function initializePool(PoolKey calldata, uint160) external payable returns (int24);
}
interface PilotPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
    function allowance(address owner, address token, address spender) external view returns (uint160,uint48,uint48);
}
interface PilotUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}
interface PilotToken {
    function decimals() external view returns (uint8);
    function balanceOf(address) external view returns (uint256);
    function approve(address,uint256) external returns (bool);
    function allowance(address,address) external view returns (uint256);
}
interface PilotReferencePool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function slot0() external view returns (uint160,int24,uint16,uint16,uint16,uint8,bool);
}

library PilotAddresses {
    uint256 internal constant CHAIN = 4663;
    address internal constant WALLET = 0xfE6Fac6620c89f7DDa96d1B3c34300C75aBBe6b8;
    address internal constant MANAGER = address(bytes20(hex"8366a39cc670b4001a1121b8f6a443a643e40951"));
    address internal constant POSITION = address(bytes20(hex"58daec3116aae6d93017baaea7749052e8a04fa7"));
    address internal constant ROUTER = address(bytes20(hex"8876789976decbfcbbbe364623c63652db8c0904"));
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address internal constant REFERENCE = address(bytes20(hex"52e65b17fb6e5ba00ed806f37afcd2daa50271ca"));
}

library PilotActions {
    // Deployed router uses the minHopPriceX36 layout. Absolute minimumOut remains mandatory.
    struct ExactIn { PoolKey key; bool zeroForOne; uint128 amountIn; uint128 minimumOut; uint256 minHopPriceX36; bytes hookData; }
    function mint(PoolKey memory key, int24 lower, int24 upper, uint128 liquidity,
        uint128 max0, uint128 max1, address owner) internal pure returns (bytes memory) {
        require(liquidity > 0 && max0 > 0 && max1 > 0 && owner != address(0), "Empty mint");
        bytes[] memory args = new bytes[](2);
        args[0] = abi.encode(key, lower, upper, uint256(liquidity), max0, max1, owner, bytes(""));
        args[1] = abi.encode(key.currency0, key.currency1);
        return abi.encode(hex"020d", args); // fixed-liquidity mint, settle pair
    }
    function burn(PoolKey memory key, uint256 tokenId, uint128 min0, uint128 min1, address owner)
        internal pure returns (bytes memory) {
        bytes[] memory args = new bytes[](2);
        args[0] = abi.encode(tokenId, min0, min1, bytes(""));
        args[1] = abi.encode(key.currency0, key.currency1, owner);
        return abi.encode(hex"0311", args); // burn position, take pair
    }
    function swap(PoolKey memory key, bool zeroForOne, uint128 amount, uint128 minimum)
        internal pure returns (bytes[] memory input) {
        require(amount > 0 && minimum > 0, "Unbounded swap");
        bytes[] memory args = new bytes[](3);
        args[0] = abi.encode(ExactIn(key, zeroForOne, amount, minimum, 0, ""));
        args[1] = abi.encode(zeroForOne ? key.currency0 : key.currency1, uint256(amount));
        args[2] = abi.encode(zeroForOne ? key.currency1 : key.currency0, uint256(minimum));
        input = new bytes[](1);
        input[0] = abi.encode(hex"060c0f", args);
    }
}
