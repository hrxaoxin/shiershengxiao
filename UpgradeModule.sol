// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title UpgradeModule
 * @dev 升级模块合约，负责升级费用计算和燃烧候选查找
 * 仅由NFTMint主合约调用，返回计算结果，不直接操作链上状态
 */
import "./NFTDataType.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/access/Ownable.sol";

contract UpgradeModule is Ownable {
    /** @dev NFTMint主合约地址（唯一调用方） */
    address public nftMint;
    /** @dev 元数据合约地址 */
    address public metadataContract;
    /** @dev 授权合约地址 */
    address public authorizer;

    /** @dev 升级费用（1->2, 2->3, 3->4, 4->5） */
    uint256 public level1UpgradeCost = 10000;
    uint256 public level2UpgradeCost = 40000;
    uint256 public level3UpgradeCost = 120000;
    uint256 public level4UpgradeCost = 480000;

    // ====================== Modifiers ======================

    modifier onlyNFTMint() {
        require(msg.sender == nftMint, "UpgradeModule: only NFTMint");
        _;
    }

    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "E10");
        _;
    }

    // ====================== Constructor ======================

    constructor() Ownable() {}

    // ====================== Public API (called by NFTMint) ======================

    /**
     * @dev 查找同类型同等级的燃烧候选NFT（排除自身）
     * @param user 用户地址
     * @param tokenId 要升级的NFT ID
     * @return burnCandidates 燃烧候选NFT ID数组（长度 = token等级）
     */
    function findBurnCandidates(address user, uint256 tokenId) external view onlyNFTMint returns (uint256[] memory) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ZodiacType t = m.tokenType(tokenId);
        uint8 lv = m.tokenLevel(tokenId);
        uint req = lv;

        uint256[] memory arr = m.userTokens(user, t);
        uint256[] memory burnCandidates = new uint256[](req);
        uint256 candidateIdx = 0;

        for (uint i = 0; i < arr.length && candidateIdx < req; i++) {
            uint256 currentId = arr[i];
            if (currentId != tokenId && m.tokenLevel(currentId) == lv) {
                burnCandidates[candidateIdx++] = currentId;
            }
        }
        require(candidateIdx == req, "E17"); // 数量不足则回退

        return burnCandidates;
    }

    /**
     * @dev 检查是否有足够的同等级NFT用于升级
     * @param user 用户地址
     * @param tokenId 要升级的NFT ID
     * @return sufficient 是否足够
     */
    function hasEnoughBurns(address user, uint256 tokenId) external view onlyNFTMint returns (bool) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ZodiacType t = m.tokenType(tokenId);
        uint8 lv = m.tokenLevel(tokenId);

        uint256[] memory arr = m.userTokens(user, t);
        uint256 count = 0;
        for (uint i = 0; i < arr.length; i++) {
            if (m.tokenLevel(arr[i]) == lv) {
                count++;
            }
        }
        return count >= lv + 1;
    }

    /**
     * @dev 获取指定等级的代币升级费用
     * @param lv 当前等级（1-4）
     * @return cost 升级费用
     */
    function getTokenUpgradeCost(uint8 lv) external view onlyNFTMint returns (uint256) {
        if (lv == 1) return level1UpgradeCost;
        if (lv == 2) return level2UpgradeCost;
        if (lv == 3) return level3UpgradeCost;
        if (lv == 4) return level4UpgradeCost;
        revert("E18");
    }

    /**
     * @dev 获取指定等级的USD升级价值
     * @param lv 当前等级（1-4）
     * @return usdValue USD价值（精度18位）
     */
    function getUSDUpgradeValue(uint8 lv) external view onlyNFTMint returns (uint256) {
        if (lv == 1) return 1e18;       // 1 USD
        if (lv == 2) return 4e18;      // 4 USD
        if (lv == 3) return 12e18;     // 12 USD
        if (lv == 4) return 48e18;     // 48 USD
        revert("E18");
    }

    /**
     * @dev 升级后等级（外部函数，用于验证升级逻辑一致性）
     * @return newLevel 升级后等级
     */
    function getUpgradedLevel(uint8 currentLevel) external view onlyNFTMint returns (uint8) {
        require(currentLevel < 5, "E16");
        return currentLevel + 1;
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
     * @dev 设置元数据合约地址
     */
    function setMetadataContract(address a) external onlyOwnerOrAuthorizer {
        metadataContract = a;
    }

    /**
     * @dev 设置授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    /**
     * @dev 设置1级升级到2级的费用
     */
    function setLevel1UpgradeCost(uint256 cost) external onlyOwnerOrAuthorizer {
        require(cost > 0, "UpgradeModule: cost must be > 0");
        level1UpgradeCost = cost;
    }

    /**
     * @dev 设置2级升级到3级的费用
     */
    function setLevel2UpgradeCost(uint256 cost) external onlyOwnerOrAuthorizer {
        require(cost > 0, "UpgradeModule: cost must be > 0");
        level2UpgradeCost = cost;
    }

    /**
     * @dev 设置3级升级到4级的费用
     */
    function setLevel3UpgradeCost(uint256 cost) external onlyOwnerOrAuthorizer {
        require(cost > 0, "UpgradeModule: cost must be > 0");
        level3UpgradeCost = cost;
    }

    /**
     * @dev 设置4级升级到5级的费用
     */
    function setLevel4UpgradeCost(uint256 cost) external onlyOwnerOrAuthorizer {
        require(cost > 0, "UpgradeModule: cost must be > 0");
        level4UpgradeCost = cost;
    }
}
