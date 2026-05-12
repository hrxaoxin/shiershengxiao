// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./NFTInterface.sol";

contract NFTData is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, INFTDataInterface {
    using NFTDataTypes for NFTDataTypes.ZodiacType;

    string[] private _elementNames = [unicode"水", unicode"风", unicode"火", unicode"暗", unicode"光"];
    string[] private _zodiacNames = [unicode"鼠", unicode"牛", unicode"虎", unicode"兔", unicode"龙", unicode"蛇", unicode"马", unicode"羊", unicode"猴", unicode"鸡", unicode"狗", unicode"猪"];
    string[] private _genderNames = [unicode"母", unicode"公"];

    mapping(uint256 => NFTDataTypes.NFTInfo) private _nftInfos;
    mapping(uint256 => NFTDataTypes.ZodiacType) public override tokenType;
    mapping(uint256 => uint8) public override tokenLevel;
    mapping(address => uint256[]) public _userTokens;
    mapping(address => mapping(uint256 => bool)) public userTokenExists;
    mapping(address => mapping(NFTDataTypes.ZodiacType => uint256)) public userTokenCount;
    mapping(address => uint256) public override userWeightCache;

    address public authorizedNFTContract;
    event AuthorizedNFTContractSet(address indexed nftContract, uint256 timestamp);
    uint256[50] private __gap;

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        transferOwnership(initialOwner);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    modifier onlyAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizedNFTContract, "NFTData: Unauthorized");
        _;
    }

    function getNFTInfo(uint256 tokenId) external view override returns (NFTDataTypes.NFTInfo memory) {
        return _nftInfos[tokenId];
    }

    function setNFTInfo(uint256 tokenId, NFTDataTypes.NFTInfo memory info) external onlyAuthorized {
        _nftInfos[tokenId] = info;
    }
    
    function clearNFTInfo(uint256 tokenId) external onlyAuthorized {
        delete _nftInfos[tokenId];
    }

    function setTokenType(uint256 tokenId, NFTDataTypes.ZodiacType type_) external override onlyAuthorized {
        tokenType[tokenId] = type_;
    }

    function setTokenLevel(uint256 tokenId, uint8 level) external override onlyAuthorized {
        tokenLevel[tokenId] = level;
    }

    function addUserToken(address user, NFTDataTypes.ZodiacType type_, uint256 tokenId) external override onlyAuthorized {
        if (!userTokenExists[user][tokenId]) {
            _userTokens[user].push(tokenId);
            userTokenExists[user][tokenId] = true;
        }
        tokenType[tokenId] = type_;
        userTokenCount[user][type_]++;
    }

    function removeUserToken(address user, NFTDataTypes.ZodiacType type_, uint256 tokenId) external override onlyAuthorized {
        uint256[] storage arr = _userTokens[user];
        uint256 length = arr.length;
        for (uint i = 0; i < length; i++) {
            if (arr[i] == tokenId) {
                if (length > 1) {
                    arr[i] = arr[length - 1];
                }
                arr.pop();
                break;
            }
        }
        delete userTokenExists[user][tokenId];
        delete _nftInfos[tokenId];
        if (userTokenCount[user][type_] > 0) userTokenCount[user][type_]--;
    }

    function updateUserWeightCache(address user, uint256 weight) external override onlyAuthorized {
        userWeightCache[user] = weight;
    }

    /** @dev 统一的权重更新函数（由NFTMint、NFTUpdate等调用） */
    function updateUserWeight(address user, uint8 level, bool add) external override onlyAuthorized {
        uint256 currentWeight = userWeightCache[user];
        uint256 weightDelta = level + 3;
        if (add) {
            userWeightCache[user] = currentWeight + weightDelta;
        } else {
            userWeightCache[user] = currentWeight >= weightDelta ? currentWeight - weightDelta : 0;
        }
    }

    function getUserTokenCount(address user, NFTDataTypes.ZodiacType type_) external view override returns (uint256) {
        return userTokenCount[user][type_];
    }

    function getUserTotalTokenCount(address user) external view override returns (uint256) {
        return _userTokens[user].length;
    }

    function userTokens(address user, NFTDataTypes.ZodiacType type_) external view override returns (uint256[] memory) {
        uint256[] memory all = _userTokens[user];
        uint cnt;
        for (uint i = 0; i < all.length; i++) if (tokenType[all[i]] == type_) cnt++;
        uint256[] memory res = new uint256[](cnt);
        uint idx;
        for (uint i = 0; i < all.length; i++) if (tokenType[all[i]] == type_) res[idx++] = all[i];
        return res;
    }

    function userAllTokens(address user) external view override returns (uint256[] memory) {
        return _userTokens[user];
    }

    function setAuthorizedNFTContract(address nftContract) external onlyOwner {
        require(nftContract != address(0), "Zero address");
        authorizedNFTContract = nftContract;
        emit AuthorizedNFTContractSet(nftContract, block.timestamp);
    }

    function getElementName(NFTDataTypes.ElementType e) external view override returns (string memory) { return _elementNames[uint256(e)]; }
    function getZodiacName(NFTDataTypes.BaseZodiac z) external view override returns (string memory) { return _zodiacNames[uint256(z)]; }
    function getGenderName(NFTDataTypes.GenderType g) external view override returns (string memory) { return _genderNames[uint256(g)]; }

    function _getFullTypeName(NFTDataTypes.ZodiacType t) internal view returns (string memory) {
        return string(abi.encodePacked(
            _elementNames[uint256(t.getElement())],
            _zodiacNames[uint256(t.getBaseZodiac())],
            unicode"（", _genderNames[uint256(t.getGender())], unicode"）"
        ));
    }

    function getFullTypeName(NFTDataTypes.ZodiacType t) external view override returns (string memory) {
        return _getFullTypeName(t);
    }

    function collName() external pure override returns (string memory) { return "Twelve Zodiacs"; }
    function collDesc() external pure override returns (string memory) { return unicode"十二生肖NFT系列 - 120种独特卡牌"; }
    function collImage() external pure override returns (string memory) { return "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/logo.png"; }
    function sellerFeeBasisPoints() external pure override returns (uint256) { return 500; }
    function getCardName(NFTDataTypes.ZodiacType t) external view override returns (string memory) { return _getFullTypeName(t); }
    function getCardDesc(NFTDataTypes.ZodiacType t) external view override returns (string memory) { return string(abi.encodePacked(unicode"十二生肖NFT - ", _getFullTypeName(t))); }

    function getCardImage(NFTDataTypes.ZodiacType t) external view override returns (string memory) {
        return string(abi.encodePacked(
            "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/",
            _elementNames[uint256(t.getElement())],
            _zodiacNames[uint256(t.getBaseZodiac())],
            t.getGender() == NFTDataTypes.GenderType.MALE ? "_1" : "_0",
            ".png"
        ));
    }

    function hasEligibility(address user) external view override returns (bool) {
        return _userTokens[user].length > 0;
    }

    function getUserTokenTypes(address user) external view override returns (NFTDataTypes.ZodiacType[] memory) {
        uint256[] memory tokens = _userTokens[user];
        NFTDataTypes.ZodiacType[] memory types = new NFTDataTypes.ZodiacType[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            types[i] = tokenType[tokens[i]];
        }
        return types;
    }

    function getUserTokenTypesByPage(address user, uint256 offset, uint256 limit) external view returns (NFTDataTypes.ZodiacType[] memory, uint256) {
        uint256[] memory tokens = _userTokens[user];
        uint256 total = tokens.length;
        if (offset >= total) {
            return (new NFTDataTypes.ZodiacType[](0), 0);
        }
        uint256 size = offset + limit > total ? total - offset : limit;
        NFTDataTypes.ZodiacType[] memory types = new NFTDataTypes.ZodiacType[](size);
        for (uint i = 0; i < size; i++) {
            types[i] = tokenType[tokens[offset + i]];
        }
        return (types, total);
    }
}