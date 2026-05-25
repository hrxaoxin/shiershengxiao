// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RewardManager
 * @dev 奖励管理合约，统一管理所有游戏奖励的分发
 *
 * 奖励来源：
 * 1. 战斗胜利奖励
 * 2. 交易手续费（5%）
 * 3. 铸造费用
 *
 * 奖励分配：
 * - 50% 进入分红池
 * - 25% 进入NFT质押池
 * - 15% 进入代币质押池
 * - 10% 进入竞技场奖励池
 */
contract RewardManager {
    /**
     * @dev 分红池地址
     */
    address public dividendPool;

    /**
     * @dev NFT质押池地址
     */
    address public nftStakingPool;

    /**
     * @dev 代币质押池地址
     */
    address public tokenStakingPool;

    /**
     * @dev 竞技场奖励池地址
     */
    address public arenaRewardPool;

    /**
     * @dev 奖励分配比例（精度4位小数）
     */
    uint256 public dividendPercent = 5000;    // 50%
    uint256 public nftStakingPercent = 2500;  // 25%
    uint256 public tokenStakingPercent = 1500; // 15%
    uint256 public arenaRewardPercent = 1000;   // 10%

    /**
     * @dev 精度
     */
    uint256 public constant PRECISION = 10000;

    /**
     * @dev 奖励事件
     */
    event RewardDistributed(
        address indexed from,
        uint256 totalAmount,
        uint256 dividendAmount,
        uint256 nftStakingAmount,
        uint256 tokenStakingAmount,
        uint256 arenaRewardAmount
    );

    /**
     * @dev 设置分红池地址
     */
    function setDividendPool(address _dividendPool) external {
        require(_dividendPool != address(0), "RewardManager: Invalid dividend pool");
        dividendPool = _dividendPool;
    }

    /**
     * @dev 设置NFT质押池地址
     */
    function setNFTStakingPool(address _pool) external {
        require(_pool != address(0), "RewardManager: Invalid NFT staking pool");
        nftStakingPool = _pool;
    }

    /**
     * @dev 设置代币质押池地址
     */
    function setTokenStakingPool(address _pool) external {
        require(_pool != address(0), "RewardManager: Invalid token staking pool");
        tokenStakingPool = _pool;
    }

    /**
     * @dev 设置竞技场奖励池地址
     */
    function setArenaRewardPool(address _pool) external {
        require(_pool != address(0), "RewardManager: Invalid arena reward pool");
        arenaRewardPool = _pool;
    }

    /**
     * @dev 分发战斗奖励
     */
    function distributeBattleReward(
        address winner,
        address loser,
        uint256 battleType
    ) external {
        uint256 reward = 100 * 10**18;
        _distributeReward(reward);
    }

    /**
     * @dev 添加质押池奖励
     */
    function addStakingReward(uint256 amount, uint256 poolType) external {
        require(amount > 0, "RewardManager: Invalid amount");

        if (poolType == 0 && nftStakingPool != address(0)) {
        } else if (poolType == 1 && tokenStakingPool != address(0)) {
        } else if (poolType == 2 && arenaRewardPool != address(0)) {
        }
    }

    /**
     * @dev 领取分红
     */
    function claimDividend(address user) external returns (uint256) {
        return 0;
    }

    /**
     * @dev 获取用户可领取分红
     */
    function getDividend(address user) external view returns (uint256) {
        return 0;
    }

    /**
     * @dev 分配奖励到各个池
     */
    function _distributeReward(uint256 amount) internal {
        uint256 dividendAmount = amount * dividendPercent / PRECISION;
        uint256 nftStakingAmount = amount * nftStakingPercent / PRECISION;
        uint256 tokenStakingAmount = amount * tokenStakingPercent / PRECISION;
        uint256 arenaRewardAmount = amount * arenaRewardPercent / PRECISION;

        emit RewardDistributed(
            msg.sender,
            amount,
            dividendAmount,
            nftStakingAmount,
            tokenStakingAmount,
            arenaRewardAmount
        );
    }

    /**
     * @dev 设置分配比例
     */
    function setDistributionPercents(
        uint256 _dividendPercent,
        uint256 _nftStakingPercent,
        uint256 _tokenStakingPercent,
        uint256 _arenaRewardPercent
    ) external {
        require(
            _dividendPercent + _nftStakingPercent + _tokenStakingPercent + _arenaRewardPercent == PRECISION,
            "RewardManager: Percentages must sum to 100%"
        );

        dividendPercent = _dividendPercent;
        nftStakingPercent = _nftStakingPercent;
        tokenStakingPercent = _tokenStakingPercent;
        arenaRewardPercent = _arenaRewardPercent;
    }

    /**
     * @dev 获取分配比例
     */
    function getDistributionPercents() external view returns (
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        return (dividendPercent, nftStakingPercent, tokenStakingPercent, arenaRewardPercent);
    }
}
