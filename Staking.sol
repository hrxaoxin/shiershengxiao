// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract Staking is Ownable, ERC165 {
    // 常量定义
    uint8 public constant MIN_STAKING_LEVEL = 6; // 最低质押等级
    uint256 public constant REWARD_INTERVAL = 1 minutes; // 奖励间隔（1分钟）
    uint256 public constant BASE_TOKEN_PER_MINUTE = 10 * 10**18; // 基础每分钟每个质押的NFT可获得的代币数量
    uint256 public constant MAX_DAILY_REWARD = 14400 * 10**18; // 每日最大奖励总量（14400 = 24*60）

    // 合约地址
    address public nftContract;
    address public tokenContract;

    // 状态变量
    uint256 public totalStakedNFTs; // 总质押NFT数量
    uint256 public lastRewardUpdate; // 上次奖励更新时间
    uint256 public dailyRewardDistributed; // 当日已分配奖励

    // 质押信息结构
    struct StakeInfo {
        uint256 tokenId;
        uint8 level;
        uint256 lastRewardTime;
        uint256 accumulatedRewards;
    }

    // 用户质押映射
    mapping(address => StakeInfo[]) public userStakes;
    // NFT质押状态映射
    mapping(uint256 => bool) public isStaked;

    // 事件定义
    event NFTStaked(address indexed user, uint256 indexed tokenId, uint8 level);
    event NFTUnstaked(address indexed user, uint256 indexed tokenId);
    event RewardsClaimed(address indexed user, uint256 amount);
    event TokensDeposited(uint256 amount);

    // 初始化函数
    function initialize(address _nftContract, address _tokenContract) external onlyOwner {
        nftContract = _nftContract;
        tokenContract = _tokenContract;
        lastRewardUpdate = block.timestamp;
        dailyRewardDistributed = 0;
    }

    // 质押NFT
    function stakeNFT(uint256 tokenId) external {
        // 检查NFT是否已经质押
        require(!isStaked[tokenId], "NFT already staked");

        // 检查NFT是否属于调用者
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");

        // 检查NFT等级是否满足要求
        (, uint8 level) = _getNFTInfo(tokenId);
        require(level >= MIN_STAKING_LEVEL, "NFT level too low");

        // 转移NFT到合约
        nft.transferFrom(msg.sender, address(this), tokenId);

        // 记录质押信息
        userStakes[msg.sender].push(StakeInfo({
            tokenId: tokenId,
            level: level,
            lastRewardTime: block.timestamp,
            accumulatedRewards: 0
        }));

        // 标记NFT为已质押
        isStaked[tokenId] = true;
        totalStakedNFTs++;

        emit NFTStaked(msg.sender, tokenId, level);
    }

    // 解除质押
    function unstakeNFT(uint256 tokenId) external {
        // 找到质押信息
        uint256 index = _findStakeIndex(msg.sender, tokenId);
        require(index < userStakes[msg.sender].length, "NFT not staked by user");

        // 计算并更新奖励
        _updateRewards(msg.sender, index);

        // 获取质押信息
        StakeInfo memory stake = userStakes[msg.sender][index];

        // 移除质押信息
        _removeStake(msg.sender, index);

        // 标记NFT为未质押
        isStaked[tokenId] = false;
        totalStakedNFTs--;

        // 转移NFT回用户
        IERC721 nft = IERC721(nftContract);
        nft.transferFrom(address(this), msg.sender, tokenId);

        emit NFTUnstaked(msg.sender, tokenId);
    }

    // 领取奖励
    function claimRewards() external {
        uint256 totalRewards = 0;

        // 更新并计算所有质押的奖励
        for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
            _updateRewards(msg.sender, i);
            totalRewards += userStakes[msg.sender][i].accumulatedRewards;
            userStakes[msg.sender][i].accumulatedRewards = 0;
        }

        require(totalRewards > 0, "No rewards to claim");

        // 检查合约代币余额
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= totalRewards, "Insufficient tokens in contract");

        // 转移代币给用户
        token.transfer(msg.sender, totalRewards);

        emit RewardsClaimed(msg.sender, totalRewards);
    }

    // 计算用户可领取的奖励
    function calculateRewards(address user) external view returns (uint256) {
        uint256 totalRewards = 0;
        uint256 currentTime = block.timestamp;
        uint256 dailyReward = _calculateDailyReward();

        for (uint256 i = 0; i < userStakes[user].length; i++) {
            StakeInfo memory stake = userStakes[user][i];
            uint256 timeElapsed = currentTime - stake.lastRewardTime;
            uint256 rewardPerMinute = _calculateRewardPerMinute(dailyReward);
            uint256 rewards = (timeElapsed / REWARD_INTERVAL) * rewardPerMinute;
            totalRewards += stake.accumulatedRewards + rewards;
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

    // 接收代币
    receive() external payable {
        // 只接受代币转账
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
        // 检查是否需要重置每日奖励计数
        uint256 dayStart = block.timestamp - (block.timestamp % 86400); // 当天开始时间
        if (lastRewardUpdate < dayStart) {
            dailyRewardDistributed = 0;
            lastRewardUpdate = block.timestamp;
        }

        // 计算合约中的代币余额
        IERC20 token = IERC20(tokenContract);
        uint256 contractBalance = token.balanceOf(address(this));

        // 计算可用奖励：取合约余额的1%或最大每日奖励的较小值
        uint256 availableReward = contractBalance / 100;
        if (availableReward > MAX_DAILY_REWARD) {
            availableReward = MAX_DAILY_REWARD;
        }

        // 确保不超过当日剩余可分配奖励
        uint256 remainingDailyReward = availableReward - dailyRewardDistributed;
        if (remainingDailyReward < 0) {
            remainingDailyReward = 0;
        }

        return remainingDailyReward;
    }

    // 内部函数：计算每分钟每个NFT的奖励
    function _calculateRewardPerMinute(uint256 dailyReward) internal view returns (uint256) {
        if (totalStakedNFTs == 0) {
            return 0;
        }

        // 计算每分钟总奖励
        uint256 totalMinuteReward = dailyReward / 1440; // 1440分钟/天
        
        // 计算每个NFT每分钟的奖励
        uint256 rewardPerMinute = totalMinuteReward / totalStakedNFTs;
        
        // 确保奖励不低于基础奖励的10%
        uint256 minReward = BASE_TOKEN_PER_MINUTE / 10;
        if (rewardPerMinute < minReward) {
            rewardPerMinute = minReward;
        }
        
        // 确保奖励不超过基础奖励
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
        // 调用NFT合约的tokenType和tokenLevel函数
        (bool success, bytes memory data) = nftContract.call(
            abi.encodeWithSignature("tokenType(uint256)", tokenId)
        );
        require(success, "Failed to get token type");
        uint8 tokenType = abi.decode(data, (uint8));

        (success, data) = nftContract.call(
            abi.encodeWithSignature("tokenLevel(uint256)", tokenId)
        );
        require(success, "Failed to get token level");
        uint8 level = abi.decode(data, (uint8));

        return (tokenType, level);
    }

    // 实现ERC165接口
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
