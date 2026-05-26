// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

/**
 * @title UpgradeModule
 * @dev NFT升级模块，提供多种升级方式
 *
 * 升级方式：
 * 1. NFT升级 - 消耗lv个同类型同等级NFT作为材料
 * 2. 代币升级 - 消耗代币支付升级费用
 * 3. USDT升级 - 按USD价值计算代币消耗
 *
 * 升级费用表（代币）：
 * - 1级 → 2级: 10000 代币
 * - 2级 → 3级: 40000 代币
 * - 3级 → 4级: 120000 代币
 * - 4级 → 5级: 480000 代币
 *
 * NFT材料消耗表：
 * - 1级 → 2级: 1个1级NFT
 * - 2级 → 3级: 2个2级NFT
 * - 3级 → 4级: 3个3级NFT
 * - 4级 → 5级: 4个4级NFT
 *
 * 升级规则：
 * - 仅同类型（同zodiacType）NFT可作为材料
 * - 材料NFT将被销毁
 * - 升级后主NFT等级+1
 * - 5级为最高等级，不可再升级
 */
contract UpgradeModule is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;

    /**
     * @dev 初始化函数
     * @param _authorizer 授权合约地址
     */
    function initialize(address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        authorizer = _authorizer;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 设置授权合约地址
     * @param a 授权合约地址
     */
    function setAuthorizer(address a) external onlyOwner {
        authorizer = a;
    }

    /**
     * @dev 检查是否为授权调用者（owner或authorizer）
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "UpgradeModule: Not authorized");
        _;
    }

    /**
     * @dev 升级费用（代币）- 1级升2级
     */
    uint256 public constant UPGRADE_COST_LEVEL_2 = 10000 * 10**18;

    /**
     * @dev 升级费用（代币）- 2级升3级
     */
    uint256 public constant UPGRADE_COST_LEVEL_3 = 40000 * 10**18;

    /**
     * @dev 升级费用（代币）- 3级升4级
     */
    uint256 public constant UPGRADE_COST_LEVEL_4 = 120000 * 10**18;

    /**
     * @dev 升级费用（代币）- 4级升5级
     */
    uint256 public constant UPGRADE_COST_LEVEL_5 = 480000 * 10**18;

    /**
     * @dev NFT材料消耗数量 - 1级升2级
     */
    uint256 public constant MATERIAL_COUNT_LEVEL_2 = 1;

    /**
     * @dev NFT材料消耗数量 - 2级升3级
     */
    uint256 public constant MATERIAL_COUNT_LEVEL_3 = 2;

    /**
     * @dev NFT材料消耗数量 - 3级升4级
     */
    uint256 public constant MATERIAL_COUNT_LEVEL_4 = 3;

    /**
     * @dev NFT材料消耗数量 - 4级升5级
     */
    uint256 public constant MATERIAL_COUNT_LEVEL_5 = 4;

    /**
     * @dev USDT代币地址（用于USDT升级）
     */
    address public usdtAddress;

    /**
     * @dev 代币价格（USD，精度18位）
     *
     * 假设代币价格 $0.1，则值为 0.1 * 10**18
     */
    uint256 public tokenPriceUSD;

    /**
     * @dev USDT价格精度
     */
    uint256 public constant USDT_PRECISION = 10**6;

    /**
     * @dev 代币精度
     */
    uint256 public constant TOKEN_PRECISION = 10**18;

    /**
     * @dev 升级事件
     *
     * @param owner  NFT所有者
     * @param tokenId 主NFT ID
     * @param materialTokenIds 材料NFT ID数组
     * @param oldLevel 旧等级
     * @param newLevel 新等级
     * @param upgradeType 升级类型（0=NFT材料, 1=代币, 2=USDT）
     */
    event Upgrade(
        address indexed owner,
        uint256 indexed tokenId,
        uint256[] materialTokenIds,
        uint8 oldLevel,
        uint8 newLevel,
        uint8 upgradeType
    );

    /**
     * @dev 获取升级费用（代币）
     *
     * @param currentLevel 当前等级（1-4）
     * @return uint256 升级费用（代币）
     *
     * 例如：
     * _getUpgradeCost(1) = 10000 * 10**18
     * _getUpgradeCost(2) = 40000 * 10**18
     * _getUpgradeCost(3) = 120000 * 10**18
     * _getUpgradeCost(4) = 480000 * 10**18
     */
    function _getUpgradeCost(uint256 currentLevel) internal pure returns (uint256) {
        require(currentLevel >= 1 && currentLevel < 5, "UpgradeModule: Invalid level");

        if (currentLevel == 1) return UPGRADE_COST_LEVEL_2;
        if (currentLevel == 2) return UPGRADE_COST_LEVEL_3;
        if (currentLevel == 3) return UPGRADE_COST_LEVEL_4;
        if (currentLevel == 4) return UPGRADE_COST_LEVEL_5;

        revert("UpgradeModule: Invalid level");
    }

    /**
     * @dev 获取升级所需材料数量
     *
     * @param currentLevel 当前等级（1-4）
     * @return uint256 所需材料数量
     *
     * 例如：
     * _getUpgradeMaterialCount(1) = 1
     * _getUpgradeMaterialCount(2) = 2
     * _getUpgradeMaterialCount(3) = 3
     * _getUpgradeMaterialCount(4) = 4
     */
    function _getUpgradeMaterialCount(uint256 currentLevel) internal pure returns (uint256) {
        require(currentLevel >= 1 && currentLevel < 5, "UpgradeModule: Invalid level");

        if (currentLevel == 1) return MATERIAL_COUNT_LEVEL_2;
        if (currentLevel == 2) return MATERIAL_COUNT_LEVEL_3;
        if (currentLevel == 3) return MATERIAL_COUNT_LEVEL_4;
        if (currentLevel == 4) return MATERIAL_COUNT_LEVEL_5;

        revert("UpgradeModule: Invalid level");
    }

    /**
     * @dev 计算USDT升级费用
     *
     * 根据当前等级和代币价格计算所需USDT数量
     *
     * @param currentLevel 当前等级
     * @return uint256 USDT数量（精度6位）
     *
     * 计算公式：
     * usdtAmount = (upgradeCost / TOKEN_PRECISION) / tokenPriceUSD * USDT_PRECISION
     *
     * 例如：
     * 如果代币价格 $0.1，升级费用 10000 代币
     * 则 USDT 费用 = 10000 / 0.1 = 100000 USDT
     */
    function _calculateUSDTUpgradeCost(uint256 currentLevel) internal view returns (uint256) {
        uint256 upgradeCost = _getUpgradeCost(currentLevel);
        if (tokenPriceUSD == 0) return 0;
        return upgradeCost * USDT_PRECISION / (tokenPriceUSD * TOKEN_PRECISION / USDT_PRECISION);
    }

    /**
     * @dev 验证材料NFT
     *
     * 检查材料NFT是否满足条件：
     * 1. 与主NFT同类型
     * 2. 等级与主NFT当前等级相同
     * 3. 数量正确
     *
     * @param mainTokenId 主NFT ID
     * @param materialTokenIds 材料NFT ID数组
     * @param mainLevel 主NFT当前等级
     * @param mainZodiacType 主NFT类型
     */
    function _validateMaterials(
        uint256 mainTokenId,
        uint256[] memory materialTokenIds,
        uint256 mainLevel,
        uint256 mainZodiacType
    ) internal pure {
        uint256 requiredCount = _getUpgradeMaterialCount(mainLevel);
        require(materialTokenIds.length == requiredCount, "UpgradeModule: Invalid material count");

        for (uint256 i = 0; i < materialTokenIds.length; i++) {
            require(materialTokenIds[i] != mainTokenId, "UpgradeModule: Cannot use self as material");
        }
    }

    /**
     * @dev 获取升级费用（公开接口）
     *
     * @param currentLevel 当前等级
     * @param useUSDT 是否使用USDT支付
     * @return uint256 升级费用
     */
    function getUpgradeCost(uint256 currentLevel, bool useUSDT) external view returns (uint256) {
        if (useUSDT) {
            return _calculateUSDTUpgradeCost(currentLevel);
        }
        return _getUpgradeCost(currentLevel);
    }

    /**
     * @dev 获取升级所需材料数量（公开接口）
     *
     * @param currentLevel 当前等级
     * @return uint256 所需材料数量
     */
    function getUpgradeMaterialCount(uint256 currentLevel) external pure returns (uint256) {
        return _getUpgradeMaterialCount(currentLevel);
    }

    /**
     * @dev 设置USDT地址
     *
     * @param _usdtAddress USDT代币合约地址
     */
    function setUSDTAddress(address _usdtAddress) external onlyAuthorized {
        require(_usdtAddress != address(0), "UpgradeModule: Invalid USDT address");
        usdtAddress = _usdtAddress;
    }

    /**
     * @dev 设置代币价格
     *
     * @param _tokenPriceUSD 代币价格（USD，精度18位）
     */
    function setTokenPrice(uint256 _tokenPriceUSD) external onlyOwner {
        require(_tokenPriceUSD > 0, "UpgradeModule: Invalid token price");
        tokenPriceUSD = _tokenPriceUSD;
    }

    /**
     * @dev 获取所有升级费用
     *
     * @return uint256[4] 各级升级费用数组
     */
    function getAllUpgradeCosts() external pure returns (uint256[4] memory) {
        return [
            UPGRADE_COST_LEVEL_2,
            UPGRADE_COST_LEVEL_3,
            UPGRADE_COST_LEVEL_4,
            UPGRADE_COST_LEVEL_5
        ];
    }

    /**
     * @dev 获取所有材料消耗数量
     *
     * @return uint256[4] 各级材料消耗数组
     */
    function getAllMaterialCounts() external pure returns (uint256[4] memory) {
        return [
            MATERIAL_COUNT_LEVEL_2,
            MATERIAL_COUNT_LEVEL_3,
            MATERIAL_COUNT_LEVEL_4,
            MATERIAL_COUNT_LEVEL_5
        ];
    }

    /**
     * @dev 获取代币精度
     *
     * @return uint256 代币精度
     */
    function getTokenPrecision() external pure returns (uint256) {
        return TOKEN_PRECISION;
    }

    /**
     * @dev 获取USDT精度
     *
     * @return uint256 USDT精度
     */
    function getUSDTPrecision() external pure returns (uint256) {
        return USDT_PRECISION;
    }
}
