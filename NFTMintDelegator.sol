// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTMintDelegator
 * @dev NFT主合约的公共逻辑库，通过DELEGATECALL调用
 *
 * 本合约使用代理模式，将存储和逻辑分离：
 * - NFTMintDelegator: 存储所有状态变量
 * - NFTMint: 包含所有业务逻辑，通过DELEGATECALL执行
 *
 * 这种设计允许：
 * 1. 逻辑合约可升级
 * 2. 存储合约地址固定，数据不丢失
 * 3. 降低升级成本（只部署逻辑合约）
 *
 * 升级流程：
 * 1. 部署新的逻辑合约
 * 2. 调用NFTMint的upgradeTo方法
 * 3. 新逻辑合约通过DELEGATECALL操作存储
 */
contract NFTMintDelegator {
    /**
     * @dev 代币地址
     */
    address public tokenAddress;

    /**
     * @dev USDT地址
     */
    address public usdtAddress;

    /**
     * @dev 铸造模块地址
     */
    address public mintModuleAddress;

    /**
     * @dev 升级模块地址
     */
    address public upgradeModuleAddress;

    /**
     * @dev 价格预言机地址
     */
    address public priceOracleAddress;

    /**
     * @dev 战斗合约地址
     */
    address public battleAddress;

    /**
     * @dev 繁殖合约地址
     */
    address public breedingAddress;

    /**
     * @dev 质押合约地址
     */
    address public stakingAddress;

    /**
     * @dev 代币质押合约地址
     */
    address public tokenStakingAddress;

    /**
     * @dev 奖励管理器地址
     */
    address public rewardManagerAddress;

    /**
     * @dev 分红管理器地址
     */
    address public dividendManagerAddress;

    /**
     * @dev 资金池管理器地址
     */
    address public poolManagerAddress;

    /**
     * @dev NFT交易合约地址
     */
    address public tradingAddress;

    /**
     * @dev 竞技场排名地址
     */
    address public arenaRankingAddress;

    /**
     * @dev 权限管理器地址
     */
    address public authorizerAddress;

    /**
     * @dev 铸币者地址
     */
    address public minterAddress;

    /**
     * @dev 管理员地址
     */
    address public admin;

    /**
     * @dev 合约暂停标志
     */
    bool public paused;

    /**
     * @dev 代币销毁地址
     */
    address public tokenBurnAddress;

    /**
     * @dev 铸币费用接收地址
     */
    address public feeReceiver;

    /**
     * @dev NFT总数
     */
    uint256 public totalSupply;

    /**
     * @dev NFT ID计数器
     */
    uint256 public tokenIdCounter;

    /**
     * @dev 每种类型的NFT数量
     * zodiacType => count
     */
    mapping(uint256 => uint256) public zodiacTypeCount;

    /**
     * @dev 每个用户的NFT数量
     * user => count
     */
    mapping(address => uint256) public balanceOf;

    /**
     * @dev NFT ID到所有者的映射
     * tokenId => owner
     */
    mapping(uint256 => address) public owners;

    /**
     * @dev 操作批准映射
     * tokenId => operator => approved
     */
    mapping(uint256 => mapping(address => bool)) public operatorApprovals;

    /**
     * @dev 暂停原因
     */
    string public pauseReason;

    /**
     * @dev 实现版本
     */
    string public implementationVersion;

    /**
     * @dev 合约名称
     */
    string public name;

    /**
     * @dev 合约符号
     */
    string public symbol;

    /**
     * @dev 构造函数
     */
    constructor() {
        admin = msg.sender;
        tokenIdCounter = 0;
        totalSupply = 0;
        paused = false;
        name = "Zodiac NFT";
        symbol = "ZNFT";
        implementationVersion = "1.0.0";
    }

    /**
     * @dev 设置实现版本
     */
    function setImplementationVersion(string memory version) external {
        require(msg.sender == admin, "Not admin");
        implementationVersion = version;
    }

    /**
     * @dev 设置合约名称
     */
    function setName(string memory _name) external {
        require(msg.sender == admin, "Not admin");
        name = _name;
    }

    /**
     * @dev 设置合约符号
     */
    function setSymbol(string memory _symbol) external {
        require(msg.sender == admin, "Not admin");
        symbol = _symbol;
    }
}
