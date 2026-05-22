// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTMintDelegator
 * @dev 十二生肖NFT合约的公共逻辑库
 * 将NFTMint中的重函数体迁移至此，通过DELEGATECALL调用，避免bytecode内联膨胀。
 * 
 * 设计原理：
 * - public 函数不会被编译器内联到调用合约中，大幅缩减主合约bytecode大小
 * - DELEGATECALL 保持调用合约的存储上下文，库可读写主合约存储
 * - 需要 ERC721 internal 函数时，通过 INFTMintDelegator 接口回调主合约的薄封装函数
 */
import "./NFTDataType.sol";
import "./NFTInterface.sol";

/**
 * @dev MintModule 接口
 */
interface IMintModule {
    function generateNormalType() external returns (NFTDataTypes.ZodiacType t, uint256 growth);
    function generateRareType() external returns (NFTDataTypes.ZodiacType t, uint256 growth);
    function generateTenNormalTypes() external returns (NFTDataTypes.ZodiacType[] memory types, uint256[] memory growthValues);
    function generateTenRareTypes() external returns (NFTDataTypes.ZodiacType[] memory types, uint256[] memory growthValues);
    function generateGrowth() external returns (uint256 growth);
}

/**
 * @dev UpgradeModule 接口
 */
interface IUpgradeModule {
    function findBurnCandidates(address user, uint256 tokenId) external view returns (uint256[] memory);
    function hasEnoughBurns(address user, uint256 tokenId) external view returns (bool);
    function getTokenUpgradeCost(uint8 lv) external view returns (uint256);
    function getUSDUpgradeValue(uint8 lv) external view returns (uint256);
}

/**
 * @dev NFTMint 主合约需要实现的薄封装接口
 * 库通过此接口回调 ERC721Upgradeable 的 internal 函数
 */
interface INFTMintDelegator {
    function delegator_safeMint(address to, uint256 tokenId) external;
    function delegator_safeTransfer(address from, address to, uint256 tokenId) external;
    function delegator_ownerOf(uint256 tokenId) external view returns (address);
}

library NFTMintDelegator {

    // ====================== Events ======================

    event CardMinted(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, address indexed owner, uint64 timestamp);
    event CardBurned(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, address indexed owner);
    event CardUpgraded(uint256 indexed cardId, NFTDataTypes.ZodiacType indexed cardType, uint8 oldLevel, uint8 newLevel, address indexed owner, uint64 timestamp);
    event TenCardsMinted(uint256[] indexed tokenIds, address indexed owner, bool isNormal, uint64 timestamp);
    event TargetedMintCompleted(uint256[] indexed tokenIds, address indexed owner, NFTDataTypes.BaseZodiac indexed baseZodiac, uint64 timestamp);
    event RewardUpdateFailed(address indexed user, NFTDataTypes.ZodiacType indexed zodiacType, uint256 count, bool add);

    // ====================== Mint ======================

    /**
     * @dev 核心单铸逻辑（原 _mintRaw）
     * @param self NFTMint主合约地址
     * @param metadataContract 元数据合约地址
     * @param currentId 当前 nextCardId 值（将被递增）
     * @param to 接收地址
     * @param t 生肖类型
     * @param growthValue 成长值
     * @return tokenId 新NFT ID
     * @return newNextId 递增后的 nextCardId
     */
    function mintRaw(
        address self,
        address metadataContract,
        uint256 currentId,
        address to,
        NFTDataTypes.ZodiacType t,
        uint256 growthValue
    ) public returns (uint256 tokenId, uint256 newNextId) {
        tokenId = currentId;
        newNextId = currentId + 1;
        INFTDataInterface m = INFTDataInterface(metadataContract);
        m.setTokenType(tokenId, t);
        m.setTokenLevel(tokenId, 1);
        m.setTokenGrowthValue(tokenId, growthValue);
        m.addUserToken(to, t, tokenId);
        INFTMintDelegator(self).delegator_safeMint(to, tokenId);
        updateUserWeight(metadataContract, to, tokenId, 1, true);
        emit CardMinted(tokenId, t, to, uint64(block.timestamp));
    }

    /**
     * @dev 批量铸造内部逻辑（原 _mintBatchRaw）
     * @param self NFTMint主合约地址
     * @param metadataContract 元数据合约地址
     * @param startId 起始 nextCardId 值
     * @param to 接收地址
     * @param types 类型数组
     * @param growthValues 成长值数组
     * @param isNormal 是否普通铸造
     * @return tokenIds 新NFT ID数组
     * @return newNextId 最终 nextCardId
     */
    function mintBatchRaw(
        address self,
        address metadataContract,
        uint256 startId,
        address to,
        NFTDataTypes.ZodiacType[] memory types,
        uint256[] memory growthValues,
        bool isNormal
    ) public returns (uint256[] memory tokenIds, uint256 newNextId) {
        uint256 len = types.length;
        tokenIds = new uint256[](len);
        uint256 currentId = startId;
        INFTDataInterface m = INFTDataInterface(metadataContract);

        // 先分配所有 ID
        for (uint i = 0; i < len; i++) {
            tokenIds[i] = currentId++;
        }

        // 再逐个铸造
        for (uint i = 0; i < len; i++) {
            uint256 id = tokenIds[i];
            NFTDataTypes.ZodiacType t = types[i];
            m.setTokenType(id, t);
            m.setTokenLevel(id, 1);
            m.setTokenGrowthValue(id, growthValues[i]);
            m.addUserToken(to, t, id);
            INFTMintDelegator(self).delegator_safeMint(to, id);
            updateUserWeight(metadataContract, to, id, 1, true);
        }

        newNextId = currentId;
        emit TenCardsMinted(tokenIds, to, isNormal, uint64(block.timestamp));
    }

    /**
     * @dev 指定铸造全逻辑（原 mintTargeted）
     * @param self NFTMint主合约地址
     * @param metadataContract 元数据合约地址
     * @param mintModule 铸造模块地址
     * @param startId 起始 nextCardId 值
     * @param to 接收地址
     * @param baseZodiac 目标生肖
     * @return tokenIds 新NFT ID数组(10个)
     * @return newNextId 最终 nextCardId
     */
    function mintTargetedLogic(
        address self,
        address metadataContract,
        address mintModule,
        uint256 startId,
        address to,
        NFTDataTypes.BaseZodiac baseZodiac
    ) public returns (uint256[] memory tokenIds, uint256 newNextId) {
        require(uint256(baseZodiac) < 12, "E28: Invalid zodiac");

        tokenIds = new uint256[](10);
        uint256 currentId = startId;
        uint256 zodiacIndex = uint256(baseZodiac) * 2;

        for (uint i = 0; i < 5; i++) {
            uint256 baseIndex = i * 24 + zodiacIndex;
            uint256 growth0 = mintModule != address(0) ? IMintModule(mintModule).generateGrowth() : 50;
            uint256 growth1 = mintModule != address(0) ? IMintModule(mintModule).generateGrowth() : 50;
            (tokenIds[i * 2], currentId) = mintRaw(self, metadataContract, currentId, to, NFTDataTypes.ZodiacType(baseIndex), growth0);
            (tokenIds[i * 2 + 1], currentId) = mintRaw(self, metadataContract, currentId, to, NFTDataTypes.ZodiacType(baseIndex + 1), growth1);
        }

        newNextId = currentId;
        emit TargetedMintCompleted(tokenIds, to, baseZodiac, uint64(block.timestamp));
    }

    // ====================== Reward ======================

    /**
     * @dev 更新奖励管理器中的用户卡牌计数（原 _updateReward）
     * @param rewardManager 奖励管理器地址
     * @param u 用户地址
     * @param t 生肖类型
     * @param add 是否增加
     */
    function updateReward(address rewardManager, address u, NFTDataTypes.ZodiacType t, bool add) public {
        if (rewardManager == address(0)) return;
        IRewardManager rm = IRewardManager(rewardManager);
        uint cnt = rm.cardCount(u, t);
        uint n = add ? cnt + 1 : (cnt > 0 ? cnt - 1 : 0);
        try rm.updateCardExternal(u, t, n) returns (bool success) {
            if (!success) {
                emit RewardUpdateFailed(u, t, n, add);
            }
        } catch {
            emit RewardUpdateFailed(u, t, n, add);
        }
    }

    // ====================== Weight ======================

    /**
     * @dev 更新用户权重缓存（原 _updateUserWeight）
     * @param metadataContract 元数据合约地址
     * @param user 用户地址
     * @param tokenId NFT ID
     * @param level 等级
     * @param add 是否增加
     */
    function updateUserWeight(address metadataContract, address user, uint256 tokenId, uint8 level, bool add) public {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ZodiacType t = m.tokenType(tokenId);
        NFTDataTypes.ElementType element = NFTDataTypes.getElement(t);
        m.updateUserWeight(user, level, add, element);
    }

    // ====================== Upgrade ======================

    /**
     * @dev 使用NFT升级全逻辑（原 upgradeWithNFT）
     * @param self NFTMint主合约地址
     * @param metadataContract 元数据合约地址
     * @param upgradeModule 升级模块地址
     * @param tokenId 要升级的NFT ID
     * @param msgSender 调用者地址（msg.sender）
     * @param BLACK_HOLE 黑洞地址常量
     * @return newLv 新等级
     */
    function upgradeWithNFTLogic(
        address self,
        address metadataContract,
        address upgradeModule,
        uint256 tokenId,
        address msgSender,
        address BLACK_HOLE
    ) public returns (uint8 newLv) {
        require(INFTMintDelegator(self).delegator_ownerOf(tokenId) == msgSender, "E15");
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ZodiacType t = m.tokenType(tokenId);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16");
        require(upgradeModule != address(0), "Module not set");

        uint256[] memory burnCandidates = IUpgradeModule(upgradeModule).findBurnCandidates(msgSender, tokenId);
        uint req = lv;

        for (uint i = 0; i < req; i++) {
            INFTMintDelegator(self).delegator_safeTransfer(msgSender, BLACK_HOLE, burnCandidates[i]);
            emit CardBurned(burnCandidates[i], t, msgSender);
        }

        newLv = lv + 1;
        m.setTokenLevel(tokenId, newLv);
        updateUserWeight(metadataContract, msgSender, tokenId, lv, false);
        updateUserWeight(metadataContract, msgSender, tokenId, newLv, true);
        emit CardUpgraded(tokenId, t, lv, newLv, msgSender, uint64(block.timestamp));
    }

    /**
     * @dev 使用代币升级全逻辑（原 upgradeWithToken）
     * @param self NFTMint主合约地址
     * @param metadataContract 元数据合约地址
     * @param upgradeModule 升级模块地址
     * @param tokenContract 代币合约地址
     * @param tokenId 要升级的NFT ID
     * @param msgSender 调用者地址
     * @param BLACK_HOLE 黑洞地址常量
     * @return newLv 新等级
     */
    function upgradeWithTokenLogic(
        address self,
        address metadataContract,
        address upgradeModule,
        address tokenContract,
        uint256 tokenId,
        address msgSender,
        address BLACK_HOLE
    ) public returns (uint8 newLv) {
        require(INFTMintDelegator(self).delegator_ownerOf(tokenId) == msgSender, "E15");
        require(tokenContract != address(0), "E7");
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16");
        require(upgradeModule != address(0), "Module not set");

        uint256 cost = IUpgradeModule(upgradeModule).getTokenUpgradeCost(lv);
        IToken t = IToken(tokenContract);
        require(t.balanceOf(msgSender) >= cost, "E8");
        require(t.transferFrom(msgSender, BLACK_HOLE, cost), "E9");

        return upgradeLevel(self, metadataContract, tokenId, lv, msgSender);
    }

    /**
     * @dev 使用USD价值升级全逻辑（原 upgradeWithUSDValue）
     * @param self NFTMint主合约地址
     * @param metadataContract 元数据合约地址
     * @param upgradeModule 升级模块地址
     * @param tokenContract 代币合约地址
     * @param priceOracle 价格预言机地址
     * @param tokenId 要升级的NFT ID
     * @param msgSender 调用者地址
     * @param BLACK_HOLE 黑洞地址常量
     * @return newLv 新等级
     */
    function upgradeWithUSDValueLogic(
        address self,
        address metadataContract,
        address upgradeModule,
        address tokenContract,
        address priceOracle,
        uint256 tokenId,
        address msgSender,
        address BLACK_HOLE
    ) public returns (uint8 newLv) {
        require(INFTMintDelegator(self).delegator_ownerOf(tokenId) == msgSender, "E15");
        require(tokenContract != address(0) && priceOracle != address(0), "E19");
        INFTDataInterface m = INFTDataInterface(metadataContract);
        uint8 lv = m.tokenLevel(tokenId);
        require(lv < 5, "E16");
        require(upgradeModule != address(0), "Module not set");

        uint256 usdValue = IUpgradeModule(upgradeModule).getUSDUpgradeValue(lv);
        uint256 price = IPriceOracle(priceOracle).getAndUpdatePrice();
        require(price > 0, "E20: Price oracle returned zero");

        uint256 cost = (usdValue * 1e18) / price;
        require(cost > 0, "E21");

        IToken t = IToken(tokenContract);
        require(t.balanceOf(msgSender) >= cost, "E8");
        require(t.transferFrom(msgSender, BLACK_HOLE, cost), "E9");

        return upgradeLevel(self, metadataContract, tokenId, lv, msgSender);
    }

    /**
     * @dev 升级等级内部逻辑（原 _upgradeLevel）
     * @param self NFTMint主合约地址
     * @param metadataContract 元数据合约地址
     * @param id NFT ID
     * @param oldLv 当前等级
     * @param msgSender 调用者地址
     * @return newLv 新等级
     */
    function upgradeLevel(
        address self,
        address metadataContract,
        uint256 id,
        uint8 oldLv,
        address msgSender
    ) public returns (uint8 newLv) {
        INFTDataInterface m = INFTDataInterface(metadataContract);
        NFTDataTypes.ZodiacType t = m.tokenType(id);
        newLv = oldLv + 1;
        m.setTokenLevel(id, newLv);
        updateUserWeight(metadataContract, msgSender, id, oldLv, false);
        updateUserWeight(metadataContract, msgSender, id, newLv, true);
        emit CardUpgraded(id, t, oldLv, newLv, msgSender, uint64(block.timestamp));
    }
}
