// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/IERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/utils/introspection/ERC165Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

// 修正：继承 可升级合约 + 初始化合约
contract Staking is Initializable, Ownable2StepUpgradeable, ERC165Upgradeable {
    // 常量定义
    uint8 public constant MIN_STAKING_LEVEL = 6;
    uint256 public constant REWARD_INTERVAL = 1 minutes;
    uint256 public constant BASE_TOKEN_PER_MINUTE = 10 * 10**18;
    uint256 public constant MAX_DAILY_REWARD = 14400 * 10**18;

    // 合约地址
    address public nftContract;
    address public tokenContract;

    // 状态变量
    uint256 public totalStakedNFTs;
    uint256 public lastRewardUpdate;
    uint256 public dailyRewardDistributed;

    // 质押信息结构
    struct StakeInfo {
        uint256 tokenId;
        uint8 level;
        uint256 lastRewardTime;
        uint256 accumulatedRewards;
    }

    // 用户质押映射
    mapping(address => StakeInfo[]) public userStakes;
    mapping(uint256 => bool) public isStaked;

    // 事件定义
    event NFTStaked(address indexed user, uint256 indexed tokenId, uint8 level);
    event NFTUnstaked(address indexed user, uint256 indexed tokenId);
    event RewardsClaimed(address indexed user, uint256 amount);
    event TokensDeposited(uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers(); // 可升级合约安全规范
    }

    // 初始化函数：添加initializable修饰符，可升级合约必须
    function initialize(address _nftContract, address _tokenContract) external initializer onlyOwner {
        // 初始化父合约
        __Ownable2Step_init();
        __ERC165_init();

        nftContract = _nftContract;
        tokenContract = _tokenContract;
        lastRewardUpdate = block.timestamp;
        dailyRewardDistributed = 0;
    }

    // 质押NFT
    function stakeNFT(uint256 tokenId) external {
        require(!isStaked[tokenId], "NFT already staked");

        IERC721Upgradeable nft = IERC721Upgradeable(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");

        (, uint8 level) = _getNFTInfo(tokenId);
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

    // 解除质押
    function unstakeNFT(uint256 tokenId) external {
        uint256 index = _findStakeIndex(msg.sender, tokenId);
        require(index < userStakes[msg.sender].length, "NFT not staked by user");

        _updateRewards(msg.sender, index);
        // StakeInfo memory stake = userStakes[msg.sender][index];

        _removeStake(msg.sender, index);
        isStaked[tokenId] = false;
        totalStakedNFTs--;

        IERC721Upgradeable nft = IERC721Upgradeable(nftContract);
        nft.transferFrom(address(this), msg.sender, tokenId);

        emit NFTUnstaked(msg.sender, tokenId);
    }

    // 领取奖励
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

    // 计算用户可领取的奖励
    function calculateRewards(address user) external view returns (uint256) {
        uint256 totalRewards = 0;
        // uint256 currentTime = block.timestamp;

        for (uint256 i = 0; i < userStakes[user].length; i++) {
            StakeInfo memory stake = userStakes[user][i];
            totalRewards += stake.accumulatedRewards;
        }

        return totalRewards;
    }

    // 获取用户质押的NFT数量
    function getUserStakeCount(address user) external view returns (uint256) {
        return userStakes[user].length;
    }

    // 获取用户质押的NFT列表
    function getUserStakes(address user) external view returns (StakeInfo[] memory) {
        return userStakes[user];
    }

    // 管理函数：设置NFT合约地址
    function setNFTContract(address _nftContract) external onlyOwner {
        nftContract = _nftContract;
    }

    // 管理函数：设置代币合约地址
    function setTokenContract(address _tokenContract) external onlyOwner {
        tokenContract = _tokenContract;
    }

    // 内部函数：更新奖励
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

    // 内部函数：计算每日奖励总量
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

        uint256 remainingDailyReward = availableReward - dailyRewardDistributed;
        if (remainingDailyReward < 0) {
            remainingDailyReward = 0;
        }

        dailyRewardDistributed += remainingDailyReward;
        return remainingDailyReward;
    }

    // 内部函数：计算每分钟每个NFT的奖励
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

    // 内部函数：查找质押索引
    function _findStakeIndex(address user, uint256 tokenId) internal view returns (uint256) {
        for (uint256 i = 0; i < userStakes[user].length; i++) {
            if (userStakes[user][i].tokenId == tokenId) {
                return i;
            }
        }
        return type(uint256).max;
    }

    // 内部函数：移除质押
    function _removeStake(address user, uint256 index) internal {
        if (index < userStakes[user].length - 1) {
            userStakes[user][index] = userStakes[user][userStakes[user].length - 1];
        }
        userStakes[user].pop();
    }

    // 内部函数：获取NFT信息
    function _getNFTInfo(uint256 tokenId) internal view returns (uint8, uint8) {
        (bool success, bytes memory data) = nftContract.staticcall(
            abi.encodeWithSignature("tokenType(uint256)", tokenId)
        );
        require(success, "Failed to get token type");
        uint8 tokenType = abi.decode(data, (uint8));

        (success, data) = nftContract.staticcall(
            abi.encodeWithSignature("tokenLevel(uint256)", tokenId)
        );
        require(success, "Failed to get token level");
        uint8 level = abi.decode(data, (uint8));

        return (tokenType, level);
    }

    // 实现ERC165接口
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}