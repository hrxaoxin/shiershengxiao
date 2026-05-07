// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Staking
 * @dev NFT质押合约，允许用户质押等级6以上的NFT来获取代币奖励
 * 奖励根据质押时间和NFT等级计算，每日有最大奖励上限
 * 基于OpenZeppelin可升级合约实现
 */
import "./FTData.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/IERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/utils/introspection/ERC165Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

/**
 * @title Staking
 * @dev NFT质押合约，支持质押NFT获取代币奖励
 */
contract Staking is Initializable, Ownable2StepUpgradeable, ERC165Upgradeable {
    /** @dev 最小质押等级：必须达到6级才能质押 */
    uint8 public constant MIN_STAKING_LEVEL = 6;
    /** @dev 奖励间隔时间：每分钟计算一次奖励 */
    uint256 public constant REWARD_INTERVAL = 1 minutes;
    /** @dev 每分钟基础代币奖励数量 */
    uint256 public constant BASE_TOKEN_PER_MINUTE = 10 * 10**18;
    /** @dev 每日最大奖励上限 */
    uint256 public constant MAX_DAILY_REWARD = 14400 * 10**18;

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
     */
    struct StakeInfo {
        uint256 tokenId;
        uint8 level;
        uint256 lastRewardTime;
        uint256 accumulatedRewards;
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
        __ERC165_init();

        nftContract = _nftContract;
        tokenContract = _tokenContract;
        authorizer = _authorizer;
        lastRewardUpdate = block.timestamp;
        dailyRewardDistributed = 0;
    }

    /**
     * @dev 质押NFT
     * 用户将NFT质押到合约中，开始累积奖励
     * 只有等级达到6级以上的NFT才能质押
     * @param tokenId 要质押的NFT ID
     */
    function stakeNFT(uint256 tokenId) external {
        require(!isStaked[tokenId], "NFT already staked");

        IERC721Upgradeable nft = IERC721Upgradeable(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");

        uint8 level = _getNFTLevel(tokenId);
        require(level >= MIN_STAKING_LEVEL, "NFT level too low");

        nft.transferFrom(msg.sender, address(this), tokenId);

        userStakes[msg.sender].push(StakeInfo({
            tokenId: tokenId,
            level: level,
            lastRewardTime: block.timestamp,
            accumulatedRewards: 0
        }));

        isStaked[tokenId] = true;
        totalStakedNFTs++;

        emit NFTStaked(msg.sender, tokenId, level);
    }

    /**
     * @dev 解除质押
     * 用户解除NFT质押，领取累计奖励，NFT转回用户钱包
     * @param tokenId 要解除质押的NFT ID
     */
    function unstakeNFT(uint256 tokenId) external {
        uint256 index = _findStakeIndex(msg.sender, tokenId);
        require(index < userStakes[msg.sender].length, "NFT not staked by user");

        _updateRewards(msg.sender, index);

        _removeStake(msg.sender, index);
        isStaked[tokenId] = false;
        totalStakedNFTs--;

        IERC721Upgradeable nft = IERC721Upgradeable(nftContract);
        nft.transferFrom(address(this), msg.sender, tokenId);

        emit NFTUnstaked(msg.sender, tokenId);
    }

    /**
     * @dev 领取奖励
     * 用户领取所有质押NFT的累计奖励
     */
    function claimRewards() external {
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
            _updateRewards(msg.sender, i);
            totalRewards += userStakes[msg.sender][i].accumulatedRewards;
            userStakes[msg.sender][i].accumulatedRewards = 0;
        }

        require(totalRewards > 0, "No rewards to claim");

        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(token.balanceOf(address(this)) >= totalRewards, "Insufficient tokens in contract");

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

    /**
     * @dev 更新用户指定质押的奖励
     * @param user 用户地址
     * @param index 质押索引
     */
    function _updateRewards(address user, uint256 index) internal {
        StakeInfo storage stake = userStakes[user][index];
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime - stake.lastRewardTime;
        
        if (timeElapsed > 0) {
            uint256 dailyReward = _calculateDailyReward();
            uint256 rewardPerMinute = _calculateRewardPerMinute(dailyReward);
            uint256 rewards = (timeElapsed / REWARD_INTERVAL) * rewardPerMinute;
            
            stake.accumulatedRewards += rewards;
            stake.lastRewardTime = currentTime;
        }
    }

    /**
     * @dev 计算每日奖励总量
     * @return 当日剩余可分配的奖励数量
     */
    function _calculateDailyReward() internal returns (uint256) {
        uint256 dayStart = block.timestamp - (block.timestamp % 86400);
        if (lastRewardUpdate < dayStart) {
            dailyRewardDistributed = 0;
            lastRewardUpdate = block.timestamp;
        }

        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        uint256 contractBalance = token.balanceOf(address(this));

        uint256 availableReward = contractBalance / 100;
        if (availableReward > MAX_DAILY_REWARD) {
            availableReward = MAX_DAILY_REWARD;
        }

        uint256 remainingDailyReward;
        if (availableReward > dailyRewardDistributed) {
            remainingDailyReward = availableReward - dailyRewardDistributed;
        } else {
            remainingDailyReward = 0;
        }

        dailyRewardDistributed += remainingDailyReward;
        return remainingDailyReward;
    }

    /**
     * @dev 计算每分钟每个NFT的奖励
     * @param dailyReward 当日可用奖励总量
     * @return 每分钟每个NFT的奖励数量
     */
    function _calculateRewardPerMinute(uint256 dailyReward) internal view returns (uint256) {
        if (totalStakedNFTs == 0) {
            return 0;
        }

        uint256 totalMinuteReward = dailyReward / 1440;
        uint256 rewardPerMinute = totalMinuteReward / totalStakedNFTs;
        
        uint256 minReward = BASE_TOKEN_PER_MINUTE / 10;
        if (rewardPerMinute < minReward) {
            rewardPerMinute = minReward;
        }
        
        if (rewardPerMinute > BASE_TOKEN_PER_MINUTE) {
            rewardPerMinute = BASE_TOKEN_PER_MINUTE;
        }
        
        return rewardPerMinute;
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
