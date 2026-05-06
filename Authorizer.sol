// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/OwnableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";



// v5 已移除：ERC721HolderUpgradeable、ReentrancyGuardUpgradeable、PausableUpgradeable
// 如需使用，需单独安装 @openzeppelin/contracts 并导入非升级版本

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

contract Authorizer is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ✅ 修复：只保留一个 initialize 函数（合并初始化逻辑）
    function initialize() external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(); // ✅ 修复：这里不传参数
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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

        ITokenBurner(tokenBurner).setAuthorizedNFTContract(fiveBlessingsNFT, true);
        IRewardManager(rewardManager).setAuthorizedNFTContract(fiveBlessingsNFT, true);

        INFTTrading(nftTrading).setNFTContract(fiveBlessingsNFT);
        INFTTrading(nftTrading).setRewardManager(rewardManager);

        IFiveBlessingsMetadata(fiveBlessingsMetadata).setRewardManager(rewardManager);

        IFiveBlessingsNFT(fiveBlessingsNFT).setAddresses(tokenBurner, rewardManager);
        IFiveBlessingsNFT(fiveBlessingsNFT).setMetadataContract(fiveBlessingsMetadata);
    }
}