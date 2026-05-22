// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Staking
 * @dev NFT质押合约，允许用户质押等级5以上的NFT来获取代币奖励
 * 奖励根据质押时间和NFT等级计算，每日有最大奖励上限
 * 基于OpenZeppelin UUPS可升级合约实现
 */
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/IERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/utils/introspection/ERC165Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title Staking
 * @dev NFT质押合约，支持质押NFT获取代币奖励
 */
contract Staking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ERC165Upgradeable, ReentrancyGuardUpgradeable {
    /** @dev 最小质押等级：必须达到5级才能质押 */
    uint8 public constant MIN_STAKING_LEVEL = 5;
    /** @dev 奖励间隔时间：每分钟计算一次奖励 */
    uint256 public constant REWARD_INTERVAL = 1 minutes;
    /** @dev 每分钟基础代币奖励数量（保底） */
    uint256 public constant BASE_TOKEN_PER_MINUTE = 10 * 10**18;
    /** @dev 每日奖励释放比例（千分之1.5 = 0.15%） */
    uint256 public dailyReleaseRatio = 15;
    uint256 public constant RELEASE_RATIO_DENOMINATOR = 10000;
    /** @dev 弹性比例上限增量（千分之0.5 = 0.05%） */
    uint256 public constant MAX_ELASTIC_INCREMENT = 5;
    /** @dev 当日转入代币量（用于弹性调控）*/
    uint256 public dailyDeposited;
    /** @dev 倍数阈值（超过此倍数触发弹性调控）*/
    uint256 public multipleThreshold = 2;
    /** @dev 上次日期重置时间戳 */
    uint256 public lastDateReset;
    
    /** @dev 最小质押锁定时间（30分钟） */
    uint256 public constant MIN_STAKING_DURATION = 30 minutes;

    /** @dev NFT合约地址 */
    address public nftContract;
    /** @dev 代币合约地址 */
    address public tokenContract;
    /** @dev 授权合约地址 */
    address public authorizer;

    /** @dev 当前质押的NFT总数量 */
    uint256 public totalStakedNFTs;
    /** @dev 上次奖励更新时间戳 */
    uint256 public lastRewardUpdate;
    /** @dev 当日已分配的奖励总量 */
    uint256 public dailyRewardDistributed;

    /**
     * @dev 质押信息结构体
     * @param tokenId NFT ID
     * @param level NFT等级
     * @param lastRewardTime 上次领取奖励时间
     * @param accumulatedRewards 累计未领取奖励
     * @param stakedAt 质押时间（用于锁定检查）
     */
    struct StakeInfo {
        uint256 tokenId;
        uint8 level;
        uint256 lastRewardTime;
        uint256 accumulatedRewards;
        uint256 stakedAt;
    }

    /** @dev 用户质押信息映射（用户地址 => 质押信息数组） */
    mapping(address => StakeInfo[]) public userStakes;
    /** @dev NFT是否已质押映射（tokenId => 是否已质押） */
    mapping(uint256 => bool) public isStaked;

    /**
     * @dev NFT质押事件
     * @param user 用户地址
     * @param tokenId NFT ID
     * @param level NFT等级
     */
    event NFTStaked(address indexed user, uint256 indexed tokenId, uint8 level);
    /**
     * @dev NFT解除质押事件
     * @param user 用户地址
     * @param tokenId NFT ID
     */
    event NFTUnstaked(address indexed user, uint256 indexed tokenId);
    /**
     * @dev 奖励领取事件
     * @param user 用户地址
     * @param amount 领取奖励数量
     */
    event RewardsClaimed(address indexed user, uint256 amount);
    /**
     * @dev 代币存入事件
     * @param amount 存入数量
     */
    event TokensDeposited(uint256 amount);

    /** @dev 存储间隙，用于合约升级兼容性 */
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化合约
     * @param _nftContract NFT合约地址
     * @param _tokenContract 代币合约地址
     * @param _authorizer 授权合约地址
     */
    function initialize(address _nftContract, address _tokenContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ERC165_init();
        __ReentrancyGuard_init();

        nftContract = _nftContract;
        tokenContract = _tokenContract;
        authorizer = _authorizer;
        lastRewardUpdate = block.timestamp;
        dailyRewardDistributed = 0;
    }

    /**
     * @dev 升级授权函数
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev 质押NFT
     * 用户将NFT质押到合约中，开始累积奖励
     * 只有等级达到5级的NFT才能质押
     * @param tokenId 要质押的NFT ID
     */
    function stakeNFT(uint256 tokenId) external nonReentrant {
        require(!isStaked[tokenId], "NFT already staked");

        IERC721Upgradeable nft = IERC721Upgradeable(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");

        uint8 level = INFTMint(nftContract).tokenLevel(tokenId);
        require(level >= MIN_STAKING_LEVEL, "NFT level too low");

        userStakes[msg.sender].push(StakeInfo({
            tokenId: tokenId,
            level: level,
            lastRewardTime: block.timestamp,
            accumulatedRewards: 0,
            stakedAt: block.timestamp
        }));

        isStaked[tokenId] = true;
        totalStakedNFTs++;

        nft.transferFrom(msg.sender, address(this), tokenId);

        emit NFTStaked(msg.sender, tokenId, level);
    }

    /**
     * @dev 解除质押
     * 用户解除NFT质押，领取累计奖励，NFT转回用户钱包
     * @param tokenId 要解除质押的NFT ID
     */
    function unstakeNFT(uint256 tokenId) external nonReentrant {
        uint256 index = _findStakeIndex(msg.sender, tokenId);
        require(index < userStakes[msg.sender].length, "Staking: NFT not staked by user");

        StakeInfo storage stake = userStakes[msg.sender][index];
        
        require(stake.stakedAt > 0, "Staking: Invalid stake timestamp");
        require(block.timestamp >= stake.stakedAt + MIN_STAKING_DURATION, 
                "Staking: Must stake for at least 30 minutes");

        _updateRewards(msg.sender, index);

        uint256 userReward = stake.accumulatedRewards;
        
        if (userReward > 0) {
            require(IERC20Upgradeable(tokenContract).balanceOf(address(this)) >= userReward, "Staking: Insufficient tokens");
            _updateDailyRewardDistributed(userReward);
        }

        _removeStake(msg.sender, index);
        isStaked[tokenId] = false;
        totalStakedNFTs--;

        IERC721Upgradeable nft = IERC721Upgradeable(nftContract);
        nft.transferFrom(address(this), msg.sender, tokenId);

        if (userReward > 0) {
            IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
            token.transfer(msg.sender, userReward);
            emit RewardsClaimed(msg.sender, userReward);
        }

        emit NFTUnstaked(msg.sender, tokenId);
    }

    /**
     * @dev 管理员提取全部代币（仅限所有者）
     * 用于提取合约中的全部代币
     */
    function withdrawTokens() external onlyOwner nonReentrant {
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        uint256 contractBalance = token.balanceOf(address(this));
        require(contractBalance > 0, "Staking: No tokens to withdraw");
        
        token.transfer(msg.sender, contractBalance);
    }

    /**
     * @dev 获取合约代币余额
     * @return 合约持有的代币数量
     */
    function getContractTokenBalance() external view returns (uint256) {
        return IERC20Upgradeable(tokenContract).balanceOf(address(this));
    }

    /**
     * @dev 存入代币（用于接收外部转入的代币）
     * @param amount 存入的代币数量
     */
    function depositToken(uint256 amount) external nonReentrant {
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(token.transferFrom(msg.sender, address(this), amount), "Staking: Token transfer failed");
        
        _updateDailyDeposited(amount);
        
        emit TokensDeposited(amount);
    }

    function _updateDailyDeposited(uint256 amount) internal {
        _resetDailyIfNeeded();
        dailyDeposited += amount;
    }

    function _updateDailyRewardDistributed(uint256 amount) internal {
        _resetDailyIfNeeded();
        dailyRewardDistributed += amount;
    }

    function _resetDailyIfNeeded() internal {
        if (block.timestamp >= lastDateReset + 1 days) {
            dailyDeposited = 0;
            dailyRewardDistributed = 0;
            lastDateReset = block.timestamp;
        }
    }

    /**
     * @dev 领取奖励
     * 用户领取所有质押NFT的累计奖励
     */
    function claimRewards() external {
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        uint256 contractBalance = token.balanceOf(address(this));
        require(contractBalance > 0, "Staking: No tokens available for rewards");

        uint256 totalRewards = 0;

        for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
            _updateRewards(msg.sender, i);
            totalRewards += userStakes[msg.sender][i].accumulatedRewards;
        }

        require(totalRewards > 0, "Staking: No rewards to claim");
        
        // 移除每日奖励限制检查，奖励累积不受天数限制
        require(totalRewards <= contractBalance, "Staking: Insufficient tokens in contract");

        for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
            userStakes[msg.sender][i].accumulatedRewards = 0;
        }

        _updateDailyRewardDistributed(totalRewards);

        token.transfer(msg.sender, totalRewards);

        emit RewardsClaimed(msg.sender, totalRewards);
    }

    /**
     * @dev 计算用户可领取的奖励
     * @param user 用户地址
     * @return 可领取的奖励总数
     */
    function calculateRewards(address user) external view returns (uint256) {
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < userStakes[user].length; i++) {
            StakeInfo memory stake = userStakes[user][i];
            totalRewards += stake.accumulatedRewards;
        }

        return totalRewards;
    }

    /**
     * @dev 获取用户质押的NFT数量
     * @param user 用户地址
     * @return 质押的NFT数量
     */
    function getUserStakeCount(address user) external view returns (uint256) {
        return userStakes[user].length;
    }

    /**
     * @dev 获取用户质押的NFT列表
     * @param user 用户地址
     * @return 质押信息数组
     */
    function getUserStakes(address user) external view returns (StakeInfo[] memory) {
        return userStakes[user];
    }

    function getUserStakesByPage(address user, uint256 offset, uint256 limit) external view returns (StakeInfo[] memory, uint256) {
        uint256 total = userStakes[user].length;
        if (offset >= total) {
            return (new StakeInfo[](0), 0);
        }
        uint256 size = offset + limit > total ? total - offset : limit;
        StakeInfo[] memory result = new StakeInfo[](size);
        for (uint i = 0; i < size; i++) {
            result[i] = userStakes[user][offset + i];
        }
        return (result, total);
    }

    /**
     * @dev 设置NFT合约地址
     * @param _nftContract NFT合约地址
     */
    function setNFTContract(address _nftContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "Staking: Unauthorized");
        nftContract = _nftContract;
    }

    /**
     * @dev 设置代币合约地址
     * @param _tokenContract 代币合约地址
     */
    function setTokenContract(address _tokenContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "Staking: Unauthorized");
        tokenContract = _tokenContract;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        authorizer = _authorizer;
    }

    

    function setDailyReleaseRatio(uint256 _ratio) external onlyOwner {
        require(_ratio > 0 && _ratio <= 1000, "Staking: Ratio must be between 1 and 1000 (0.01% to 10%)");
        dailyReleaseRatio = _ratio;
    }

    function setMultipleThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold >= 1, "Staking: Multiple threshold must be >= 1");
        multipleThreshold = _threshold;
    }

    /**
     * @dev 获取当前释放比例（外部接口）
     * @return 当前释放比例
     */
    function getCurrentReleaseRatio() external view returns (uint256) {
        return _calculateCurrentReleaseRatio();
    }

    /**
     * @dev 内部函数：计算当前释放比例（包含弹性调控）
     * @return 当前释放比例
     */
    function _calculateCurrentReleaseRatio() internal view returns (uint256) {
        if (dailyDeposited <= dailyReleaseRatio * multipleThreshold) {
            return dailyReleaseRatio;
        }
        
        // 使用 safeMath 避免溢出
        uint256 baseThreshold = dailyReleaseRatio * multipleThreshold;
        if (dailyDeposited <= baseThreshold) {
            return dailyReleaseRatio;
        }
        
        uint256 excess = dailyDeposited - baseThreshold;
        uint256 excessMultiple = excess / dailyReleaseRatio;
        uint256 additionalRatio = excessMultiple > MAX_ELASTIC_INCREMENT ? MAX_ELASTIC_INCREMENT : excessMultiple;
        
        return dailyReleaseRatio + additionalRatio;
    }

    /**
     * @dev 更新用户指定质押的奖励
     * @param user 用户地址
     * @param index 质押索引
     */
    function _updateRewards(address user, uint256 index) internal {
        StakeInfo storage stake = userStakes[user][index];
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime - stake.lastRewardTime;
        
        if (timeElapsed > 0 && totalStakedNFTs > 0) {
            uint256 dailyReward = _getAvailableDailyReward();
            uint256 rewardPerMinute = _calculateRewardPerMinute(dailyReward);
            
            uint256 intervals = timeElapsed / REWARD_INTERVAL;
            if (intervals > 0 && rewardPerMinute > 0) {
                require(intervals <= type(uint256).max / rewardPerMinute, "Staking: intervals overflow");
                uint256 rewards = intervals * rewardPerMinute;
                require(stake.accumulatedRewards <= type(uint256).max - rewards, "Staking: rewards overflow");
                stake.accumulatedRewards += rewards;
                stake.lastRewardTime = currentTime;
            }
        }
    }

    /**
     * @dev 计算当日可用奖励总量
     * 根据合约剩余代币总量的一定比例计算
     * 支持根据当日转入量弹性调控释放比例
     * @return 当日可用奖励总量
     */
    function _getAvailableDailyReward() internal view returns (uint256) {
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        uint256 contractBalance = token.balanceOf(address(this));
        
        // 复用弹性调控逻辑计算当前释放比例
        uint256 currentRatio = _calculateCurrentReleaseRatio();
        
        return (contractBalance * currentRatio) / RELEASE_RATIO_DENOMINATOR;
    }

    /**
     * @dev 计算每分钟每个NFT的奖励
     * 根据当日奖励总量和质押NFT数量计算，无保底和上限
     * @param dailyReward 当日可用奖励总量
     * @return 每分钟每个NFT的奖励数量
     */
    function _calculateRewardPerMinute(uint256 dailyReward) internal view returns (uint256) {
        if (totalStakedNFTs == 0 || dailyReward == 0) {
            return 0;
        }

        return dailyReward / (1440 * totalStakedNFTs);
    }

    /**
     * @dev 查找用户在质押列表中的索引
     * @param user 用户地址
     * @param tokenId NFT ID
     * @return 质押索引，如果未找到返回type(uint256).max
     */
    function _findStakeIndex(address user, uint256 tokenId) internal view returns (uint256) {
        for (uint256 i = 0; i < userStakes[user].length; i++) {
            if (userStakes[user][i].tokenId == tokenId) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /**
     * @dev 从用户质押列表中移除质押
     * @param user 用户地址
     * @param index 要移除的质押索引
     */
    function _removeStake(address user, uint256 index) internal {
        if (index < userStakes[user].length - 1) {
            userStakes[user][index] = userStakes[user][userStakes[user].length - 1];
        }
        userStakes[user].pop();
    }

    /**
     * @dev 获取NFT等级
     * @param tokenId NFT ID
     * @return level NFT等级
     */
    function _getNFTLevel(uint256 tokenId) internal view returns (uint8) {
        return INFTMint(nftContract).tokenLevel(tokenId);
    }

    /**
     * @dev 实现ERC165接口
     * @param interfaceId 接口ID
     * @return 是否支持该接口
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}