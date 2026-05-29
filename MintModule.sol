// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

/**
 * @title MintModule
 * @dev 【已废弃】NFT铸造模块。实际铸造入口为 TokenBurner → NFTMint 流程，本合约不再使用。
 *
 * 保留原因：参考实现（概率计算、类型枚举），便于后续升级参考。
 * 前端铸造流程：mint.html → TokenBurner.burnAndMint() → NFTMint.mintNormal()
 *
 * @deprecated 请使用 TokenBurner + NFTMint 合约进行铸造操作。
 *
 * 原始设计：
 * 铸造方式：
 * 1. 普通铸造 - 消耗8888代币，随机属性
 * 2. 稀有铸造 - 消耗88888代币，仅光/暗属性
 * 3. 普通十连 - 消耗88880代币，10张普通
 * 4. 稀有十连 - 消耗888880代币，10张稀有
 * 5. 指定生肖 - 消耗88880代币，指定一个生肖的所有变体（10张）
 *
 * 属性概率分布：
 * - 普通铸造：水32%、火32%、风32%、暗2%、光2%
 * - 稀有铸造：暗50%、光50%
 */
contract MintModule is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 普通铸造费用（代币）
     *
     * 用户支付8888代币进行普通铸造
     * 费用分配：
     * - 50% 销毁
     * - 50% 进入奖励池
     */
    uint256 public constant MINT_COST = 8888 * 10**18;

    /**
     * @dev 稀有铸造费用（代币）
     *
     * 用户支付88888代币进行稀有铸造
     * 仅能铸造光/暗属性NFT
     */
    uint256 public constant RARE_MINT_COST = 88888 * 10**18;

    /**
     * @dev 普通十连铸造费用
     * 10 × 8888 = 88880
     */
    uint256 public constant BATCH_MINT_COST = 88880 * 10**18;

    /**
     * @dev 稀有十连铸造费用
     * 10 × 88888 = 888880
     */
    uint256 public constant RARE_BATCH_MINT_COST = 888880 * 10**18;

    /**
     * @dev 指定生肖铸造费用
     * 铸造指定生肖的10种变体（6公+6母-2重复=10）
     */
    uint256 public constant ZODIAC_MINT_COST = 88880 * 10**18;

    /**
     * @dev 普通铸造属性概率分布（水/风/火/暗/光）
     *
     * 概率（百分比）：
     * - WATER (水): 32%
     * - WIND (风): 32%
     * - FIRE (火): 32%
     * - DARK (暗): 2%
     * - LIGHT (光): 2%
     *
     * 用于_chooseElement函数中的随机选择
     */
    uint256[5] public elementProbabilities = [32, 32, 32, 2, 2];

    /**
     * @dev 稀有铸造属性概率分布（仅暗/光）
     *
     * 概率（百分比）：
     * - DARK (暗): 50%
     * - LIGHT (光): 50%
     */
    uint256[2] public rareElementProbabilities = [50, 50];

    /**
     * @dev 稀有属性起始索引
     *
     * 在ZodiacType枚举中，暗属性从72开始，光属性从96开始
     * 用于稀有铸造时的属性范围计算
     */
    uint256 public constant RARE_ELEMENT_START = 72;

    /**
     * @dev 属性对应的类型范围大小
     *
     * 每种属性包含：12生肖 × 2性别 = 24种类型
     */
    uint256 public constant ELEMENT_TYPE_COUNT = 24;

    /**
     * @dev 普通铸造的属性范围
     *
     * 普通属性：水(0-23)、风(24-47)、火(48-71)
     */
    uint256 public constant COMMON_ELEMENT_MAX = 72;

    /**
     * @dev 铸造计数器（用于增加随机性）
     *
     * 每次铸造后递增，确保相同参数产生不同结果
     */
    uint256 public mintCounter;

    /**
     * @dev 最后一次铸造的区块号（用于随机数生成）
     */
    uint256 public lastMintBlock;

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
        mintCounter = 0;
        lastMintBlock = 0;
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
        require(msg.sender == owner() || msg.sender == authorizer, "MintModule: Not authorized");
        _;
    }

    /**
     * @dev 普通铸造事件
     *
     * @param minter 铸造者地址
     * @param tokenId 铸造的NFT ID
     * @param zodiacType 生肖类型
     */
    event Mint(address indexed minter, uint256 indexed tokenId, uint256 zodiacType);

    /**
     * @dev 稀有铸造事件
     *
     * @param minter 铸造者地址
     * @param tokenId 铸造的NFT ID
     * @param zodiacType 生肖类型
     */
    event RareMint(address indexed minter, uint256 indexed tokenId, uint256 zodiacType);

    /**
     * @dev 十连铸造事件
     *
     * @param minter 铸造者地址
     * @param tokenIds 铸造的NFT ID数组
     */
    event BatchMint(address indexed minter, uint256[] tokenIds);

    /**
     * @dev 铸造随机数种子
     *
     * 使用blockhash和多个变量生成，提高随机性
     * 但注意：此方法仍存在被验证者操控的风险
     *
     * @return uint256 随机数种子
     */
    function _generateSecureRandom() internal returns (uint256) {
        lastMintBlock = block.number;
        mintCounter++;

        bytes32 entropy = keccak256(
            abi.encodePacked(
                blockhash(block.number > 1 ? block.number - 1 : block.number),
                msg.sender,
                block.timestamp,
                mintCounter,
                gasleft(),
                tx.origin,
                block.coinbase,
                block.prevrandao
            )
        );
        return uint256(entropy);
    }

    /**
     * @dev 选择属性类型（普通铸造）
     *
     * 根据概率分布随机选择属性
     * 使用_generateSecureRandom生成的随机数进行选择
     *
     * @param randomVal 随机数值
     * @return uint256 属性索引（0-4）
     *
     * 概率计算：
     * - 0-31: 水 (WATER)
     * - 32-63: 风 (WIND)
     * - 64-95: 火 (FIRE)
     * - 96-97: 暗 (DARK)
     * - 98-99: 光 (LIGHT)
     */
    function _chooseElement(uint256 randomVal) internal view returns (uint256) {
        uint256[5] memory cumulativeProbabilities;
        cumulativeProbabilities[0] = elementProbabilities[0];
        for (uint256 i = 1; i < 5; i++) {
            cumulativeProbabilities[i] = cumulativeProbabilities[i-1] + elementProbabilities[i];
        }

        uint256 roll = randomVal % 100;
        for (uint256 i = 0; i < 5; i++) {
            if (roll < cumulativeProbabilities[i]) {
                return i;
            }
        }
        return 0;
    }

    /**
     * @dev 选择属性类型（稀有铸造）
     *
     * 仅在暗/光两种属性中选择
     *
     * @param randomVal 随机数值
     * @return uint256 属性索引（3=暗, 4=光）
     *
     * 概率计算：
     * - 0-49: 暗 (DARK)
     * - 50-99: 光 (LIGHT)
     */
    function _chooseRareElement(uint256 randomVal) internal view returns (uint256) {
        uint256 roll = randomVal % 100;
        if (roll < rareElementProbabilities[0]) {
            return 3; // DARK
        }
        return 4; // LIGHT
    }

    /**
     * @dev 计算生肖类型的完整索引
     *
     * 根据属性、生肖和性别计算ZodiacType枚举值
     *
     * @param element 属性索引（0-4）
     * @param zodiac 生肖索引（0-11）
     * @param gender 性别（0=母, 1=公）
     * @return uint256 ZodiacType索引（0-119）
     *
     * 计算公式：
     * ZodiacType = element × 24 + zodiac × 2 + gender
     *
     * 使用示例：
     * - (0, 0, 1) = 0 × 24 + 0 × 2 + 1 = 1 (水鼠_1)
     * - (4, 4, 0) = 4 × 24 + 4 × 2 + 0 = 96 + 8 = 104 (光龙_0)
     */
    function _calculateZodiacType(uint256 element, uint256 zodiac, uint256 gender) internal pure returns (uint256) {
        return element * 24 + zodiac * 2 + gender;
    }

    /**
     * @dev 普通铸造 - 铸造一张随机属性NFT
     *
     * @param randomSeed 随机数种子
     * @return uint256 生肖类型（0-119）
     *
     * 铸造流程：
     * 1. 随机选择属性（水/风/火/暗/光）
     * 2. 随机选择生肖（0-11）
     * 3. 随机选择性别（0=母, 1=公）
     * 4. 计算完整ZodiacType
     */
    function _mintNormal(uint256 randomSeed) internal view returns (uint256) {
        uint256 element = _chooseElement(randomSeed % 100);
        uint256 zodiac = (randomSeed / 100) % 12;
        uint256 gender = (randomSeed / 100 / 12) % 2;
        return _calculateZodiacType(element, zodiac, gender);
    }

    /**
     * @dev 稀有铸造 - 铸造一张稀有属性NFT
     *
     * @param randomSeed 随机数种子
     * @return uint256 生肖类型（72-119）
     *
     * 铸造流程：
     * 1. 随机选择稀有属性（暗/光）
     * 2. 随机选择生肖（0-11）
     * 3. 随机选择性别（0=母, 1=公）
     * 4. 计算完整ZodiacType
     */
    function _mintRare(uint256 randomSeed) internal view returns (uint256) {
        uint256 element = _chooseRareElement(randomSeed % 100);
        uint256 zodiac = (randomSeed / 100) % 12;
        uint256 gender = (randomSeed / 100 / 12) % 2;
        return _calculateZodiacType(element, zodiac, gender);
    }

    /**
     * @dev 十连铸造 - 铸造10张NFT
     *
     * @param isRare 是否为稀有十连
     * @param baseSeed 基础随机数种子
     * @return uint256[] 10个生肖类型数组
     *
     * 注意：每一张都使用不同的随机数种子
     */
    function _mintBatch(bool isRare, uint256 baseSeed) internal view returns (uint256[] memory) {
        uint256[] memory types = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            uint256 seed = baseSeed + i * 7919;
            if (isRare) {
                types[i] = _mintRare(seed);
            } else {
                types[i] = _mintNormal(seed);
            }
        }
        return types;
    }

    /**
     * @dev 指定生肖铸造 - 铸造一个生肖的所有变体
     *
     * @param zodiac 生肖索引（0-11）
     * @return uint256[] 10个生肖类型数组
     *
     * 铸造内容：
     * - 公母各6种属性 = 12张
     * - 但同一属性的公母算作同一"类型"的基础
     * - 实际返回10张：水/风/火/暗/光 各公母 = 10张
     *
     * 使用示例：
     * - zodiac = 0 (鼠) 返回：水鼠_1, 水鼠_0, 风鼠_1, 风鼠_0, 火鼠_1, 火鼠_0, 暗鼠_1, 暗鼠_0, 光鼠_1, 光鼠_0
     */
    function _mintZodiac(uint256 zodiac) internal pure returns (uint256[] memory) {
        require(zodiac < 12, "MintModule: Invalid zodiac");
        uint256[] memory types = new uint256[](10);
        uint256 index = 0;
        for (uint256 element = 0; element < 5; element++) {
            for (uint256 gender = 0; gender < 2; gender++) {
                if (index < 10) {
                    types[index] = _calculateZodiacType(element, zodiac, gender);
                    index++;
                }
            }
        }
        return types;
    }

    /**
     * @dev 获取铸造费用
     *
     * @param mintType 铸造类型（0=普通, 1=稀有, 2=十连普通, 3=十连稀有, 4=指定生肖）
     * @param zodiac 生肖索引（仅指定生肖铸造时使用）
     * @return uint256 铸造费用（代币）
     */
    function getMintCost(uint256 mintType, uint256 zodiac) external view returns (uint256) {
        if (mintType == 0) return MINT_COST;
        if (mintType == 1) return RARE_MINT_COST;
        if (mintType == 2) return BATCH_MINT_COST;
        if (mintType == 3) return RARE_BATCH_MINT_COST;
        if (mintType == 4) return ZODIAC_MINT_COST;
        revert("MintModule: Invalid mint type");
    }

    /**
     * @dev 获取当前属性概率分布
     *
     * @return uint256[] 概率数组
     */
    function getElementProbabilities() external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            result[i] = elementProbabilities[i];
        }
        return result;
    }

    /**
     * @dev 获取稀有属性概率分布
     *
     * @return uint256[] 概率数组
     */
    function getRareElementProbabilities() external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            result[i] = rareElementProbabilities[i];
        }
        return result;
    }

    /**
     * @dev 获取铸造计数器
     *
     * @return uint256 当前计数器值
     */
    function getMintCounter() external view returns (uint256) {
        return mintCounter;
    }

    // ============ 外部铸造入口（供 Burner/前端调用） ============

    /**
     * @dev 普通铸造 - 外部入口
     * @return uint256 zodiacType
     */
    function mintNormal() external returns (uint256) {
        uint256 seed = _generateSecureRandom();
        return _mintNormal(seed);
    }

    /**
     * @dev 稀有铸造 - 外部入口
     * @return uint256 zodiacType
     */
    function mintRare() external returns (uint256) {
        uint256 seed = _generateSecureRandom();
        return _mintRare(seed);
    }

    /**
     * @dev 十连普通铸造 - 外部入口
     * @return uint256[] zodiacTypes
     */
    function mintNormalTen() external returns (uint256[] memory) {
        uint256 seed = _generateSecureRandom();
        return _mintBatch(false, seed);
    }

    /**
     * @dev 十连稀有铸造 - 外部入口
     * @return uint256[] zodiacTypes
     */
    function mintRareTen() external returns (uint256[] memory) {
        uint256 seed = _generateSecureRandom();
        return _mintBatch(true, seed);
    }

    /**
     * @dev 指定生肖铸造 - 外部入口
     * @param zodiac 生肖索引 (0-11)
     * @return uint256[] zodiacTypes
     */
    function mintTargeted(uint256 zodiac) external returns (uint256[] memory) {
        return _mintZodiac(zodiac);
    }
}
