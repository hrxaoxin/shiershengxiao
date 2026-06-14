// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTLib.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";

/**
 * @title NFTMintMetadata
 * @dev NFT元数据管理合约，负责生成和返回NFT的元数据信息
 * 
 * 核心职责：
 * 1. 生成TokenURI：为每个NFT生成符合ERC721标准的TokenURI
 * 2. 获取NFT数据：提供NFT的完整属性信息查询接口
 * 3. 属性计算：根据等级和成长值计算NFT的战斗属性
 * 
 * TokenURI生成：
 * - 采用Base64编码的JSON格式
 * - 包含NFT的名称、描述、属性等信息
 * - 图片URL指向外部API
 * 
 * NFT数据结构（NFTDataResult）：
 * - tokenType_: NFT类型（生肖+属性+性别）
 * - attack: 攻击力
 * - defense: 防御力
 * - health: 生命值
 * - speed: 速度（含生肖加成）
 * - level: 等级
 * - rank: 排名
 * - name: NFT名称
 * - imageUrl: 图片URL
 * 
 * 属性计算逻辑：
 * - 基础属性由等级和成长值决定
 * - 生肖加成会影响速度属性
 * - 加成可能为正或负
 * 
 * 与其他合约的交互：
 * - 从NFTMintCore读取NFT的类型、等级和成长值
 * - 使用NFTLib计算属性和获取生肖加成
 * 
 * 权限控制：
 * - onlyMintCore: 仅NFTMintCore合约可调用特定函数
 * - onlyOwner: 可升级合约
 */
contract NFTMintMetadata is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
    using Strings for uint256;
    using NFTLib for uint256;
    using Base64 for bytes;
    
    /**
     * @dev NFT铸造核心合约地址
     */
    address public nftMintCore;
    
    /**
     * @dev 授权合约地址（Authorizer）
     */
    address public authorizer;
    
    /**
     * @dev IPFS 基础 URL（普通NFT）
     */
    string public ipfsBaseNormal;
    
    /**
     * @dev IPFS 基础 URL（稀有NFT）
     */
    string public ipfsBaseRare;
    
    /**
     * @dev NFT数据结果结构体
     * @param tokenType_ NFT类型
     * @param attack 攻击力
     * @param defense 防御力
     * @param health 生命值
     * @param speed 速度
     * @param level 等级
     * @param rank 排名
     * @param name NFT名称
     * @param imageUrl 图片URL
     */
    struct NFTDataResult {
        uint256 tokenType_;
        uint256 attack;
        uint256 defense;
        uint256 health;
        uint256 speed;
        uint8 level;
        uint256 rank;
        string name;
        string imageUrl;
    }
    
    /**
     * @dev 修饰器：仅NFTMintCore合约可调用
     */
    modifier onlyMintCore() {
        require(msg.sender == nftMintCore, "NFTMintMetadata: Only NFTMintCore");
        _;
    }
    
    /**
     * @dev 修饰器：仅所有者或授权器可调用
     */
    modifier onlyOwnerOrAuthorizer() {
        require(msg.sender == owner() || msg.sender == authorizer, "NFTMintMetadata: Not owner or authorizer");
        _;
    }
    
    /**
     * @dev 初始化函数
     * @param _nftMintCoreAddress NFT铸造核心合约地址
     * @param _authorizerAddress 授权合约地址
     * @param _ipfsBaseNormal 普通NFT的IPFS基础URL（可选，有默认值）
     * @param _ipfsBaseRare 稀有NFT的IPFS基础URL（可选，有默认值）
     */
    function initialize(
        address _nftMintCoreAddress, 
        address _authorizerAddress,
        string calldata _ipfsBaseNormal,
        string calldata _ipfsBaseRare
    ) public initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        require(_nftMintCoreAddress != address(0), "NFTMintMetadata: Invalid NFTMintCore address");
        require(_authorizerAddress != address(0), "NFTMintMetadata: Invalid authorizer address");
        nftMintCore = _nftMintCoreAddress;
        authorizer = _authorizerAddress;
        
        if (bytes(_ipfsBaseNormal).length > 0) {
            ipfsBaseNormal = _ipfsBaseNormal;
        } else {
            ipfsBaseNormal = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/";
        }
        
        if (bytes(_ipfsBaseRare).length > 0) {
            ipfsBaseRare = _ipfsBaseRare;
        } else {
            ipfsBaseRare = "https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/";
        }
    }
    
    /**
     * @dev UUPS升级授权
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}
    
    /**
     * @dev 生成NFT的TokenURI
     * @param tokenId NFT ID
     * @return TokenURI字符串
     */
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(INFTMintCore(nftMintCore)._exists(tokenId), "NFTMint: Token not exists");
        
        uint256 tokenType_ = INFTMintCore(nftMintCore).tokenType(tokenId);
        uint8 level = INFTMintCore(nftMintCore).tokenLevel(tokenId);
        
        string memory json = _buildTokenURIJson(tokenId, tokenType_, level);
        return string(abi.encodePacked("data:application/json;base64,", bytes(json).encode()));
    }
    
    /**
     * @dev 获取NFT的完整数据
     * @param tokenId NFT ID
     * @return NFTDataResult 包含NFT的所有属性信息
     */
    function getNFTData(uint256 tokenId) external view returns (NFTDataResult memory) {
        require(INFTMintCore(nftMintCore)._exists(tokenId), "NFTMint: Token not exists");
        
        uint256 t = INFTMintCore(nftMintCore).tokenType(tokenId);
        uint8 l = INFTMintCore(nftMintCore).tokenLevel(tokenId);
        
        (uint256 attack, uint256 defense, uint256 health, uint256 speed) = NFTLib.computeAttributes(l, INFTMintCore(nftMintCore).tokenGrowth(tokenId));
        int256 zodiacBonus = NFTLib.getZodiacBonus(t);
        string memory tokenName = NFTLib.buildNFTName(t);
        
        uint256 finalSpeed = zodiacBonus >= 0 ? speed + uint256(zodiacBonus) : 
                             (speed > uint256(-zodiacBonus) ? speed - uint256(-zodiacBonus) : 0);
        
        return NFTDataResult({
            tokenType_: t,
            attack: attack,
            defense: defense,
            health: health,
            speed: finalSpeed,
            level: l,
            rank: 0,
            name: tokenName,
            imageUrl: string(abi.encodePacked("https://api.example.com/nft/", tokenId.toString()))
        });
    }
    
    function _buildTokenURIJson(uint256 tokenId, uint256 tokenType_, uint8 level) internal view returns (string memory) {
        uint256 element = tokenType_ / 24;
        uint256 zodiac = (tokenType_ % 24 / 2) % 12;
        uint8 gender = uint8(tokenType_ % 2);
        
        string memory elementName = NFTLib.getElementNameCN(element);
        string memory zodiacName = NFTLib.getZodiacNameCN(zodiac);
        string memory genderName = gender == 0 ? unicode"\u516C" : unicode"\u6BCD";
        string memory rarity = tokenType_ >= 72 ? unicode"\u7A00\u6709" : unicode"\u666E\u901A";
        string memory levelStr = uint256(level).toString();
        string memory tokenIdStr = tokenId.toString();
        
        string memory namePart = NFTLib.concat5(
            '{"name":"Zodiac NFT #', tokenIdStr, ' - ',
            NFTLib.concat2(elementName, NFTLib.concat2(zodiacName, unicode"\u00B7")),
            NFTLib.concat2(genderName, '"')
        );
        
        string memory descPart = NFTLib.concat5(
            NFTLib.concat2(',"description":"', unicode"\u5341\u4E8C\u751F\u8096NFT - \u5C5E\u6027\uFF1A"),
            NFTLib.concat2(elementName, unicode"\u00B7\u751F\u8096\uFF1A"),
            NFTLib.concat2(zodiacName, unicode"\u00B7\u6027\u522B\uFF1A"),
            NFTLib.concat2(genderName, unicode"\u00B7\u7B49\u7EA7\uFF1A"),
            NFTLib.concat2(levelStr, unicode"\u00B7\u6301\u6709\u53EF\u4EB2\u53D7\u751F\u6001\u5206\u5143\"")
        );
        
        string memory imageBase = tokenType_ >= 72 ? ipfsBaseRare : ipfsBaseNormal;
        string memory imagePath = NFTLib.buildImagePath(imageBase, tokenType_);
        string memory imagePart = NFTLib.concat2(',"image":"', NFTLib.concat2(imagePath, '"'));
        
        string memory attrs = NFTLib.concat5(
            NFTLib.buildAttr(unicode"\u5C5E\u6027", elementName),
            NFTLib.buildAttr(unicode"\u751F\u8096", zodiacName),
            NFTLib.buildAttr(unicode"\u6027\u522B", genderName),
            NFTLib.buildAttr(unicode"\u7B49\u7EA7", levelStr),
            NFTLib.buildAttrLast(unicode"\u7C7B\u578B", rarity)
        );
        string memory attrPart = NFTLib.concat2(',"attributes":[', NFTLib.concat2(attrs, ']}'));
        
        return NFTLib.concat5(namePart, descPart, imagePart, attrPart, "");
    }
    
    function setNftMintCore(address _nftMintCoreAddress) external onlyOwnerOrAuthorizer {
        require(_nftMintCoreAddress != address(0), "NFTMintMetadata: Invalid address");
        nftMintCore = _nftMintCoreAddress;
    }

    function setIPFSBases(string calldata _ipfsBaseNormal, string calldata _ipfsBaseRare) external onlyOwnerOrAuthorizer {
        ipfsBaseNormal = _ipfsBaseNormal;
        ipfsBaseRare = _ipfsBaseRare;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizerAddress 新的授权合约地址
     */
    function setAuthorizer(address _authorizerAddress) external onlyOwnerOrAuthorizer {
        require(_authorizerAddress != address(0), "NFTMintMetadata: Invalid authorizer address");
        authorizer = _authorizerAddress;
    }
}