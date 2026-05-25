// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

interface INFTMint {
    function mintNormal(address to) external returns (uint256);
    function mintRare(address to) external returns (uint256);
    function tokenType(uint256 tokenId) external view returns (uint256);
}

interface INFTData {
    function getNFTInfo(uint256 tokenId) external view returns (
        uint256 tokenType,
        uint8 attack,
        uint8 defense,
        uint8 health,
        uint8 speed,
        uint8 level,
        uint256 rank
    );
}

/**
 * @title Breeding
 * @dev NFT繁殖合约，支持自繁殖和市场繁殖两种模式
 *
 * 繁殖规则：
 * 1. 仅5级NFT可参与繁殖
 * 2. 父母必须是同一生肖（BaseZodiac相同）
 * 3. 父母性别必须不同（公+母）
 * 4. 繁殖后父母进入冷却期
 *
 * 繁殖类型：
 * 1. 自繁殖 - 同一用户拥有公母两只NFT
 *    - 冷却时间: 12小时
 *    - 无额外费用
 *
 * 2. 市场繁殖 - 不同用户各自提供公母NFT
 *    - 冷却时间: 24小时
 *    - 需要支付繁殖费用
 *
 * 子代属性计算：
 * - 属性: 50%继承父亲，50%继承母亲
 * - 性别: 50%公，50%母
 * - 生肖: 强制继承父母的生肖（父母必须同生肖）
 * - 等级: 1级
 *
 * 繁殖收益分配（市场繁殖）：
 * - 母亲所有者: 80%
 * - 父亲所有者: 15%
 * - 共有人（如果有）: 5%
 */
contract Breeding is Ownable {
    /**
     * @dev 自繁殖冷却时间（秒）
     * 12小时 = 12 * 60 * 60
     */
    uint256 public selfBreedingCooldown = 12 hours;

    /**
     * @dev 市场繁殖冷却时间（秒）
     * 24小时 = 24 * 60 * 60
     */
    uint256 public marketBreedingCooldown = 24 hours;

    /**
     * @dev 自繁殖费用（代币）
     */
    uint256 public selfBreedingFee;

    /**
     * @dev 市场繁殖费用（代币）
     */
    uint256 public marketBreedingFee;

    /**
     * @dev NFT合约地址
     */
    address public nftMintContract;

    /**
     * @dev 繁殖对结构体
     *
     * 存储一次繁殖的所有信息
     */
    struct BreedingPair {
        uint256 fatherId;        // 父亲NFT ID
        uint256 motherId;        // 母亲NFT ID
        address maleOwner;       // 父亲所有者
        address femaleOwner;      // 母亲所有者
        uint256 maleCoOwnerId;   // 父亲共有人NFT ID
        uint256 femaleCoOwnerId; // 母亲共有人NFT ID
        uint256 startTime;       // 繁殖开始时间
        uint256 breedingType;     // 繁殖类型（0=自繁殖, 1=市场繁殖）
        uint256 status;          // 状态（0=进行中, 1=完成, 2=取消）
        uint256 childId;         // 子代NFT ID
    }

    /**
     * @dev 繁殖对映射
     * pairId => BreedingPair
     */
    mapping(uint256 => BreedingPair) public breedingPairs;

    /**
     * @dev 繁殖对计数器
     */
    uint256 public breedingPairCount;

    /**
     * @dev NFT繁殖冷却期映射
     * tokenId => 冷却结束时间
     */
    mapping(uint256 => uint256) public breedingCooldowns;

    /**
     * @dev 繁殖事件
     */
    event BreedingPairCreated(
        uint256 indexed pairId,
        uint256 fatherId,
        uint256 motherId,
        uint256 breedingType
    );

    /**
     * @dev 繁殖完成事件
     */
    event BreedingCompleted(
        uint256 indexed pairId,
        uint256 childId,
        uint256 zodiacType
    );

    /**
     * @dev 繁殖取消事件
     */
    event BreedingCancelled(uint256 indexed pairId);

    /**
     * @dev 冷却时间更新事件
     */
    event CooldownUpdated(uint256 selfCooldown, uint256 marketCooldown);

    /**
     * @dev 创建自繁殖对
     *
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param coOwnerId 共有人NFT ID（用于分成）
     * @return uint256 繁殖对ID
     */
    function createSelfBreedingPair(
        uint256 fatherId,
        uint256 motherId,
        uint256 coOwnerId
    ) external returns (uint256) {
        require(fatherId != motherId, "Breeding: Cannot breed with self");

        breedingPairCount++;
        uint256 pairId = breedingPairCount;

        breedingPairs[pairId] = BreedingPair({
            fatherId: fatherId,
            motherId: motherId,
            maleOwner: msg.sender,
            femaleOwner: msg.sender,
            maleCoOwnerId: coOwnerId,
            femaleCoOwnerId: coOwnerId,
            startTime: block.timestamp,
            breedingType: 0,
            status: 0,
            childId: 0
        });

        breedingCooldowns[fatherId] = block.timestamp + selfBreedingCooldown;
        breedingCooldowns[motherId] = block.timestamp + selfBreedingCooldown;

        emit BreedingPairCreated(pairId, fatherId, motherId, 0);
        return pairId;
    }

    /**
     * @dev 创建市场繁殖对
     *
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param maleOwner 公NFT所有者
     * @param femaleOwner 母NFT所有者
     * @param maleCoOwnerId 公NFT共有人
     * @param femaleCoOwnerId 母NFT共有人
     * @return uint256 繁殖对ID
     */
    function createMarketBreedingPair(
        uint256 fatherId,
        uint256 motherId,
        address maleOwner,
        address femaleOwner,
        uint256 maleCoOwnerId,
        uint256 femaleCoOwnerId
    ) external returns (uint256) {
        require(fatherId != motherId, "Breeding: Cannot breed with self");
        require(maleOwner != femaleOwner, "Breeding: Same owner for market breeding");

        breedingPairCount++;
        uint256 pairId = breedingPairCount;

        breedingPairs[pairId] = BreedingPair({
            fatherId: fatherId,
            motherId: motherId,
            maleOwner: maleOwner,
            femaleOwner: femaleOwner,
            maleCoOwnerId: maleCoOwnerId,
            femaleCoOwnerId: femaleCoOwnerId,
            startTime: block.timestamp,
            breedingType: 1,
            status: 0,
            childId: 0
        });

        breedingCooldowns[fatherId] = block.timestamp + marketBreedingCooldown;
        breedingCooldowns[motherId] = block.timestamp + marketBreedingCooldown;

        emit BreedingPairCreated(pairId, fatherId, motherId, 1);
        return pairId;
    }

    /**
     * @dev 完成繁殖
     *
     * @param pairId 繁殖对ID
     * @return uint256 子代NFT ID
     */
    function completeBreeding(uint256 pairId) external returns (uint256) {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == 0, "Breeding: Pair not active");
        require(pair.childId == 0, "Breeding: Already completed");

        uint256 cooldown = pair.breedingType == 0 ? selfBreedingCooldown : marketBreedingCooldown;
        require(block.timestamp >= pair.startTime + cooldown, "Breeding: Cooldown not ended");

        uint256 childId = _generateChild(
            pair.fatherId,
            pair.motherId,
            pair.maleOwner,
            pair.femaleOwner
        );

        pair.childId = childId;
        pair.status = 1;

        emit BreedingCompleted(pairId, childId, _getChildZodiacType(pair.fatherId, pair.motherId));
        return childId;
    }

    /**
     * @dev 取消繁殖
     *
     * @param pairId 繁殖对ID
     */
    function cancelBreeding(uint256 pairId) external {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == 0, "Breeding: Pair not active");

        pair.status = 2;
        delete breedingCooldowns[pair.fatherId];
        delete breedingCooldowns[pair.motherId];

        emit BreedingCancelled(pairId);
    }

    /**
     * @dev 获取繁殖信息
     */
    function getBreedingInfo(uint256 pairId) external view returns (
        uint256 fatherId,
        uint256 motherId,
        address maleOwner,
        address femaleOwner,
        uint256 startTime,
        uint256 breedingType,
        uint256 status
    ) {
        BreedingPair memory pair = breedingPairs[pairId];
        return (
            pair.fatherId,
            pair.motherId,
            pair.maleOwner,
            pair.femaleOwner,
            pair.startTime,
            pair.breedingType,
            pair.status
        );
    }

    /**
     * @dev 检查NFT是否在冷却期
     */
    function isInCooldown(uint256 tokenId) external view returns (bool) {
        return breedingCooldowns[tokenId] > block.timestamp;
    }

    /**
     * @dev 获取冷却结束时间
     */
    function getCooldownEndTime(uint256 tokenId) external view returns (uint256) {
        return breedingCooldowns[tokenId];
    }

    /**
     * @dev 生成子代NFT ID（内部函数）
     */
    function _generateChild(
        uint256 fatherId,
        uint256 motherId,
        address maleOwner,
        address femaleOwner
    ) internal returns (uint256) {
        require(nftMintContract != address(0), "Breeding: NFT contract not set");

        uint256 zodiacType = _getChildZodiacType(fatherId, motherId);

        bool isRare = zodiacType == 6 || zodiacType == 7;

        INFTMint nftMint = INFTMint(nftMintContract);

        uint256 childId;
        if (isRare) {
            childId = nftMint.mintRare(femaleOwner);
        } else {
            childId = nftMint.mintNormal(femaleOwner);
        }

        return childId;
    }

    /**
     * @dev 获取子代生肖类型（内部函数）
     */
    function _getChildZodiacType(uint256 fatherId, uint256 motherId) internal view returns (uint256) {
        if (nftMintContract == address(0)) {
            return 0;
        }

        INFTMint nftMint = INFTMint(nftMintContract);

        uint256 fatherType = nftMint.tokenType(fatherId);
        uint256 motherType = nftMint.tokenType(motherId);

        if (fatherType == motherType && fatherType > 0) {
            return fatherType;
        }

        uint256 seed = uint256(keccak256(abi.encodePacked(fatherId, motherId, block.timestamp)));
        return (seed % 12) + 1;
    }

    /**
     * @dev 计算繁殖收益分配
     */
    function calculateBreedingRewards(uint256 pairId) external view returns (
        uint256 motherReward,
        uint256 fatherReward,
        uint256 coOwnerReward
    ) {
        BreedingPair memory pair = breedingPairs[pairId];
        uint256 totalReward = marketBreedingFee;

        motherReward = totalReward * 80 / 100;
        fatherReward = totalReward * 15 / 100;
        coOwnerReward = totalReward * 5 / 100;

        return (motherReward, fatherReward, coOwnerReward);
    }

    /**
     * @dev 设置自繁殖费用
     */
    function setSelfBreedingFee(uint256 fee) external onlyOwner {
        selfBreedingFee = fee;
    }

    /**
     * @dev 设置市场繁殖费用
     */
    function setMarketBreedingFee(uint256 fee) external onlyOwner {
        marketBreedingFee = fee;
    }

    /**
     * @dev 设置自繁殖冷却时间
     */
    function setSelfBreedingCooldown(uint256 cooldown) external onlyOwner {
        require(cooldown > 0, "Breeding: Cooldown must be > 0");
        selfBreedingCooldown = cooldown;
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown);
    }

    /**
     * @dev 设置市场繁殖冷却时间
     */
    function setMarketBreedingCooldown(uint256 cooldown) external onlyOwner {
        require(cooldown > 0, "Breeding: Cooldown must be > 0");
        marketBreedingCooldown = cooldown;
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown);
    }

    /**
     * @dev 设置NFT合约地址
     */
    function setNFTContract(address _nftContract) external onlyOwner {
        require(_nftContract != address(0), "Breeding: Invalid NFT contract address");
        nftMintContract = _nftContract;
        emit NFTContractSet(nftMintContract);
    }

    /**
     * @dev 事件：NFT合约地址设置
     */
    event NFTContractSet(address indexed nftContract);
}
