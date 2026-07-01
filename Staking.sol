// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NFTInterface.sol";
import "./StakingLib.sol";

/**
 * @title Staking
 * @dev NFT质押合约（优化版：支持大规模用户，实时奖励计算）
 *
 * 核心功能：
 * 1. NFT质押（stakeNFT）：用户将NFT转入合约，进入质押池开始产生奖励
 * 2. 奖励领取（claimReward）：用户领取累计奖励，基于全局累积奖励快照计算
 * 3. 解除质押（unstakeNFT）：取出质押的NFT，需经过最小锁仓期（minStakingDuration）
 * 4. 紧急提取（emergencyWithdraw）：经过 timelock 后可强制提取，防止合约异常锁死资产
 *
 * 奖励机制设计（O(1) 计算，Gas 优化版）：
 * - 核心思想：用一个全局累积变量（globalRewardPerWeight）记录"每单位权重的历史累积奖励"
 * - 每个 NFT 记录质押时的 globalRewardPerWeight 快照（accumulatedReward）
 * - 用户领取时：(当前 globalRewardPerWeight - NFT快照) × NFT权重 = 该NFT应得奖励
 * - 这样无论多少用户质押，每次新增奖励池只需更新全局变量，无需遍历所有用户
 *
 * 权重系统：
 * - 普通NFT（水/木/火属性，type < 72）：根据等级赋予权重 1/2/6/18/66
 * - 稀有NFT（暗/光属性，type >= 72）：根据等级赋予权重 10/12/16/28/76
 * - 等级越高，权重越大，奖励比例越高
 * - 权重同时会更新到 WeightManager / DividendManager，用于分红池分配
 *
 * 动态奖励率调整：
 * - 基础奖励率（rewardRate）：默认1%（100/10000）
 * - 最大奖励率（maxRewardRate）：默认2%
 * - 根据每日流入资金自动调整，激励长期持有者
 *
 * 溢出保护：
 * - globalRewardPerWeight 使用 uint256，设置 REWARD_OVERFLOW_THRESHOLD 预警
 * - 用户快照权重（_userSnapshotWeight）同样有溢出阈值保护
 * - 达到阈值时触发 rewardResetCount，重置累积变量防止溢出
 *
 * 安全限制：
 * - 最小质押持续时间（minStakingDuration = 30分钟）：防止刷奖励
 * - 重入保护（ReentrancyGuard）：防止 claimReward 时的重入攻击
 * - 紧急提取 timelock（emergencyWithdrawTimelock = 48小时）：防止恶意 owner 提取
 * - 暂停机制（paused）：紧急情况下暂停全部用户操作
 *
 * 典型用户流程：
 * 1. 授权合约转移NFT（approve/setApprovalForAll）
 * 2. 调用 stakeNFT(tokenId) 质押NFT
 * 3. 等待若干时间（合约持续更新 globalRewardPerWeight）
 * 4. 调用 claimReward() 领取累计奖励
 * 5. 30分钟锁仓期后调用 unstakeNFT(tokenId) 解除质押
 *
 * 合约升级：
 * - UUPS 可升级模式，需 onlyOwner 授权升级
 * - 所有状态变量均在 storage 存储，升级后保留
 */
contract Staking is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /**
     * @dev 构造函数：禁用初始化器，防止直接部署实现合约时的初始化攻击
     */
    constructor() {
        _disableInitializers();
    }

    /** @dev 最小质押持续时间（30分钟），防止刷奖励 */
    uint256 public minStakingDuration = 30 minutes;

    /** @dev 已质押NFT总数 */
    uint256 public totalStakedNFTs;
    /** @dev 已质押NFT的总权重（用于计算奖励分配） */
    uint256 public totalWeightedNFTs;

    /** @dev 紧急提取timelock锁定期（48小时），防止恶意owner立即提取 */
    uint256 public emergencyWithdrawTimelock = 48 hours;
    /** @dev 紧急提取解锁时间戳，owner可在该时间后执行紧急提取 */
    uint256 public emergencyWithdrawUnlockTime;

    /** @dev 用户待领取奖励映射（地址 => 待领取金额） */
    mapping(address => uint256) public pendingRewards;
    /** @dev 今日流入合约的代币数量（用于动态奖励率调整） */
    uint256 public todayIncomingTokens;
    /** @dev 全局累积奖励（每单位权重），用于O(1)奖励计算 */
    uint256 public globalRewardPerWeight;

    /** @dev 用户质押的NFT总权重（地址 => 总权重），优化getPendingReward/claimReward的Gas消耗 */
    mapping(address => uint256) public userStakedWeight;
    /** @dev 用户级别累计快照权重（地址 => Σ(accumulatedReward * weight)），用于O(1)计算待领取奖励 */
    mapping(address => uint256) private _userSnapshotWeight;
    
    /** @dev 用户快照权重溢出保护阈值（约90%的uint256最大值），距离最大值的安全距离 */
    uint256 public constant USER_SNAPSHOT_OVERFLOW_THRESHOLD = 158456325028528675187087900672;

    /** @dev NFT质押信息结构
     * @param owner NFT所有者地址
     * @param stakeTime 质押时间戳
     * @param lastClaimTime 上次领取奖励时间戳
     * @param accumulatedReward 该NFT上次结算时的globalRewardPerWeight快照
     * @param isRare 是否为稀有NFT
     * @param level NFT等级（用于计算权重）
     */
    struct StakingInfo {
        address owner;
        uint256 stakeTime;
        uint256 lastClaimTime;
        uint256 accumulatedReward;
        bool isRare;
        uint8 level;
    }

    /** @dev tokenId => 质押信息映射 */
    mapping(uint256 => StakingInfo) public stakingInfo;
    /** @dev 用户地址 => 该用户质押的tokenId数组映射 */
    mapping(address => uint256[]) public userStakedNFTs;
    /** @dev 用户是否正在质押（用于快速判断） */
    mapping(address => bool) public isStakingUser;
    /** @dev 用户在stakingUsers数组中的索引（用于高效删除） */
    mapping(address => uint256) public stakingUserIndex;
    /** @dev 所有质押用户地址数组 */
    address[] public stakingUsers;
    
    /** @dev tokenId到用户在userStakedNFTs数组中索引的映射（优化删除操作） */
    mapping(uint256 => uint256) public tokenIdToUserIndex;

    /** @dev 允许质押的最低NFT等级 */
    uint8 public minStakingLevel = 1;
    /** @dev 授权合约地址，用于获取NFT合约和代币合约等依赖 */
    address public authorizer;
    
    /** @dev 合约暂停状态标记 */
    bool public paused;
    /** @dev 暂停原因描述 */
    string public pauseReason;

    /** @dev NFT质押事件
     * @param user 质押用户地址
     * @param tokenIds 质押的tokenId数组
     */
    event Staked(address indexed user, uint256[] tokenIds);
    /** @dev NFT解除质押事件
     * @param user 解除质押用户地址
     * @param tokenIds 解除质押的tokenId数组
     */
    event Unstaked(address indexed user, uint256[] tokenIds);
    /** @dev 奖励领取事件
     * @param user 领取奖励用户地址
     * @param amount 领取奖励金额
     */
    event RewardClaimed(address indexed user, uint256 amount);
    /** @dev 奖励率更新事件
     * @param newRate 新的奖励率
     */
    /** @dev 合约暂停事件
     * @param account 暂停操作者
     * @param reason 暂停原因
     */
    event Paused(address account, string reason);
    /** @dev 合约恢复事件
     * @param account 恢复操作者
     */
    event Unpaused(address account);
    /** @dev 紧急提取BNB事件
     * @param operator 操作者
     * @param to 接收地址
     * @param amount 提取金额
     */
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    /** @dev 紧急提取代币事件
     * @param operator 操作者
     * @param to 接收地址
     * @param amount 提取金额
     */
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);

    /**
     * @dev 初始化合约函数
     * @param _authorizerAddress 授权合约地址，用于获取NFT合约和代币合约等依赖
     */
    function initialize(address _authorizerAddress) external initializer {
        require(_authorizerAddress != address(0), "Staking: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizerAddress;
        
        // 初始化带默认值的参数
        minStakingDuration = 30 minutes;
        emergencyWithdrawTimelock = 48 hours;
        minStakingLevel = 1;
        
        emergencyWithdrawUnlockTime = block.timestamp + emergencyWithdrawTimelock;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 新的授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "Staking: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }

    /**
     * @dev 设置最小质押等级
     * @param _minLevel 最小质押等级要求
     */
    function setMinStakingLevel(uint8 _minLevel) external onlyOwnerOrAuthorizer {
        require(_minLevel > 0, "Staking: Minimum level must be at least 1");
        minStakingLevel = _minLevel;
    }

    /**
     * @dev 仅owner或authorizer或系统合约的修饰符
     */
    modifier onlyOwnerOrAuthorizer() {
        if (msg.sender == owner() || msg.sender == authorizer) {
            _;
            return;
        }
        // 修复：先检查authorizer是否有效
        require(authorizer != address(0), "Staking: Authorizer not set");
        IAuthorizer auth = IAuthorizer(authorizer);
        require(auth.isSystemContract(msg.sender), "Staking: Not authorized");
        _;
    }

    /**
     * @dev UUPS升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 非暂停状态检查修饰符
     */
    modifier whenNotPaused() {
        require(!paused, "Staking: Paused");
        _;
    }

    /**
     * @dev 质押NFT函数
     * @param tokenIds 要质押的tokenId数组
     */
    function stake(uint256[] calldata tokenIds) external whenNotPaused nonReentrant {
        require(tokenIds.length > 0, "Staking: Empty tokenIds");
        address nftContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftContract != address(0), "Staking: NFT contract not set");

        if (!isStakingUser[msg.sender] && userStakedNFTs[msg.sender].length == 0) {
            isStakingUser[msg.sender] = true;
            stakingUserIndex[msg.sender] = stakingUsers.length;
            stakingUsers.push(msg.sender);
        }

        INFT nft = INFT(nftContract);
        require(nft.isApprovedForAll(msg.sender, address(this)), "Staking: Contract not approved for transfer");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "Staking: Invalid token ID");
            require(stakingInfo[tokenId].owner == address(0), "Staking: Already staked");
            require(nft.ownerOf(tokenId) == msg.sender, "Staking: Not owner of token");

            // 检查 NFT 等级是否满足质押要求
            uint8 tokenLevel = nft.tokenLevel(tokenId);
            require(tokenLevel >= minStakingLevel, "Staking: NFT level below minimum requirement");

            bool isRareToken = nft.isRare(tokenId);
            nft.safeTransferFrom(msg.sender, address(this), tokenId);

            stakingInfo[tokenId] = StakingInfo({
                owner: msg.sender,
                stakeTime: block.timestamp,
                lastClaimTime: block.timestamp,
                accumulatedReward: globalRewardPerWeight,
                isRare: isRareToken,
                level: tokenLevel
            });

            uint256 newIndex = userStakedNFTs[msg.sender].length;
            userStakedNFTs[msg.sender].push(tokenId);
            tokenIdToUserIndex[tokenId] = newIndex;
            totalStakedNFTs++;
            uint256 weight = _getNFTWeight(tokenLevel, isRareToken);
            totalWeightedNFTs += weight;
            // 更新用户级别累计跟踪
            userStakedWeight[msg.sender] += weight;
            
            uint256 snapshotIncrement = globalRewardPerWeight * weight;
            if (snapshotIncrement < USER_SNAPSHOT_OVERFLOW_THRESHOLD && _userSnapshotWeight[msg.sender] < USER_SNAPSHOT_OVERFLOW_THRESHOLD - snapshotIncrement) {
                _userSnapshotWeight[msg.sender] += snapshotIncrement;
            }
            
            _syncWeight(msg.sender, tokenId, nftContract, true);
        }
        
        emit Staked(msg.sender, tokenIds);
    }

    /**
     * @dev 解除质押NFT函数
     * @param tokenIds 要解除质押的tokenId数组
     */
    function unstake(uint256[] calldata tokenIds) external whenNotPaused nonReentrant {
        address nftContract = IAuthorizer(authorizer).getNFTMintCore();
        require(nftContract != address(0), "Staking: NFT contract not set");
        INFT nft = INFT(nftContract);

        uint256 totalWeightBefore = userStakedWeight[msg.sender];

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "Staking: Invalid token ID");
            StakingInfo storage info = stakingInfo[tokenId];
            require(info.owner == msg.sender, "Staking: Not owner");
            require(block.timestamp >= info.stakeTime + minStakingDuration, "Staking: Lock period");

            bool wasRare = info.isRare;
            uint256 weight = _getNFTWeight(info.level, wasRare);
            delete stakingInfo[tokenId];
            _removeFromUserStakedNFTs(msg.sender, tokenId);
            totalStakedNFTs--;
            totalWeightedNFTs -= weight;
            // 更新用户级别累计跟踪
            userStakedWeight[msg.sender] -= weight;
            uint256 snapshotDecrement = globalRewardPerWeight * weight;
            // 修复：当 globalRewardPerWeight 重置为 0 时，先处理pendingRewards再重置快照
            if (globalRewardPerWeight == 0) {
                // 先将pendingRewards转移到用户余额，确保不丢失
                if (pendingRewards[msg.sender] > 0) {
                    uint256 pending = pendingRewards[msg.sender];
                    pendingRewards[msg.sender] = 0;
                    address rewardTokenContract = IAuthorizer(authorizer).getToken();
                    if (rewardTokenContract != address(0)) {
                        IERC20 rewardToken = IERC20(rewardTokenContract);
                        if (rewardToken.balanceOf(address(this)) >= pending) {
                            rewardToken.safeTransfer(msg.sender, pending);
                            emit RewardClaimed(msg.sender, pending);
                        } else {
                            // 如果合约余额不足，恢复pendingRewards
                            pendingRewards[msg.sender] = pending;
                        }
                    }
                }
                _userSnapshotWeight[msg.sender] = 0;
            } else {
                require(_userSnapshotWeight[msg.sender] >= snapshotDecrement, "Staking: Snapshot underflow");
                _userSnapshotWeight[msg.sender] -= snapshotDecrement;
            }

            nft.safeTransferFrom(address(this), msg.sender, tokenId);
            
            _syncWeight(msg.sender, tokenId, nftContract, false);
        }
        
        if (userStakedNFTs[msg.sender].length == 0) {
            isStakingUser[msg.sender] = false;
            _removeFromStakingUsers(msg.sender);
            
            uint256 totalClaimable = _calcUserPending(msg.sender);
            if (totalClaimable > 0) {
                address rewardTokenContract = IAuthorizer(authorizer).getToken();
                require(rewardTokenContract != address(0), "Staking: Reward token contract not set");
                IERC20 rewardToken = IERC20(rewardTokenContract);
                require(rewardToken.balanceOf(address(this)) >= totalClaimable, "Staking: Insufficient reward balance for unstake");
                rewardToken.safeTransfer(msg.sender, totalClaimable);
                emit RewardClaimed(msg.sender, totalClaimable);
                pendingRewards[msg.sender] = 0;
            }
        }
        emit Unstaked(msg.sender, tokenIds);
    }

    /**
     * @dev 领取奖励函数（Gas优化：用户级别累计公式计算总量，避免逐NFT计算）
     */
    function claimReward() external whenNotPaused nonReentrant {
        uint256[] storage nfts = userStakedNFTs[msg.sender];
        require(nfts.length > 0, "Staking: No staked NFTs");
        address rewardTokenContract = IAuthorizer(authorizer).getToken();
        require(rewardTokenContract != address(0), "Staking: Reward token not set");

        // O(1) 用户级别公式计算总量
        uint256 totalClaimable = _calcUserPending(msg.sender);
        require(totalClaimable > 0, "Staking: No pending reward");

        IERC20 rewardToken = IERC20(rewardTokenContract);
        require(rewardToken.balanceOf(address(this)) >= totalClaimable, "Staking: Insufficient reward balance");
        
        // 重置所有 NFT 的快照为当前全局值（必须遍历以更新 storage ）
        for (uint256 i = 0; i < nfts.length; i++) {
            StakingInfo storage info = stakingInfo[nfts[i]];
            if (info.owner == msg.sender) {
                info.accumulatedReward = globalRewardPerWeight;
                info.lastClaimTime = block.timestamp;
            }
        }
        
        // 重置用户级别累计快照
        _userSnapshotWeight[msg.sender] = globalRewardPerWeight * userStakedWeight[msg.sender];
        pendingRewards[msg.sender] = 0;
        
        rewardToken.safeTransfer(msg.sender, totalClaimable);
        
        emit RewardClaimed(msg.sender, totalClaimable);
    }

    // --- 内部核心逻辑 ---

    /**
     * @dev 从NFTData合约获取指定等级和稀有度的NFT权重
     * @param level NFT等级
     * @param isRare 是否稀有
     * @return 权重值
     */
    function _getNFTWeight(uint8 level, bool isRare) internal view returns (uint256) {
        address nftDataAddr = IAuthorizer(authorizer).getNFTData();
        if (nftDataAddr == address(0)) {
            return StakingLib.calculateNFTWeight(isRare, level);
        }
        try INFTData(nftDataAddr).getWeightByLevel(level, isRare) returns (uint256 w) {
            return w > 0 ? w : StakingLib.calculateNFTWeight(isRare, level);
        } catch {
            return StakingLib.calculateNFTWeight(isRare, level);
        }
    }

    /**
     * @dev 计算单个NFT待领取奖励（内部函数）
     * @param info 质押信息结构体指针
     * @return 待领取奖励金额
     */
    function _calculatePendingForNFT(StakingInfo storage info) internal view returns (uint256) {
        uint256 weight = _getNFTWeight(info.level, info.isRare);
        // 奖励 = (当前全局值 - 上次快照) * 权重 / 精度
        if (globalRewardPerWeight <= info.accumulatedReward) return 0;
        
        uint256 rewardDiff = globalRewardPerWeight - info.accumulatedReward;
        // 修复：添加乘法溢出检查
        require(rewardDiff == 0 || weight <= type(uint256).max / rewardDiff, "Staking: Reward calculation overflow");
        
        return rewardDiff * weight / STAKING_REWARD_PRECISION;
    }

    /**
     * @dev 结算单个NFT奖励（内部函数）
     * @param info 质押信息结构体指针
     */
    function _settleNFTReward(StakingInfo storage info) internal {
        uint256 reward = _calculatePendingForNFT(info);
        if (reward > 0) {
            pendingRewards[info.owner] += reward;
            info.accumulatedReward = globalRewardPerWeight;
        }
    }

    /** @dev 质押奖励精度缩放因子（1e18），用于避免整数截断 */
    uint256 public constant STAKING_REWARD_PRECISION = 1e18;

    

    /**
     * @dev 从用户质押列表中移除NFT（内部函数）
     * @param user 用户地址
     * @param tokenId 要移除的tokenId
     */
    function _removeFromUserStakedNFTs(address user, uint256 tokenId) internal {
        uint256[] storage nfts = userStakedNFTs[user];
        uint256 removeIndex = tokenIdToUserIndex[tokenId];
        
        // 验证索引有效性：如果 removeIndex 超出范围，或者对应位置的 tokenId 不匹配，说明未质押
        require(removeIndex < nfts.length && nfts[removeIndex] == tokenId, "Staking: Token not in user's staked list");
        
        uint256 lastIndex = nfts.length - 1;
        if (removeIndex != lastIndex) {
            // 将最后一个元素移到当前位置
            uint256 lastTokenId = nfts[lastIndex];
            nfts[removeIndex] = lastTokenId;
            tokenIdToUserIndex[lastTokenId] = removeIndex;
        }
        nfts.pop();
        delete tokenIdToUserIndex[tokenId];
    }

    /**
     * @dev 从质押用户列表中移除用户（内部函数）
     * @param user 要移除的用户地址
     */
    function _removeFromStakingUsers(address user) internal {
        uint256 index = stakingUserIndex[user];
        uint256 lastIndex = stakingUsers.length - 1;
        
        if (index != lastIndex) {
            address lastUser = stakingUsers[lastIndex];
            stakingUsers[index] = lastUser;
            stakingUserIndex[lastUser] = index;
        }
        
        stakingUsers.pop();
        delete stakingUserIndex[user];
        delete isStakingUser[user];
    }

    /**
     * @dev 获取NFT质押信息
     * @param tokenId NFT的tokenId
     * @return owner NFT所有者
     * @return stakeTime 质押时间
     * @return lastClaimTime 上次领取时间
     * @return accumulatedReward 累计奖励快照
     * @return isRare 是否稀有
     */
    function getStakingInfo(uint256 tokenId) external view returns (
        address owner,
        uint256 stakeTime,
        uint256 lastClaimTime,
        uint256 accumulatedReward,
        bool isRare
    ) {
        StakingInfo memory info = stakingInfo[tokenId];
        return (info.owner, info.stakeTime, info.lastClaimTime, info.accumulatedReward, info.isRare);
    }

    /**
     * @dev 获取用户质押的所有NFT
     * @param user 用户地址
     * @return 用户质押的tokenId数组
     */
    function getUserStakedNFTs(address user) external view returns (uint256[] memory) {
        return userStakedNFTs[user];
    }

    /**
     * @dev 查询待领取奖励（Gas优化：O(1)用户级别累计公式，不遍历NFT列表）
     * @param user 用户地址
     * @return 待领取奖励金额
     */
    function getPendingReward(address user) external view returns (uint256) {
        return _calcUserPending(user);
    }

    /**
     * @dev 获取普通NFT所有等级权重（用于前端显示）
     * @return weights 等级1-5的权重数组
     */
    function normalNFTWeight() external view returns (uint256[5] memory weights) {
        address nftDataAddr = IAuthorizer(authorizer).getNFTData();
        if (nftDataAddr == address(0)) {
            weights = StakingLib.getNormalNFTWeights();
            return weights;
        }
        try INFTData(nftDataAddr).getWeightByLevel(1, false) returns (uint256 w1) {
            weights[0] = w1;
        } catch {
            weights[0] = 1;
        }
        try INFTData(nftDataAddr).getWeightByLevel(2, false) returns (uint256 w2) {
            weights[1] = w2;
        } catch {
            weights[1] = 2;
        }
        try INFTData(nftDataAddr).getWeightByLevel(3, false) returns (uint256 w3) {
            weights[2] = w3;
        } catch {
            weights[2] = 6;
        }
        try INFTData(nftDataAddr).getWeightByLevel(4, false) returns (uint256 w4) {
            weights[3] = w4;
        } catch {
            weights[3] = 18;
        }
        try INFTData(nftDataAddr).getWeightByLevel(5, false) returns (uint256 w5) {
            weights[4] = w5;
        } catch {
            weights[4] = 66;
        }
    }

    /**
     * @dev 获取稀有NFT所有等级权重（用于前端显示）
     * @return weights 等级1-5的权重数组
     */
    function rareNFTWeight() external view returns (uint256[5] memory weights) {
        address nftDataAddr = IAuthorizer(authorizer).getNFTData();
        if (nftDataAddr == address(0)) {
            weights = StakingLib.getRareNFTWeights();
            return weights;
        }
        try INFTData(nftDataAddr).getWeightByLevel(1, true) returns (uint256 w1) {
            weights[0] = w1;
        } catch {
            weights[0] = 10;
        }
        try INFTData(nftDataAddr).getWeightByLevel(2, true) returns (uint256 w2) {
            weights[1] = w2;
        } catch {
            weights[1] = 12;
        }
        try INFTData(nftDataAddr).getWeightByLevel(3, true) returns (uint256 w3) {
            weights[2] = w3;
        } catch {
            weights[2] = 16;
        }
        try INFTData(nftDataAddr).getWeightByLevel(4, true) returns (uint256 w4) {
            weights[3] = w4;
        } catch {
            weights[3] = 28;
        }
        try INFTData(nftDataAddr).getWeightByLevel(5, true) returns (uint256 w5) {
            weights[4] = w5;
        } catch {
            weights[4] = 76;
        }
    }

    /**
     * @dev 内部函数：O(1)计算用户总待领取奖励
     * 公式：(G - Ai) * Wi / P = (G * ΣWi - Σ(Ai * Wi)) / PRECISION
     * 采用先乘后除方式，避免早期除法导致精度损失
     * @param user 用户地址
     * @return 用户总待领取奖励金额
     */
    function _calcUserPending(address user) internal view returns (uint256) {
        uint256 totalWeight = userStakedWeight[user];
        if (totalWeight == 0) return pendingRewards[user];

        uint256 snapshotBase = _userSnapshotWeight[user];
        
        // 修复：添加乘法溢出检查
        require(globalRewardPerWeight == 0 || totalWeight <= type(uint256).max / globalRewardPerWeight, "Staking: Reward calculation overflow");
        uint256 rewardBase = globalRewardPerWeight * totalWeight;

        if (rewardBase <= snapshotBase) return pendingRewards[user];
        
        uint256 earnedReward = (rewardBase - snapshotBase) / STAKING_REWARD_PRECISION;
        
        // 修复：添加加法溢出检查
        require(earnedReward <= type(uint256).max - pendingRewards[user], "Staking: Pending rewards overflow");
        return earnedReward + pendingRewards[user];
    }

    /**
     * @dev 暂停合约
     * @param reason 暂停原因描述
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /**
     * @dev 恢复合约
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 获取用户质押统计（Gas优化：使用用户级别O(1)公式计算待领取奖励）
     * @param user 用户地址
     * @return totalStaked NFT总数
     * @return totalPendingReward 待领取奖励
     * @return rareCount 稀有NFT数量
     * @return normalCount 普通NFT数量
     */
    function getUserStakingStats(address user) external view returns (
        uint256 totalStaked,
        uint256 totalPendingReward,
        uint256 rareCount,
        uint256 normalCount
    ) {
        uint256[] storage nfts = userStakedNFTs[user];
        totalStaked = nfts.length;
        totalPendingReward = _calcUserPending(user);
        rareCount = 0;
        normalCount = 0;
        
        for (uint256 i = 0; i < nfts.length; i++) {
            StakingInfo memory info = stakingInfo[nfts[i]];
            if (info.isRare) {
                rareCount++;
            } else {
                normalCount++;
            }
        }
    }

    /**
     * @dev 获取质押池统计
     * @return totalStakers 质押者总数
     * @return totalNFTs 质押NFT总数
     * @return todayIncoming 今日流入
     */
    function getPoolStats() external view returns (
        uint256 totalStakers,
        uint256 totalNFTs,
        uint256 todayIncoming
    ) {
        totalStakers = stakingUsers.length;
        totalNFTs = totalStakedNFTs;
        todayIncoming = todayIncomingTokens;
    }

    /**
     * @dev 获取用户在质押池中的排名（按质押时间）
     * @param user 用户地址
     * @return rank 排名（从1开始），0表示未质押
     */
    function getUserStakingRank(address user) external view returns (uint256 rank) {
        if (!isStakingUser[user]) {
            return 0;
        }
        uint256 index = stakingUserIndex[user];
        return index + 1;
    }

    /**
     * @dev 紧急提取BNB（仅owner，timelock后可用）
     * @param amount 提取金额
     */
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner nonReentrant {
        require(block.timestamp >= emergencyWithdrawUnlockTime, "Staking: Timelock not expired");
        require(amount > 0, "Staking: Amount must be > 0");
        require(amount <= address(this).balance, "Staking: Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Staking: BNB transfer failed");
        emergencyWithdrawUnlockTime = block.timestamp + emergencyWithdrawTimelock;
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取代币（仅owner，timelock后可用）
     * @param amount 提取金额
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner nonReentrant {
        require(block.timestamp >= emergencyWithdrawUnlockTime, "Staking: Timelock not expired");
        require(amount > 0, "Staking: Amount must be > 0");
        address rewardTokenContract = IAuthorizer(authorizer).getToken();
        require(rewardTokenContract != address(0), "Staking: Token contract not set");
        IERC20 token = IERC20(rewardTokenContract);
        require(token.balanceOf(address(this)) >= amount, "Staking: Insufficient token balance");
        token.safeTransfer(owner(), amount);
        emergencyWithdrawUnlockTime = block.timestamp + emergencyWithdrawTimelock;
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 设置紧急提取timelock
     * @param _timelock 新的timelock时间（秒）
     */
    function setEmergencyWithdrawTimelock(uint256 _timelock) external onlyOwner {
        require(_timelock >= 24 hours, "Staking: Timelock must be at least 24 hours");
        emergencyWithdrawTimelock = _timelock;
    }

    /**
     * @dev 安排紧急提取（重置timelock）
     */
    function scheduleEmergencyWithdraw() external onlyOwner {
        emergencyWithdrawUnlockTime = block.timestamp + emergencyWithdrawTimelock;
    }

    /**
     * @dev 清空合约内部的所有数据
     * 仅合约所有者和authorizer合约可调用
     * 用于紧急情况下重置整个项目数据
     * 注意：由于Solidity无法遍历mapping的所有键，此函数只重置核心状态变量
     */
    function resetContractData() external onlyOwnerOrAuthorizer {
        // 重置质押池统计
        totalStakedNFTs = 0;
        totalWeightedNFTs = 0;
        todayIncomingTokens = 0;
        globalRewardPerWeight = 0;

        // 重置紧急提取时间锁
        emergencyWithdrawUnlockTime = block.timestamp + emergencyWithdrawTimelock;

        // 重置最小质押等级
        minStakingLevel = 1;

        // 重置暂停状态
        paused = false;
        pauseReason = "";

        // 清空质押用户列表
        delete stakingUsers;

        // 发出数据重置事件
        emit ContractDataReset(msg.sender, block.timestamp);
    }

    /**
     * @dev 合约数据重置事件
     * @param operator 执行重置的操作者地址
     * @param timestamp 重置时间戳
     */
    event ContractDataReset(address indexed operator, uint256 timestamp);

    /**
     * @dev 同步权重到WeightManager和DividendManager（内部函数）
     * @param user 用户地址
     * @param tokenId NFT ID
     * @param nftContract NFT合约地址
     * @param isStaking true=质押操作（移除NFT），false=解除质押操作（添加NFT）
     */
    function _syncWeight(address user, uint256 tokenId, address nftContract, bool isStaking) internal {
        address nftDataContract = IAuthorizer(authorizer).getNFTData();
        if (nftDataContract != address(0)) {
            if (isStaking) {
                try INFTDataInterface(nftDataContract).removeUserNFT(user, tokenId) {
                } catch {
                }
            } else {
                try INFTDataInterface(nftDataContract).addUserNFT(user, tokenId) {
                } catch {
                }
            }
        }
        
        address weightManager = IAuthorizer(authorizer).getWeightManager();
        if (weightManager != address(0)) {
            try IWeightManager(weightManager).syncUserWeight(user) {
            } catch {
            }
        }
        
        address dividendManager = IAuthorizer(authorizer).getDividendManager();
        if (dividendManager != address(0)) {
            try IDividendManager(dividendManager).syncUserWeight(user) {
            } catch {
            }
        }
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
