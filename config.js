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

    // DEX Router 配置（支持 FlapSwap、PancakeSwap、Uniswap）
    const DEX_ROUTERS = {
        flapswap: getEnvContractAddress('flapswapRouter', '0x1111111111111111111111111111111111111111'),
        pancakeswap: getEnvContractAddress('pancakeswapRouter', '0x10ED43C718714eb63d5aA57B78B54704E256024E'),
        uniswap: getEnvContractAddress('uniswapRouter', '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'),
        wbnb: getEnvContractAddress('wbnb', '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c')
    };

    // 示例合约地址配置 - 部署后请替换为真实地址
    const CONTRACT_ADDRESSES = {
        tokenContract: getEnvContractAddress('token', '0xd06994d9ff24dc4a579f53c91f65d95b6be97777'),
        authorizer: getEnvContractAddress('authorizer', '0xaEca8eeDbd6b5c3f0BE7f455CBbB9a4D7D3ACb4E'),
        rewardManager: getEnvContractAddress('rewardManager', '0xC48419D52131A68d5399Fd4c8e9969bF7AeF2Ba0'),
        dividendManager: getEnvContractAddress('dividendManager', '0x58032Cc1AceD16a9A1412c1898E39e162D786B82'),
        weightManager: getEnvContractAddress('weightManager', '0xE9e8ff9172c24191809bA367e0518e332a7B65E1'),
        poolManager: getEnvContractAddress('poolManager', '0xE7f4396A2e75103500f8ED3B94790969EBB12FCd'),
        tokenBurner: getEnvContractAddress('tokenBurner', '0x8c2345A68d0eD20cc80bd12fdC29A993b65b5126'),
        nftMint: getEnvContractAddress('nftMint', '0xF90fF85e84c685Df88e493dfF1c5E45B373C232D'),
        nftMintCore: getEnvContractAddress('nftMintCore', '0xF90fF85e84c685Df88e493dfF1c5E45B373C232D'),
        nftMintBatch: getEnvContractAddress('nftMintBatch', '0x6c39eE3977589Aa5B0f2974C969aF4540942F8B4'),
        nftMintMetadata: getEnvContractAddress('nftMintMetadata', '0xBf262E129CCf74Ee4184c1b7FeAdb27F1cbFe1ef'),
        nftData: getEnvContractAddress('nftData', '0xb6476a82d8cf264d7989d0e3e80ad23095c0d076'),
        nftUpdate: getEnvContractAddress('nftUpdate', '0x54EB8F7C9Bd6fe1a15c0a72D23c72c9E03BCB2c4'),
        nftTrading: getEnvContractAddress('nftTrading', '0xC9871DCD76092016d95B8Ae34409D505970Fe8f3'),
        nftBuyback: getEnvContractAddress('nftBuyback', '0x5d03d6b1dDaFE78920094DA092975D98b515cfE2'),
        breedingCore: getEnvContractAddress('breedingCore', '0x788f720cDCB02da277Df598C26D4DCc642641C86'),
        breedingMarket: getEnvContractAddress('breedingMarket', '0x9157284f75b1561436818a6C984Ab55CDEf3F903'),
        staking: getEnvContractAddress('staking', '0x3A87B0F6513068F0f0C3AB34d1277540c03c609C'),
        tokenStaking: getEnvContractAddress('tokenStaking', '0x66683982c6d85027CD5BA09d333d4f760eE118a5'),
        arena: getEnvContractAddress('arena', '0xc2a11F373B2e148DC238e70d86b4f26D88d495F7'),
        arenaRankingManager: getEnvContractAddress('arenaRankingManager', '0xc2a11F373B2e148DC238e70d86b4f26D88d495F7'),
        arenaRankingQuery: getEnvContractAddress('arenaRankingQuery', '0xAB127a866c3Bb374cF02c1DD0B92509A242FA01d'),
        arenaReward: getEnvContractAddress('arenaReward', '0x3Ba4bd9Ac6C986608e0Cd85ff47ea945789Ca04a'),
        arenaLeaderboard: getEnvContractAddress('arenaLeaderboard', '0x2FeA3392E9A8C697457081D655806a37E1880700'),
        arenaPlayer: getEnvContractAddress('arenaPlayer', '0xee42d236af59a69d29aCA887d78766EFa0C20D38'),
        arenaBattle: getEnvContractAddress('arenaBattle', '0x189beC8b9a3c8fdd96EF679b547E9D886175cAE8'),
        battle: getEnvContractAddress('battle', '0x5ea61d6a99aE8dB141cBcD1de684571a38b81A6c'),
        battleHistory: getEnvContractAddress('battleHistory', '0x04c79aEBC54d4BA5a4E93d4748B7922c97c7B4c1'),
        battleSkillData: getEnvContractAddress('battleSkillData', '0x0079F2f000f6469f77968f6D63aCA5458D278a73'),
        priceOracle: getEnvContractAddress('priceOracle', '0x4B9Ac431F5aC3d92ca8E9Ec85a32A14921474280')
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
        nftMintABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        tokenBurnerABI: [{"inputs":[],"stateMutability":"nonpayable","type":"constructor"},{"inputs":[{"internalType":"address","name":"account","type":"address"},{"internalType":"bytes","name":"reason","type":"bytes"}],"name":"DividendShareUpdateFailed","type":"error"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":true,"internalType":"address","name":"spender","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Approval","type":"event"},{"anonymous":false,"inputs":[],"name":"EIP712DomainChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint8","name":"version","type":"uint8"}],"name":"Initialized","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"previousOwner","type":"address"},{"indexed":true,"internalType":"address","name":"newOwner","type":"address"}],"name":"OwnershipTransferred","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint8","name":"fromState","type":"uint8"},{"indexed":false,"internalType":"uint8","name":"toState","type":"uint8"}],"name":"PoolStateChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"bytes","name":"reason","type":"bytes"}],"name":"TaxLiquidationError","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"TokensBurned","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"from","type":"address"},{"indexed":true,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"Transfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"from","type":"address"},{"indexed":false,"internalType":"address","name":"to","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"}],"name":"TransferFlapToken","type":"event"},{"inputs":[],"name":"DOMAIN_SEPARATOR","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"MIN_LIQ_THRESHOLD","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"START_LIQ_THRESHOLD","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"}],"name":"allowance","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"antiFarmerDuration","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"antiFarmerExpirationTime","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"subtractedValue","type":"uint256"}],"name":"decreaseAllowance","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"dividendContract","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"eip712Domain","outputs":[{"internalType":"bytes1","name":"fields","type":"bytes1"},{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"version","type":"string"},{"internalType":"uint256","name":"chainId","type":"uint256"},{"internalType":"address","name":"verifyingContract","type":"address"},{"internalType":"bytes32","name":"salt","type":"bytes32"},{"internalType":"uint256[]","name":"extensions","type":"uint256[]"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"finalizeMigration","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"getPoolStateData","outputs":[{"internalType":"enum FlapTaxTokenV2.PoolState","name":"currentState","type":"uint8"},{"internalType":"uint16","name":"currentTaxRate","type":"uint16"},{"internalType":"uint256","name":"currentLiquidationThreshold","type":"uint256"},{"internalType":"uint256","name":"currentTaxExpirationTime","type":"uint256"},{"internalType":"uint256","name":"currentAntiFarmerExpirationTime","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"addedValue","type":"uint256"}],"name":"increaseAllowance","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"components":[{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"symbol","type":"string"},{"internalType":"string","name":"meta","type":"string"},{"internalType":"uint16","name":"tax","type":"uint16"},{"internalType":"address","name":"taxProcessor","type":"address"},{"internalType":"address","name":"dividendContract","type":"address"},{"internalType":"address","name":"quoteToken","type":"address"},{"internalType":"uint256","name":"liqExpectedOutputAmount","type":"uint256"},{"internalType":"uint256","name":"taxDuration","type":"uint256"},{"internalType":"address[]","name":"pools","type":"address[]"},{"internalType":"address","name":"v2Router","type":"address"},{"internalType":"uint256","name":"antiFarmerDuration","type":"uint256"}],"internalType":"struct IFlapTaxTokenV2.InitParams","name":"params","type":"tuple"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"liqExpectedOutputAmount","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"liquidationThreshold","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"mainPool","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"maxSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"metaURI","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"name","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"}],"name":"nonces","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"owner","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"owner","type":"address"},{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"value","type":"uint256"},{"internalType":"uint256","name":"deadline","type":"uint256"},{"internalType":"uint8","name":"v","type":"uint8"},{"internalType":"bytes32","name":"r","type":"bytes32"},{"internalType":"bytes32","name":"s","type":"bytes32"}],"name":"permit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"poolState","outputs":[{"internalType":"uint8","name":"state","type":"uint8"},{"internalType":"uint16","name":"taxRate","type":"uint16"},{"internalType":"bool","name":"notLiquidating","type":"bool"},{"internalType":"uint96","name":"liquidationThreshold","type":"uint96"},{"internalType":"uint64","name":"taxExpirationTime","type":"uint64"},{"internalType":"uint64","name":"antiFarmerExpirationTime","type":"uint64"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"pools","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"quoteToken","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"renounceOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"startMigration","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"state","outputs":[{"internalType":"enum FlapTaxTokenV2.PoolState","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"symbol","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"taxExpirationTime","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"taxProcessor","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"taxRate","outputs":[{"internalType":"uint16","name":"","type":"uint16"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalSupply","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"transfer","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"from","type":"address"},{"internalType":"address","name":"to","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"transferFrom","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"newOwner","type":"address"}],"name":"transferOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"v2Router","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"}],
        tokenABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        rewardManagerABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        nftUpdateABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        NFTTradingABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        breedingABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        breedingCoreABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        breedingMarketABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        buybackABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        nftDataABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        stakingABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        arenaABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        arenaRankingManagerABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        arenaRankingQueryABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        arenaLeaderboardABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        arenaPlayerABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        arenaBattleABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        tokenStakingABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        dividendManagerABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        priceOracleABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}],
        battleABI: [{"inputs":[{"internalType":"address","name":"_logic","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"}],"stateMutability":"payable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"previousAdmin","type":"address"},{"indexed":false,"internalType":"address","name":"newAdmin","type":"address"}],"name":"AdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"beacon","type":"address"}],"name":"BeaconUpgraded","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"stateMutability":"payable","type":"receive"}]
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