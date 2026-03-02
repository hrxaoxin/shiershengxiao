// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

enum BlessingType { AiGuo, FuQiang, HeXie, YouShan, JingYe, WanNeng, WuFuLinMen }

interface ITokenBurner {
    function setAuthorizedNFTContract(address nft, bool ok) external;
}

interface IRewardManager {
    function setAuthorizedNFTContract(address nft, bool ok) external;
    function setNFTContract(address _newNFTContract) external;
}

interface INFTTrading {
    function setNFTContract(address newNFTContract) external;
    function setRewardManager(address newRewardManager) external;
}

interface IFiveBlessingsMetadata {
    function setRewardManager(address rm) external;
}

interface IFiveBlessingsNFT {
    function setAddresses(address tb, address rm) external;
    function setMetadataContract(address _metadataContract) external;
}

contract Authorizer is 
    Initializable, 
    OwnableUpgradeable, 
    UUPSUpgradeable
{
    // 存储间隙
    uint256[49] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
    }

    // UUPS升级授权
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 一次性授权所有合约
     * @param tokenBurner TokenBurner合约地址
     * @param rewardManager RewardManager合约地址
     * @param nftTrading NFTTrading合约地址
     * @param fiveBlessingsMetadata FiveBlessingsMetadata合约地址
     * @param fiveBlessingsNFT FiveBlessingsNFT合约地址
     */
    function authorizeAll(
        address tokenBurner,
        address rewardManager,
        address nftTrading,
        address fiveBlessingsMetadata,
        address fiveBlessingsNFT
    ) external onlyOwner {
        require(tokenBurner != address(0), "TokenBurner address cannot be zero");
        require(rewardManager != address(0), "RewardManager address cannot be zero");
        require(nftTrading != address(0), "NFTTrading address cannot be zero");
        require(fiveBlessingsMetadata != address(0), "FiveBlessingsMetadata address cannot be zero");
        require(fiveBlessingsNFT != address(0), "FiveBlessingsNFT address cannot be zero");

        // 1. 给tokenburner合约授权，调用setAuthorizedNFTContract
        ITokenBurner(tokenBurner).setAuthorizedNFTContract(fiveBlessingsNFT, true);

        // 2. 给rewardmanager合约授权，调用setAuthorizedNFTContract
        IRewardManager(rewardManager).setAuthorizedNFTContract(fiveBlessingsNFT, true);

        // 3. 给nfttrading合约授权，调用setNFTContract和setRewardManager
        INFTTrading(nftTrading).setNFTContract(fiveBlessingsNFT);
        INFTTrading(nftTrading).setRewardManager(rewardManager);

        // 4. 给fiveblessingsmetadata合约授权，调用setRewardManager
        IFiveBlessingsMetadata(fiveBlessingsMetadata).setRewardManager(rewardManager);

        // 5. 给fiveblessingsnft合约授权，调用setAddresses和setMetadataContract
        IFiveBlessingsNFT(fiveBlessingsNFT).setAddresses(tokenBurner, rewardManager);
        IFiveBlessingsNFT(fiveBlessingsNFT).setMetadataContract(fiveBlessingsMetadata);
    }
}
