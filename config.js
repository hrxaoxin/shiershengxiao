window.ZODIAC_CONFIG = (function() {
    const NETWORK_ID = 56;
    const NETWORK_NAME = 'Binance Mainnet';
    const NETWORK_LABEL = 'BNB主网';

    const NETWORK_CONFIG = {
        explorerUrl: 'https://bscscan.com'
    };

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

    const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

    function isValidAddress(address) {
        return address && /^0x[a-fA-F0-9]{40}$/.test(address);
    }

    function isZeroAddress(address) {
        return address === ZERO_ADDRESS;
    }

    function validateContractAddress(address, contractName) {
        if (!isValidAddress(address)) {
            console.warn(`[Config] ${contractName} address is invalid: ${address}`);
            return false;
        }
        if (isZeroAddress(address)) {
            console.warn(`[Config] ${contractName} address is zero address`);
            return false;
        }
        return true;
    }

    function validateAllAddresses() {
        const missingAddresses = [];
        for (const [name, address] of Object.entries(CONTRACT_ADDRESSES)) {
            if (isZeroAddress(address)) {
                missingAddresses.push(name);
            }
        }
        if (missingAddresses.length > 0) {
            console.error('[Config] Missing contract addresses:', missingAddresses.join(', '));
            return false;
        }
        return true;
    }

    function getEnvContractAddress(key, defaultAddress) {
        const envKey = `ZODIAC_${key.toUpperCase()}_ADDRESS`;
        const envValue = typeof window !== 'undefined' ? window[envKey] : null;
        if (envValue && /^0x[a-fA-F0-9]{40}$/.test(envValue)) {
            return envValue;
        }
        return defaultAddress;
    }

    const DEX_ROUTERS = {
        flapswap: getEnvContractAddress('flapswapRouter', '0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0'),
        pancakeswap: getEnvContractAddress('pancakeswapRouter', '0x10ED43C718714eb63d5aA57B78B54704E256024E'),
        uniswap: getEnvContractAddress('uniswapRouter', '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'),
        wbnb: getEnvContractAddress('wbnb', '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c')
    };

    const CONTRACT_ADDRESSES = {
        tokenContract: getEnvContractAddress('token', '0xd06994d9ff24dc4a579f53c91f65d95b6be97777'),
        authorizer: getEnvContractAddress('authorizer', '0x409A59c107E8670963cb628e4E09ae4186b4BebF'),
        rewardManager: getEnvContractAddress('rewardManager', '0x6D55EFB4Ebd1d669C67bc05FF90E1f5277D01D5A'),
        dividendManager: getEnvContractAddress('dividendManager', '0x50240F87d37334f95474F4b26dadFc02D1f87767'),
        weightManager: getEnvContractAddress('weightManager', '0x2fE5De4e37b82C73642d0498A0e56F5A9463D769'),
        poolManager: getEnvContractAddress('poolManager', '0x0400C494B28b731957A12A41dAf73349e6B66967'),
        tokenBurner: getEnvContractAddress('tokenBurner', '0x6c33019B6EDc26cFB6fb4F43760100Be30b821e2'),
        nftMint: getEnvContractAddress('nftMint', '0x2716C46B184aaDcD16bA402F01cF3DC5459e3d60'),
        nftMintCore: getEnvContractAddress('nftMintCore', '0x2716C46B184aaDcD16bA402F01cF3DC5459e3d60'),
        nftMintMetadata: getEnvContractAddress('nftMintMetadata', '0x2ee4dC26886E68c9EACDab47EC94525A4f2D43e1'),
        nftData: getEnvContractAddress('nftData', '0x11B4E7043d82c9376Fc90C6b73353262b4D39e10'),
        nftUpdate: getEnvContractAddress('nftUpdate', '0x780b78A5fd4e67876c02025caae9A7Bab6E1f0Ed'),
        nftTrading: getEnvContractAddress('nftTrading', '0x565b1C7Fc3609898583EBBa7f438172084063796'),
        nftBuyback: getEnvContractAddress('nftBuyback', '0x588abAcAce6cf149b299c63f9aDCf833fB2AF748'),
        breedingCore: getEnvContractAddress('breedingCore', '0x315a469d71E5e6bfdC56325a81399d6609fb0F41'),
        breedingMarket: getEnvContractAddress('breedingMarket', '0x8D9b20834963128D7A04dCE06e15666De759e202'),
        staking: getEnvContractAddress('staking', '0x02C5824812495E273AfE2449dfa0EAFB2E638A85'),
        tokenStaking: getEnvContractAddress('tokenStaking', '0xbe98b16313616a6090ccccc7fc70f2f679bcabe7'),
        arena: getEnvContractAddress('arena', '0x6231ec0A4835b93907e6Dc8f2246Dd998A1f338A'),
        arenaRankingManager: getEnvContractAddress('arenaRankingManager', '0xC762FBFc2A68877025941DaE2F85a3c69b3720B1'),
        arenaRankingQuery: getEnvContractAddress('arenaRankingQuery', '0xEA1478679E9dFb3564f007ef1CA2F3Af97D573de'),
        arenaReward: getEnvContractAddress('arenaReward', '0xb19D763F7a2Fac41F77cEc3c9816f804d6719012'),
        arenaLeaderboard: getEnvContractAddress('arenaLeaderboard', '0xA2DEc96b9F94C9d86D64c472Fe1392618F9068af'),
        arenaPlayer: getEnvContractAddress('arenaPlayer', '0x7d52eACbB22221Bba2C9Aad8BFa123DeF8F8898C'),
        arenaBattle: getEnvContractAddress('arenaBattle', '0x6231ec0A4835b93907e6Dc8f2246Dd998A1f338A'),
        battle: getEnvContractAddress('battle', '0xB4512a36D9398C3C2C26d3ca57547301cD0524d6'),
        battleHistory: getEnvContractAddress('battleHistory', '0xE2931bd0bc6E5C9509350A86117748403C6293Ae'),
        battleSkillData: getEnvContractAddress('battleSkillData', '0x331B7d99A491145E6fE900C14ED78940AfC62B45'),
        priceOracle: getEnvContractAddress('priceOracle', '0x60678Fc8608C4cd16bF1F07A2312F664486A1E4C')
    };

    function getContractAddresses() {
        return CONTRACT_ADDRESSES;
    }

    const CONTRACT_ADDRESS_CATEGORIES = {
        core: ['nftMint', 'tokenContract', 'battle', 'nftData'],
        staking: ['staking', 'tokenStaking'],
        trading: ['nftTrading', 'breedingCore', 'breedingMarket'],
        rewards: ['rewardManager', 'dividendManager', 'poolManager', 'arenaReward'],
        system: ['authorizer', 'weightManager', 'tokenBurner'],
        arena: ['arena', 'arenaReward', 'arenaLeaderboard', 'arenaPlayer', 'arenaBattle', 'battleHistory', 'battleSkillData'],
        oracle: ['priceOracle'],
        upgrade: ['nftUpdate']
    };

    function validateContractAddresses() {
        const INVALID_ADDRESS = '0x0000000000000000000000000000000000000000';
        const TEST_ADDRESS_PATTERN = /^0x[0-9a-fA-F]{8}0{32}$/;
        const PLACEHOLDER_PATTERN = /^0x0{40}$/;
        
        const invalidAddresses = Object.entries(CONTRACT_ADDRESSES)
            .filter(([name, addr]) => {
                if (!/^0x[a-fA-F0-9]{40}$/.test(addr)) return true;
                if (addr === INVALID_ADDRESS) return true;
                if (TEST_ADDRESS_PATTERN.test(addr)) return true;
                return false;
            });
        
        const placeholderAddresses = Object.entries(CONTRACT_ADDRESSES)
            .filter(([name, addr]) => PLACEHOLDER_PATTERN.test(addr));
        
        if (invalidAddresses.length > 0 || placeholderAddresses.length > 0) {
            console.error('[ZODIAC_CONFIG] Contract configuration issues detected');
            if (invalidAddresses.length > 0) {
                console.error('Invalid addresses:', invalidAddresses);
            }
            if (placeholderAddresses.length > 0) {
                console.warn('[ZODIAC_CONFIG] Placeholder addresses:', placeholderAddresses);
            }
        }
        return invalidAddresses.length === 0;
    }

    function getContractStatus() {
        const INVALID_ADDRESS = '0x0000000000000000000000000000000000000000';
        const TEST_ADDRESS_PATTERN = /^0x[0-9a-fA-F]{8}0{32}$/;
        
        const status = {};
        let deployedCount = 0;
        let totalCount = 0;
        
        Object.entries(CONTRACT_ADDRESSES).forEach(([name, addr]) => {
            totalCount++;
            const isValid = /^0x[a-fA-F0-9]{40}$/.test(addr) && 
                           addr !== INVALID_ADDRESS && 
                           !TEST_ADDRESS_PATTERN.test(addr);
            
            status[name] = {
                address: addr,
                isDeployed: isValid,
                category: Object.keys(CONTRACT_ADDRESS_CATEGORIES).find(
                    cat => CONTRACT_ADDRESS_CATEGORIES[cat].includes(name)
                ) || 'other'
            };
            
            if (isValid) deployedCount++;
        });
        
        return {
            contracts: status,
            deployedCount,
            totalCount,
            isProductionReady: deployedCount === totalCount
        };
    }

    function getRequiredContracts() {
        return Object.entries(CONTRACT_ADDRESS_CATEGORIES)
            .filter(([cat]) => ['core', 'staking', 'trading'].includes(cat))
            .flatMap(([, names]) => names)
            .filter(name => {
                const addr = CONTRACT_ADDRESSES[name];
                return addr && addr !== '0x0000000000000000000000000000000000000000';
            });
    }

    const MINT_COSTS = {
        normal: 8888,
        rare: 88888,
        normalTen: 88880,
        rareTen: 888880,
        targeted: (8888 * 6 + 88888 * 4) * 10
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
        dailyAttempts: 3,
        teamSize: 6,
        rechargeCost: 888,
        rechargeAttempts: 3,
        battleCooldown: 60,
        maxRechargeAttempts: 5
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
        nftMintABI: [
            { "inputs": [], "name": "name", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "symbol", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "ownerOf", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "owner", "type": "address" }], "name": "balanceOf", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "totalSupply", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "tokenURI", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "to", "type": "address" }, { "internalType": "uint256", "name": "zodiacType", "type": "uint256" }], "name": "mint", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "to", "type": "address" }], "name": "mintNormal", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "to", "type": "address" }], "name": "mintRare", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "from", "type": "address" }, { "internalType": "address", "name": "to", "type": "address" }, { "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "safeTransferFrom", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "isRare", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "getNFTData", "outputs": [{ "internalType": "uint256", "name": "tokenType_", "type": "uint256" }, { "internalType": "uint8", "name": "level", "type": "uint8" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "owner", "type": "address" }], "name": "getTokenIdsByOwner", "outputs": [{ "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "authorizer", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" },
            { "anonymous": false, "inputs": [{ "indexed": true, "internalType": "uint256", "name": "tokenId", "type": "uint256" }, { "indexed": false, "internalType": "address", "name": "from", "type": "address" }, { "indexed": false, "internalType": "address", "name": "to", "type": "address" }], "name": "Transfer", "type": "event" }
        ],
        tokenABI: [
            { "inputs": [], "name": "name", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "symbol", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "decimals", "outputs": [{ "internalType": "uint8", "name": "", "type": "uint8" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "totalSupply", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "account", "type": "address" }], "name": "balanceOf", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "owner", "type": "address" }, { "internalType": "address", "name": "spender", "type": "address" }], "name": "allowance", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "recipient", "type": "address" }, { "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "transfer", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "spender", "type": "address" }, { "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "approve", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "sender", "type": "address" }, { "internalType": "address", "name": "recipient", "type": "address" }, { "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "transferFrom", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "nonpayable", "type": "function" }
        ],
        NFTTradingABI: [
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }, { "internalType": "uint256", "name": "priceWei", "type": "uint256" }], "name": "listNFT", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "buyNFT", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "delistNFT", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "name": "listings", "outputs": [{ "internalType": "address", "name": "seller", "type": "address" }, { "internalType": "uint256", "name": "priceWei", "type": "uint256" }, { "internalType": "uint256", "name": "startTime", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "account", "type": "address" }], "name": "getUserListings", "outputs": [{ "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "getAllListings", "outputs": [{ "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "nftContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        stakingABI: [
            { "inputs": [{ "internalType": "uint256[]", "name": "tokenIds", "type": "uint256[]" }], "name": "stake", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256[]", "name": "tokenIds", "type": "uint256[]" }], "name": "unstake", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [], "name": "claimReward", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }], "name": "getPendingReward", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }], "name": "getUserStakingStats", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }], "name": "getUserStakedNFTs", "outputs": [{ "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "nftContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        tokenStakingABI: [
            { "inputs": [{ "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "stakeTokens", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "unstakeTokens", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [], "name": "claimRewards", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }], "name": "getPendingRewards", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        breedingCoreABI: [
            { "inputs": [{ "internalType": "uint256", "name": "maleTokenId", "type": "uint256" }, { "internalType": "uint256", "name": "femaleTokenId", "type": "uint256" }], "name": "createSelfBreedingPair", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "pairId", "type": "uint256" }], "name": "completeBreeding", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "pairId", "type": "uint256" }], "name": "cancelBreeding", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }], "name": "getUserBreedingPairs", "outputs": [{ "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "nftContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        breedingMarketABI: [
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }, { "internalType": "uint256", "name": "fee", "type": "uint256" }], "name": "listForMarketBreeding", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "listingId", "type": "uint256" }], "name": "delistFromMarketBreeding", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "listingId", "type": "uint256" }, { "internalType": "uint256", "name": "maleTokenId", "type": "uint256" }], "name": "useMarketBreeding", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [], "name": "getAllMarketListings", "outputs": [{ "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" }
        ],
        rewardManagerABI: [
            { "inputs": [{ "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "distributeRewards", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [], "name": "totalDistributed", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "getDistributionPercents", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        dividendManagerABI: [
            { "inputs": [], "name": "claimDividend", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }], "name": "calcUserDividend", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }], "name": "getUserWeight", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "getWeightConfig", "outputs": [{ "internalType": "uint256[]", "name": "", "type": "uint256[]" }, { "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "level", "type": "uint256" }, { "internalType": "bool", "name": "isRare", "type": "bool" }], "name": "getNFTWeight", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "dividendPoolBalance", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        tokenBurnerABI: [
            { "inputs": [{ "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "burn", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [], "name": "burnedTotal", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        nftUpdateABI: [
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "upgrade", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }, { "internalType": "uint256", "name": "nftCount", "type": "uint256" }], "name": "upgradeWithNFT", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [], "name": "nftContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        battleABI: [
            { "inputs": [{ "internalType": "uint256", "name": "attackerId", "type": "uint256" }, { "internalType": "uint256", "name": "defenderId", "type": "uint256" }], "name": "battle", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }, { "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "getNFTStats", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "nftContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        arenaABI: [
            { "inputs": [{ "internalType": "uint256[]", "name": "tokenIds", "type": "uint256[]" }], "name": "stakeArenaNFTs", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256[]", "name": "tokenIds", "type": "uint256[]" }], "name": "unstakeArenaNFTs", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [], "name": "rechargeChallengeAttempts", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "opponentPlayerId", "type": "uint256" }], "name": "challengeRealPlayer", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [], "name": "challengeMockPlayer", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }], "name": "getRemainingAttempts", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        arenaRewardABI: [
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }], "name": "claimSeasonReward", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }], "name": "getPendingReward", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        arenaLeaderboardABI: [
            { "inputs": [], "name": "getTopPlayers", "outputs": [{ "internalType": "address[]", "name": "", "type": "address[]" }, { "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "player", "type": "address" }], "name": "getPlayerRank", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" }
        ],
        arenaPlayerABI: [
            { "inputs": [{ "internalType": "uint256[]", "name": "team", "type": "uint256[]" }], "name": "setBattleTeam", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }], "name": "getPlayerId", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "playerId", "type": "uint256" }], "name": "getPlayerInfo", "outputs": [{ "internalType": "address", "name": "", "type": "address" }, { "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "arena", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        arenaBattleABI: [
            { "inputs": [{ "internalType": "uint256", "name": "player1Id", "type": "uint256" }, { "internalType": "uint256", "name": "player2Id", "type": "uint256" }], "name": "startBattle", "outputs": [], "stateMutability": "nonpayable", "type": "function" }
        ],
        priceOracleABI: [
            { "inputs": [], "name": "latestAnswer", "outputs": [{ "internalType": "int256", "name": "", "type": "int256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "decimals", "outputs": [{ "internalType": "uint8", "name": "", "type": "uint8" }], "stateMutability": "view", "type": "function" }
        ],
        buybackABI: [
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "buybackNFT", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [], "name": "nftContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        nftDataABI: [
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "getCardInfo", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "zodiacType", "type": "uint256" }, { "internalType": "uint256", "name": "level", "type": "uint256" }], "name": "getCardInfoByType", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" }
        ],
        authorizerABI: [
            { "inputs": [], "name": "getToken", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "bytes32", "name": "key", "type": "bytes32" }, { "internalType": "address", "name": "addr", "type": "address" }], "name": "setAddress", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "addr", "type": "address" }], "name": "isSystemContract", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "bytes32[]", "name": "keys", "type": "bytes32[]" }, { "internalType": "address[]", "name": "addrs", "type": "address[]" }], "name": "setAllContracts", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "bytes32", "name": "key", "type": "bytes32" }], "name": "_addresses", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        poolManagerABI: [
            { "inputs": [{ "internalType": "uint256", "name": "amount", "type": "uint256" }, { "internalType": "uint8", "name": "poolType", "type": "uint8" }], "name": "deposit", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "amount", "type": "uint256" }, { "internalType": "uint8", "name": "poolType", "type": "uint8" }], "name": "withdraw", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "user", "type": "address" }, { "internalType": "uint8", "name": "poolType", "type": "uint8" }], "name": "getUserBalance", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ],
        weightManagerABI: [
            { "inputs": [], "name": "getNormalWeights", "outputs": [{ "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "getRareWeights", "outputs": [{ "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "uint256[]", "name": "normalWeights", "type": "uint256[]" }, { "internalType": "uint256[]", "name": "rareWeights", "type": "uint256[]" }], "name": "setWeights", "outputs": [], "stateMutability": "nonpayable", "type": "function" }
        ],
        battleSkillDataABI: [
            { "inputs": [{ "internalType": "uint256", "name": "skillId", "type": "uint256" }], "name": "getSkill", "outputs": [{ "internalType": "string", "name": "", "type": "string" }, { "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "skillId", "type": "uint256" }, { "internalType": "string", "name": "name", "type": "string" }, { "internalType": "uint256", "name": "damage", "type": "uint256" }, { "internalType": "uint256", "name": "cooldown", "type": "uint256" }], "name": "setSkill", "outputs": [], "stateMutability": "nonpayable", "type": "function" }
        ],
        arenaRankingManagerABI: [
            { "inputs": [], "name": "currentSeason", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "endSeason", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "name": "seasonRankings", "outputs": [{ "internalType": "address", "name": "player", "type": "address" }, { "internalType": "uint256", "name": "score", "type": "uint256" }], "stateMutability": "view", "type": "function" }
        ],
        arenaRankingQueryABI: [
            { "inputs": [], "name": "getTop100Players", "outputs": [{ "internalType": "address[]", "name": "", "type": "address[]" }, { "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "address", "name": "player", "type": "address" }], "name": "getPlayerCurrentRank", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }, { "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" }
        ],
        battleHistoryABI: [
            { "inputs": [{ "internalType": "address", "name": "player", "type": "address" }], "name": "getPlayerHistory", "outputs": [{ "internalType": "uint256[]", "name": "", "type": "uint256[]" }], "stateMutability": "view", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "name": "history", "outputs": [{ "internalType": "address", "name": "player", "type": "address" }, { "internalType": "uint256", "name": "opponentId", "type": "uint256" }, { "internalType": "bool", "name": "won", "type": "bool" }, { "internalType": "uint256", "name": "timestamp", "type": "uint256" }], "stateMutability": "view", "type": "function" }
        ],
        breedingABI: [
            { "inputs": [{ "internalType": "uint256", "name": "maleTokenId", "type": "uint256" }, { "internalType": "uint256", "name": "femaleTokenId", "type": "uint256" }], "name": "breed", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }, { "internalType": "uint256", "name": "fee", "type": "uint256" }], "name": "listForBreeding", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "tokenId", "type": "uint256" }], "name": "delistFromBreeding", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [{ "internalType": "uint256", "name": "listingId", "type": "uint256" }, { "internalType": "uint256", "name": "maleTokenId", "type": "uint256" }], "name": "useBreedingService", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
            { "inputs": [], "name": "tokenContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" },
            { "inputs": [], "name": "nftContract", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }
        ]
    };

    function getABI(abiName) {
        return ABIS[abiName] || null;
    }

    return {
        NETWORK_ID,
        NETWORK_NAME,
        NETWORK_LABEL,
        NETWORK_CONFIG,
        ERROR_CODES,
        ERROR_PATTERNS,
        UI_ERROR_CODES,
        getErrorCodeMessage,
        getErrorMessage,
        ZERO_ADDRESS,
        isValidAddress,
        isZeroAddress,
        validateContractAddress,
        validateAllAddresses,
        getEnvContractAddress,
        CONTRACT_ADDRESSES,
        getContractAddresses,
        CONTRACT_ADDRESS_CATEGORIES,
        validateContractAddresses,
        getContractStatus,
        getRequiredContracts,
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
        getABI
    };
})();
