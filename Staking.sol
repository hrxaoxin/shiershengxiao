// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "./NFTInterface.sol";

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
contract Staking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    /**
     * @dev 最低质押时长（秒）
     * 30分钟 = 30 * 60
     */
    uint256 public minStakingDuration = 30 minutes;

    /**
     * @dev 基础奖励比例（万分比，默认10 = 0.1%）
     */
    uint256 public rewardRate = 10;

    /**
     * @dev 最大奖励比例（万分比，默认20 = 0.2%）
     */
    uint256 public maxRewardRate = 20;

    /**
     * @dev 每次上调比例（万分比，1 = 0.01%）
     */
    uint256 public rateStep = 1;

    /**
     * @dev 质押的NFT总数
     */
    uint256 public totalStakedNFTs;

    /**
     * @dev 用户待领取奖励
     */
    mapping(address => uint256) public pendingRewards;

    /**
     * @dev 今日已进入合约的代币数量
     */
    uint256 public todayIncomingTokens;

    /**
     * @dev 今日奖励总量
     */
    uint256 public todayRewardAmount;

    /**
     * @dev 今日开始时间
     */
    uint256 public todayStart;

    /**
     * @dev 质押信息结构体
     */
    struct StakingInfo {
        address owner;           // 质押者地址
        uint256 stakeTime;      // 质押时间
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
     * @dev 质押用户列表（用于奖励分发）
     */
    address[] public stakingUsers;

    /**
     * @dev 用户是否在质押用户列表中
     */
    mapping(address => bool) public isStakingUser;

    /**
     * @dev 质押权重映射（为了保持向后兼容）
     */
    uint256 public normalNFTWeight = 66;
    uint256 public rareNFTWeight = 76;

    /**
     * @dev 奖励代币合约地址
     */
    address public rewardTokenContract;

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
        require(msg.sender == owner() || msg.sender == authorizer, "Staking: Not authorized");
        _;
    }

    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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
     * @dev 奖励比例更新事件
     */
    event RewardRateUpdated(uint256 newRate);

    /**
     * @dev 最大奖励比例更新事件
     */
    event MaxRewardRateUpdated(uint256 newMaxRate);

    /**
     * @dev 上调步长更新事件
     */
    event RateStepUpdated(uint256 newStep);

    /**
     * @dev 每日奖励计算事件
     */
    event DailyRewardCalculated(uint256 totalReward, uint256 totalStaked, uint256 rewardPerNFT);

    /**
     * @dev 流入代币记录事件
     */
    event IncomingTokensRecorded(uint256 amount, uint256 totalToday);

    /**
     * @dev 质押NFT
     *
     * @param tokenIds NFT ID数组
     * @param areRares 是否为稀有NFT数组（与tokenIds对应）
     */
    function stake(uint256[] calldata tokenIds, bool[] calldata areRares) external {
        require(tokenIds.length == areRares.length, "Staking: Array length mismatch");
        
        _checkNewDay();

        // 如果用户是首次质押，添加到用户列表
        if (!isStakingUser[msg.sender] && userStakedNFTs[msg.sender].length == 0) {
            isStakingUser[msg.sender] = true;
            stakingUsers.push(msg.sender);
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(stakingInfo[tokenId].owner == address(0), "Staking: Already staked");

            stakingInfo[tokenId] = StakingInfo({
                owner: msg.sender,
                stakeTime: block.timestamp,
                isRare: areRares[i]
            });

            userStakedNFTs[msg.sender].push(tokenId);
            totalStakedNFTs++;
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

            delete stakingInfo[tokenId];
            _removeFromUserStakedNFTs(msg.sender, tokenId);
            totalStakedNFTs--;
        }

        // 如果用户已经没有质押的NFT，从用户列表中移除
        if (userStakedNFTs[msg.sender].length == 0) {
            isStakingUser[msg.sender] = false;
            _removeFromStakingUsers(msg.sender);
        }

        emit Unstaked(msg.sender, tokenIds);
    }

    /**
     * @dev 领取奖励
     */
    function claimReward() external {
        uint256 reward = pendingRewards[msg.sender];
        require(reward > 0, "Staking: No pending reward");
        require(rewardTokenContract != address(0), "Staking: Reward token not set");

        pendingRewards[msg.sender] = 0;
        
        IERC20 rewardToken = IERC20(rewardTokenContract);
        require(rewardToken.balanceOf(address(this)) >= reward, "Staking: Insufficient reward");
        require(rewardToken.transfer(msg.sender, reward), "Staking: Reward transfer failed");
        
        emit RewardClaimed(msg.sender, reward);
    }

    /**
     * @dev 获取质押信息
     */
    function getStakingInfo(uint256 tokenId) external view returns (
        address owner,
        uint256 stakeTime,
        bool isRare
    ) {
        StakingInfo memory info = stakingInfo[tokenId];
        return (
            info.owner,
            info.stakeTime,
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
        return pendingRewards[user];
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
     * @dev 从质押用户列表移除
     */
    function _removeFromStakingUsers(address user) internal {
        for (uint256 i = 0; i < stakingUsers.length; i++) {
            if (stakingUsers[i] == user) {
                stakingUsers[i] = stakingUsers[stakingUsers.length - 1];
                stakingUsers.pop();
                break;
            }
        }
    }

    /**
     * @dev 设置奖励比例（仅owner）
     * @param _rewardRate 新的奖励比例（万分比）
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0 && _rewardRate <= maxRewardRate, "Staking: Invalid reward rate");
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    /**
     * @dev 设置最大奖励比例（仅owner）
     * @param _maxRewardRate 最大奖励比例（万分比）
     */
    function setMaxRewardRate(uint256 _maxRewardRate) external onlyOwner {
        require(_maxRewardRate >= rewardRate, "Staking: Max rate must be >= current rate");
        maxRewardRate = _maxRewardRate;
        emit MaxRewardRateUpdated(_maxRewardRate);
    }

    /**
     * @dev 设置上调步长（仅owner）
     * @param _rateStep 上调步长（万分比）
     */
    function setRateStep(uint256 _rateStep) external onlyOwner {
        require(_rateStep > 0, "Staking: Step must be > 0");
        rateStep = _rateStep;
        emit RateStepUpdated(_rateStep);
    }

    /**
     * @dev 记录进入合约的代币数量
     */
    function recordIncomingTokens(uint256 amount) external onlyAuthorized {
        _checkNewDay();
        todayIncomingTokens += amount;
        emit IncomingTokensRecorded(amount, todayIncomingTokens);
    }

    /**
     * @dev 检查是否进入新的一天
     */
    function _checkNewDay() internal {
        uint256 currentDayStart = (block.timestamp / 1 days) * 1 days;

        if (todayStart != currentDayStart) {
            todayStart = currentDayStart;
            todayIncomingTokens = 0;
            todayRewardAmount = 0;
            _adjustRewardRate();
        }
    }

    /**
     * @dev 动态调整奖励比例
     * 规则：流入代币量是每日奖励总量的倍数，每增加1倍，比例上调0.01%，最多上调0.1%
     */
    function _adjustRewardRate() internal {
        if (todayRewardAmount > 0 && todayIncomingTokens > todayRewardAmount) {
            uint256 multiple = todayIncomingTokens / todayRewardAmount;
            uint256 maxSteps = (maxRewardRate - rewardRate) / rateStep;
            uint256 steps = multiple - 1;

            if (steps > maxSteps) {
                steps = maxSteps;
            }

            uint256 newRate = rewardRate + (steps * rateStep);

            if (newRate != rewardRate) {
                rewardRate = newRate;
                emit RewardRateUpdated(rewardRate);
            }
        }
    }

    /**
     * @dev 计算并分发每日奖励
     */
    function calculateDailyReward() external {
        _checkNewDay();

        IERC20 rewardToken = IERC20(rewardTokenContract);
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        uint256 totalPending = _getTotalPendingRewards();

        todayRewardAmount = (contractBalance - totalPending) * rewardRate / 10000;

        if (totalStakedNFTs > 0 && todayRewardAmount > 0) {
            uint256 rewardPerNFT = todayRewardAmount / totalStakedNFTs;
            _distributeRewards(rewardPerNFT);
            emit DailyRewardCalculated(todayRewardAmount, totalStakedNFTs, rewardPerNFT);
        }
    }

    /**
     * @dev 分发奖励（根据用户质押数量分配）
     */
    function _distributeRewards(uint256 rewardPerNFT) internal {
        for (uint256 i = 0; i < stakingUsers.length; i++) {
            address user = stakingUsers[i];
            uint256 userNFTCount = userStakedNFTs[user].length;
            pendingRewards[user] += rewardPerNFT * userNFTCount;
        }
    }

    /**
     * @dev 获取所有用户待领取奖励总和
     */
    function _getTotalPendingRewards() internal view returns (uint256) {
        return 0;
    }

    /**
     * @dev 设置奖励代币合约地址
     */
    function setRewardTokenContract(address _tokenContract) external onlyAuthorized {
        require(_tokenContract != address(0), "Staking: Invalid token address");
        rewardTokenContract = _tokenContract;
        emit RewardTokenSet(_tokenContract);
    }

    /**
     * @dev 事件：奖励代币设置
     */
    event RewardTokenSet(address indexed tokenContract);
}
