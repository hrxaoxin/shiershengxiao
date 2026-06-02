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
            console.warn(`[Config] ${contractName} address is zero address - please deploy and configure`);
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

    // 示例合约地址配置 - 部署后请替换为真实地址
    const CONTRACT_ADDRESSES = {
        tokenContract: getEnvContractAddress('token', '0x1234567890abcdef1234567890abcdef12345678'),
        rewardManager: getEnvContractAddress('rewardManager', '0x2345678901abcdef2345678901abcdef23456789'),
        dividendManager: getEnvContractAddress('dividendManager', '0x3456789012abcdef3456789012abcdef34567890'),
        weightManager: getEnvContractAddress('weightManager', '0x4567890123abcdef4567890123abcdef45678901'),
        poolManager: getEnvContractAddress('poolManager', '0x5678901234abcdef5678901234abcdef56789012'),
        tokenBurner: getEnvContractAddress('tokenBurner', '0x6789012345abcdef6789012345abcdef67890123'),
        nftMint: getEnvContractAddress('nftMint', '0x7890123456abcdef7890123456abcdef78901234'),
        nftData: getEnvContractAddress('nftData', '0x8901234567abcdef8901234567abcdef89012345'),
        nftUpdate: getEnvContractAddress('nftUpdate', '0x9012345678abcdef9012345678abcdef90123456'),
        nftTrading: getEnvContractAddress('nftTrading', '0x0123456789abcdef0123456789abcdef01234567'),
        breeding: getEnvContractAddress('breeding', '0xabcdef1234567890abcdef1234567890abcdef12'),
        staking: getEnvContractAddress('staking', '0xbcdef1234567890abcdef1234567890abcdef123'),
        tokenStaking: getEnvContractAddress('tokenStaking', '0xcdef1234567890abcdef1234567890abcdef1234'),
        arena: getEnvContractAddress('arena', '0xdef1234567890abcdef1234567890abcdef12345'),
        battle: getEnvContractAddress('battle', '0xef1234567890abcdef1234567890abcdef123456'),
        battleHistory: getEnvContractAddress('battleHistory', '0xf1234567890abcdef1234567890abcdef1234567'),
        priceOracle: getEnvContractAddress('priceOracle', '0x1111111111111111111111111111111111111111'),
        authorizer: getEnvContractAddress('authorizer', '0x2222222222222222222222222222222222222222'),
        battleSkillData: getEnvContractAddress('battleSkillData', '0x3333333333333333333333333333333333333333')
    };

    function getContractAddresses() {
        return CONTRACT_ADDRESSES;
    }

    const CONTRACT_ADDRESS_CATEGORIES = {
        core: ['nftMint', 'tokenContract', 'battle'],
        staking: ['staking', 'tokenStaking'],
        trading: ['nftTrading', 'breeding'],
        rewards: ['rewardManager', 'dividendManager', 'poolManager'],
        system: ['authorizer', 'weightManager', 'tokenBurner']
    };

    function validateContractAddresses() {
        const INVALID_ADDRESS = '0x0000000000000000000000000000000000000000';
        const TEST_ADDRESS_PATTERN = /^0x[0-9a-fA-F]{8}0{32}$/;
        const PLACEHOLDER_PATTERN = /^0x[0-9a-fA-F]{40}$/;
        
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
            console.error('[ZODIAC_CONFIG] Contract configuration issues detected:');
            
            if (invalidAddresses.length > 0) {
                console.error('Invalid addresses:', invalidAddresses);
            }
            
            if (placeholderAddresses.length > 0) {
                console.warn('[ZODIAC_CONFIG] Placeholder addresses (not deployed yet):');
                placeholderAddresses.forEach(([name, addr]) => {
                    console.warn(`  ${name}: ${addr}`);
                });
            }
            
            if (typeof window !== 'undefined' && window.console) {
                let warningMsg = '';
                
                if (invalidAddresses.length > 0) {
                    warningMsg += `错误: 检测到 ${invalidAddresses.length} 个无效合约地址！\n`;
                    warningMsg += '无效地址列表:\n';
                    warningMsg += invalidAddresses.map(([name, addr]) => `  ❌ ${name}: ${addr}`).join('\n');
                    warningMsg += '\n\n';
                }
                
                if (placeholderAddresses.length > 0) {
                    warningMsg += `警告: 检测到 ${placeholderAddresses.length} 个未部署的占位符地址\n`;
                    warningMsg += '占位符地址列表:\n';
                    warningMsg += placeholderAddresses.map(([name, addr]) => `  ⚠️  ${name}: ${addr}`).join('\n');
                    warningMsg += '\n\n';
                }
                
                warningMsg += '请参考 CONTRACT_DEPLOYMENT_GUIDE.md 进行合约部署和配置。\n';
                warningMsg += '或使用环境变量覆盖地址，如: window.ZODIAC_NFTMINT_ADDRESS = "0x..."';
                
                console.warn(warningMsg);
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
        targeted: 8888 * 6 * 10 + 88888 * 4 * 10
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
        dailyAttempts: 3,        // 与合约 DAILY_ATTEMPTS = 3 保持一致
        teamSize: 6,
        rechargeCost: 888,       // 销毁代币数量
        rechargeAttempts: 3,     // 充值获得的挑战次数
        battleCooldown: 60,      // 战斗冷却时间（秒）
        maxRechargeAttempts: 10  // 每日最大充值次数
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
            {"inputs":[{"internalType":"address","name":"_authorizer","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"owner","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint256","name":"index","type":"uint256"}],"name":"tokenOfOwnerByIndex","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getNFTData","outputs":[{"internalType":"uint256","name":"tokenType_","type":"uint256"},{"internalType":"uint256","name":"attack","type":"uint256"},{"internalType":"uint256","name":"defense","type":"uint256"},{"internalType":"uint256","name":"health","type":"uint256"},{"internalType":"uint256","name":"speed","type":"uint256"},{"internalType":"uint256","name":"level","type":"uint256"},{"internalType":"uint256","name":"rank","type":"uint256"},{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"imageUrl","type":"string"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"tokenType","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"tokenLevel","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"tokenGrowth","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"zodiacType","type":"uint256"}],"name":"mint","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256[]","name":"zodiacTypes","type":"uint256[]"}],"name":"mintBatch","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mintNormal","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mintRare","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mintNormalTen","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"}],"name":"mintRareTen","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint8","name":"baseZodiac","type":"uint8"}],"name":"mintTargeted","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"nextCardId","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"ownerOf","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"operator","type":"address"}],"name":"isApprovedForAll","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"operator","type":"address"},{"internalType":"bool","name":"approved","type":"bool"}],"name":"setApprovalForAll","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"uint256","name":"newLevel","type":"uint256"}],"name":"adminSetNFTLevel","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"string","name":"reason","type":"string"}],"name":"pause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"unpause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"paused","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"allowPublicMinting","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"bool","name":"allowed","type":"bool"}],"name":"setAllowPublicMinting","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getNFTType","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getNFTInfo","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint8","name":"","type":"uint8"},{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getNFTGrowth","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"isRare","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"isMaxLevel","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getNFTLevel","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"getNFTInfoBatch","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"owner","type":"address"}],"name":"getTokenIdsByOwner","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"safeTransferFrom","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"transferFrom","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"_tokenBurner","type":"address"}],"name":"setTokenBurner","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"_nftData","type":"address"}],"name":"setNFTDataContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"_threshold","type":"uint256"}],"name":"setRareTypeThreshold","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":false,"internalType":"uint256","name":"tokenId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"tokenType","type":"uint256"},{"indexed":false,"internalType":"uint8","name":"growth","type":"uint8"}],"name":"Mint","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":false,"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"BatchMint","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":false,"internalType":"uint256","name":"tokenId","type":"uint256"},{"indexed":false,"internalType":"uint8","name":"oldLevel","type":"uint8"},{"indexed":false,"internalType":"uint8","name":"newLevel","type":"uint8"}],"name":"Upgrade","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"tokenId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"zodiacType","type":"uint256"}],"name":"NFTDataSyncFailed","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":false,"internalType":"bool","name":"allowed","type":"bool"}],"name":"PublicMintingToggled","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"string","name":"reason","type":"string"}],"name":"Paused","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"}],"name":"Unpaused","type":"event"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawBNB","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"emergencyWithdrawNFT","outputs":[],"stateMutability":"nonpayable","type":"function"}
        ],
        tokenBurnerABI: [
            {"inputs":[],"name":"normalMintCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rareMintCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"normalMintTenCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rareMintTenCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"targetedMintCost","outputs":[{"internalType":"uint256","name":"normalPart","type":"uint256"},{"internalType":"uint256","name":"rarePart","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"bool","name":"isRare","type":"bool"}],"name":"burnAndMint","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"bool","name":"isRare","type":"bool"}],"name":"burnAndMintTen","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"uint8","name":"zodiac","type":"uint8"}],"name":"burnAndMintTargeted","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}
        ],
        tokenABI: [
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}
        ],
        rewardManagerABI: [
            {"inputs":[],"name":"dividendPool","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"totalDistributed","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"holdersCount","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"calcUserDividend","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"claimDividend","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"dividendPoolBalance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawBNB","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawTokens","outputs":[],"stateMutability":"nonpayable","type":"function"}
        ],
        battleABI: [
            {"inputs":[{"internalType":"uint256[6]","name":"attackerTeam","type":"uint256[6]"},{"internalType":"uint256[6]","name":"defenderTeam","type":"uint256[6]"}],"name":"battle","outputs":[{"internalType":"bool","name":"","type":"bool"},{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256[6]","name":"team1","type":"uint256[6]"},{"internalType":"uint256[6]","name":"team2","type":"uint256[6]"}],"name":"simulateBattle","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenType","type":"uint256"}],"name":"getSkill","outputs":[{"internalType":"uint256","name":"skillId","type":"uint256"},{"internalType":"uint8","name":"skillType_","type":"uint8"},{"internalType":"uint256","name":"damage","type":"uint256"},{"internalType":"uint256","name":"cooldown","type":"uint256"},{"internalType":"uint256","name":"duration","type":"uint256"},{"internalType":"bool","name":"isAoe","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"challengerId","type":"uint256"},{"internalType":"uint256","name":"challengedId","type":"uint256"},{"internalType":"uint256[6]","name":"challengerTeam","type":"uint256[6]"},{"internalType":"uint256[6]","name":"challengedTeam","type":"uint256[6]"},{"internalType":"address","name":"challengedAddress","type":"address"}],"name":"challenge","outputs":[{"internalType":"bool","name":"","type":"bool"},{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"MAX_ROUNDS","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"PRECISION","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"string","name":"reason","type":"string"}],"name":"pause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"unpause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"paused","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"_nftContract","type":"address"}],"name":"setNFTContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawBNB","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"emergencyWithdrawNFT","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"battleId","type":"uint256"},{"indexed":true,"internalType":"address","name":"challenger","type":"address"},{"indexed":true,"internalType":"address","name":"challenged","type":"address"},{"indexed":false,"internalType":"uint256[6]","name":"challengerTeam","type":"uint256[6]"},{"indexed":false,"internalType":"uint256[6]","name":"challengedTeam","type":"uint256[6]"}],"name":"BattleStarted","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"battleId","type":"uint256"},{"indexed":true,"internalType":"uint8","name":"winner","type":"uint8"}],"name":"BattleEnded","type":"event"}
        ],
        nftUpdateABI: [
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"upgradeWithNFT","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"upgradeWithToken","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"upgradeWithUSDValue","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"getTokenPriceFromPancakeSwap","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"level1UpgradeCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"level2UpgradeCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"level3UpgradeCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"level4UpgradeCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
        ],
        NFTTradingABI: [
            {"inputs":[{"internalType":"string","name":"reason","type":"string"}],"name":"pause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"unpause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"uint256","name":"priceWei","type":"uint256"}],"name":"listNFT","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"delistNFT","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"uint256","name":"newPriceWei","type":"uint256"}],"name":"updatePrice","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"buyNFT","outputs":[],"stateMutability":"payable","type":"function"},
            {"inputs":[],"name":"getListedNFTs","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getListingInfo","outputs":[{"internalType":"address","name":"seller","type":"address"},{"internalType":"uint256","name":"price","type":"uint256"},{"internalType":"uint256","name":"listTime","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"listings","outputs":[{"internalType":"address","name":"seller","type":"address"},{"internalType":"uint256","name":"priceWei","type":"uint256"},{"internalType":"uint256","name":"listTime","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"feePercent","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"feeReceiver","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"paused","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"pauseReason","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"_feeReceiver","type":"address"}],"name":"setFeeReceiver","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"_nftContract","type":"address"}],"name":"setNFTContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"percent","type":"uint256"}],"name":"setFeePercent","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"tokenId","type":"uint256"},{"indexed":false,"internalType":"address","name":"seller","type":"address"},{"indexed":false,"internalType":"uint256","name":"priceWei","type":"uint256"}],"name":"NFTListed","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"NFTDelisted","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"tokenId","type":"uint256"},{"indexed":false,"internalType":"address","name":"buyer","type":"address"},{"indexed":false,"internalType":"address","name":"seller","type":"address"},{"indexed":false,"internalType":"uint256","name":"priceWei","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"fee","type":"uint256"}],"name":"NFTBought","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"string","name":"reason","type":"string"}],"name":"Paused","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"}],"name":"Unpaused","type":"event"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawBNB","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"emergencyWithdrawNFT","outputs":[],"stateMutability":"nonpayable","type":"function"}
        ],
        breedingABI: [
            {"inputs":[],"name":"selfBreedingCooldown","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"marketBreedingCooldown","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"isInCooldown","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"fatherId","type":"uint256"},{"internalType":"uint256","name":"motherId","type":"uint256"},{"internalType":"uint256","name":"coOwnerId","type":"uint256"}],"name":"createSelfBreedingPair","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"fatherId","type":"uint256"},{"internalType":"uint256","name":"motherId","type":"uint256"}],"name":"createMarketBreedingPairPublic","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"breedingPairCount","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"pairId","type":"uint256"}],"name":"breedingPairs","outputs":[{"internalType":"uint256","name":"fatherId","type":"uint256"},{"internalType":"uint256","name":"motherId","type":"uint256"},{"internalType":"address","name":"maleOwner","type":"address"},{"internalType":"address","name":"femaleOwner","type":"address"},{"internalType":"uint256","name":"maleCoOwnerId","type":"uint256"},{"internalType":"uint256","name":"femaleCoOwnerId","type":"uint256"},{"internalType":"uint256","name":"startTime","type":"uint256"},{"internalType":"uint256","name":"breedingType","type":"uint256"},{"internalType":"uint256","name":"status","type":"uint256"},{"internalType":"uint256","name":"childId","type":"uint256"},{"internalType":"uint256","name":"maleChildId","type":"uint256"},{"internalType":"bool","name":"rewardsClaimed","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"pairId","type":"uint256"}],"name":"completeBreeding","outputs":[{"internalType":"uint256","name":"femaleChildId","type":"uint256"},{"internalType":"uint256","name":"maleChildId","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"pairId","type":"uint256"}],"name":"cancelBreeding","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"pairId","type":"uint256"}],"name":"getBreedingInfo","outputs":[{"internalType":"uint256","name":"fatherId","type":"uint256"},{"internalType":"uint256","name":"motherId","type":"uint256"},{"internalType":"address","name":"maleOwner","type":"address"},{"internalType":"address","name":"femaleOwner","type":"address"},{"internalType":"uint256","name":"maleCoOwnerId","type":"uint256"},{"internalType":"uint256","name":"femaleCoOwnerId","type":"uint256"},{"internalType":"uint256","name":"startTime","type":"uint256"},{"internalType":"uint256","name":"breedingType","type":"uint256"},{"internalType":"uint256","name":"status","type":"uint256"},{"internalType":"uint256","name":"childId","type":"uint256"},{"internalType":"uint256","name":"maleChildId","type":"uint256"},{"internalType":"bool","name":"rewardsClaimed","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"_nftContract","type":"address"}],"name":"setNFTContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"nftMintContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"listForMarketBreeding","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"delistFromMarketBreeding","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"getMarketListingIds","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getMarketListing","outputs":[{"components":[{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint256","name":"listTime","type":"uint256"},{"internalType":"bool","name":"isActive","type":"bool"}],"internalType":"struct Breeding.MarketListing","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getMarketListingCount","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"string","name":"reason","type":"string"}],"name":"pause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"unpause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"paused","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"_tokenContract","type":"address"}],"name":"setTokenContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"fee","type":"uint256"}],"name":"setSelfBreedingFee","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"fee","type":"uint256"}],"name":"setMarketBreedingFee","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"cooldown","type":"uint256"}],"name":"setSelfBreedingCooldown","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"cooldown","type":"uint256"}],"name":"setMarketBreedingCooldown","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"pairId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"fatherId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"motherId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"breedingType","type":"uint256"}],"name":"BreedingPairCreated","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"pairId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"childId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"zodiacType","type":"uint256"}],"name":"BreedingCompleted","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"pairId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"childId","type":"uint256"}],"name":"MaleChildGenerated","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"pairId","type":"uint256"}],"name":"BreedingCancelled","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"BreedingFeeBurned","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"tokenId","type":"uint256"},{"indexed":false,"internalType":"address","name":"owner","type":"address"}],"name":"MarketListingCreated","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"MarketListingRemoved","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"string","name":"reason","type":"string"}],"name":"Paused","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"}],"name":"Unpaused","type":"event"}
        ],
        stakingABI: [
            {"inputs":[{"internalType":"address","name":"_authorizer","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"stake","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"unstake","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"claimReward","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getPendingReward","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"stakingInfo","outputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint256","name":"stakeTime","type":"uint256"},{"internalType":"uint256","name":"lastClaimTime","type":"uint256"},{"internalType":"uint256","name":"accumulatedReward","type":"uint256"},{"internalType":"bool","name":"isRare","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserStakedNFTs","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"getStakingInfo","outputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint256","name":"stakeTime","type":"uint256"},{"internalType":"uint256","name":"lastClaimTime","type":"uint256"},{"internalType":"uint256","name":"accumulatedReward","type":"uint256"},{"internalType":"bool","name":"isRare","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserStakingStats","outputs":[{"internalType":"uint256","name":"totalStaked","type":"uint256"},{"internalType":"uint256","name":"totalPendingReward","type":"uint256"},{"internalType":"uint256","name":"rareCount","type":"uint256"},{"internalType":"uint256","name":"normalCount","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getPoolStats","outputs":[{"internalType":"uint256","name":"totalStakers","type":"uint256"},{"internalType":"uint256","name":"totalNFTs","type":"uint256"},{"internalType":"uint256","name":"todayIncoming","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserStakingRank","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"totalStakedNFTs","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"totalWeightedNFTs","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"minStakingDuration","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rewardRate","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"normalNFTWeight","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rareNFTWeight","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"_tokenContract","type":"address"}],"name":"setRewardTokenContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"rewardTokenContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"calculateDailyReward","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"string","name":"reason","type":"string"}],"name":"pause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"unpause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"paused","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"pauseReason","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"authorizer","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"_nftContract","type":"address"}],"name":"setNFTContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"nftContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"recordIncomingTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"Staked","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"Unstaked","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"RewardClaimed","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"string","name":"reason","type":"string"}],"name":"Paused","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"}],"name":"Unpaused","type":"event"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawBNB","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawTokens","outputs":[],"stateMutability":"nonpayable","type":"function"}
        ],
        arenaABI: [
            {"inputs":[],"stateMutability":"nonpayable","type":"constructor"},
            {"inputs":[{"internalType":"address","name":"_battleContract","type":"address"},{"internalType":"address","name":"_nftContract","type":"address"},{"internalType":"address","name":"_tokenContract","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"currentSeasonId","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"seasonDuration","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"baseRewardPerWin","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rewardTokenContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"authorizer","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"battleContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"nftContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"tokenContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"DAILY_ATTEMPTS","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rechargeCost","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"seasonRewardRate","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"rank","type":"uint256"}],"name":"calculateRewardForRank","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"rank","type":"uint256"}],"name":"getRewardForRank","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"seasonNumber","type":"uint256"}],"name":"calculateSeasonRewards","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256[6]","name":"playerTeam","type":"uint256[6]"},{"internalType":"uint256","name":"mockIndex","type":"uint256"}],"name":"challengeMockPlayer","outputs":[{"internalType":"bool","name":"success","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"challengedPlayer","type":"address"},{"internalType":"uint256[6]","name":"playerTeam","type":"uint256[6]"}],"name":"challengeRealPlayer","outputs":[{"internalType":"bool","name":"success","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"seasonNumber","type":"uint256"}],"name":"claimReward","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"claimSeasonReward","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"seasonNumber","type":"uint256"}],"name":"getPendingRewards","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"getPendingRewards","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"getPlayerRank","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"limit","type":"uint256"}],"name":"getLeaderboard","outputs":[{"components":[{"internalType":"address","name":"playerAddress","type":"address"},{"internalType":"uint256","name":"points","type":"uint256"},{"internalType":"uint256","name":"wins","type":"uint256"},{"internalType":"uint256","name":"losses","type":"uint256"},{"internalType":"bool","name":"isMock","type":"bool"}],"internalType":"struct ArenaRanking.LeaderboardEntry[]","name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"seasonId","type":"uint256"},{"internalType":"uint256","name":"count","type":"uint256"}],"name":"getTopPlayers","outputs":[{"internalType":"address[]","name":"playerAddrs","type":"address[]"},{"internalType":"uint256[]","name":"scores","type":"uint256[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"getPlayerBattleTeam","outputs":[{"internalType":"uint256[6]","name":"","type":"uint256[6]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"getRemainingAttempts","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"players","outputs":[{"internalType":"uint256","name":"score","type":"uint256"},{"internalType":"uint256","name":"wins","type":"uint256"},{"internalType":"uint256","name":"losses","type":"uint256"},{"internalType":"uint256","name":"lastBattleTime","type":"uint256"},{"internalType":"uint256","name":"lastResetTime","type":"uint256"},{"internalType":"uint256","name":"remainingAttempts","type":"uint256"},{"internalType":"uint256[]","name":"battleTeam","type":"uint256[]"},{"internalType":"bool","name":"hasTeam","type":"bool"},{"internalType":"uint256","name":"seasonId","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"seasonId","type":"uint256"}],"name":"seasons","outputs":[{"internalType":"uint256","name":"seasonId","type":"uint256"},{"internalType":"uint256","name":"startTime","type":"uint256"},{"internalType":"uint256","name":"endTime","type":"uint256"},{"internalType":"bool","name":"isActive","type":"bool"},{"internalType":"bool","name":"isSettled","type":"bool"},{"internalType":"uint256","name":"totalPlayers","type":"uint256"},{"internalType":"uint256","name":"rewardPool","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rechargeChallengeAttempts","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"clearBattleTeam","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256[6]","name":"tokenIds","type":"uint256[6]"}],"name":"setBattleTeam","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"stakeNFTs","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"unstakeNFTs","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserStakedNFTs","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"nftStakedOwner","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"uint256","name":"index","type":"uint256"}],"name":"userStakedNFTs","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"string","name":"reason","type":"string"}],"name":"pause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"unpause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setBattleContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setNFTContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setTokenContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"cost","type":"uint256"}],"name":"setRechargeCost","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"rate","type":"uint256"}],"name":"setSeasonRewardRate","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"startNewSeason","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"seasonId","type":"uint256"}],"name":"settleSeason","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"_tokenContract","type":"address"}],"name":"setRewardTokenContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"duration","type":"uint256"}],"name":"setSeasonDuration","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"addRewardToPool","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"seasonId","type":"uint256"}],"name":"getSeasonInfo","outputs":[{"internalType":"uint256","name":"startTime","type":"uint256"},{"internalType":"uint256","name":"endTime","type":"uint256"},{"internalType":"bool","name":"isActive","type":"bool"},{"internalType":"bool","name":"isSettled","type":"bool"},{"internalType":"uint256","name":"totalPlayers","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"getPlayerRecord","outputs":[{"internalType":"uint256","name":"score","type":"uint256"},{"internalType":"uint256","name":"wins","type":"uint256"},{"internalType":"uint256","name":"losses","type":"uint256"},{"internalType":"uint256","name":"seasonId","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"playerScores","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"playerInfo","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getCurrentRewardPool","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"getSeasonReward","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"player","type":"address"}],"name":"seasonRewardsClaimed","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"currentSeason","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"player","type":"address"},{"indexed":false,"internalType":"uint256","name":"newScore","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"seasonId","type":"uint256"}],"name":"ScoreUpdated","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"seasonId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"startTime","type":"uint256"}],"name":"SeasonStarted","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"seasonId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"endTime","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"totalPlayers","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"rewardPool","type":"uint256"}],"name":"SeasonSettled","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"player","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"seasonId","type":"uint256"}],"name":"RewardClaimed","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"player","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"seasonId","type":"uint256"}],"name":"SeasonRewardClaimed","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"challenger","type":"address"},{"indexed":true,"internalType":"address","name":"challenged","type":"address"},{"indexed":false,"internalType":"bool","name":"isVictory","type":"bool"},{"indexed":false,"internalType":"uint256","name":"seasonId","type":"uint256"}],"name":"ChallengeResult","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"player","type":"address"},{"indexed":false,"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"NFTsStaked","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"player","type":"address"},{"indexed":false,"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"NFTsUnstaked","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"player","type":"address"},{"indexed":false,"internalType":"uint256[]","name":"tokenIds","type":"uint256[]"}],"name":"BattleTeamSet","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"player","type":"address"}],"name":"BattleTeamCleared","type":"event"}
        ],
        tokenStakingABI: [
            {"inputs":[{"internalType":"address","name":"_tokenContract","type":"address"},{"internalType":"address","name":"_authorizer","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"tokenContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"authorizer","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"totalStakedTokens","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rewardRate","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"lastRewardUpdate","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"MIN_STAKING_DURATION","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"userStakes","outputs":[{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"lastRewardTime","type":"uint256"},{"internalType":"uint256","name":"accumulatedRewards","type":"uint256"},{"internalType":"uint256","name":"stakedAt","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"stakeTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"unstakeTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"claimRewards","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"rate","type":"uint256"}],"name":"setRewardRate","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"maxRate","type":"uint256"}],"name":"setMaxRewardRate","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"step","type":"uint256"}],"name":"setRateStep","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"_tokenContract","type":"address"}],"name":"setTokenContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"_tokenContract","type":"address"}],"name":"setTokenAddress","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"calculateDailyReward","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"string","name":"reason","type":"string"}],"name":"pause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"unpause","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"paused","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserStake","outputs":[{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"lastRewardTime","type":"uint256"},{"internalType":"uint256","name":"accumulatedRewards","type":"uint256"},{"internalType":"uint256","name":"stakedAt","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getTotalStaked","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getContractBNBBalance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getContractTokenBalance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"withdrawBNB","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"withdrawTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawBNB","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawTokens","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TokensStaked","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TokensUnstaked","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"RewardsClaimed","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"BNBReceived","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"operator","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"EmergencyBNBWithdrawn","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"operator","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"EmergencyTokensWithdrawn","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"string","name":"reason","type":"string"}],"name":"Paused","type":"event"},
            {"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"}],"name":"Unpaused","type":"event"}
        ],
        dividendManagerABI: [
            {"inputs":[{"internalType":"address","name":"_authorizer","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"authorizer","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"userWeights","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"pendingDividends","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"totalWeight","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"dividendPoolBalance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"dividendPool","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"tokenContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"lastSnapshotTime","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"snapshots","outputs":[{"internalType":"uint256","name":"totalWeight","type":"uint256"},{"internalType":"uint256","name":"totalDividend","type":"uint256"},{"internalType":"uint256","name":"perWeightDividend","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"lastSyncedBalance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"addDividendPool","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"syncDividendPool","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"claim","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"claimDividend","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"calcUserDividend","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"_pool","type":"address"}],"name":"setDividendPool","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"_tokenContract","type":"address"}],"name":"setTokenContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getClaimableDividend","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserWeight","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getTotalWeight","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"uint256","name":"weight","type":"uint256"}],"name":"setUserWeight","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"uint256","name":"level","type":"uint256"},{"internalType":"bool","name":"isAdd","type":"bool"},{"internalType":"uint8","name":"element","type":"uint8"}],"name":"updateUserWeight","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"index","type":"uint256"}],"name":"getSnapshot","outputs":[{"internalType":"uint256","name":"totalWeight","type":"uint256"},{"internalType":"uint256","name":"totalDividend","type":"uint256"},{"internalType":"uint256","name":"perWeightDividend","type":"uint256"},{"internalType":"uint256","name":"timestamp","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getSnapshotCount","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address[]","name":"users","type":"address[]"},{"internalType":"uint256[]","name":"weights","type":"uint256[]"}],"name":"updateUserWeightsBatch","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"calculateDividend","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getCurrentSnapshot","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawBNB","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdrawTokens","outputs":[],"stateMutability":"nonpayable","type":"function"}
        ],
        weightManagerABI: [
            {"inputs":[{"internalType":"address","name":"_authorizer","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"nftDataContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"authorizer","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"userWeight","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"cachedUserWeight","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"cachedWeightTimestamp","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"weightCacheDuration","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"eligibleUserPrev","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"eligibleUserNext","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"inEligibleList","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"eligibleUserHead","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"eligibleUserTail","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"minOwnerWeight","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"ownerWeight","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"_nftDataContract","type":"address"}],"name":"setNFTDataContract","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"_minWeight","type":"uint256"}],"name":"setMinOwnerWeight","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"_w","type":"uint256"}],"name":"setOwnerWeight","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserWeight","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"refreshUserWeightCache","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address[]","name":"users","type":"address[]"}],"name":"batchRefreshUserWeightCache","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"duration","type":"uint256"}],"name":"setWeightCacheDuration","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"clearUserWeightCache","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"hasEligibility","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"updateUserWeight","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"addHolder","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"removeHolder","outputs":[],"stateMutability":"nonpayable","type":"function"}
        ],
        priceOracleABI: [
            {"inputs":[{"internalType":"address","name":"_authorizer","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"tokenAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"usdtAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"authorizer","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"tokenPriceUSD","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"ethPriceUSD","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"TOKEN_PRECISION","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"USDT_PRECISION","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"_tokenAddress","type":"address"}],"name":"setTokenAddress","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"_usdtAddress","type":"address"}],"name":"setUSDTAddress","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"_tokenPriceUSD","type":"uint256"}],"name":"updateTokenPrice","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"_ethPriceUSD","type":"uint256"}],"name":"updateETHPrice","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"_tokenPriceUSD","type":"uint256"},{"internalType":"uint256","name":"_ethPriceUSD","type":"uint256"}],"name":"updatePrices","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"getTokenPrice","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getETHPrice","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenAmount","type":"uint256"}],"name":"calculateUSDTEquivalent","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"usdtAmount","type":"uint256"}],"name":"calculateTokenEquivalent","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"ethAmount","type":"uint256"}],"name":"calculateETHUSDTEquivalent","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getPrecisionInfo","outputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"isPriceValid","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"}
        ],
        poolManagerABI: [
            {"inputs":[{"internalType":"address","name":"_authorizer","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"authorizer","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"poolBalances","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"paused","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"addToNFTStakingPool","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"addToTokenStakingPool","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"addToArenaRewardPool","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"withdrawFromNFTStakingPool","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"withdrawFromTokenStakingPool","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"poolType","type":"uint256"}],"name":"getPoolBalance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"emergencyWithdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"bool","name":"_paused","type":"bool"}],"name":"setPaused","outputs":[],"stateMutability":"nonpayable","type":"function"}
        ],
        nftDataABI: [
            {"inputs":[{"internalType":"address","name":"_authorizer","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"authorizer","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"tokenType","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"tokenLevel","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"uint8","name":"level","type":"uint8"}],"name":"setTokenLevel","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"calcUserWeight","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"tokenId","type":"uint256"},{"internalType":"uint256","name":"zodiacType","type":"uint256"},{"internalType":"uint8","name":"level","type":"uint8"},{"internalType":"uint8","name":"growth","type":"uint8"},{"internalType":"uint256","name":"mintTime","type":"uint256"},{"internalType":"address","name":"owner","type":"address"}],"name":"setNFTInfo","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"addUserNFT","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"uint256","name":"tokenId","type":"uint256"}],"name":"removeUserNFT","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserNFTs","outputs":[{"internalType":"uint256[]","name":"","type":"uint256[]"}],"stateMutability":"view","type":"function"}
        ],
        battleHistoryABI: [
            {"inputs":[{"internalType":"address","name":"_authorizer","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"battleId","type":"uint256"},{"internalType":"address","name":"challenger","type":"address"},{"internalType":"address","name":"challenged","type":"address"},{"internalType":"uint8","name":"winner","type":"uint8"},{"internalType":"uint256","name":"challengerTeamHash","type":"uint256"},{"internalType":"uint256","name":"challengedTeamHash","type":"uint256"},{"internalType":"uint256","name":"battleTime","type":"uint256"}],"name":"addBattleHistory","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[{"internalType":"address","name":"user","type":"address"}],"name":"getUserBattleHistory","outputs":[{"components":[{"internalType":"uint256","name":"battleId","type":"uint256"},{"internalType":"address","name":"challenger","type":"address"},{"internalType":"address","name":"challenged","type":"address"},{"internalType":"uint8","name":"winner","type":"uint8"},{"internalType":"uint256","name":"battleTime","type":"uint256"}],"internalType":"struct BattleHistory.BattleRecord[]","name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"battleId","type":"uint256"}],"name":"getBattleRecord","outputs":[{"components":[{"internalType":"uint256","name":"battleId","type":"uint256"},{"internalType":"address","name":"challenger","type":"address"},{"internalType":"address","name":"challenged","type":"address"},{"internalType":"uint8","name":"winner","type":"uint8"},{"internalType":"uint256","name":"challengerTeamHash","type":"uint256"},{"internalType":"uint256","name":"challengedTeamHash","type":"uint256"},{"internalType":"uint256","name":"battleTime","type":"uint256"}],"internalType":"struct BattleHistory.BattleRecord","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"getRecentBattles","outputs":[{"components":[{"internalType":"uint256","name":"battleId","type":"uint256"},{"internalType":"address","name":"challenger","type":"address"},{"internalType":"address","name":"challenged","type":"address"},{"internalType":"uint8","name":"winner","type":"uint8"},{"internalType":"uint256","name":"battleTime","type":"uint256"}],"internalType":"struct BattleHistory.BattleRecord[]","name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"authorizer","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"uint256","name":"","type":"uint256"}],"name":"userBattleIds","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"battleRecords","outputs":[{"internalType":"uint256","name":"battleId","type":"uint256"},{"internalType":"address","name":"challenger","type":"address"},{"internalType":"address","name":"challenged","type":"address"},{"internalType":"uint8","name":"winner","type":"uint8"},{"internalType":"uint256","name":"challengerTeamHash","type":"uint256"},{"internalType":"uint256","name":"challengedTeamHash","type":"uint256"},{"internalType":"uint256","name":"battleTime","type":"uint256"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"battleCount","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
        ],
        authorizerABI: [
            {"inputs":[{"internalType":"address","name":"_authorizer","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"authorizer","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"a","type":"address"}],"name":"setAuthorizer","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"admin","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[{"internalType":"address","name":"_admin","type":"address"}],"name":"setAdmin","outputs":[],"stateMutability":"nonpayable","type":"function"},
            {"inputs":[],"name":"tokenAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"usdtAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"battleAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"breedingAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"stakingAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"rewardManagerAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"dividendManagerAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"priceOracleAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"arenaRankingAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"nftDataAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"poolManagerAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"weightManagerAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"battleHistoryAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"nftTradingAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
            {"inputs":[],"name":"nftMintAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"}
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