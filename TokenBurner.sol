// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TokenBurner
 * @dev NFT销毁合约，用于销毁NFT并立即铸造新的NFT
 * 支持两种模式：销毁后铸造随机类型NFT，或销毁后铸造指定类型NFT
 * 基于OpenZeppelin可升级合约实现
 */
import "./NFTData.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC721/IERC721Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/access/Ownable2StepUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/proxy/utils/UUPSUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/release-v4.9/contracts/security/PausableUpgradeable.sol";

/**
 * @title TokenBurner
 * @dev NFT销毁合约
 */
contract TokenBurner is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    /** @dev 黑洞地址，用于销毁NFT */
    address public constant BLACK_HOLE = 0x000000000000000000000000000000000000dEaD;
    
    /** @dev 销毁铸造费用 */
    uint256 public constant BURN_MINT_FEE = 50000 * 10**18;

    /** @dev NFT合约地址 */
    address public nftContract;
    /** @dev 代币合约地址 */
    address public tokenContract;
    /** @dev 授权合约地址 */
    address public authorizer;

    /** @dev 销毁铸造事件 */
    event NFTBurnedAndMinted(
        address indexed user, 
        uint256 indexed burnedTokenId, 
        NFTDataTypes.ZodiacType burnedType,
        uint256 indexed newTokenId, 
        NFTDataTypes.ZodiacType newType,
        uint256 timestamp
    );
    /** @dev 销毁失败事件 */
    event BurnFailed(
        address indexed user, 
        uint256 indexed tokenId, 
        string reason, 
        uint256 timestamp
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化合约
     * @param _nftContract NFT合约地址
     * @param _tokenContract 代币合约地址
     * @param _authorizer 授权合约地址
     */
    function initialize(address _nftContract, address _tokenContract, address _authorizer) external initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        nftContract = _nftContract;
        tokenContract = _tokenContract;
        authorizer = _authorizer;
    }

    /**
     * @dev 升级授权函数
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 销毁代币用于铸造
     * 用户需要先授权代币给合约，然后调用此函数销毁代币
     * @return bool 是否成功
     */
    function burnTokenForMint() external whenNotPaused returns (bool) {
        require(tokenContract != address(0), "TokenBurner: tokenContract not set");
        
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(token.transferFrom(msg.sender, BLACK_HOLE, BURN_MINT_FEE), "TokenBurner: Token transfer failed");
        
        return true;
    }

    /**
     * @dev 销毁代币并铸造（由NFT合约调用）
     * 用户需要先授权代币给合约
     * @param user 用户地址
     * @return bool 是否成功
     */
    function burnAndMint(address user) external whenNotPaused returns (bool) {
        require(tokenContract != address(0), "TokenBurner: tokenContract not set");
        
        IERC20Upgradeable token = IERC20Upgradeable(tokenContract);
        require(token.transferFrom(user, BLACK_HOLE, BURN_MINT_FEE), "TokenBurner: Token transfer failed");
        
        return true;
    }

    /**
     * @dev 销毁NFT并铸造新的随机类型NFT
     * 用户销毁一个NFT，支付费用后获得一个新的随机类型NFT
     * @param tokenId 要销毁的NFT ID
     * @return uint256 新铸造的NFT ID
     */
    function burnAndMintRandom(uint256 tokenId) external whenNotPaused returns (uint256) {
        INFTMint nft = INFTMint(nftContract);
        
        // 验证用户拥有NFT
        require(nft.ownerOf(tokenId) == msg.sender, "TokenBurner: Not owner of NFT");
        
        // 验证授权
        require(nft.isApprovedForAll(msg.sender, address(this)) || 
                nft.getApproved(tokenId) == address(this), "TokenBurner: Contract not approved");

        // 获取销毁的NFT类型
        NFTDataTypes.ZodiacType burnedType = nft.tokenType(tokenId);

        // 销毁NFT
        nft.transferFrom(msg.sender, BLACK_HOLE, tokenId);

        // 铸造新的随机类型NFT
        uint256 newTokenId = nft.mint(msg.sender);
        
        // 获取新NFT类型
        NFTDataTypes.ZodiacType newType = nft.tokenType(newTokenId);

        emit NFTBurnedAndMinted(msg.sender, tokenId, burnedType, newTokenId, newType, block.timestamp);
        return newTokenId;
    }

    /**
     * @dev 销毁NFT并铸造指定类型的新NFT
     * 用户销毁一个NFT，支付费用后获得一个指定类型的新NFT
     * @param tokenId 要销毁的NFT ID
     * @param targetType 目标NFT类型
     * @return uint256 新铸造的NFT ID
     */
    function burnAndMintSpecific(uint256 tokenId, NFTDataTypes.ZodiacType targetType) external whenNotPaused returns (uint256) {
        INFTMint nft = INFTMint(nftContract);
        
        // 验证用户拥有NFT
        require(nft.ownerOf(tokenId) == msg.sender, "TokenBurner: Not owner of NFT");
        
        // 验证授权
        require(nft.isApprovedForAll(msg.sender, address(this)) || 
                nft.getApproved(tokenId) == address(this), "TokenBurner: Contract not approved");

        // 获取销毁的NFT类型
        NFTDataTypes.ZodiacType burnedType = nft.tokenType(tokenId);

        // 销毁NFT
        nft.transferFrom(msg.sender, BLACK_HOLE, tokenId);

        // 铸造指定类型的NFT
        uint256 newTokenId = nft.mintSpecificType(msg.sender, targetType);

        emit NFTBurnedAndMinted(msg.sender, tokenId, burnedType, newTokenId, targetType, block.timestamp);
        return newTokenId;
    }

    /**
     * @dev 销毁NFT并铸造光/暗属性的新NFT
     * 用户销毁一个NFT，支付费用后获得一个光或暗属性的新NFT
     * @param tokenId 要销毁的NFT ID
     * @param isLight 是否铸造光属性（true=光，false=暗）
     * @return uint256 新铸造的NFT ID
     */
    function burnAndMintLightDark(uint256 tokenId, bool isLight) external whenNotPaused returns (uint256) {
        INFTMint nft = INFTMint(nftContract);
        
        // 验证用户拥有NFT
        require(nft.ownerOf(tokenId) == msg.sender, "TokenBurner: Not owner of NFT");
        
        // 验证授权
        require(nft.isApprovedForAll(msg.sender, address(this)) || 
                nft.getApproved(tokenId) == address(this), "TokenBurner: Contract not approved");

        // 获取销毁的NFT类型
        NFTDataTypes.ZodiacType burnedType = nft.tokenType(tokenId);

        // 销毁NFT
        nft.transferFrom(msg.sender, BLACK_HOLE, tokenId);

        // 铸造光/暗属性的NFT
        uint256 newTokenId = nft.mintLightDark(msg.sender, isLight);
        
        // 获取新NFT类型
        NFTDataTypes.ZodiacType newType = nft.tokenType(newTokenId);

        emit NFTBurnedAndMinted(msg.sender, tokenId, burnedType, newTokenId, newType, block.timestamp);
        return newTokenId;
    }

    /**
     * @dev 设置NFT合约地址
     * @param _nftContract NFT合约地址
     */
    function setNFTContract(address _nftContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "TokenBurner: Unauthorized");
        nftContract = _nftContract;
    }

    /**
     * @dev 设置代币合约地址
     * @param _tokenContract 代币合约地址
     */
    function setTokenContract(address _tokenContract) external {
        require(msg.sender == owner() || msg.sender == authorizer, "TokenBurner: Unauthorized");
        tokenContract = _tokenContract;
    }

    /**
     * @dev 设置授权合约地址
     * @param _authorizer 授权合约地址
     */
    function setAuthorizer(address _authorizer) external onlyOwner {
        authorizer = _authorizer;
    }

    /**
     * @dev 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 恢复合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}