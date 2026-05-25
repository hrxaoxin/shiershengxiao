// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title Staking
 * @dev NFT质押合约，允许用户质押5级以上NFT以获取奖励
 *
 * 质押规则：
 * 1. 仅5级NFT可质押
 * 2. 质押后进入30分钟锁定期
 * 3. 锁定期后可随时解除质押
 * 4. 质押期间可领取奖励
 *
 * 奖励机制：
 * - 质押奖励来自游戏池（交易税、战斗费等）
 * - 奖励按质押NFT的权重分配
 * - 稀有NFT权重更高
 *
 * 权重表（普通NFT）：
 * - 5级: 66
 *
 * 权重表（稀有NFT）：
 * - 5级: 76
 */
contract Staking is Ownable {
    /**
     * @dev 最低质押时长（秒）
     * 30分钟 = 30 * 60
     */
    uint256 public minStakingDuration = 30 minutes;

    /**
     * @dev 每秒基础奖励（wei）
     */
    uint256 public rewardPerSecond = 1 wei;

    /**
     * @dev 普通NFT权重
     */
    uint256 public normalNFTWeight = 66;

    /**
     * @dev 稀有NFT权重
     */
    uint256 public rareNFTWeight = 76;

    /**
     * @dev 质押信息结构体
     */
    struct StakingInfo {
        address owner;           // 质押者地址
        uint256 stakeTime;      // 质押时间
        uint256 lastClaimTime;  // 最后领取时间
        uint256 accumulatedReward; // 累积奖励
        bool isRare;            // 是否为稀有NFT
    }

    /**
     * @dev 质押映射
     * tokenId => StakingInfo
     */
    mapping(uint256 => StakingInfo) public stakingInfo;

    /**
     * @dev 用户质押的NFT列表
     * user => tokenIds
     */
    mapping(address => uint256[]) public userStakedNFTs;

    /**
     * @dev 总质押权重
     */
    uint256 public totalStakedWeight;

    /**
     * @dev 奖励代币合约地址
     */
    address public rewardTokenContract;

    /**
     * @dev 质押事件
     */
    event Staked(address indexed user, uint256[] tokenIds);

    /**
     * @dev 解除质押事件
     */
    event Unstaked(address indexed user, uint256[] tokenIds);

    /**
     * @dev 领取奖励事件
     */
    event RewardClaimed(address indexed user, uint256 amount);

    /**
     * @dev 参数更新事件
     */
    event StakingParamsUpdated(
        uint256 minDuration,
        uint256 rewardPerSec,
        uint256 normalWeight,
        uint256 rareWeight
    );

    /**
     * @dev 质押NFT
     *
     * @param tokenIds NFT ID数组
     * @param areRares 是否为稀有NFT数组（与tokenIds对应）
     */
    function stake(uint256[] calldata tokenIds, bool[] calldata areRares) external {
        require(tokenIds.length == areRares.length, "Staking: Array length mismatch");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(stakingInfo[tokenId].owner == address(0), "Staking: Already staked");

            uint256 weight = areRares[i] ? rareNFTWeight : normalNFTWeight;
            totalStakedWeight += weight;

            stakingInfo[tokenId] = StakingInfo({
                owner: msg.sender,
                stakeTime: block.timestamp,
                lastClaimTime: block.timestamp,
                accumulatedReward: 0,
                isRare: areRares[i]
            });

            userStakedNFTs[msg.sender].push(tokenId);
        }

        emit Staked(msg.sender, tokenIds);
    }

    /**
     * @dev 解除质押
     *
     * @param tokenIds NFT ID数组
     */
    function unstake(uint256[] calldata tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            StakingInfo storage info = stakingInfo[tokenId];
            require(info.owner == msg.sender, "Staking: Not owner");
            require(block.timestamp >= info.stakeTime + minStakingDuration, "Staking: Lock period");

            uint256 weight = info.isRare ? rareNFTWeight : normalNFTWeight;
            totalStakedWeight -= weight;

            delete stakingInfo[tokenId];
            _removeFromUserStakedNFTs(msg.sender, tokenId);
        }

        emit Unstaked(msg.sender, tokenIds);
    }

    /**
     * @dev 领取奖励
     */
    function claimReward() external {
        uint256 totalReward = 0;
        uint256[] storage stakedNFTs = userStakedNFTs[msg.sender];

        for (uint256 i = 0; i < stakedNFTs.length; i++) {
            StakingInfo storage info = stakingInfo[stakedNFTs[i]];
            if (info.owner == msg.sender) {
                uint256 reward = _calculateReward(stakedNFTs[i]);
                totalReward += reward;
                info.accumulatedReward += reward;
                info.lastClaimTime = block.timestamp;
            }
        }

        require(totalReward > 0, "Staking: No reward");
        require(rewardTokenContract != address(0), "Staking: Reward token not set");
        
        IERC20 rewardToken = IERC20(rewardTokenContract);
        require(rewardToken.balanceOf(address(this)) >= totalReward, "Staking: Insufficient reward");
        require(rewardToken.transfer(msg.sender, totalReward), "Staking: Reward transfer failed");
        
        emit RewardClaimed(msg.sender, totalReward);
    }

    /**
     * @dev 获取质押信息
     */
    function getStakingInfo(uint256 tokenId) external view returns (
        address owner,
        uint256 stakeTime,
        uint256 lastClaimTime,
        uint256 accumulatedReward,
        bool isRare
    ) {
        StakingInfo memory info = stakingInfo[tokenId];
        return (
            info.owner,
            info.stakeTime,
            info.lastClaimTime,
            info.accumulatedReward,
            info.isRare
        );
    }

    /**
     * @dev 获取用户质押的NFT列表
     */
    function getUserStakedNFTs(address user) external view returns (uint256[] memory) {
        return userStakedNFTs[user];
    }

    /**
     * @dev 获取用户待领取奖励
     */
    function getPendingReward(address user) external view returns (uint256) {
        uint256 total = 0;
        uint256[] storage stakedNFTs = userStakedNFTs[user];

        for (uint256 i = 0; i < stakedNFTs.length; i++) {
            total += _calculateReward(stakedNFTs[i]);
        }

        return total;
    }

    /**
     * @dev 计算单个NFT的奖励
     */
    function _calculateReward(uint256 tokenId) internal view returns (uint256) {
        StakingInfo memory info = stakingInfo[tokenId];
        if (info.owner == address(0)) return 0;

        uint256 timeDiff = block.timestamp - info.lastClaimTime;
        uint256 weight = info.isRare ? rareNFTWeight : normalNFTWeight;
        
        return timeDiff * rewardPerSecond * weight;
    }

    /**
     * @dev 从用户质押列表移除
     */
    function _removeFromUserStakedNFTs(address user, uint256 tokenId) internal {
        uint256[] storage nfts = userStakedNFTs[user];
        for (uint256 i = 0; i < nfts.length; i++) {
            if (nfts[i] == tokenId) {
                nfts[i] = nfts[nfts.length - 1];
                nfts.pop();
                break;
            }
        }
    }

    /**
     * @dev 获取质押常量
     */
    function getStakingConstants() external view returns (
        uint256 minDuration,
        uint256 rewardPerSec,
        uint256 normalWeight,
        uint256 rareWeight
    ) {
        return (minStakingDuration, rewardPerSecond, normalNFTWeight, rareNFTWeight);
    }

    /**
     * @dev 设置质押参数
     */
    function setStakingParams(
        uint256 _minDuration,
        uint256 _rewardPerSecond,
        uint256 _normalWeight,
        uint256 _rareWeight
    ) external onlyOwner {
        require(_minDuration > 0, "Staking: Invalid duration");
        require(_normalWeight > 0, "Staking: Invalid normal weight");
        require(_rareWeight > 0, "Staking: Invalid rare weight");

        minStakingDuration = _minDuration;
        rewardPerSecond = _rewardPerSecond;
        normalNFTWeight = _normalWeight;
        rareNFTWeight = _rareWeight;

        emit StakingParamsUpdated(_minDuration, _rewardPerSecond, _normalWeight, _rareWeight);
    }

    /**
     * @dev 设置奖励代币合约地址
     */
    function setRewardTokenContract(address _tokenContract) external onlyOwner {
        require(_tokenContract != address(0), "Staking: Invalid token address");
        rewardTokenContract = _tokenContract;
        emit RewardTokenSet(_tokenContract);
    }

    /**
     * @dev 事件：奖励代币设置
     */
    event RewardTokenSet(address indexed tokenContract);
}
