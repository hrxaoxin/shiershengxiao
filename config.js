window.ZODIAC_CONFIG = (function() {
    const NETWORK_ID = 56;
    const NETWORK_NAME = 'Binance Mainnet';
    const NETWORK_LABEL = 'BNB主网';

    const ERROR_CODES = {
        4001: '用户拒绝了操作',
        '-32000': 'RPC错误',
        '-32601': '方法不存在',
        '-32602': '参数无效'
    };

    const ERROR_PATTERNS = [
        { pattern: /MetaMask not detected/i, message: '未检测到MetaMask钱包，请安装后重试' },
        { pattern: /User rejected the request/i, message: '用户拒绝了操作' },
        { pattern: /Wallet not connected/i, message: '钱包未连接，请先连接钱包' },
        { pattern: /Web3 not initialized/i, message: 'Web3初始化失败，请刷新页面重试' },
        { pattern: /insufficient funds/i, message: '余额不足，请确保钱包有足够的资金' },
        { pattern: /Gas estimation failed/i, message: 'Gas估算失败，请稍后重试' },
        { pattern: /reverted/i, message: '交易执行失败，合约调用被拒绝' },
        { pattern: /execution reverted/i, message: '交易执行失败，合约调用被拒绝' },
        { pattern: /invalid opcode/i, message: '无效操作码，合约执行失败' },
        { pattern: /out of gas/i, message: 'Gas不足，交易失败' },
        { pattern: /nonce too low/i, message: '交易序号过低，请等待上一笔交易完成' },
        { pattern: /already known/i, message: '交易已存在，正在处理中' },
        { pattern: /unknown contract/i, message: '未知合约，请检查配置' },
        { pattern: /address not configured/i, message: '合约地址未配置' },
        { pattern: /contract method not found/i, message: '合约方法不存在' },
        { pattern: /invalid address/i, message: '无效的钱包地址' },
        { pattern: /block gas limit/i, message: '区块Gas限制不足' },
        { pattern: /max priority fee per gas/i, message: 'Gas费用设置不合理' },
        { pattern: /replacement transaction underpriced/i, message: '替换交易价格过低' },
        { pattern: /cannot estimate gas/i, message: '无法估算Gas，请检查合约状态' }
    ];

    const UI_ERROR_CODES = {
        WEB3_NOT_INITIALIZED: '请先连接钱包',
        WALLET_NOT_CONNECTED: '钱包未连接，请先连接钱包',
        INSUFFICIENT_FUNDS: '余额不足，请确保钱包有足够的资金',
        INVALID_ADDRESS: '无效的钱包地址',
        CONTRACT_ERROR: '合约调用失败',
        NETWORK_ERROR: '网络连接失败，请检查网络',
        USER_REJECTED: '用户拒绝了操作',
        TIMEOUT: '操作超时，请重试',
        UNKNOWN_ERROR: '操作失败，请稍后重试'
    };

    function getErrorCodeMessage(code) {
        if (ERROR_CODES[code] !== undefined) {
            return ERROR_CODES[code];
        }
        const stringCode = String(code);
        if (ERROR_CODES[stringCode] !== undefined) {
            return ERROR_CODES[stringCode];
        }
        return null;
    }

    function getErrorMessage(error) {
        const errorStr = error.message || error.toString();

        if (error.code !== undefined && error.code !== null) {
            const codeMessage = getErrorCodeMessage(error.code);
            if (codeMessage) {
                return codeMessage;
            }
        }

        for (const { pattern, message } of ERROR_PATTERNS) {
            if (pattern.test(errorStr)) {
                return message;
            }
        }

        if (errorStr.includes('0x')) {
            const hexError = errorStr.match(/0x[0-9a-fA-F]+/);
            if (hexError) {
                return `交易失败 (错误码: ${hexError[0]})`;
            }
        }

        return errorStr.length > 100 ? '操作失败，请稍后重试' : errorStr;
    }

    function getEnvContractAddress(key, defaultAddress) {
        const envKey = `ZODIAC_${key.toUpperCase()}_ADDRESS`;
        const envValue = typeof window !== 'undefined' ? window[envKey] : null;
        if (envValue && /^0x[a-fA-F0-9]{40}$/.test(envValue)) {
            return envValue;
        }
        return defaultAddress;
    }

    const CONTRACT_ADDRESSES = {
        tokenContract: getEnvContractAddress('token', '0x1234567890abcdef1234567890abcdef12345678'),
        rewardManager: getEnvContractAddress('rewardManager', '0xabcdef1234567890abcdef1234567890abcdef12'),
        tokenBurner: getEnvContractAddress('tokenBurner', '0xabcdef1234567890abcdef1234567890abcdef13'),
        nftMint: getEnvContractAddress('nftMint', '0xabcdef1234567890abcdef1234567890abcdef14'),
        nftUpdate: getEnvContractAddress('nftUpdate', '0xabcdef1234567890abcdef1234567890abcdef15'),
        nftTrading: getEnvContractAddress('nftTrading', '0xabcdef1234567890abcdef1234567890abcdef16'),
        breeding: getEnvContractAddress('breeding', '0xabcdef1234567890abcdef1234567890abcdef17'),
        staking: getEnvContractAddress('staking', '0xabcdef1234567890abcdef1234567890abcdef18'),
        tokenStaking: getEnvContractAddress('tokenStaking', '0xabcdef1234567890abcdef1234567890abcdef19'),
        arena: getEnvContractAddress('arena', '0xabcdef1234567890abcdef1234567890abcdef20'),
        battle: getEnvContractAddress('battle', '0xabcdef1234567890abcdef1234567890abcdef21')
    };

    function getContractAddresses() {
        return CONTRACT_ADDRESSES;
    }

    function validateContractAddresses() {
        const INVALID_ADDRESS = '0x0000000000000000000000000000000000000000';
        const TEST_ADDRESS_PATTERN = /^0x[0-9a-fA-F]{8}0{32}$/;
        
        const invalidAddresses = Object.entries(CONTRACT_ADDRESSES)
            .filter(([name, addr]) => {
                if (!/^0x[a-fA-F0-9]{40}$/.test(addr)) return true;
                if (addr === INVALID_ADDRESS) return true;
                return TEST_ADDRESS_PATTERN.test(addr);
            });
        
        if (invalidAddresses.length > 0) {
            console.error('[ZODIAC_CONFIG] Invalid contract addresses detected:', invalidAddresses);
            if (typeof window !== 'undefined' && window.console) {
                const warningMsg = `警告: 检测到 ${invalidAddresses.length} 个无效合约地址，请检查环境变量配置。\n\n无效地址列表:\n${invalidAddresses.map(([name, addr]) => `  ${name}: ${addr}`).join('\n')}`;
                console.warn(warningMsg);
                if (typeof alert === 'function' && window.location.hostname !== 'localhost') {
                    alert(warningMsg);
                }
            }
        }
        
        return invalidAddresses.length === 0;
    }

    const MINT_COSTS = {
        normal: 8888,
        rare: 88888,
        normalTen: 88880,
        rareTen: 888880
    };

    const UPGRADE_COSTS = {
        1: { nft: 1, tokens: 10000, usdtValue: 1 },
        2: { nft: 2, tokens: 40000, usdtValue: 4 },
        3: { nft: 3, tokens: 120000, usdtValue: 12 },
        4: { nft: 4, tokens: 480000, usdtValue: 48 }
    };

    const WEIGHTS = {
        normal: { 1: 1, 2: 2, 3: 6, 4: 18, 5: 66 },
        rare: { 1: 10, 2: 12, 3: 16, 4: 28, 5: 76 }
    };

    const TAX_RATES = {
        total: 3,
        dividendPool: 1.0,
        burn: 1.0,
        nftStakingPool: 0.5,
        arenaRewards: 0.3,
        tokenStakingPool: 0.2
    };

    const BREEDING_CONFIG = {
        minLevel: 5,
        selfBreedingDuration: 12 * 60 * 60,
        marketBreedingDuration: 24 * 60 * 60
    };

    const ARENA_CONFIG = {
        dailyAttempts: 10,
        teamSize: 6,
        rechargeCost: 1000
    };

    const IPFS_BASES = {
        water: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
        wind: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
        fire: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
        dark: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/',
        light: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/'
    };

    const ZODIAC_NAMES = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];
    const ATTR_NAMES = { water: '水', wind: '风', fire: '火', dark: '暗', light: '光' };
    const ATTR_PREFIXES = { water: 'shui', wind: 'feng', fire: 'huo', dark: 'an', light: 'guang' };
    const ANIMAL_KEYS = ['shu', 'niu', 'hu', 'tu', 'long', 'she', 'ma', 'yang', 'hou', 'ji', 'gou', 'zhu'];

    const ABIS = {
        nftABI: [
            {"inputs":[{"internalType":"address","name":"owner","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint256","name":"index","type":"uint256"}],"name":"tokenOfOwnerByIndex","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getNFTData","outputs":[{"components":[{"internalType":"uint256","name":"tokenType","type":"uint256"},{"internalType":"uint256","name":"attack","type":"uint256"},{"internalType":"uint256","name":"defense","type":"uint256"},{"internalType":"uint256","name":"health","type":"uint256"},{"internalType":"uint256","name":"speed","type":"uint256"},{"internalType":"uint256","name":"level","type":"uint256"},{"internalType":"uint256","name":"rank","type":"uint256"},{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"imageUrl","type":"string"}],"internalType":"struct NFTData","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"transferFrom","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"owner","type":"address"}],"name":"getTokenIdsByOwner","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"}
        ],
        nftMintABI: [
            {"inputs":[{"internalType":"address","name":"owner","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"tokenType","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"tokenLevel","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"tokenURI","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mintNormal","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mintRare","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mintNormalTen","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mintRareTen","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint8","name":"baseZodiac","type":"uint8"}],"name":"mintTargeted","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"nextCardId","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"ownerOf","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"operator","type":"address"}],"name":"isApprovedForAll","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"operator","type":"address"},{"internalType":"bool","name":"approved","type":"bool"}],"name":"setApprovalForAll","outputs":[],"stateMutability":"nonpayable","type":"function"}
        ],
        tokenBurnerABI: [
            {"inputs":[],"name":"normalMintCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rareMintCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"normalMintTenCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rareMintTenCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"targetedMintCost","outputs":[{"internalType":"uint256","name":"normalPart","type":"uint256"},{"internalType":"uint256","name":"rarePart","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"bool","name":"isRare","type":"bool"}],"name":"burnAndMint","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"bool","name":"isRare","type":"bool"}],"name":"burnAndMintTen","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"burnAndMintTargeted","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}
        ],
        tokenABI: [
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}
        ],
        rewardManagerABI: [
            {"inputs":[],"name":"dividendPool","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"totalDistributed","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"holdersCount","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"calcUserDividend","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"claimDividend","outputs":[],"stateMutability":"nonpayable","type":"function"}
        ],
        battleABI: [
            {"inputs":[{"internalType":"uint256[6]","name":"attackerTeam","type":"uint256[6]"},{"internalType":"uint256[6]","name":"defenderTeam","type":"uint256[6]"}],"name":"battle","outputs":[{"internalType":"bool","name":"","type":"bool"},{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
        ],
        nftUpdateABI: [
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"upgradeLevel","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getUpgradeCost","outputs":[{"internalType":"uint256","name":"tokenCost","type":"uint256"},{"internalType":"uint256","name":"nftCost","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"level","type":"uint256"}],"name":"getUpgradeCostForLevel","outputs":[{"internalType":"uint256","name":"tokenCost","type":"uint256"},{"internalType":"uint256","name":"nftCost","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"uint256","name":"targetLevel","type":"uint256"}],"name":"upgradeToLevel","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"upgradeWithNFT","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"upgradeWithToken","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"upgradeWithUSDValue","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}
        ],
        NFTTradingABI: [
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"uint256","name":"price","type":"uint256"}],"name":"listNFT","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"cancelListing","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"buyNFT","outputs":[],"stateMutability":"payable","type":"function"},
            {"inputs":[],"name":"getAllListings","outputs":[{"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"},{"internalType":"address[]","name":"sellers","type":"address[]"},{"internalType":"uint256[]","name":"prices","type":"uint256[]"},{"internalType":"bool[]","name":"actives","type":"bool[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"offset","type":"uint256"},{"internalType":"uint256","name":"limit","type":"uint256"}],"name":"getPaginatedListings","outputs":[{"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"},{"internalType":"address[]","name":"sellers","type":"address[]"},{"internalType":"uint256[]","name":"prices","type":"uint256[]"},{"internalType":"bool[]","name":"actives","type":"bool[]"},{"internalType":"uint256","name":"total","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getListing","outputs":[{"internalType":"address","name":"seller","type":"address"},{"internalType":"uint256","name":"price","type":"uint256"},{"internalType":"bool","name":"active","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"seller","type":"address"}],"name":"getSellerListings","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"isListed","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getAllListedNFTs","outputs":[{"components":[{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"address","name":"seller","type":"address"},{"internalType":"uint256","name":"price","type":"uint256"},{"internalType":"uint256","name":"tokenType","type":"uint256"},{"internalType":"uint256","name":"level","type":"uint256"}],"internalType":"struct ListedNFT[]","name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getListedNFT","outputs":[{"components":[{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"address","name":"seller","type":"address"},{"internalType":"uint256","name":"price","type":"uint256"},{"internalType":"uint256","name":"tokenType","type":"uint256"},{"internalType":"uint256","name":"level","type":"uint256"}],"internalType":"struct ListedNFT","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getNFTPrice","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
        ],
        breedingABI: [
            {"inputs":[{"internalType":"uint256","name":"parent1","type":"uint256"},{"internalType":"uint256","name":"parent2","type":"uint256"}],"name":"breed","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"canBreed","outputs":[{"internalType":"bool","name":"","type":"bool"},{"internalType":"uint256","name":"remainingTime","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getBreedingTime","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"owner","type":"address"}],"name":"getBreedingPairs","outputs":[{"components":[{"internalType":"uint256","name":"parent1","type":"uint256"},{"internalType":"uint256","name":"parent2","type":"uint256"},{"internalType":"uint256","name":"startTime","type":"uint256"},{"internalType":"uint256","name":"endTime","type":"uint256"},{"internalType":"bool","name":"completed","type":"bool"}],"internalType":"struct BreedingPair[]","name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"parent1","type":"uint256"},{"internalType":"uint256","name":"parent2","type":"uint256"}],"name":"getBreedingCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"minBreedingLevel","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"selfBreedingDuration","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"marketBreedingDuration","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"pairId","type":"uint256"}],"name":"claimBaby","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId1","type":"uint256"},{"internalType":"uint256","name":"tokenId2","type":"uint256"}],"name":"startSelfBreeding","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"orderId","type":"uint256"}],"name":"completeSelfBreeding","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"listForBreeding","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"orderId","type":"uint256"}],"name":"cancelListing","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"orderId","type":"uint256"},{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"joinBreeding","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"orderId","type":"uint256"}],"name":"completeMarketBreeding","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"getMarketBreedingOrders","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserBreedingOrders","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"orderId","type":"uint256"}],"name":"breedingOrders","outputs":[{"components":[{"internalType":"address","name":"owner1","type":"address"},{"internalType":"address","name":"owner2","type":"address"},{"internalType":"uint256","name":"tokenId1","type":"uint256"},{"internalType":"uint256","name":"tokenId2","type":"uint256"},{"internalType":"uint256","name":"startTime","type":"uint256"},{"internalType":"bool","name":"completed","type":"bool"},{"internalType":"bool","name":"owner1Claimed","type":"bool"},{"internalType":"bool","name":"owner2Claimed","type":"bool"}],"internalType":"struct BreedingOrder","name":"","type":"tuple"}],"stateMutability":"view","type":"function"}
        ],
        stakingABI: [
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"stakeNFT","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"unstakeNFT","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"claimRewards","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"calculateRewards","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"isStaked","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"getUserStakes","outputs":[{"components":[{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"uint256","name":"level","type":"uint256"},{"internalType":"uint256","name":"stakedAt","type":"uint256"},{"internalType":"uint256","name":"lastRewardTime","type":"uint256"}],"internalType":"struct Stake[]","name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"getUserStakeCount","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"totalStakedNFTs","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getCurrentReleaseRatio","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
        ],
        tokenStakingABI: [
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"stakeTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"unstakeTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"claimRewards","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"getUserStake","outputs":[{"components":[{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"stakedAt","type":"uint256"},{"internalType":"uint256","name":"accumulatedRewards","type":"uint256"}],"internalType":"struct UserStake","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getContractBNBBalance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"totalStakedTokens","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getCurrentReleaseRatio","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"minimumStakeDuration","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
        ],
        arenaABI: [
            {"inputs":[],"stateMutability":"nonpayable","type":"constructor"},
            {"inputs":[{"internalType":"address","name":"_battleContract","type":"address"},{"internalType":"address","name":"_nftContract","type":"address"},{"internalType":"address","name":"_tokenContract","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"currentSeason","outputs":[{"internalType":"uint256","name":"seasonNumber","type":"uint256"},{"internalType":"uint256","name":"startTime","type":"uint256"},{"internalType":"uint256","name":"endTime","type":"uint256"},{"internalType":"bool","name":"isActive","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"rank","type":"uint256"}],"name":"calculateRewardForRank","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"rank","type":"uint256"}],"name":"getRewardForRank","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"seasonNumber","type":"uint256"}],"name":"calculateSeasonRewards","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"defender","type":"address"}],"name":"challenge","outputs":[{"internalType":"bool","name":"","type":"bool"},{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"seasonNumber","type":"uint256"}],"name":"claimReward","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"seasonNumber","type":"uint256"}],"name":"getPendingRewards","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"getPendingRewards","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"getPlayerRank","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"limit","type":"uint256"}],"name":"getLeaderboard","outputs":[{"components":[{"internalType":"address","name":"playerAddress","type":"address"},{"internalType":"uint256","name":"points","type":"uint256"},{"internalType":"uint256","name":"wins","type":"uint256"},{"internalType":"uint256","name":"losses","type":"uint256"},{"internalType":"bool","name":"isMock","type":"bool"}],"internalType":"struct ArenaRanking.LeaderboardEntry[]","name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"getPlayerBattleTeam","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"getRemainingAttempts","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"battleContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"nftContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"tokenContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"DAILY_ATTEMPTS","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"RECHARGE_AMOUNT","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"DEFAULT_RECHARGE_COST","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"TIER1_NFT_COUNT","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"DEFAULT_SEASON_REWARD_RATE","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"BPS","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rechargeCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"seasonRewardRate","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"mockPlayerCount","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"isMockPlayerActive","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"rewardTiers","outputs":[{"internalType":"uint256","name":"startRank","type":"uint256"},{"internalType":"uint256","name":"endRank","type":"uint256"},{"internalType":"uint256","name":"percentage","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"players","outputs":[{"internalType":"uint256","name":"points","type":"uint256"},{"internalType":"uint256","name":"wins","type":"uint256"},{"internalType":"uint256","name":"losses","type":"uint256"},{"internalType":"uint256","name":"lastBattleTime","type":"uint256"},{"internalType":"uint256","name":"lastResetTime","type":"uint256"},{"internalType":"uint256","name":"remainingAttempts","type":"uint256"},{"internalType":"uint256[]","name":"battleTeam","type":"uint256[]"},{"internalType":"bool","name":"hasTeam","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"seasonNumber","type":"uint256"}],"name":"seasons","outputs":[{"internalType":"uint256","name":"seasonNumber","type":"uint256"},{"internalType":"uint256","name":"startTime","type":"uint256"},{"internalType":"uint256","name":"endTime","type":"uint256"},{"internalType":"bool","name":"isActive","type":"bool"},{"internalType":"uint256","name":"totalRewardPool","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rechargeChallengeAttempts","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"clearBattleTeam","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"setBattleTeam","outputs":[],"stateMutability":"nonpayable","type":"function"}
        ]
    };

    validateContractAddresses();
    
    return {
        CONTRACT_ADDRESSES,
        NETWORK_ID,
        NETWORK_NAME,
        NETWORK_LABEL,
        getContractAddresses,
        MINT_COSTS,
        UPGRADE_COSTS,
        WEIGHTS,
        TAX_RATES,
        BREEDING_CONFIG,
        ARENA_CONFIG,
        IPFS_BASES,
        ZODIAC_NAMES,
        ATTR_NAMES,
        ATTR_PREFIXES,
        ANIMAL_KEYS,
        ABIS,
        ERROR_CODES,
        ERROR_PATTERNS,
        UI_ERROR_CODES,
        getErrorCodeMessage,
        getErrorMessage,
        validateContractAddresses
    };
})();