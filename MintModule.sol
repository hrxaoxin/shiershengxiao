// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MintModule
 * @dev 铸造模块合约，负责随机类型生成和成长值计算
 * 仅由NFTMint主合约调用，返回计算结果，不直接操作链上状态
 */
import "./NFTDataType.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/utils/Counters.sol";

contract MintModule is Ownable {
    using Counters for Counters.Counter;

    /** @dev 用于生成随机数的计数器 */
    Counters.Counter private _nonce;
    /** @dev NFTMint主合约地址（唯一调用方） */
    address public nftMint;
    /** @dev 授权合约地址 */
    address public authorizer;

    // ====================== Modifiers ======================

    modifier onlyNFTMint() {
        require(msg.sender == nftMint, "MintModule: only NFTMint");
        _;
    }

    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        _;
    }

    // ====================== Constructor ======================

    constructor() Ownable() {
        _nonce.increment();
    }

    // ====================== Random Type ======================

    /**
     * @dev 安全随机数生成器
     * 使用链上数据源生成不可预测的随机数
     */
    function _generateSecureRandom() internal returns (uint256) {
        _nonce.increment();
        bytes32 entropy = keccak256(
            abi.encodePacked(
                blockhash(block.number > 1 ? block.number - 1 : block.number),
                msg.sender,
                block.timestamp,
                _nonce.current(),
                gasleft(),
                tx.origin,
                block.coinbase,
                block.prevrandao
            )
        );
        return uint256(entropy);
    }

    /**
     * @dev 普通铸造随机类型生成：五种属性随机
     * 概率分布：水(32%)、火(32%)、风(32%)、光(2%)、暗(2%)
     */
    function _getRandomNormalType() internal returns (NFTDataTypes.ZodiacType) {
        uint rand = _generateSecureRandom();
        uint r = rand % 100;
        if (r < 2) return NFTDataTypes.ZodiacType(72 + (rand % 24));      // 暗属性(2%)
        else if (r < 4) return NFTDataTypes.ZodiacType(96 + (rand % 24));  // 光属性(2%)
        else if (r < 36) return NFTDataTypes.ZodiacType(rand % 24);        // 水属性(32%)
        else if (r < 68) return NFTDataTypes.ZodiacType(24 + (rand % 24)); // 风属性(32%)
        else return NFTDataTypes.ZodiacType(48 + (rand % 24));              // 火属性(32%)
    }

    /**
     * @dev 稀有铸造随机类型生成：仅光/暗属性随机
     * 概率分布：光(50%)、暗(50%)
     */
    function _getRandomRareType() internal returns (NFTDataTypes.ZodiacType) {
        uint rand = _generateSecureRandom();
        if (rand % 2 == 0) {
            return NFTDataTypes.ZodiacType(96 + (rand % 24));  // 光属性(50%)
        } else {
            return NFTDataTypes.ZodiacType(72 + (rand % 24));  // 暗属性(50%)
        }
    }

    /**
     * @dev 生成随机成长值（10-100）
     */
    function _generateGrowthValue() internal returns (uint256) {
        uint256 rand = _generateSecureRandom();
        return 10 + (rand % 91);
    }

    // ====================== Public API (called by NFTMint) ======================

    /**
     * @dev 生成普通铸造的随机类型和成长值
     * @return t 随机生肖类型
     * @return growth 随机成长值
     */
    function generateNormalType() external onlyNFTMint returns (NFTDataTypes.ZodiacType t, uint256 growth) {
        t = _getRandomNormalType();
        growth = _generateGrowthValue();
    }

    /**
     * @dev 生成稀有铸造的随机类型和成长值
     * @return t 随机生肖类型
     * @return growth 随机成长值
     */
    function generateRareType() external onlyNFTMint returns (NFTDataTypes.ZodiacType t, uint256 growth) {
        t = _getRandomRareType();
        growth = _generateGrowthValue();
    }

    /**
     * @dev 生成10连普通铸造的类型和成长值数组
     * @return types 类型数组
     * @return growthValues 成长值数组
     */
    function generateTenNormalTypes() external onlyNFTMint returns (NFTDataTypes.ZodiacType[] memory types, uint256[] memory growthValues) {
        types = new NFTDataTypes.ZodiacType[](10);
        growthValues = new uint256[](10);
        for (uint i = 0; i < 10; i++) {
            types[i] = _getRandomNormalType();
            growthValues[i] = _generateGrowthValue();
        }
    }

    /**
     * @dev 生成10连稀有铸造的类型和成长值数组
     * @return types 类型数组
     * @return growthValues 成长值数组
     */
    function generateTenRareTypes() external onlyNFTMint returns (NFTDataTypes.ZodiacType[] memory types, uint256[] memory growthValues) {
        types = new NFTDataTypes.ZodiacType[](10);
        growthValues = new uint256[](10);
        for (uint i = 0; i < 10; i++) {
            types[i] = _getRandomRareType();
            growthValues[i] = _generateGrowthValue();
        }
    }

    /**
     * @dev 生成单个成长值（用于指定铸造、繁殖铸造）
     * @return growth 随机成长值
     */
    function generateGrowth() external onlyNFTMint returns (uint256 growth) {
        growth = _generateGrowthValue();
    }

    // ====================== Config Setters ======================

    /**
     * @dev 设置NFTMint主合约地址
     */
    function setNFTMint(address a) external onlyOwner {
        require(a != address(0), "Zero address");
        nftMint = a;
    }

    /**
     * @dev 设置授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }
}
