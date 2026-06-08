// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTLib.sol";
import "./NFTInterface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol";

contract NFTMintMetadata {
    using Strings for uint256;
    using NFTLib for uint256;
    
    address public nftMintCore;
    
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
    
    modifier onlyMintCore() {
        require(msg.sender == nftMintCore, "NFTMintMetadata: Only NFTMintCore");
        _;
    }
    
    function initialize(address _nftMintCore) public {
        nftMintCore = _nftMintCore;
    }
    
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(INFTMintCore(nftMintCore)._exists(tokenId), "NFTMint: Token not exists");
        
        uint256 tokenType_ = INFTMintCore(nftMintCore).tokenType(tokenId);
        uint8 level = INFTMintCore(nftMintCore).tokenLevel(tokenId);
        
        string memory json = _buildTokenURIJson(tokenId, tokenType_, level);
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }
    
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
    
    function _buildTokenURIJson(uint256 tokenId, uint256 tokenType_, uint8 level) internal pure returns (string memory) {
        uint256 element = tokenType_ / 24;
        uint256 zodiac = (tokenType_ % 24 / 2) % 12;
        uint8 gender = uint8(tokenType_ % 2);
        
        string memory elementName = NFTLib.getElementNameCN(element);
        string memory zodiacName = NFTLib.getZodiacNameCN(zodiac);
        string memory genderName = gender == 0 ? unicode"\u516C" : unicode"\u6BCD";
        string memory rarity = tokenType_ >= 72 ? unicode"\u7A00\u6709" : unicode"\u666E\u901A";
        string memory levelStr = level.toString();
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
            NFTLib.concat2(genderName, unicode"\u00B7\u7B49\uEA7\uFF1A"),
            NFTLib.concat2(levelStr, unicode"\u00B7\u6301\u6709\u53EF\u4EB2\u53D7\u751F\u6001\u5206\u5143\"")
        );
        
        string memory attrs = NFTLib.concat5(
            NFTLib.buildAttr(unicode"\u5C5E\u6027", elementName),
            NFTLib.buildAttr(unicode"\u751F\u8096", zodiacName),
            NFTLib.buildAttr(unicode"\u6027\u522B", genderName),
            NFTLib.buildAttr(unicode"\u7B49\uEA7", levelStr),
            NFTLib.buildAttrLast(unicode"\u7C7B\u578B", rarity)
        );
        string memory attrPart = NFTLib.concat2(',"attributes":[', NFTLib.concat2(attrs, ']}'));
        
        return NFTLib.concat5(namePart, descPart, attrPart, "", "");
    }
    
    function setNftMintCore(address _nftMintCore) external {
        require(msg.sender == INFTMintCore(nftMintCore).owner(), "NFTMintMetadata: Only owner");
        nftMintCore = _nftMintCore;
    }
    
    library Base64 {
        bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        
        function encode(bytes memory data) internal pure returns (string memory) {
            uint256 len = data.length;
            if (len == 0) return "";
            
            uint256 encodedLen = (len + 2) / 3 * 4;
            bytes memory result = new bytes(encodedLen);
            
            uint256 i = 0;
            uint256 j = 0;
            
            while (i < len) {
                uint256 octetA = i < len ? uint8(data[i++]) : 0;
                uint256 octetB = i < len ? uint8(data[i++]) : 0;
                uint256 octetC = i < len ? uint8(data[i++]) : 0;
                
                uint256 triple = (octetA << 16) | (octetB << 8) | octetC;
                
                result[j++] = TABLE[(triple >> 18) & 0x3F];
                result[j++] = TABLE[(triple >> 12) & 0x3F];
                result[j++] = TABLE[(triple >> 6) & 0x3F];
                result[j++] = TABLE[triple & 0x3F];
            }
            
            uint256 padding = encodedLen - ((len * 4) / 3);
            if (padding > 0) {
                result[encodedLen - 1] = "=";
                if (padding > 1) {
                    result[encodedLen - 2] = "=";
                }
            }
            
            return string(result);
        }
    }
}