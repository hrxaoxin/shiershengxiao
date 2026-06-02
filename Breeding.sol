// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/ReentrancyGuardUpgradeable.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

contract Breeding is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    uint256 public selfBreedingCooldown = 12 hours;
    uint256 public marketBreedingCooldown = 24 hours;
    uint256 public selfBreedingFee = 100 * 1e18;
    uint256 public marketBreedingFee = 500 * 1e18;
    address public nftMintContract;
    address public authorizer;
    address public tokenContract;
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    
    uint256 public maxDailyPublicBreedings = 5;
    mapping(address => uint256) public dailyPublicBreedings;
    mapping(address => uint256) public lastBreedingDay;

    bool public paused;
    string public pauseReason;

    struct BreedingPair {
        uint256 fatherId;
        uint256 motherId;
        address maleOwner;
        address femaleOwner;
        uint256 maleCoOwnerId;
        uint256 femaleCoOwnerId;
        uint256 startTime;
        uint256 breedingType;
        uint256 status;
        uint256 childId;
        uint256 maleChildId;
        bool rewardsClaimed;
    }

    struct MarketListing { 
        uint256 tokenId; 
        address owner; 
        uint256 listTime; 
        bool isActive; 
    }

    mapping(uint256 => BreedingPair) public breedingPairs;
    uint256 public breedingPairCount;
    mapping(uint256 => uint256) public breedingCooldowns;
    mapping(uint256 => bool) public isNFTInActiveBreeding;
    mapping(uint256 => MarketListing) public marketListings;
    uint256[] public listedTokenIds;

    event BreedingPairCreated(uint256 indexed pairId, uint256 fatherId, uint256 motherId, uint256 breedingType);
    event BreedingCompleted(uint256 indexed pairId, uint256 childId, uint256 zodiacType);
    event MaleChildGenerated(uint256 indexed pairId, uint256 childId);
    event BreedingCancelled(uint256 indexed pairId);
    event CooldownUpdated(uint256 selfCooldown, uint256 marketCooldown);
    event BreedingFeeBurned(uint256 amount);
    event Paused(address account, string reason);
    event Unpaused(address account);
    event NFTContractSet(address indexed nftContract);
    event TokenContractSet(address indexed tokenContract);
    event EmergencyNFTLocked(uint256 indexed tokenId, address indexed owner);
    event MarketListingCreated(uint256 indexed tokenId, address indexed owner);
    event MarketListingRemoved(uint256 indexed tokenId);
    event EmergencyBNBWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed operator, address indexed to, uint256 amount);
    event EmergencyNFTWithdrawn(address indexed operator, address indexed to, uint256 tokenId);

    modifier whenNotPaused() {
        require(!paused, "Breeding: Paused");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizer, "Breeding: Not authorized");
        _;
    }

    /**
     * @dev 初始化合约
     * @param _authorizer 授权器合约地址
     */
    function initialize(address _authorizer) external initializer {
        require(_authorizer != address(0), "Breeding: Invalid authorizer address");
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        authorizer = _authorizer;
    }

    /**
     * @dev 设置授权器地址
     * @param a 新的授权器地址
     */
    function setAuthorizer(address a) external onlyOwner { 
        authorizer = a; 
    }

    /**
     * @dev 授权升级
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 暂停合约
     * @param reason 暂停原因
     */
    function pause(string memory reason) external onlyOwner {
        paused = true;
        pauseReason = reason;
        emit Paused(msg.sender, reason);
    }

    /**
     * @dev 取消暂停
     */
    function unpause() external onlyOwner {
        paused = false;
        pauseReason = "";
        emit Unpaused(msg.sender);
    }

    /**
     * @dev 创建自己的NFT繁殖对（玩家用自己的两个NFT繁殖）
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param coOwnerId 共同所有者NFT ID（可选）
     * @return pairId 繁殖对ID
     */
    function createSelfBreedingPair(uint256 fatherId, uint256 motherId, uint256 coOwnerId) external nonReentrant whenNotPaused returns (uint256) {
        require(fatherId != motherId, "Breeding: Cannot breed with self");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        require(!isNFTInActiveBreeding[fatherId], "Breeding: Father already in breeding");
        require(!isNFTInActiveBreeding[motherId], "Breeding: Mother already in breeding");
        INFTMint nft = INFTMint(nftMintContract);

        require(nft.ownerOf(fatherId) == msg.sender, "Breeding: Not father owner");
        require(nft.ownerOf(motherId) == msg.sender, "Breeding: Not mother owner");
        require(nft.tokenLevel(fatherId) >= 5 && nft.tokenLevel(motherId) >= 5, "Breeding: Level < 5");

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);
        require((fatherType / 2) % 12 == (motherType / 2) % 12, "Breeding: Different zodiac");
        require((fatherType % 2) != (motherType % 2), "Breeding: Same gender");

        require(breedingCooldowns[fatherId] <= block.timestamp, "Breeding: Father in cooldown");
        require(breedingCooldowns[motherId] <= block.timestamp, "Breeding: Mother in cooldown");

        if (coOwnerId > 0) {
            require(nft.ownerOf(coOwnerId) == msg.sender, "Breeding: Not co-owner owner");
            require(!isNFTInActiveBreeding[coOwnerId], "Breeding: Co-owner already in breeding");
        }

        if (selfBreedingFee > 0) {
            require(tokenContract != address(0), "Breeding: Token contract not set");
            require(IERC20(tokenContract).transferFrom(msg.sender, address(this), selfBreedingFee), "Breeding: Fee transfer failed");
        }

        breedingPairCount++;
        uint256 pairId = breedingPairCount;
        breedingPairs[pairId] = BreedingPair({
            fatherId: fatherId, motherId: motherId, maleOwner: msg.sender, femaleOwner: msg.sender,
            maleCoOwnerId: coOwnerId, femaleCoOwnerId: coOwnerId, startTime: block.timestamp,
            breedingType: 0, status: 0, childId: 0, maleChildId: 0, rewardsClaimed: false
        });

        try nft.safeTransferFrom(msg.sender, address(this), fatherId) {
        } catch {
            revert("Breeding: Father NFT transfer failed");
        }
        
        try nft.safeTransferFrom(msg.sender, address(this), motherId) {
        } catch {
            try nft.safeTransferFrom(address(this), msg.sender, fatherId) {
            } catch {
                emit EmergencyNFTLocked(fatherId, msg.sender);
            }
            revert("Breeding: Mother NFT transfer failed");
        }
        
        isNFTInActiveBreeding[fatherId] = true;
        isNFTInActiveBreeding[motherId] = true;
        breedingCooldowns[fatherId] = block.timestamp + selfBreedingCooldown;
        breedingCooldowns[motherId] = block.timestamp + selfBreedingCooldown;
        emit BreedingPairCreated(pairId, fatherId, motherId, 0);
        return pairId;
    }

    /**
     * @dev 创建市场繁殖对（管理员调用，跨玩家繁殖）
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @param maleOwner 父亲所有者地址
     * @param femaleOwner 母亲所有者地址
     * @param maleCoOwnerId 父亲共同所有者NFT ID（可选）
     * @param femaleCoOwnerId 母亲共同所有者NFT ID（可选）
     * @return pairId 繁殖对ID
     */
    function createMarketBreedingPair(
        uint256 fatherId, uint256 motherId, address maleOwner, address femaleOwner,
        uint256 maleCoOwnerId, uint256 femaleCoOwnerId
    ) external nonReentrant whenNotPaused onlyAuthorized returns (uint256) {
        require(fatherId != motherId, "Breeding: Cannot breed with self");
        require(maleOwner != femaleOwner, "Breeding: Same owner for market breeding");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        INFTMint nft = INFTMint(nftMintContract);

        require(nft.ownerOf(fatherId) == maleOwner, "Breeding: Father ownership mismatch");
        require(nft.ownerOf(motherId) == femaleOwner, "Breeding: Mother ownership mismatch");
        require(nft.tokenLevel(fatherId) >= 5 && nft.tokenLevel(motherId) >= 5, "Breeding: Level < 5");

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);
        require((fatherType / 2) % 12 == (motherType / 2) % 12, "Breeding: Different zodiac");
        require((fatherType % 2) != (motherType % 2), "Breeding: Same gender");

        require(breedingCooldowns[fatherId] <= block.timestamp, "Breeding: Father in cooldown");
        require(breedingCooldowns[motherId] <= block.timestamp, "Breeding: Mother in cooldown");

        if (maleCoOwnerId > 0) {
            require(nft.ownerOf(maleCoOwnerId) == maleOwner, "Breeding: Not male co-owner owner");
            require(!isNFTInActiveBreeding[maleCoOwnerId], "Breeding: Male co-owner already in breeding");
            require(breedingCooldowns[maleCoOwnerId] <= block.timestamp, "Breeding: Male co-owner in cooldown");
        }

        if (femaleCoOwnerId > 0) {
            require(nft.ownerOf(femaleCoOwnerId) == femaleOwner, "Breeding: Not female co-owner owner");
            require(!isNFTInActiveBreeding[femaleCoOwnerId], "Breeding: Female co-owner already in breeding");
            require(breedingCooldowns[femaleCoOwnerId] <= block.timestamp, "Breeding: Female co-owner in cooldown");
        }

        if (marketBreedingFee > 0) {
            require(tokenContract != address(0), "Breeding: Token contract not set");
            require(IERC20(tokenContract).transferFrom(msg.sender, address(this), marketBreedingFee), "Breeding: Fee transfer failed");
        }

        breedingPairCount++;
        uint256 pairId = breedingPairCount;
        breedingPairs[pairId] = BreedingPair({
            fatherId: fatherId, motherId: motherId, maleOwner: maleOwner, femaleOwner: femaleOwner,
            maleCoOwnerId: maleCoOwnerId, femaleCoOwnerId: femaleCoOwnerId, startTime: block.timestamp,
            breedingType: 1, status: 0, childId: 0, maleChildId: 0, rewardsClaimed: false
        });

        try INFTMint(nftMintContract).safeTransferFrom(maleOwner, address(this), fatherId) {
        } catch {
            revert("Breeding: Father NFT transfer failed");
        }
        
        try INFTMint(nftMintContract).safeTransferFrom(femaleOwner, address(this), motherId) {
        } catch {
            try INFTMint(nftMintContract).safeTransferFrom(address(this), maleOwner, fatherId) {
            } catch {
                emit EmergencyNFTLocked(fatherId, maleOwner);
            }
            revert("Breeding: Mother NFT transfer failed");
        }
        
        breedingCooldowns[fatherId] = block.timestamp + marketBreedingCooldown;
        breedingCooldowns[motherId] = block.timestamp + marketBreedingCooldown;
        emit BreedingPairCreated(pairId, fatherId, motherId, 1);
        return pairId;
    }

    /**
     * @dev 创建公开市场繁殖对（玩家与其他玩家的NFT繁殖）
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @return pairId 繁殖对ID
     */
    function createMarketBreedingPairPublic(
        uint256 fatherId, uint256 motherId
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(fatherId != motherId, "Breeding: Cannot breed with self");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        INFTMint nft = INFTMint(nftMintContract);

        address maleOwner = nft.ownerOf(fatherId);
        address femaleOwner = nft.ownerOf(motherId);
        
        require(maleOwner != femaleOwner, "Breeding: Must use NFTs from different owners");
        require(msg.sender == maleOwner || msg.sender == femaleOwner, "Breeding: Must be owner of one NFT");
        require(nft.tokenLevel(fatherId) >= 5 && nft.tokenLevel(motherId) >= 5, "Breeding: Level < 5");
        
        _checkDailyBreedingLimit(msg.sender);

        uint256 fatherType = nft.tokenType(fatherId);
        uint256 motherType = nft.tokenType(motherId);
        require((fatherType / 2) % 12 == (motherType / 2) % 12, "Breeding: Different zodiac");
        require((fatherType % 2) != (motherType % 2), "Breeding: Same gender");

        require(breedingCooldowns[fatherId] <= block.timestamp, "Breeding: Father in cooldown");
        require(breedingCooldowns[motherId] <= block.timestamp, "Breeding: Mother in cooldown");

        require(nft.isApprovedForAll(maleOwner, address(this)), "Breeding: Father owner not approved");
        require(nft.isApprovedForAll(femaleOwner, address(this)), "Breeding: Mother owner not approved");

        if (marketBreedingFee > 0) {
            require(tokenContract != address(0), "Breeding: Token contract not set");
            require(IERC20(tokenContract).transferFrom(msg.sender, address(this), marketBreedingFee), "Breeding: Fee transfer failed");
        }

        breedingPairCount++;
        uint256 pairId = breedingPairCount;
        breedingPairs[pairId] = BreedingPair({
            fatherId: fatherId, motherId: motherId, maleOwner: maleOwner, femaleOwner: femaleOwner,
            maleCoOwnerId: 0, femaleCoOwnerId: 0, startTime: block.timestamp,
            breedingType: 1, status: 0, childId: 0, maleChildId: 0, rewardsClaimed: false
        });

        nft.safeTransferFrom(maleOwner, address(this), fatherId);
        nft.safeTransferFrom(femaleOwner, address(this), motherId);
        
        breedingCooldowns[fatherId] = block.timestamp + marketBreedingCooldown;
        breedingCooldowns[motherId] = block.timestamp + marketBreedingCooldown;
        _updateDailyBreedingCount(msg.sender);
        emit BreedingPairCreated(pairId, fatherId, motherId, 1);
        return pairId;
    }

    /**
     * @dev 检查每日公开繁殖限制
     * @param user 用户地址
     */
    function _checkDailyBreedingLimit(address user) internal {
        uint256 currentDay = block.timestamp / 1 days;
        if (lastBreedingDay[user] != currentDay) {
            dailyPublicBreedings[user] = 0;
            lastBreedingDay[user] = currentDay;
        }
        require(dailyPublicBreedings[user] < maxDailyPublicBreedings, "Breeding: Daily breeding limit exceeded");
    }

    /**
     * @dev 更新每日繁殖计数
     * @param user 用户地址
     */
    function _updateDailyBreedingCount(address user) internal {
        uint256 currentDay = block.timestamp / 1 days;
        if (lastBreedingDay[user] != currentDay) {
            dailyPublicBreedings[user] = 1;
            lastBreedingDay[user] = currentDay;
        } else {
            dailyPublicBreedings[user]++;
        }
    }

    /**
     * @dev 设置每日最大公开繁殖次数
     * @param limit 最大次数
     */
    function setMaxDailyPublicBreedings(uint256 limit) external onlyOwner {
        maxDailyPublicBreedings = limit;
    }

    /**
     * @dev 完成繁殖（产出子代NFT）
     * @param pairId 繁殖对ID
     * @return childId 母方获得的子代NFT ID
     * @return maleChildId 父方获得的子代NFT ID（市场繁殖时）
     */
    function completeBreeding(uint256 pairId) external nonReentrant whenNotPaused returns (uint256, uint256) {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == 0, "Breeding: Pair not active");
        require(pair.childId == 0, "Breeding: Already completed");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "Breeding: Not pair owner");
        require(nftMintContract != address(0), "Breeding: NFT contract not set");

        uint256 cooldown = pair.breedingType == 0 ? selfBreedingCooldown : marketBreedingCooldown;
        require(block.timestamp >= pair.startTime + cooldown, "Breeding: Cooldown not ended");

        INFTMint nft = INFTMint(nftMintContract);
        uint256 zodiacType = _getChildZodiacType(pair.fatherId, pair.motherId);

        if (pair.breedingType == 0) {
            uint256 childId = nft.mint(pair.femaleOwner, zodiacType);
            require(childId > 0, "Breeding: NFT mint failed");
            pair.childId = childId;
            pair.status = 1;

            try nft.safeTransferFrom(address(this), pair.maleOwner, pair.fatherId) {
            } catch {
                emit EmergencyNFTLocked(pair.fatherId, pair.maleOwner);
            }
            
            try nft.safeTransferFrom(address(this), pair.femaleOwner, pair.motherId) {
            } catch {
                emit EmergencyNFTLocked(pair.motherId, pair.femaleOwner);
            }

            isNFTInActiveBreeding[pair.fatherId] = false;
            isNFTInActiveBreeding[pair.motherId] = false;

            _burnFee(pair.breedingType);

            emit BreedingCompleted(pairId, childId, zodiacType);
            return (childId, 0);
        } else {
            uint256 childIdForFemale = nft.mint(pair.femaleOwner, zodiacType);
            require(childIdForFemale > 0, "Breeding: Female child mint failed");

            uint256 childIdForMale = nft.mint(pair.maleOwner, zodiacType);
            require(childIdForMale > 0, "Breeding: Male child mint failed");

            pair.childId = childIdForFemale;
            pair.maleChildId = childIdForMale;
            pair.status = 1;

            try INFTMint(nftMintContract).safeTransferFrom(address(this), pair.maleOwner, pair.fatherId) {
            } catch {
                emit EmergencyNFTLocked(pair.fatherId, pair.maleOwner);
            }
            
            try INFTMint(nftMintContract).safeTransferFrom(address(this), pair.femaleOwner, pair.motherId) {
            } catch {
                emit EmergencyNFTLocked(pair.motherId, pair.femaleOwner);
            }

            isNFTInActiveBreeding[pair.fatherId] = false;
            isNFTInActiveBreeding[pair.motherId] = false;

            _burnFee(pair.breedingType);

            emit BreedingCompleted(pairId, childIdForFemale, zodiacType);
            emit MaleChildGenerated(pairId, childIdForMale);
            return (childIdForFemale, childIdForMale);
        }
    }

    /**
     * @dev 取消繁殖
     * @param pairId 繁殖对ID
     */
    function cancelBreeding(uint256 pairId) external whenNotPaused nonReentrant {
        BreedingPair storage pair = breedingPairs[pairId];
        require(pair.status == 0, "Breeding: Pair not active");
        require(msg.sender == pair.maleOwner || msg.sender == pair.femaleOwner, "Breeding: Not pair owner");

        INFTMint nft = INFTMint(nftMintContract);
        
        try nft.safeTransferFrom(address(this), pair.maleOwner, pair.fatherId) {
        } catch {
            emit EmergencyNFTLocked(pair.fatherId, pair.maleOwner);
        }
        
        try nft.safeTransferFrom(address(this), pair.femaleOwner, pair.motherId) {
        } catch {
            emit EmergencyNFTLocked(pair.motherId, pair.femaleOwner);
        }

        pair.status = 2;
        isNFTInActiveBreeding[pair.fatherId] = false;
        isNFTInActiveBreeding[pair.motherId] = false;
        breedingCooldowns[pair.fatherId] = block.timestamp;
        breedingCooldowns[pair.motherId] = block.timestamp;
        emit BreedingCancelled(pairId);
    }

    /**
     * @dev 获取繁殖对信息
     * @param pairId 繁殖对ID
     * @return fatherId 父亲ID
     * @return motherId 母亲ID
     * @return maleOwner 父方所有者
     * @return femaleOwner 母方所有者
     * @return maleCoOwnerId 父方共同所有者NFT ID
     * @return femaleCoOwnerId 母方共同所有者NFT ID
     * @return startTime 开始时间
     * @return breedingType 繁殖类型（0=自己繁殖，1=市场繁殖）
     * @return status 状态（0=进行中，1=已完成，2=已取消）
     * @return childId 子代ID（母方）
     * @return maleChildId 子代ID（父方，市场繁殖）
     * @return rewardsClaimed 奖励是否已领取
     */
    function getBreedingInfo(uint256 pairId) external view returns (
        uint256 fatherId,
        uint256 motherId,
        address maleOwner,
        address femaleOwner,
        uint256 maleCoOwnerId,
        uint256 femaleCoOwnerId,
        uint256 startTime,
        uint256 breedingType,
        uint256 status,
        uint256 childId,
        uint256 maleChildId,
        bool rewardsClaimed
    ) {
        BreedingPair memory pair = breedingPairs[pairId];
        return (
            pair.fatherId,
            pair.motherId,
            pair.maleOwner,
            pair.femaleOwner,
            pair.maleCoOwnerId,
            pair.femaleCoOwnerId,
            pair.startTime,
            pair.breedingType,
            pair.status,
            pair.childId,
            pair.maleChildId,
            pair.rewardsClaimed
        );
    }

    /**
     * @dev 检查NFT是否在冷却期
     * @param tokenId NFT ID
     * @return 是否在冷却期
     */
    function isInCooldown(uint256 tokenId) external view returns (bool) { 
        return breedingCooldowns[tokenId] > block.timestamp; 
    }

    /**
     * @dev 获取NFT冷却结束时间
     * @param tokenId NFT ID
     * @return 冷却结束时间戳
     */
    function getCooldownEndTime(uint256 tokenId) external view returns (uint256) { 
        return breedingCooldowns[tokenId]; 
    }

    /**
     * @dev 计算子代NFT的生肖类型
     * @param fatherId 父亲NFT ID
     * @param motherId 母亲NFT ID
     * @return 子代生肖类型
     */
    function _getChildZodiacType(uint256 fatherId, uint256 motherId) internal view returns (uint256) {
        if (nftMintContract == address(0)) return 0;
        INFTMint nftMint = INFTMint(nftMintContract);
        uint256 fatherType = nftMint.tokenType(fatherId);
        uint256 motherType = nftMint.tokenType(motherId);
        uint256 fatherZodiac = (fatherType / 2) % 12;
        uint256 motherZodiac = (motherType / 2) % 12;
        require(fatherZodiac == motherZodiac, "Breeding: Parent zodiac mismatch");

        uint256 seed = uint256(keccak256(abi.encodePacked(fatherId, motherId, block.timestamp)));
        uint256 fatherElement = fatherType / 24;
        uint256 motherElement = motherType / 24;
        uint256 inheritedElement = (seed % 2 == 0) ? fatherElement : motherElement;
        uint256 inheritedGender = (seed / 2) % 2;
        return inheritedElement * 24 + fatherZodiac * 2 + inheritedGender;
    }

    /**
     * @dev 销毁繁殖费用
     * @param breedingType 繁殖类型
     */
    function _burnFee(uint256 breedingType) internal {
        if (tokenContract == address(0)) return;
        uint256 fee = breedingType == 0 ? selfBreedingFee : marketBreedingFee;
        if (fee == 0) return;
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= fee, "Breeding: Insufficient fee balance");
        token.transfer(BLACK_HOLE, fee);
        emit BreedingFeeBurned(fee);
    }

    /**
     * @dev 设置自己繁殖费用
     * @param fee 费用金额
     */
    function setSelfBreedingFee(uint256 fee) external onlyOwner { 
        selfBreedingFee = fee; 
    }

    /**
     * @dev 设置市场繁殖费用
     * @param fee 费用金额
     */
    function setMarketBreedingFee(uint256 fee) external onlyOwner { 
        marketBreedingFee = fee; 
    }

    /**
     * @dev 设置自己繁殖冷却时间
     * @param cooldown 冷却时间（秒）
     */
    function setSelfBreedingCooldown(uint256 cooldown) external onlyOwner { 
        require(cooldown > 0, "Breeding: Cooldown must be > 0"); 
        selfBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    /**
     * @dev 设置市场繁殖冷却时间
     * @param cooldown 冷却时间（秒）
     */
    function setMarketBreedingCooldown(uint256 cooldown) external onlyOwner { 
        require(cooldown > 0, "Breeding: Cooldown must be > 0"); 
        marketBreedingCooldown = cooldown; 
        emit CooldownUpdated(selfBreedingCooldown, marketBreedingCooldown); 
    }

    /**
     * @dev 设置NFT合约地址
     * @param _nftContract NFT合约地址
     */
    function setNFTContract(address _nftContract) external onlyAuthorized { 
        require(_nftContract != address(0), "Breeding: Invalid NFT contract address"); 
        nftMintContract = _nftContract; 
        emit NFTContractSet(nftMintContract); 
    }

    /**
     * @dev 设置代币合约地址
     * @param _tokenContract 代币合约地址
     */
    function setTokenContract(address _tokenContract) external onlyAuthorized { 
        require(_tokenContract != address(0), "Breeding: Invalid token contract address"); 
        tokenContract = _tokenContract; 
        emit TokenContractSet(_tokenContract); 
    }

    /**
     * @dev 将NFT上架到繁殖市场
     * @param tokenId NFT ID
     */
    function listForMarketBreeding(uint256 tokenId) external whenNotPaused {
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        require(INFTMint(nftMintContract).ownerOf(tokenId) == msg.sender, "Breeding: Not token owner");
        require(!marketListings[tokenId].isActive, "Breeding: Already listed");
        require(!isInCooldown(tokenId), "Breeding: NFT in cooldown");
        require(INFTMint(nftMintContract).tokenLevel(tokenId) >= 5, "Breeding: Level too low");

        marketListings[tokenId] = MarketListing({ tokenId: tokenId, owner: msg.sender, listTime: block.timestamp, isActive: true });
        listedTokenIds.push(tokenId);
        emit MarketListingCreated(tokenId, msg.sender);
    }

    /**
     * @dev 将NFT从繁殖市场下架
     * @param tokenId NFT ID
     */
    function delistFromMarketBreeding(uint256 tokenId) external whenNotPaused {
        require(marketListings[tokenId].isActive, "Breeding: Not listed");
        require(marketListings[tokenId].owner == msg.sender, "Breeding: Not listing owner");
        delete marketListings[tokenId];
        for (uint256 i = 0; i < listedTokenIds.length; i++) {
            if (listedTokenIds[i] == tokenId) {
                listedTokenIds[i] = listedTokenIds[listedTokenIds.length - 1];
                listedTokenIds.pop();
                break;
            }
        }
        emit MarketListingRemoved(tokenId);
    }

    /**
     * @dev 获取所有活跃的市场上架NFT ID列表
     * @return 活跃NFT ID数组
     */
    function getMarketListingIds() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < listedTokenIds.length; i++) {
            if (marketListings[listedTokenIds[i]].isActive) {
                count++;
            }
        }

        uint256[] memory activeIds = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < listedTokenIds.length; i++) {
            if (marketListings[listedTokenIds[i]].isActive) {
                activeIds[index] = listedTokenIds[i];
                index++;
            }
        }
        return activeIds;
    }

    /**
     * @dev 获取市场上架信息
     * @param tokenId NFT ID
     * @return 上架信息结构体
     */
    function getMarketListing(uint256 tokenId) external view returns (MarketListing memory) { 
        return marketListings[tokenId]; 
    }

    /**
     * @dev 获取市场上架数量
     * @return 上架数量
     */
    function getMarketListingCount() external view returns (uint256) { 
        return listedTokenIds.length; 
    }

    /**
     * @dev 获取NFT的繁殖冷却剩余时间
     * @param tokenId NFT ID
     * @return remainingCooldown 剩余冷却时间（秒），0表示无冷却
     */
    function getNFTBreedingCooldown(uint256 tokenId) external view returns (uint256 remainingCooldown) {
        if (breedingCooldowns[tokenId] == 0) {
            return 0;
        }
        if (block.timestamp >= breedingCooldowns[tokenId]) {
            return 0;
        }
        return breedingCooldowns[tokenId] - block.timestamp;
    }

    /**
     * @dev 批量获取NFT的繁殖冷却剩余时间
     * @param tokenIds NFT ID数组
     * @return remainingCooldowns 剩余冷却时间数组
     */
    function getNFTBreedingCooldowns(uint256[] calldata tokenIds) external view returns (uint256[] memory remainingCooldowns) {
        remainingCooldowns = new uint256[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            remainingCooldowns[i] = getNFTBreedingCooldown(tokenIds[i]);
        }
    }

    /**
     * @dev 获取用户的繁殖对统计
     * @param user 用户地址
     * @return totalPairs 总繁殖对数
     * @return activePairs 进行中繁殖对数
     * @return completedPairs 已完成繁殖对数
     * @return claimablePairs 可领取奖励对数
     */
    function getUserBreedingStats(address user) external view returns (
        uint256 totalPairs,
        uint256 activePairs,
        uint256 completedPairs,
        uint256 claimablePairs
    ) {
        uint256 pairCount = breedingPairCount;
        totalPairs = 0;
        activePairs = 0;
        completedPairs = 0;
        claimablePairs = 0;

        for (uint256 i = 1; i <= pairCount; i++) {
            BreedingPair memory pair = breedingPairs[i];
            bool isRelated = (pair.maleOwner == user || pair.femaleOwner == user);
            if (pair.maleCoOwnerId != 0) {
                if (INFTMint(nftMintContract).ownerOf(pair.maleCoOwnerId) == user) {
                    isRelated = true;
                }
            }
            if (pair.femaleCoOwnerId != 0) {
                if (INFTMint(nftMintContract).ownerOf(pair.femaleCoOwnerId) == user) {
                    isRelated = true;
                }
            }

            if (isRelated) {
                totalPairs++;
                if (pair.status == 0) {
                    activePairs++;
                } else if (pair.status == 1) {
                    completedPairs++;
                    if (!pair.rewardsClaimed) {
                        claimablePairs++;
                    }
                }
            }
        }
    }

    /**
     * @dev 获取繁殖对详情（带冷却信息）
     * @param pairId 繁殖对ID
     * @return fatherId 父亲ID
     * @return motherId 母亲ID
     * @return fatherCooldown 父亲剩余冷却
     * @return motherCooldown 母亲剩余冷却
     * @return remainingTime 剩余繁殖时间
     * @return status 状态
     */
    function getBreedingPairWithCooldown(uint256 pairId) external view returns (
        uint256 fatherId,
        uint256 motherId,
        uint256 fatherCooldown,
        uint256 motherCooldown,
        uint256 remainingTime,
        uint256 status
    ) {
        BreedingPair memory pair = breedingPairs[pairId];
        fatherId = pair.fatherId;
        motherId = pair.motherId;
        fatherCooldown = getNFTBreedingCooldown(pair.fatherId);
        motherCooldown = getNFTBreedingCooldown(pair.motherId);
        status = pair.status;

        if (pair.status == 0) {
            if (pair.startTime > 0) {
                uint256 breedingDuration = pair.breedingType == 0 ? selfBreedingCooldown : marketBreedingCooldown;
                if (block.timestamp >= pair.startTime + breedingDuration) {
                    remainingTime = 0;
                } else {
                    remainingTime = pair.startTime + breedingDuration - block.timestamp;
                }
            } else {
                remainingTime = 0;
            }
        } else {
            remainingTime = 0;
        }
    }

    /**
     * @dev 紧急提取BNB
     * @param amount 提取数量
     */
    function emergencyWithdrawBNB(uint256 amount) external onlyOwner {
        require(amount > 0, "Breeding: Amount must be > 0");
        require(amount <= address(this).balance, "Breeding: Insufficient balance");
        payable(owner()).transfer(amount);
        emit EmergencyBNBWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取代币
     * @param amount 提取数量
     */
    function emergencyWithdrawTokens(uint256 amount) external onlyOwner {
        require(amount > 0, "Breeding: Amount must be > 0");
        require(tokenContract != address(0), "Breeding: Token contract not set");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(address(this)) >= amount, "Breeding: Insufficient token balance");
        require(token.transfer(owner(), amount), "Breeding: Token transfer failed");
        emit EmergencyTokensWithdrawn(msg.sender, owner(), amount);
    }

    /**
     * @dev 紧急提取NFT
     * @param tokenId NFT ID
     */
    function emergencyWithdrawNFT(uint256 tokenId) external onlyOwner {
        require(nftMintContract != address(0), "Breeding: NFT contract not set");
        require(!isNFTInActiveBreeding[tokenId], "Breeding: NFT in active breeding");
        INFTMint nft = INFTMint(nftMintContract);
        nft.safeTransferFrom(address(this), owner(), tokenId);
        emit EmergencyNFTWithdrawn(msg.sender, owner(), tokenId);
    }
}