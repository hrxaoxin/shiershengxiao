/**
 * ZODIAC_WEB3 - 十二生肖 Web3 工具
 * 提供钱包连接、合约实例获取、事件监听、Gas 估算、交易跟踪等功能
 */
window.ZODIAC_WEB3 = (function() {
    const config = window.ZODIAC_CONFIG || {};
    const NETWORK_ID = config.NETWORK_ID || 56;
    const NETWORK_NAME = config.NETWORK_NAME || 'Binance Mainnet';
    const CONTRACT_ADDRESSES = config.CONTRACT_ADDRESSES || {};
    const ABIS = config.ABIS || {};

    let web3 = null;
    let account = null;
    let contracts = {};
    let isInitialized = false;

    // --- Utility Functions ---
    function safeToString(value, defaultValue = '0') {
        if (value === null || value === undefined || value === '') {
            return defaultValue;
        }
        if (typeof value.toString === 'function') {
            return value.toString();
        }
        return String(value);
    }

    const isProduction = () => {
        return window.location.hostname !== 'localhost' && 
               window.location.hostname !== '127.0.0.1' &&
               !window.location.href.includes('localhost') &&
               !window.location.href.includes('127.0.0.1');
    };

    function logError(tag, message, error) {
        if (isProduction()) {
            console.error(`${tag}: ${message}`);
        } else {
            console.error(`${tag}: ${message}`, error);
        }
    }

    function logWarn(tag, message, data) {
        if (!isProduction() || data === undefined) {
            console.warn(`${tag}: ${message}`, data);
        } else {
            console.warn(`${tag}: ${message}`);
        }
    }

    // --- Event System ---
    const listeners = {};

    function on(event, callback) {
        if (!listeners[event]) listeners[event] = [];
        listeners[event].push(callback);
    }

    function off(event, callback) {
        if (!listeners[event]) return;
        listeners[event] = listeners[event].filter(cb => cb !== callback);
    }

    function emit(event, data) {
        if (!listeners[event]) return;
        listeners[event].forEach(cb => {
            try { cb(data); } catch (e) { console.error(`[ZODIAC_WEB3] Event "${event}" handler error:`, e); }
        });
    }

    // --- Wallet Connection ---
    async function initWeb3() {
        if (isInitialized && account) {
            return true;
        }

        if (typeof window.ethereum === 'undefined') {
            console.error('[ZODIAC_WEB3] MetaMask not detected');
            if (window.ZODIAC_UI) {
                ZODIAC_UI.showToast('请安装 MetaMask 钱包', 'error');
            }
            return false;
        }

        try {
            web3 = new window.Web3(window.ethereum);
            const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });

            if (accounts && accounts.length > 0) {
                account = accounts[0];
                isInitialized = true;
                setupEventListeners();
                await checkNetwork();
                initContracts();
                emit('connect', { account });
                return true;
            }
            return false;
        } catch (error) {
            console.error('[ZODIAC_WEB3] initWeb3 failed:', error);
            if (error.code === 4001) {
                if (window.ZODIAC_UI) ZODIAC_UI.showToast('用户拒绝了钱包连接', 'error');
            }
            return false;
        }
    }

    let isEventListenersSetup = false;
    let ethereumEventHandlers = {
        accountsChanged: null,
        chainChanged: null,
        disconnect: null
    };

    function setupEventListeners() {
        if (!window.ethereum || isEventListenersSetup) return;
        isEventListenersSetup = true;

        ethereumEventHandlers.accountsChanged = function(accounts) {
            if (accounts.length === 0) {
                account = null;
                isInitialized = false;
                contracts = {};
                emit('disconnect', {});
                emit('accountsChanged', []);
            } else {
                const oldAccount = account;
                account = accounts[0];
                if (oldAccount !== account) {
                    initContracts();
                    emit('connect', { account });
                    emit('accountsChanged', [account]);
                }
            }
        };

        ethereumEventHandlers.chainChanged = function(chainId) {
            web3 = new window.Web3(window.ethereum);
            contracts = {};
            initContracts();
            checkNetwork();
            emit('chainChanged', { chainId });
        };

        ethereumEventHandlers.disconnect = function() {
            account = null;
            isInitialized = false;
            contracts = {};
            emit('disconnect', {});
        };

        window.ethereum.on('accountsChanged', ethereumEventHandlers.accountsChanged);
        window.ethereum.on('chainChanged', ethereumEventHandlers.chainChanged);
        window.ethereum.on('disconnect', ethereumEventHandlers.disconnect);
    }

    function removeEventListeners() {
        if (!window.ethereum) return;
        
        window.ethereum.removeListener('accountsChanged', ethereumEventHandlers.accountsChanged);
        window.ethereum.removeListener('chainChanged', ethereumEventHandlers.chainChanged);
        window.ethereum.removeListener('disconnect', ethereumEventHandlers.disconnect);
        ethereumEventHandlers = { accountsChanged: null, chainChanged: null, disconnect: null };
        isEventListenersSetup = false;
    }

    async function checkNetwork() {
        if (!window.ethereum || !web3) return true;
        try {
            const chainId = await web3.eth.getChainId();
            if (parseInt(chainId) !== NETWORK_ID) {
                if (window.ZODIAC_UI) {
                    ZODIAC_UI.showToast(`请切换到 ${NETWORK_NAME} (Chain ID: ${NETWORK_ID})`, 'error');
                }
                return false;
            }
            return true;
        } catch (e) {
            console.error('[ZODIAC_WEB3] checkNetwork failed:', e);
            return false;
        }
    }

    // --- Contract Management ---
    const ABI_MAP = {
        'nftMint': ABIS.nftMintABI,
        'tokenContract': ABIS.tokenABI,
        'nftTrading': ABIS.NFTTradingABI,
        'staking': ABIS.stakingABI,
        'stakingLP': ABIS.stakingLPABI,
        'tokenStaking': ABIS.tokenStakingABI,
        'tokenStakingLP': ABIS.tokenStakingLPABI,
        'breeding': ABIS.breedingABI,
        'breedingCore': ABIS.breedingCoreABI,
        'breedingMarket': ABIS.breedingMarketABI,
        'rewardManager': ABIS.rewardManagerABI,
        'dividendManager': ABIS.dividendManagerABI,
        'dividendManagerLP': ABIS.dividendManagerLPABI,
        'tokenBurner': ABIS.tokenBurnerABI,
        'nftUpdate': ABIS.nftUpdateABI,
        'battle': ABIS.battleABI,
        'arena': ABIS.arenaABI,
        'arenaRankingManager': ABIS.arenaRankingManagerABI,
        'arenaReward': ABIS.arenaRewardABI,
        'arenaLeaderboard': ABIS.arenaLeaderboardABI,
        'arenaPlayer': ABIS.arenaPlayerABI,
        'arenaBattle': ABIS.arenaBattleABI,
        'priceOracle': ABIS.priceOracleABI,
        'buyback': ABIS.buybackABI,
        'nftData': ABIS.nftDataABI,
        'authorizer': ABIS.authorizerABI
    };

    // 动态获取 authorizer 中的 token 地址
    async function getTokenAddressFromAuthorizer() {
        try {
            const authorizerAddr = CONTRACT_ADDRESSES.authorizer;
            if (!authorizerAddr || authorizerAddr === '0x0000000000000000000000000000000000000000') {
                console.warn('[ZODIAC_WEB3] authorizer address not configured');
                return CONTRACT_ADDRESSES.tokenContract;
            }
            const authorizerContract = new web3.eth.Contract(ABIS.authorizerABI, authorizerAddr);
            const tokenAddress = await authorizerContract.methods.getToken().call();
            console.log('[ZODIAC_WEB3] Token address from authorizer:', tokenAddress);
            if (tokenAddress && tokenAddress !== '0x0000000000000000000000000000000000000000') {
                return tokenAddress;
            } else {
                console.warn('[ZODIAC_WEB3] Authorizer returned zero token address, falling back to config');
                return CONTRACT_ADDRESSES.tokenContract;
            }
        } catch (e) {
            console.warn('[ZODIAC_WEB3] Failed to get token from authorizer, using configured address:', e.message);
            return CONTRACT_ADDRESSES.tokenContract;
        }
    }

    async function initContracts() {
        if (!web3 || !account) return;
        contracts = {};
        
        // 先初始化 authorizer 合约
        const authorizerAddr = CONTRACT_ADDRESSES.authorizer;
        if (authorizerAddr && authorizerAddr !== '0x0000000000000000000000000000000000000000') {
            try {
                contracts.authorizer = new web3.eth.Contract(ABIS.authorizerABI, authorizerAddr);
            } catch (e) {
                console.warn('[ZODIAC_WEB3] Failed to init authorizer:', e);
            }
        }
        
        // 动态获取 token 地址
        const tokenAddr = await getTokenAddressFromAuthorizer();
        if (tokenAddr && tokenAddr !== '0x0000000000000000000000000000000000000000') {
            try {
                contracts.tokenContract = new web3.eth.Contract(ABIS.tokenABI, tokenAddr);
            } catch (e) {
                console.warn('[ZODIAC_WEB3] Failed to init tokenContract:', e);
            }
        }
        
        // 初始化其他合约
        for (const [name, abi] of Object.entries(ABI_MAP)) {
            if (name === 'tokenContract' || name === 'authorizer') continue; // 已单独处理
            const addr = CONTRACT_ADDRESSES[name];
            if (addr && addr !== '0x0000000000000000000000000000000000000000' && abi) {
                try {
                    contracts[name] = new web3.eth.Contract(abi, addr);
                } catch (e) {
                    console.warn(`[ZODIAC_WEB3] Failed to init contract "${name}":`, e);
                }
            }
        }
    }

    async function getContract(name, requireAccount = true) {
        if (contracts[name]) return contracts[name];
        
        if (!web3) {
            if (typeof window.ethereum === 'undefined') {
                console.error('[ZODIAC_WEB3] MetaMask not detected');
                throw new Error('[ZODIAC_WEB3] MetaMask not detected');
            }
            web3 = new window.Web3(window.ethereum);
        }
        
        if (requireAccount && !account) {
            const initialized = await initWeb3();
            if (!initialized) {
                throw new Error(`[ZODIAC_WEB3] Web3 not initialized, cannot get contract: ${name}`);
            }
        }
        
        if (contracts[name]) return contracts[name];

        const abi = ABI_MAP[name];
        if (!abi) throw new Error(`[ZODIAC_WEB3] No ABI for contract: ${name}`);
        
        // tokenContract 从 authorizer 动态获取
        if (name === 'tokenContract') {
            const tokenAddr = await getTokenAddressFromAuthorizer();
            if (!tokenAddr || tokenAddr === '0x0000000000000000000000000000000000000000') {
                throw new Error(`[ZODIAC_WEB3] Token address not found in authorizer`);
            }
            contracts[name] = new web3.eth.Contract(abi, tokenAddr);
            return contracts[name];
        }
        
        let addr = CONTRACT_ADDRESSES[name];
        if (!addr && name === 'buyback') {
            addr = CONTRACT_ADDRESSES.nftBuyback;
        }
        if (!addr || addr === '0x0000000000000000000000000000000000000000') {
            throw new Error(`[ZODIAC_WEB3] Contract address not configured: ${name}`);
        }
        
        try {
            contracts[name] = new web3.eth.Contract(abi, addr);
            return contracts[name];
        } catch (e) {
            console.error(`[ZODIAC_WEB3] Failed to create contract instance for ${name}:`, e);
            throw new Error(`[ZODIAC_WEB3] Failed to initialize contract: ${name}`);
        }
    }

    // --- Getters ---
    function getWeb3() { return web3; }
    function getAccount() { return account; }
    function isConnected() { return isInitialized && !!account; }
    function getChainIdDecimal() {
        if (!web3) return null;
        return web3.eth.getChainId().then(id => parseInt(id)).catch(() => null);
    }

    // --- User Weight ---
    async function getUserWeight(userAddress) {
        try {
            const contract = await getContract('dividendManager');
            const [claimable, weight] = await contract.methods.calcUserDividend(userAddress).call();
            return weight || 0;
        } catch (e) {
            console.error('[ZODIAC_WEB3] getUserWeight failed:', e);
            return 0;
        }
    }

    // --- Staking Methods ---
    async function stakeNFTs(tokenIds) {
        if (!tokenIds || !Array.isArray(tokenIds) || tokenIds.length === 0) {
            throw new Error('[ZODIAC_WEB3] stakeNFTs requires a non-empty array of tokenIds');
        }
        for (let i = 0; i < tokenIds.length; i++) {
            if (!tokenIds[i] || tokenIds[i] <= 0) {
                throw new Error(`[ZODIAC_WEB3] Invalid tokenId at index ${i}`);
            }
        }
        try {
            const contract = await getContract('staking');
            const receipt = await sendAndTrackTransaction(contract, 'stake', [tokenIds]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] stakeNFTs failed:', e);
            throw e;
        }
    }

    async function unstakeNFTs(tokenIds) {
        if (!tokenIds || !Array.isArray(tokenIds) || tokenIds.length === 0) {
            throw new Error('[ZODIAC_WEB3] unstakeNFTs requires a non-empty array of tokenIds');
        }
        for (let i = 0; i < tokenIds.length; i++) {
            if (!tokenIds[i] || tokenIds[i] <= 0) {
                throw new Error(`[ZODIAC_WEB3] Invalid tokenId at index ${i}`);
            }
        }
        try {
            const contract = await getContract('staking');
            const receipt = await sendAndTrackTransaction(contract, 'unstake', [tokenIds]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] unstakeNFTs failed:', e);
            throw e;
        }
    }

    async function claimStakingReward() {
        try {
            const contract = await getContract('staking');
            const pendingReward = await contract.methods.getPendingReward(account).call();
            if (!pendingReward || pendingReward === '0' || pendingReward.toString() === '0') {
                throw new Error('[ZODIAC_WEB3] No pending reward to claim');
            }
            const receipt = await sendAndTrackTransaction(contract, 'claimReward', []);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] claimStakingReward failed:', e);
            throw e;
        }
    }

    // --- Alias functions for backward compatibility ---
    /**
     * @dev 质押NFT（别名函数，向后兼容）
     * 底层调用 Staking 合约的 stake 方法
     * @param tokenIds - 要质押的NFT ID数组
     */
    async function stake(tokenIds) {
        return stakeNFTs(tokenIds);
    }

    /**
     * @dev 赎回NFT（别名函数，向后兼容）
     * 底层调用 Staking 合约的 unstake 方法
     * @param tokenIds - 要赎回的NFT ID数组
     */
    async function unstake(tokenIds) {
        return unstakeNFTs(tokenIds);
    }

    /**
     * @dev 领取质押奖励（别名函数，向后兼容）
     * 底层调用 Staking 合约的 claimReward 方法
     */
    async function claimReward() {
        return claimStakingReward();
    }

    /**
     * @dev 领取分红
     * 底层调用 DividendManager 合约的 claim 方法
     */
    async function claimDividend() {
        try {
            const contract = await getContract('dividendManager');
            const receipt = await sendAndTrackTransaction(contract, 'claimDividend', []);
            
            if (!receipt) {
                throw new Error('[ZODIAC_WEB3] claimDividend returned no receipt');
            }
            
            if (receipt.status === false) {
                throw new Error('[ZODIAC_WEB3] claimDividend transaction failed');
            }
            
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] claimDividend failed:', e);
            throw e;
        }
    }

    async function claimStakingRewardBatch(tokenIds) {
        try {
            const contract = await getContract('staking');
            const receipt = await sendAndTrackTransaction(contract, 'claimReward', []);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] claimStakingRewardBatch failed:', e);
            throw e;
        }
    }

    async function getStakingInfo(userAddress) {
        try {
            const contract = await getContract('staking');
            return await contract.methods.getUserStakingStats(userAddress).call();
        } catch (e) {
            console.error('[ZODIAC_WEB3] getStakingInfo failed:', e);
            return null;
        }
    }

    // --- Token Staking Methods ---
    async function stakeTokens(amount) {
        if (!amount || amount <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid staking amount: must be greater than 0');
        }
        const web3Instance = getWeb3();
        const amountBN = web3Instance.utils.toBN(amount);
        if (amountBN.isZero() || amountBN.isNeg()) {
            throw new Error('[ZODIAC_WEB3] Staking amount must be positive');
        }
        try {
            const contract = await getContract('tokenStaking');
            const receipt = await sendAndTrackTransaction(contract, 'stakeTokens', [amount]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] stakeTokens failed:', e);
            throw e;
        }
    }

    async function unstakeTokens(amount) {
        if (!amount || amount <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid unstaking amount: must be greater than 0');
        }
        const web3Instance = getWeb3();
        const amountBN = web3Instance.utils.toBN(amount);
        if (amountBN.isZero() || amountBN.isNeg()) {
            throw new Error('[ZODIAC_WEB3] Unstaking amount must be positive');
        }
        try {
            const contract = await getContract('tokenStaking');
            const receipt = await sendAndTrackTransaction(contract, 'unstakeTokens', [amount]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] unstakeTokens failed:', e);
            throw e;
        }
    }

    async function claimTokenStakingReward() {
        try {
            const contract = await getContract('tokenStaking');
            const receipt = await sendAndTrackTransaction(contract, 'claimRewards', []);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] claimTokenStakingReward failed:', e);
            throw e;
        }
    }

    async function claimTokenRewards() {
        return claimTokenStakingReward();
    }

    async function approveToken(spender, amount) {
        if (!spender || spender === '0x0000000000000000000000000000000000000000') {
            throw new Error('Invalid spender address');
        }
        if (!amount || amount <= 0) {
            throw new Error('Invalid approval amount');
        }
        try {
            const contract = await getContract('tokenContract');
            const currentAllowance = await contract.methods.allowance(account, spender).call();
            if (currentAllowance >= amount) {
                console.log(`[ZODIAC_WEB3] Already approved ${amount} tokens for ${spender}`);
                return { status: true, alreadyApproved: true };
            }
            if (currentAllowance > 0) {
                await sendAndTrackTransaction(contract, 'approve', [spender, 0]);
            }
            const receipt = await sendAndTrackTransaction(contract, 'approve', [spender, amount]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] approveToken failed:', e);
            throw e;
        }
    }

    // --- Gas Estimation ---
    async function estimateGas(contract, methodName, args, from) {
        try {
            const gas = await contract.methods[methodName](...args).estimateGas({ from: from || account });
            return { gas: Math.ceil(gas * 1.2), estimated: true };
        } catch (e) {
            console.warn(`[ZODIAC_WEB3] Gas estimation failed for ${methodName}, using default gas limit:`, e);
            const gasLimits = {
                'mint': 600000,
                'mintBatch': 3000000,
                'stake': 800000,
                'unstake': 800000,
                'rechargeChallengeAttempts': 150000,
                'challengeMockPlayer': 500000,
                'challengeRealPlayer': 800000,
                'listNFT': 500000,
                'buyNFT': 600000,
                'delistNFT': 400000,
                'upgradeWithToken': 800000,
                'upgradeWithNFT': 1200000,
                'upgradeWithUSDValue': 800000,
                'createSelfBreedingPair': 1200000,
                'createMarketBreedingPairPublic': 1500000,
                'completeBreeding': 800000,
                'cancelBreeding': 400000,
                'listForMarketBreeding': 300000,
                'delistFromMarketBreeding': 250000,
                'claimReward': 300000,
                'claimDividend': 300000,
                'setBattleTeam': 250000,
                'stakeArenaNFTs': 600000,
                'unstakeArenaNFTs': 600000,
                'approveToken': 150000
            };
            return { gas: gasLimits[methodName] || 500000, estimated: false };
        }
    }

    function getGasLimit(methodName) {
        const gasLimits = {
            'mint': 2000000,
            'mintBatch': 5000000,
            'stake': 1500000,
            'unstake': 1500000,
            'rechargeChallengeAttempts': 300000,
            'challengeMockPlayer': 2000000,
            'challengeRealPlayer': 2500000,
            'listNFT': 800000,
            'buyNFT': 1000000,
            'delistNFT': 600000,
            'upgradeWithToken': 1500000,
            'upgradeWithNFT': 2000000,
            'upgradeWithUSDValue': 1500000,
            'createSelfBreedingPair': 2000000,
            'createMarketBreedingPairPublic': 2500000,
            'completeBreeding': 1500000,
            'cancelBreeding': 800000,
            'listForMarketBreeding': 500000,
            'delistFromMarketBreeding': 500000,
            'claimReward': 200000,
            'claimDividend': 200000,
            'stakeTokens': 300000,
            'unstakeTokens': 300000,
            'claimRewards': 200000,
            'claimTokenStakingReward': 200000,
            'approve': 100000,
            'burnAndMint': 2000000,
            'burnAndMintTen': 5000000,
            'burnAndMintTargeted': 5000000,
            'stakeArenaNFTs': 2000000,
            'unstakeArenaNFTs': 1500000,
            'clearBattleTeam': 500000,
            'claimSeasonReward': 200000,
            'claimStakingReward': 200000,
            'claimStakingRewardBatch': 400000,
            'setNFTApprovalForAll': 150000,
            'listNFTBatch': 500000
        };
        return { gas: gasLimits[methodName] || 800000, estimated: false };
    }

    // --- Event Listening ---
    let activeEventSubscriptions = [];
    const MAX_EVENT_SUBSCRIPTIONS = 100;
    const EVENT_SUBSCRIPTION_RETRY_LIMIT = 5;
    const EVENT_SUBSCRIPTION_RETRY_DELAY_MS = 3000;
    const EVENT_SUBSCRIPTION_MAX_RETRY_DELAY = 30000;

    function cleanupOldestSubscription() {
        if (activeEventSubscriptions.length === 0) return;
        
        let oldestIndex = 0;
        let oldestTime = activeEventSubscriptions[0].timestamp;
        
        for (let i = 1; i < activeEventSubscriptions.length; i++) {
            if (activeEventSubscriptions[i].timestamp < oldestTime) {
                oldestTime = activeEventSubscriptions[i].timestamp;
                oldestIndex = i;
            }
        }
        
        const oldest = activeEventSubscriptions[oldestIndex];
        try {
            if (oldest.subscription && typeof oldest.subscription.unsubscribe === 'function') {
                oldest.subscription.unsubscribe();
            }
        } catch (e) {
            console.warn('[ZODIAC_WEB3] Failed to unsubscribe oldest subscription:', e);
        }
        
        activeEventSubscriptions.splice(oldestIndex, 1);
    }

    async function listenToEvent(contractName, eventName, callback, options) {
        if (!web3 || !account) {
            console.warn('[ZODIAC_WEB3] Web3 not initialized or account not connected');
            return;
        }
        
        if (activeEventSubscriptions.length >= MAX_EVENT_SUBSCRIPTIONS) {
            cleanupOldestSubscription();
        }

        let lastError = null;
        let retryDelay = EVENT_SUBSCRIPTION_RETRY_DELAY_MS;
        
        for (let attempt = 0; attempt < EVENT_SUBSCRIPTION_RETRY_LIMIT; attempt++) {
            try {
                const contract = await getContract(contractName);
                if (!contract) {
                    throw new Error(`Contract ${contractName} not available`);
                }
                
                const eventOptions = { fromBlock: 'latest' };
                
                if (options) {
                    if (options.filter) {
                        eventOptions.filter = options.filter;
                    }
                    if (options.topics) {
                        eventOptions.topics = options.topics;
                    }
                    if (options.fromBlock !== undefined) {
                        eventOptions.fromBlock = options.fromBlock;
                    }
                    if (options.toBlock !== undefined) {
                        eventOptions.toBlock = options.toBlock;
                    }
                }
                
                if (!contract.events || !contract.events[eventName]) {
                    console.warn(`[ZODIAC_WEB3] Event "${eventName}" not found on contract "${contractName}" ABI`);
                    return;
                }

                const subscription = contract.events[eventName](eventOptions, callback);
                
                subscription.on('error', (error) => {
                    console.error(`[ZODIAC_WEB3] Event subscription error for ${contractName}.${eventName}:`, error);
                    
                    const subIndex = activeEventSubscriptions.findIndex(
                        sub => sub.subscription === subscription
                    );
                    if (subIndex !== -1) {
                        activeEventSubscriptions.splice(subIndex, 1);
                    }
                    
                    setTimeout(() => {
                        console.log(`[ZODIAC_WEB3] Attempting to re-subscribe to ${contractName}.${eventName}`);
                        listenToEvent(contractName, eventName, callback, options);
                    }, retryDelay);
                    retryDelay = Math.min(retryDelay * 2, EVENT_SUBSCRIPTION_MAX_RETRY_DELAY);
                });
                
                subscription.on('connected', (subscriptionId) => {
                    console.log(`[ZODIAC_WEB3] Event subscription connected for ${contractName}.${eventName}: ${subscriptionId}`);
                    retryDelay = EVENT_SUBSCRIPTION_RETRY_DELAY_MS;
                });
                
                activeEventSubscriptions.push({
                    contractName,
                    eventName,
                    subscription,
                    timestamp: Date.now(),
                    filter: options?.filter
                });
                return;
            } catch (e) {
                lastError = e;
                console.warn(`[ZODIAC_WEB3] Event subscription attempt ${attempt + 1} failed for ${contractName}.${eventName}:`, e.message);
                
                if (attempt === EVENT_SUBSCRIPTION_RETRY_LIMIT - 1) break;
                
                const waitTime = EVENT_SUBSCRIPTION_RETRY_DELAY_MS * Math.pow(2, attempt);
                await new Promise(resolve => setTimeout(resolve, waitTime));
            }
        }
        
        console.error(`[ZODIAC_WEB3] Event subscription for ${contractName}.${eventName} failed after ${EVENT_SUBSCRIPTION_RETRY_LIMIT} attempts:`, lastError);
    }
    
    function clearOldSubscriptions(maxAge = 3600000) {
        const now = Date.now();
        activeEventSubscriptions = activeEventSubscriptions.filter(sub => {
            if (now - sub.timestamp > maxAge) {
                if (sub.subscription && sub.subscription.unsubscribe) {
                    sub.subscription.unsubscribe();
                }
                return false;
            }
            return true;
        });
    }

    async function listenToEvents(events) {
        for (const ev of events) {
            await listenToEvent(ev.contract, ev.event, ev.callback, ev.options);
        }
    }

    let eventCleanupInterval = null;

    function startEventCleanup() {
        if (eventCleanupInterval) return;
        
        eventCleanupInterval = setInterval(() => {
            clearOldSubscriptions(1800000);
        }, 600000);
    }

    function stopEventCleanup() {
        if (eventCleanupInterval) {
            clearInterval(eventCleanupInterval);
            eventCleanupInterval = null;
        }
    }

    async function listenToAllEvents(callbacks) {
        startEventCleanup();
        
        const events = [];
        if (callbacks.onTransfer) {
            events.push({ contract: 'nftMint', event: 'Transfer', callback: callbacks.onTransfer });
        }
        if (callbacks.onBattleEnded) {
            events.push({ contract: 'battle', event: 'BattleEnded', callback: callbacks.onBattleEnded });
        }
        if (callbacks.onMint) {
            events.push({ contract: 'nftMint', event: 'Mint', callback: callbacks.onMint });
        }
        if (callbacks.onUpgrade) {
            events.push({ contract: 'nftUpdate', event: 'CardUpgraded', callback: callbacks.onUpgrade });
        }
        if (callbacks.onBreedingCompleted) {
            events.push({ contract: 'breedingCore', event: 'BreedingCompleted', callback: callbacks.onBreedingCompleted });
        }
        if (callbacks.onBreedingStarted) {
            events.push({ contract: 'breedingCore', event: 'BreedingPairCreated', callback: callbacks.onBreedingStarted });
        }
        if (callbacks.onRewardClaimed) {
            events.push({ contract: 'arena', event: 'RewardClaimed', callback: callbacks.onRewardClaimed });
        }
        if (callbacks.onStaked) {
            events.push({ contract: 'staking', event: 'Staked', callback: callbacks.onStaked });
        }
        if (callbacks.onUnstaked) {
            events.push({ contract: 'staking', event: 'Unstaked', callback: callbacks.onUnstaked });
        }
        await listenToEvents(events);
    }

    function clearAllEventListeners() {
        activeEventSubscriptions.forEach(sub => {
            try {
                if (sub.subscription && sub.subscription.unsubscribe) {
                    sub.subscription.unsubscribe();
                }
            } catch (e) {}
        });
        activeEventSubscriptions = [];
    }

    function getEventListeners() {
        return activeEventSubscriptions.length;
    }

    // --- Transaction Tracking ---
    const pendingTransactions = new Map();
    const transactionHistory = [];
    const MAX_HISTORY = 100;

    function trackTransaction(txHash, options) {
        const opts = options || {};
        const entry = {
            txHash,
            timestamp: Date.now(),
            status: 'pending',
            contractName: opts.contractName || 'unknown',
            methodName: opts.methodName || 'unknown'
        };
        pendingTransactions.set(txHash, entry);

        waitForReceipt(txHash).then(receipt => {
            entry.status = receipt.status ? 'success' : 'failed';
            pendingTransactions.delete(txHash);
            transactionHistory.unshift(entry);
            if (transactionHistory.length > MAX_HISTORY) transactionHistory.pop();
            if (opts.onSuccess && receipt.status) opts.onSuccess(receipt);
            if (opts.onError && !receipt.status) opts.onError(receipt);
        }).catch(err => {
            entry.status = 'error';
            entry.error = err.message;
            pendingTransactions.delete(txHash);
            if (opts.onError) opts.onError(err);
        });

        return entry;
    }

    async function waitForReceipt(txHash, maxAttempts, intervalMs) {
        const defaultMaxAttempts = 60;
        const defaultIntervalMs = 2000;
        
        maxAttempts = maxAttempts || defaultMaxAttempts;
        intervalMs = intervalMs || defaultIntervalMs;
        
        const maxWaitTime = maxAttempts * intervalMs;
        console.log(`[ZODIAC_WEB3] Waiting for transaction ${txHash} (max ${maxWaitTime / 1000}s)`);
        
        for (let i = 0; i < maxAttempts; i++) {
            try {
                const receipt = await web3.eth.getTransactionReceipt(txHash);
                if (receipt) {
                    if (receipt.status === false) {
                        throw new Error(`Transaction ${txHash} failed (reverted)`);
                    }
                    return receipt;
                }
                
                const tx = await web3.eth.getTransaction(txHash);
                if (tx && tx.blockNumber === null && i > maxAttempts / 2) {
                    const gasPrice = await web3.eth.getGasPrice();
                    if (tx.gasPrice && web3.utils.toBN(tx.gasPrice).lt(web3.utils.toBN(gasPrice).mul(web3.utils.toBN(2)))) {
                        console.warn(`[ZODIAC_WEB3] Transaction ${txHash} may be stuck (low gas price)`);
                    }
                }
            } catch (e) {
                if (e.message && e.message.includes('cancelled')) {
                    throw new Error(`Transaction ${txHash} was cancelled by user`);
                }
                console.warn(`[ZODIAC_WEB3] Error checking transaction ${txHash}:`, e.message);
            }
            
            if (i < maxAttempts - 1) {
                await new Promise(resolve => setTimeout(resolve, intervalMs));
            }
        }
        
        throw new Error(`Transaction ${txHash} not confirmed after ${maxWaitTime / 1000}s`);
    }

    function getPendingTransactions() { return Array.from(pendingTransactions.values()); }
    function getTransactionHistory(limit) {
        return transactionHistory.slice(0, limit || 50);
    }

    const pendingTransactionNonces = new Map();

    async function sendAndTrackTransaction(contract, methodName, args, options) {
        const opts = options || {};
        const maxRetries = opts.maxRetries || 2;
        const retryDelayMs = opts.retryDelayMs || 3000;
        const from = opts.from || account;

        if (opts.value !== undefined && opts.value !== null) {
            if (typeof opts.value === 'string' && opts.value.startsWith('0x')) {
                opts.value = opts.value;
            } else if (typeof opts.value === 'number') {
                if (opts.value < 0) {
                    throw new Error('[ZODIAC_WEB3] Transaction value cannot be negative');
                }
            } else if (typeof opts.value === 'string') {
                const numValue = BigInt(opts.value);
                if (numValue < 0) {
                    throw new Error('[ZODIAC_WEB3] Transaction value cannot be negative');
                }
            }
        }

        let gas = opts.gas;
        let usedDefaultGas = false;
        if (!gas) {
            try {
                console.log(`[ZODIAC_WEB3] Estimating gas for ${methodName}...`);
                const estimatedGas = await contract.methods[methodName](...args).estimateGas({ 
                    from: from || account,
                    value: opts.value || 0
                });
                gas = Math.ceil(estimatedGas * 1.5);
                console.log(`[ZODIAC_WEB3] Gas estimated: ${estimatedGas}, using: ${gas}`);
            } catch (e) {
                console.warn(`[ZODIAC_WEB3] Gas estimation failed for ${methodName}:`, e.message);
                const defaultGas = getGasLimit(methodName);
                gas = defaultGas.gas;
                usedDefaultGas = true;
                console.warn(`[ZODIAC_WEB3] Using default gas limit: ${gas}`);
            }
        }

        let lastTxHash = null;

        for (let attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                if (lastTxHash && attempt > 1) {
                    const previousTxStatus = await checkTransactionStatus(lastTxHash);
                    if (previousTxStatus === 'success') {
                        console.warn(`[ZODIAC_WEB3] Previous transaction ${lastTxHash} succeeded, skipping retry`);
                        const receipt = await web3.eth.getTransactionReceipt(lastTxHash);
                        return receipt;
                    } else if (previousTxStatus === 'pending' && attempt > 1) {
                        console.warn(`[ZODIAC_WEB3] Previous transaction ${lastTxHash} still pending, waiting before retry`);
                        await new Promise(resolve => setTimeout(resolve, retryDelayMs * 2));
                    }
                }

                const sendParams = {
                    from,
                    gas: gas,
                    value: opts.value || 0
                };

                const receipt = await new Promise((resolve, reject) => {
                    contract.methods[methodName](...args).send(sendParams)
                    .on('transactionHash', function(txHash) {
                        lastTxHash = txHash;
                        trackTransaction(txHash, {
                            contractName: contract._address || 'unknown',
                            methodName,
                            onSuccess: opts.onSuccess,
                            onError: opts.onError
                        });
                        if (opts.onTransactionHash) opts.onTransactionHash(txHash);
                    })
                    .on('receipt', (receipt) => {
                        resolve(receipt);
                    })
                    .on('error', (error) => {
                        reject(error);
                    });
                });
                return receipt;
            } catch (error) {
                const isRetryableError = isRetryableTransactionError(error);
                
                if (attempt < maxRetries && isRetryableError) {
                    console.warn(`[ZODIAC_WEB3] Transaction attempt ${attempt} failed, retrying in ${retryDelayMs}ms: ${methodName}`, error.message);
                    
                    if (usedDefaultGas) {
                        const defaultGas = getGasLimit(methodName);
                        gas = Math.ceil(defaultGas.gas * 1.5);
                        console.log(`[ZODIAC_WEB3] Increasing gas limit to ${gas}`);
                    }
                    
                    await new Promise(resolve => setTimeout(resolve, retryDelayMs));
                    continue;
                }
                
                console.error(`[ZODIAC_WEB3] Transaction failed after ${attempt} attempts: ${methodName}`, error);
                if (window.ZODIAC_UI) {
                    const errorMessage = parseErrorMessage(error);
                    ZODIAC_UI.showToast(errorMessage, 'error');
                }
                throw error;
            }
        }
        
        throw new Error(`[ZODIAC_WEB3] Transaction failed after ${maxRetries} attempts: ${methodName}`);
    }

    async function checkTransactionStatus(txHash) {
        try {
            const receipt = await web3.eth.getTransactionReceipt(txHash);
            if (!receipt) return 'pending';
            return receipt.status === true ? 'success' : 'failed';
        } catch (error) {
            return 'unknown';
        }
    }

    function isRetryableTransactionError(error) {
        if (!error) return false;
        
        const message = error.message || error.toString().toLowerCase();
        
        return message.includes('timeout') ||
               message.includes('network') ||
               message.includes('connection') ||
               message.includes('reset') ||
               message.includes('aborted') ||
               message.includes('cancelled') ||
               message.includes('gas estimation failed');
    }
    
    function parseErrorMessage(error) {
        if (!error) return '交易失败';
        
        const message = error.message || error.toString();
        const lowerMessage = message.toLowerCase();
        
        if (lowerMessage.includes('user rejected') || lowerMessage.includes('user denied')) {
            return '用户取消了操作';
        }
        
        if (lowerMessage.includes('insufficient funds')) {
            return '余额不足';
        }
        
        if (lowerMessage.includes('gas')) {
            if (lowerMessage.includes('exceeds block gas limit')) {
                return 'Gas限制不足，请尝试增加Gas';
            }
            if (lowerMessage.includes('price too low') || lowerMessage.includes('underpriced')) {
                return 'Gas价格过低，请提高Gas价格';
            }
            if (lowerMessage.includes('out of gas')) {
                return 'Gas不足，交易失败';
            }
            return 'Gas费用不足';
        }
        
        if (lowerMessage.includes('reverted')) {
            const match = message.match(/reason:\s*['"]?([^'"]+)['"]?/i);
            if (match && match[1]) {
                const reason = match[1].trim();
                if (reason.startsWith('0x')) {
                    try {
                        return web3.utils.hexToUtf8(reason);
                    } catch (e) {
                        return '交易失败：合约执行异常';
                    }
                }
                return reason;
            }
            return '交易失败：合约执行异常';
        }
        
        if (lowerMessage.includes('timeout') || lowerMessage.includes('time out')) {
            return '交易超时，请重试';
        }
        
        if (lowerMessage.includes('connection') || lowerMessage.includes('network')) {
            return '网络连接异常，请检查网络';
        }
        
        if (lowerMessage.includes('invalid') || lowerMessage.includes('invalid address')) {
            return '无效的地址';
        }
        
        if (lowerMessage.includes('approve') && lowerMessage.includes('allowance')) {
            return '授权额度不足，请先授权';
        }
        
        if (lowerMessage.includes('contract') && lowerMessage.includes('not found')) {
            return '合约地址未配置或不存在';
        }
        
        return message.length > 100 ? message.substring(0, 100) + '...' : message;
    }

    // --- Network Methods ---
    function isCorrectNetwork() {
        if (!web3) return false;
        return web3.eth.getChainId().then(id => parseInt(id) === NETWORK_ID).catch(() => false);
    }

    function getNetworkName(chainIdHex) {
        const networks = {
            '0x38': 'BNB Mainnet',
            '0x61': 'BNB Testnet',
            '0x1': 'Ethereum Mainnet',
            '0x5': 'Goerli Testnet'
        };
        return networks[chainIdHex] || `Chain ${parseInt(chainIdHex, 16)}`;
    }

    function showNetworkError(expectedNetwork) {
        if (window.ZODIAC_UI) {
            const networkName = expectedNetwork || NETWORK_NAME;
            ZODIAC_UI.showToast(`请切换到 ${networkName} (Chain ID: ${NETWORK_ID})`, 'error', 8000);
        }
    }

    async function checkAndSwitchNetwork(forceSwitch) {
        if (!window.ethereum) return false;
        try {
            const chainId = await window.ethereum.request({ method: 'eth_chainId' });
            if (parseInt(chainId, 16) === NETWORK_ID) return true;
            if (forceSwitch) {
                const success = await switchToNetwork(1, 0);
                if (success) {
                    if (window.ZODIAC_UI) {
                        ZODIAC_UI.showToast(`已切换到 ${NETWORK_NAME}`, 'success');
                    }
                }
            }
            return false;
        } catch (e) {
            return false;
        }
    }

    async function switchToNetwork(retries, delayMs) {
        retries = retries || 1;
        delayMs = delayMs || 0;
        for (let i = 0; i < retries; i++) {
            try {
                await window.ethereum.request({
                    method: 'wallet_switchEthereumChain',
                    params: [{ chainId: `0x${NETWORK_ID.toString(16)}` }]
                });
                return true;
            } catch (e) {
                if (e.code === 4001) {
                    if (window.ZODIAC_UI) {
                        ZODIAC_UI.showToast('请手动切换到正确的网络', 'warning');
                        showNetworkInfo();
                    }
                    return false;
                }
                
                if (e.code === 4902) {
                    try {
                        const rpcUrls = NETWORK_ID === 56 
                            ? ['https://bsc-dataseed.binance.org/', 'https://bsc-dataseed1.defibit.io/', 'https://bsc-dataseed1.ninicoin.io/']
                            : ['https://data-seed-prebsc-1-s1.binance.org:8545/'];
                        
                        const explorerUrls = NETWORK_ID === 56
                            ? ['https://bscscan.com/']
                            : ['https://testnet.bscscan.com/'];
                        
                        await window.ethereum.request({
                            method: 'wallet_addEthereumChain',
                            params: [{
                                chainId: `0x${NETWORK_ID.toString(16)}`,
                                chainName: NETWORK_NAME,
                                rpcUrls: rpcUrls,
                                nativeCurrency: { name: 'BNB', symbol: 'BNB', decimals: 18 },
                                blockExplorerUrls: explorerUrls
                            }]
                        });
                        return true;
                    } catch (addError) {
                        if (window.ZODIAC_UI) {
                            ZODIAC_UI.showToast('添加网络失败，请手动添加', 'error');
                            showNetworkInfo();
                        }
                    }
                }
            }
            if (i < retries - 1) {
                await new Promise(r => setTimeout(r, delayMs));
            }
        }
        return false;
    }
    
    function showNetworkInfo() {
        const info = `网络配置信息：\n链ID: ${NETWORK_ID}\n网络名称: ${NETWORK_NAME}\nRPC地址: ${NETWORK_ID === 56 ? 'https://bsc-dataseed.binance.org/' : 'https://data-seed-prebsc-1-s1.binance.org:8545/'}`;
        if (window.ZODIAC_UI) {
            ZODIAC_UI.showToast(info, 'info');
        } else {
            alert(info);
        }
    }

    function startEventCleanup(intervalMs) {
        intervalMs = intervalMs || 60000;
        setInterval(cleanupOrphanedListeners, intervalMs);
    }

    function stopEventCleanup() {
        // Interval cleanup handled externally
    }

    function cleanupOrphanedListeners() {
        // Clean up listeners where the contract is no longer accessible
        activeEventSubscriptions = activeEventSubscriptions.filter(sub => {
            try {
                return sub.subscription !== null;
            } catch (e) {
                return false;
            }
        });
    }

    // --- Trading Methods ---
    async function listNFT(tokenId, priceWei) {
        if (!tokenId || tokenId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid token ID');
        }
        if (!priceWei || priceWei <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid price');
        }
        const contract = await getContract('nftTrading');
        const receipt = await sendAndTrackTransaction(contract, 'listNFT', [tokenId, priceWei]);
        return receipt;
    }

    async function buyNFT(tokenId) {
        if (!tokenId || tokenId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid token ID');
        }
        const contract = await getContract('nftTrading');
        const listing = await contract.methods.listings(tokenId).call();
        
        const seller = listing.seller || listing['0'];
        const price = listing.priceWei || listing['1'];
        
        if (!seller || seller === '0x0000000000000000000000000000000000000000') {
            throw new Error('[ZODIAC_WEB3] NFT is not listed for sale');
        }
        if (!price || price === '0' || price.toString() === '0') {
            throw new Error('[ZODIAC_WEB3] Invalid listing price');
        }
        if (seller.toLowerCase() === account.toLowerCase()) {
            throw new Error('[ZODIAC_WEB3] Cannot buy your own NFT');
        }
        
        const tokenContract = await getContract('tokenContract');
        const tradingAddress = CONTRACT_ADDRESSES.nftTrading;
        
        const balance = await tokenContract.methods.balanceOf(account).call();
        const allowance = await tokenContract.methods.allowance(account, tradingAddress).call();
        
        const web3Instance = getWeb3();
        const priceBN = web3Instance.utils.toBN(price);
        const balanceBN = web3Instance.utils.toBN(balance);
        const allowanceBN = web3Instance.utils.toBN(allowance);
        
        if (balanceBN.lt(priceBN)) {
            throw new Error(`[ZODIAC_WEB3] Insufficient token balance. Need ${web3Instance.utils.fromWei(price, 'ether')} tokens, have ${web3Instance.utils.fromWei(balance, 'ether')} tokens`);
        }
        
        if (allowanceBN.lt(priceBN)) {
            await approveToken(tradingAddress, web3Instance.utils.toWei('1000000', 'ether'));
        }

        const receipt = await sendAndTrackTransaction(contract, 'buyNFT', [tokenId]);

        return receipt;
    }

    async function delistNFT(tokenId) {
        if (!tokenId || tokenId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid token ID');
        }
        const contract = await getContract('nftTrading');
        const receipt = await sendAndTrackTransaction(contract, 'delistNFT', [tokenId]);
        return receipt;
    }

    async function setNFTApprovalForAll(operator, approved) {
        if (!operator || operator === '0x0000000000000000000000000000000000000000') {
            throw new Error('[ZODIAC_WEB3] Invalid operator address');
        }
        if (approved === undefined || approved === null) {
            throw new Error('[ZODIAC_WEB3] Invalid approved flag');
        }
        const contract = await getContract('nftMint');
        const receipt = await sendAndTrackTransaction(contract, 'setApprovalForAll', [operator, approved]);
        return receipt;
    }

    async function listNFTBatch(tokenIds, prices, options = {}) {
        if (!tokenIds || !Array.isArray(tokenIds)) {
            throw new Error('[ZODIAC_WEB3] listNFTBatch requires an array of tokenIds');
        }
        if (!prices || !Array.isArray(prices)) {
            throw new Error('[ZODIAC_WEB3] listNFTBatch requires an array of prices');
        }
        if (tokenIds.length === 0) {
            throw new Error('[ZODIAC_WEB3] listNFTBatch requires at least 1 NFT');
        }
        if (tokenIds.length !== prices.length) {
            throw new Error(`[ZODIAC_WEB3] listNFTBatch tokenIds length (${tokenIds.length}) does not match prices length (${prices.length})`);
        }
        for (let i = 0; i < tokenIds.length; i++) {
            if (!tokenIds[i] || tokenIds[i] <= 0) {
                throw new Error(`[ZODIAC_WEB3] listNFTBatch invalid tokenId at index ${i}`);
            }
            if (!prices[i] || prices[i] <= 0) {
                throw new Error(`[ZODIAC_WEB3] listNFTBatch invalid price at index ${i}`);
            }
        }
        const seenIds = new Set();
        for (let i = 0; i < tokenIds.length; i++) {
            if (seenIds.has(tokenIds[i])) {
                throw new Error(`[ZODIAC_WEB3] listNFTBatch duplicate tokenId ${tokenIds[i]} at index ${i}`);
            }
            seenIds.add(tokenIds[i]);
        }
        const { atomic = false } = options;
        
        if (atomic) {
            const results = [];
            for (let i = 0; i < tokenIds.length; i++) {
                try {
                    const result = await listNFT(tokenIds[i], prices[i]);
                    results.push({ tokenId: tokenIds[i], success: true, result });
                } catch (error) {
                    results.push({ tokenId: tokenIds[i], success: false, error: error.message });
                    if (atomic) {
                        throw new Error(`Batch operation failed at tokenId ${tokenIds[i]}: ${error.message}`);
                    }
                }
            }
            return results;
        } else {
            return Promise.all(tokenIds.map((id, i) => listNFT(id, prices[i])));
        }
    }

    // --- Token Burner Methods (Mint) ---
    async function checkTokenBalanceAndAllowance(requiredAmount) {
        const tokenContract = await getContract('tokenContract');
        const burnerAddress = CONTRACT_ADDRESSES.tokenBurner;
        
        if (!burnerAddress || burnerAddress === '0x0000000000000000000000000000000000000000') {
            throw new Error('[ZODIAC_WEB3] TokenBurner address not configured');
        }
        
        const balance = await tokenContract.methods.balanceOf(account).call();
        const balanceBN = getWeb3().utils.toBN(balance);
        const requiredBN = getWeb3().utils.toBN(requiredAmount);
        
        if (balanceBN.lt(requiredBN)) {
            throw new Error(`[ZODIAC_WEB3] Insufficient token balance. Need ${requiredAmount}, have ${balance.toString()}`);
        }
        
        const allowance = await tokenContract.methods.allowance(account, burnerAddress).call();
        const allowanceBN = getWeb3().utils.toBN(allowance);
        
        if (allowanceBN.lt(requiredBN)) {
            console.log('[ZODIAC_WEB3] Auto-approving token spending with infinite allowance...');
            const MAX_UINT256 = '115792089237316195423570985008687907853269984665640564039457584007913129639935';
            await sendAndTrackTransaction(tokenContract, 'approve', [burnerAddress, MAX_UINT256]);
        }
        
        return true;
    }

    async function _executeMint(methodName, isRare, zodiac, userAccount) {
        if (!userAccount) {
            throw new Error('[ZODIAC_WEB3] Invalid account address');
        }
        
        const burnerContract = await getContract('tokenBurner');
        
        let mintCost;
        if (methodName === 'burnAndMint') {
            mintCost = isRare 
                ? await burnerContract.methods.rareMintCost().call()
                : await burnerContract.methods.normalMintCost().call();
        } else if (methodName === 'burnAndMintTen') {
            mintCost = isRare 
                ? await burnerContract.methods.rareMintTenCost().call()
                : await burnerContract.methods.normalMintTenCost().call();
        } else if (methodName === 'burnAndMintTargeted') {
            mintCost = await burnerContract.methods.targetedMintCost().call();
        } else {
            throw new Error(`[ZODIAC_WEB3] Unsupported mint method: ${methodName}`);
        }
        
        await checkTokenBalanceAndAllowance(mintCost);
        
        let args = [userAccount];
        if (methodName !== 'burnAndMintTargeted') {
            args.push(isRare);
        } else {
            args.push(zodiac);
        }
        
        const receipt = await sendAndTrackTransaction(burnerContract, methodName, args, { from: userAccount });
        return receipt;
    }

    async function burnAndMint(isRare) {
        if (isRare !== true && isRare !== false) {
            throw new Error('[ZODIAC_WEB3] isRare must be a boolean value');
        }
        
        const currentAccount = await _getCurrentAccount();
        console.log('[ZODIAC_WEB3] burnAndMint called with account:', currentAccount);
        
        try {
            return await _executeMint('burnAndMint', isRare, null, currentAccount);
        } catch (e) {
            console.error('[ZODIAC_WEB3] burnAndMint failed:', e);
            throw e;
        }
    }

    async function burnAndMintTen(isRare) {
        if (isRare !== true && isRare !== false) {
            throw new Error('[ZODIAC_WEB3] isRare must be a boolean value');
        }
        
        const currentAccount = await _getCurrentAccount();
        console.log('[ZODIAC_WEB3] burnAndMintTen called with account:', currentAccount);
        
        try {
            return await _executeMint('burnAndMintTen', isRare, null, currentAccount);
        } catch (e) {
            console.error('[ZODIAC_WEB3] burnAndMintTen failed:', e);
            throw e;
        }
    }

    async function burnAndMintTargeted(zodiac) {
        if (zodiac === undefined || zodiac === null || zodiac < 0 || zodiac > 11) {
            throw new Error('[ZODIAC_WEB3] Invalid zodiac index (0-11)');
        }
        
        // 确保 zodiac 是 BigInt 类型，避免精度问题
        const zodiacBigInt = BigInt(Math.floor(Number(zodiac)));
        
        const currentAccount = await _getCurrentAccount();
        console.log('[ZODIAC_WEB3] burnAndMintTargeted called with account:', currentAccount);
        
        try {
            return await _executeMint('burnAndMintTargeted', null, zodiacBigInt, currentAccount);
        } catch (e) {
            console.error('[ZODIAC_WEB3] burnAndMintTargeted failed:', e);
            throw e;
        }
    }
    
    async function _getCurrentAccount() {
        if (!web3 && !window.ethereum) {
            throw new Error('[ZODIAC_WEB3] Web3 not initialized');
        }
        
        try {
            // 先尝试使用 web3.eth.getAccounts()
            if (web3) {
                const accounts = await web3.eth.getAccounts();
                if (accounts && accounts.length > 0) {
                    return accounts[0];
                }
            }
            
            // 如果 web3 没有返回账户，尝试使用 ethereum.request
            if (window.ethereum) {
                const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
                if (accounts && accounts.length > 0) {
                    return accounts[0];
                }
            }
            
            throw new Error('[ZODIAC_WEB3] No accounts found');
        } catch (e) {
            console.error('[ZODIAC_WEB3] Failed to get current account:', e);
            throw e;
        }
    }

    // --- Arena Methods ---
    async function stakeArenaNFTs(tokenIds) {
        if (!tokenIds || !Array.isArray(tokenIds)) {
            throw new Error('[ZODIAC_WEB3] stakeArenaNFTs requires an array of tokenIds');
        }
        if (tokenIds.length === 0 || tokenIds.length > 6) {
            throw new Error(`[ZODIAC_WEB3] stakeArenaNFTs requires 1-6 NFTs, got ${tokenIds.length}`);
        }
        for (let i = 0; i < tokenIds.length; i++) {
            if (!tokenIds[i] || tokenIds[i] <= 0) {
                throw new Error(`[ZODIAC_WEB3] stakeArenaNFTs invalid tokenId at index ${i}`);
            }
        }
        const seen = new Set();
        for (let i = 0; i < tokenIds.length; i++) {
            if (seen.has(tokenIds[i])) {
                throw new Error(`[ZODIAC_WEB3] stakeArenaNFTs duplicate tokenId at index ${i}`);
            }
            seen.add(tokenIds[i]);
        }
        const contract = await getContract('arenaPlayer');
        const receipt = await sendAndTrackTransaction(contract, 'stakeNFTs', [tokenIds]);
        return receipt;
    }

    async function unstakeArenaNFTs(tokenIds) {
        if (!tokenIds || !Array.isArray(tokenIds)) {
            throw new Error('[ZODIAC_WEB3] unstakeArenaNFTs requires an array of tokenIds');
        }
        if (tokenIds.length === 0 || tokenIds.length > 6) {
            throw new Error(`[ZODIAC_WEB3] unstakeArenaNFTs requires 1-6 NFTs, got ${tokenIds.length}`);
        }
        for (let i = 0; i < tokenIds.length; i++) {
            if (!tokenIds[i] || tokenIds[i] <= 0) {
                throw new Error(`[ZODIAC_WEB3] unstakeArenaNFTs invalid tokenId at index ${i}`);
            }
        }
        const seen = new Set();
        for (let i = 0; i < tokenIds.length; i++) {
            if (seen.has(tokenIds[i])) {
                throw new Error(`[ZODIAC_WEB3] unstakeArenaNFTs duplicate tokenId at index ${i}`);
            }
            seen.add(tokenIds[i]);
        }
        const contract = await getContract('arenaPlayer');
        const receipt = await sendAndTrackTransaction(contract, 'unstakeNFTs', [tokenIds]);
        return receipt;
    }

    async function clearArenaTeam() {
        const contract = await getContract('arenaPlayer');
        const receipt = await sendAndTrackTransaction(contract, 'clearBattleTeam', []);
        return receipt;
    }

    async function challengeMockPlayer(playerTeam, mockIndex) {
        if (mockIndex === undefined || mockIndex === null) {
            throw new Error('[ZODIAC_WEB3] Invalid mock player index');
        }
        if (typeof mockIndex === 'number' && mockIndex < 1) {
            throw new Error('[ZODIAC_WEB3] Invalid mock player index, must be >= 1');
        }
        try {
            const contract = await getContract('arenaBattle');
            if (!contract) {
                throw new Error('[ZODIAC_WEB3] ArenaBattle contract not available');
            }
            const mockIndexStr = typeof mockIndex === 'number' ? String(mockIndex) : mockIndex;
            console.log(`[ZODIAC_WEB3] challengeMockPlayer (direct ArenaBattle): mockIndex=${mockIndexStr}`);
            
            console.log('[ZODIAC_WEB3] Performing dry-run call...');
            try {
                const result = await contract.methods.challengeMockPlayer(mockIndexStr).call({ from: account });
                console.log('[ZODIAC_WEB3] Dry-run succeeded:', result);
            } catch (dryRunError) {
                console.warn('[ZODIAC_WEB3] Dry-run warning:', dryRunError.message);
            }
            
            const receipt = await sendAndTrackTransaction(contract, 'challengeMockPlayer', [mockIndexStr], {
                gas: 3000000
            });
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] challengeMockPlayer failed:', e);
            throw e;
        }
    }

    async function challengeRealPlayer(challengedPlayer, playerTeam) {
        if (!challengedPlayer || challengedPlayer === '0x0000000000000000000000000000000000000000') {
            throw new Error('[ZODIAC_WEB3] Invalid challenged player address');
        }
        try {
            const contract = await getContract('arenaBattle');
            if (!contract) {
                throw new Error('[ZODIAC_WEB3] ArenaBattle contract not available');
            }
            console.log(`[ZODIAC_WEB3] challengeRealPlayer (direct ArenaBattle): challengedPlayer=${challengedPlayer}`);
            
            console.log('[ZODIAC_WEB3] Performing dry-run call...');
            try {
                const result = await contract.methods.challengeRealPlayer(challengedPlayer).call({ from: account });
                console.log('[ZODIAC_WEB3] Dry-run succeeded:', result);
            } catch (dryRunError) {
                console.warn('[ZODIAC_WEB3] Dry-run warning:', dryRunError.message);
            }
            
            const receipt = await sendAndTrackTransaction(contract, 'challengeRealPlayer', [challengedPlayer], {
                gas: 3000000
            });
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] challengeRealPlayer failed:', e);
            throw e;
        }
    }

    async function claimSeasonReward(seasonNumber) {
        try {
            const contract = await getContract('arena');
            let targetSeason = seasonNumber;
            if (targetSeason === undefined || targetSeason === null) {
                try {
                    const seasonInfo = await contract.methods.getCurrentSeasonInfo().call();
                    targetSeason = seasonInfo && seasonInfo.seasonId ? seasonInfo.seasonId : 1;
                } catch (err) {
                    console.warn('[ZODIAC_WEB3] Cannot get current season, defaulting to 1:', err.message);
                    targetSeason = 1;
                }
            }
            if (targetSeason < 0) {
                throw new Error('Invalid season number');
            }
            const receipt = await sendAndTrackTransaction(contract, 'claimSeasonReward', [targetSeason]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] claimSeasonReward failed:', e);
            throw e;
        }
    }
    
    async function setArenaRewardType(rewardType) {
        if (rewardType === undefined || rewardType === null) {
            throw new Error('[ZODIAC_WEB3] setArenaRewardType requires a reward type');
        }
        if (rewardType !== 0 && rewardType !== 1) {
            throw new Error(`[ZODIAC_WEB3] Invalid reward type ${rewardType}, must be 0 (BNB) or 1 (Token)`);
        }
        try {
            const contract = await getContract('arena');
            const receipt = await sendAndTrackTransaction(contract, 'setRewardType', [rewardType]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] setArenaRewardType failed:', e);
            throw e;
        }
    }
    
    async function getArenaRewardType() {
        try {
            const contract = await getContract('arena');
            return await contract.methods.rewardType().call();
        } catch (e) {
            console.error('[ZODIAC_WEB3] getArenaRewardType failed:', e);
            return 1; // 默认代币
        }
    }

    // --- Breeding Methods ---
    async function createSelfBreedingPair(fatherId, motherId, coOwnerId = 0) {
        if (!fatherId || fatherId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid father ID');
        }
        if (!motherId || motherId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid mother ID');
        }
        if (fatherId === motherId) {
            throw new Error('[ZODIAC_WEB3] Father and mother must be different');
        }
        try {
            const contract = await getContract('breedingCore');
            const receipt = await sendAndTrackTransaction(contract, 'createSelfBreedingPair', [fatherId, motherId, coOwnerId]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] createSelfBreedingPair failed:', e);
            throw e;
        }
    }

    async function completeBreeding(pairId) {
        if (!pairId || pairId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid pair ID');
        }
        try {
            const contract = await getContract('breedingCore');
            const receipt = await sendAndTrackTransaction(contract, 'completeBreeding', [pairId]);
            
            let result = { receipt };
            if (receipt.events) {
                if (receipt.events.BreedingCompleted) {
                    result.breedingCompleted = receipt.events.BreedingCompleted.returnValues;
                }
                if (receipt.events.MaleChildGenerated) {
                    result.maleChildGenerated = receipt.events.MaleChildGenerated.returnValues;
                }
                if (receipt.events.FemaleChildGenerated) {
                    result.femaleChildGenerated = receipt.events.FemaleChildGenerated.returnValues;
                }
            }
            return result;
        } catch (e) {
            console.error('[ZODIAC_WEB3] completeBreeding failed:', e);
            throw e;
        }
    }

    async function cancelBreeding(pairId) {
        if (!pairId || pairId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid pair ID');
        }
        try {
            const contract = await getContract('breedingCore');
            const receipt = await sendAndTrackTransaction(contract, 'cancelBreeding', [pairId]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] cancelBreeding failed:', e);
            throw e;
        }
    }

    async function listForMarketBreeding(tokenId) {
        if (!tokenId || tokenId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid token ID');
        }
        try {
            const contract = await getContract('breedingMarket');
            const receipt = await sendAndTrackTransaction(contract, 'listForMarketBreeding', [tokenId]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] listForMarketBreeding failed:', e);
            throw e;
        }
    }

    async function createMarketBreedingPairPublic(fatherId, motherId) {
        if (!fatherId || fatherId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid father ID');
        }
        if (!motherId || motherId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid mother ID');
        }
        if (fatherId === motherId) {
            throw new Error('[ZODIAC_WEB3] Father and mother must be different');
        }
        try {
            const contract = await getContract('breedingCore');
            const receipt = await sendAndTrackTransaction(contract, 'createMarketBreedingPairPublic', [fatherId, motherId]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] createMarketBreedingPairPublic failed:', e);
            throw e;
        }
    }

    async function delistFromMarketBreeding(tokenId) {
        if (!tokenId || tokenId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid token ID');
        }
        try {
            const contract = await getContract('breedingMarket');
            const receipt = await sendAndTrackTransaction(contract, 'delistFromMarketBreeding', [tokenId]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] delistFromMarketBreeding failed:', e);
            throw e;
        }
    }
    
    async function getBreedingConfig() {
        try {
            const contract = await getContract('breedingCore');
            const [selfFee, marketFee, selfCooldown, marketCooldown] = await Promise.all([
                contract.methods.selfBreedingFee().call(),
                contract.methods.marketBreedingFee().call(),
                contract.methods.selfBreedingCooldown().call(),
                contract.methods.marketBreedingCooldown().call()
            ]);
            return {
                selfBreedingFee: selfFee,
                marketBreedingFee: marketFee,
                selfBreedingCooldown: selfCooldown,
                marketBreedingCooldown: marketCooldown
            };
        } catch (e) {
            console.error('[ZODIAC_WEB3] getBreedingConfig failed:', e);
            return null;
        }
    }

    // --- Upgrade Methods ---
    async function upgradeWithNFT(nftId) {
        if (!nftId || nftId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid NFT ID');
        }
        try {
            const contract = await getContract('nftUpdate');
            const receipt = await sendAndTrackTransaction(contract, 'upgradeWithNFT', [nftId]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] upgradeWithNFT failed:', e);
            throw e;
        }
    }

    async function upgradeWithToken(nftId) {
        if (!nftId || nftId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid NFT ID');
        }
        try {
            const contract = await getContract('nftUpdate');
            const receipt = await sendAndTrackTransaction(contract, 'upgradeWithToken', [nftId]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] upgradeWithToken failed:', e);
            throw e;
        }
    }

    async function upgradeWithUSDValue(nftId) {
        if (!nftId || nftId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid NFT ID');
        }
        try {
            const contract = await getContract('nftUpdate');
            const receipt = await sendAndTrackTransaction(contract, 'upgradeWithUSDValue', [nftId]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] upgradeWithUSDValue failed:', e);
            throw e;
        }
    }

    // --- Contract Pause Check Functions ---
    async function isContractPaused(contractName) {
        try {
            const contract = await getContract(contractName);
            if (!contract) return false;
            
            if (contract.methods.paused) {
                return await contract.methods.paused().call();
            }
            return false;
        } catch (e) {
            console.warn(`[ZODIAC_WEB3] Failed to check if ${contractName} is paused:`, e);
            return false;
        }
    }
    
    async function checkAndWarnPaused(contractName, actionName = '此操作') {
        const isPaused = await isContractPaused(contractName);
        if (isPaused) {
            const message = `合约已暂停，无法执行${actionName}`;
            console.warn(`[ZODIAC_WEB3] ${message}`);
            if (window.ZODIAC_UI) {
                ZODIAC_UI.showToast(message, 'error');
            }
            return true;
        }
        return false;
    }

    // --- RewardManager DEX Functions ---
    async function setDEXRouter(routerAddress, dexType) {
        try {
            const contract = await getContract('rewardManager');
            const receipt = await sendAndTrackTransaction(contract, 'setDEXRouter', [routerAddress, dexType]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] setDEXRouter failed:', e);
            throw e;
        }
    }

    async function distributeBNB() {
        try {
            const contract = await getContract('rewardManager');
            const receipt = await sendAndTrackTransaction(contract, 'distributeBNB', []);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] distributeBNB failed:', e);
            throw e;
        }
    }

    async function getDEXRouter() {
        try {
            const contract = await getContract('rewardManager');
            return await contract.methods.dexRouter().call();
        } catch (e) {
            console.error('[ZODIAC_WEB3] getDEXRouter failed:', e);
            return null;
        }
    }

    async function getActiveDEX() {
        try {
            const contract = await getContract('rewardManager');
            const dexType = await contract.methods.activeDEX().call();
            const dexNames = ['FlapSwap', 'PancakeSwap', 'Uniswap'];
            return {
                type: parseInt(dexType),
                name: dexNames[parseInt(dexType)] || 'Unknown'
            };
        } catch (e) {
            console.error('[ZODIAC_WEB3] getActiveDEX failed:', e);
            return { type: 0, name: 'Unknown' };
        }
    }

    async function setAutoSwapEnabled(enabled) {
        try {
            const contract = await getContract('rewardManager');
            const receipt = await sendAndTrackTransaction(contract, 'setAutoSwapEnabled', [enabled]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] setAutoSwapEnabled failed:', e);
            throw e;
        }
    }

    async function setSlippage(slippage) {
        try {
            const contract = await getContract('rewardManager');
            const receipt = await sendAndTrackTransaction(contract, 'setSlippage', [slippage]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] setSlippage failed:', e);
            throw e;
        }
    }

    // --- PriceOracle DEX Functions ---
    async function setPriceOracleDEXRouters(flapSwapRouter, pancakeSwapRouter, uniswapRouter) {
        try {
            const contract = await getContract('priceOracle');
            const receipt = await sendAndTrackTransaction(contract, 'setDEXRouters', [flapSwapRouter, pancakeSwapRouter, uniswapRouter]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] setPriceOracleDEXRouters failed:', e);
            throw e;
        }
    }

    async function setPriceOracleActiveDEX(dexType) {
        try {
            const contract = await getContract('priceOracle');
            const receipt = await sendAndTrackTransaction(contract, 'setActiveDEX', [dexType]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] setPriceOracleActiveDEX failed:', e);
            throw e;
        }
    }

    async function fetchPriceFromDEX() {
        try {
            const contract = await getContract('priceOracle');
            const receipt = await sendAndTrackTransaction(contract, 'fetchPriceFromDEX', []);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] fetchPriceFromDEX failed:', e);
            throw e;
        }
    }

    async function fetchPriceFromAllDEX() {
        try {
            const contract = await getContract('priceOracle');
            const receipt = await sendAndTrackTransaction(contract, 'fetchPriceFromAllDEX', []);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] fetchPriceFromAllDEX failed:', e);
            throw e;
        }
    }
    
    async function isTokenPriceValid() {
        try {
            const contract = await getContract('priceOracle');
            const price = await contract.methods.getTokenPriceUSD().call();
            return parseInt(price) > 0;
        } catch (e) {
            console.error('[ZODIAC_WEB3] isTokenPriceValid failed:', e);
            return false;
        }
    }

    async function getPriceOracleActiveDEX() {
        try {
            const contract = await getContract('priceOracle');
            const dexType = await contract.methods.activeDEX().call();
            const dexNames = ['FlapSwap', 'PancakeSwap', 'Uniswap'];
            return {
                type: parseInt(dexType),
                name: dexNames[parseInt(dexType)] || 'Unknown'
            };
        } catch (e) {
            console.error('[ZODIAC_WEB3] getPriceOracleActiveDEX failed:', e);
            return { type: 0, name: 'Unknown' };
        }
    }

    // --- Buyback Methods ---
    async function sellNFTWithGrowthPrice(tokenId) {
        if (!tokenId || tokenId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid token ID');
        }
        try {
            const contract = await getContract('buyback');
            const receipt = await sendAndTrackTransaction(contract, 'sellWithGrowthPrice', [tokenId]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] sellNFTWithGrowthPrice failed:', e);
            throw e;
        }
    }

    async function sellNFTWithFixedPrice(tokenId) {
        if (!tokenId || tokenId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid token ID');
        }
        try {
            const contract = await getContract('buyback');
            const receipt = await sendAndTrackTransaction(contract, 'sellWithFixedPrice', [tokenId]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] sellNFTWithFixedPrice failed:', e);
            throw e;
        }
    }

    async function sellNFTWithBalanceRatioPrice(tokenId) {
        if (!tokenId || tokenId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid token ID');
        }
        try {
            const contract = await getContract('buyback');
            const receipt = await sendAndTrackTransaction(contract, 'sellWithBalanceRatioPrice', [tokenId]);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] sellNFTWithBalanceRatioPrice failed:', e);
            throw e;
        }
    }

    async function calculateBuybackPrice(tokenId) {
        if (!tokenId || tokenId <= 0) {
            throw new Error('[ZODIAC_WEB3] Invalid token ID');
        }
        try {
            const contract = await getContract('buyback');
            return await contract.methods.calculateBuybackPrice(tokenId).call();
        } catch (e) {
            console.error('[ZODIAC_WEB3] calculateBuybackPrice failed:', e);
            throw e;
        }
    }

    async function calculateBalanceRatioPrice() {
        try {
            const contract = await getContract('buyback');
            const result = await contract.methods.calculateBalanceRatioPrice().call();
            return {
                pricePerNFT: result.pricePerNFT || result['0'],
                balance: result.balance || result['1'],
                totalSupply: result.totalSupply || result['2']
            };
        } catch (e) {
            console.error('[ZODIAC_WEB3] calculateBalanceRatioPrice failed:', e);
            throw e;
        }
    }

    async function getBuybackConfig() {
        try {
            const contract = await getContract('buyback');
            const [fixedBuybackOpen, growthBuybackOpen, balanceRatioBuybackOpen, fixedBuybackPrice, maxBonusPercent] = await Promise.all([
                contract.methods.fixedBuybackOpen().call(),
                contract.methods.growthBuybackOpen().call(),
                contract.methods.balanceRatioBuybackOpen().call(),
                contract.methods.fixedBuybackPrice().call(),
                contract.methods.maxBonusPercent().call()
            ]);
            return {
                fixedBuybackOpen: fixedBuybackOpen,
                growthBuybackOpen: growthBuybackOpen,
                balanceRatioBuybackOpen: balanceRatioBuybackOpen,
                fixedBuybackPrice: fixedBuybackPrice,
                maxBonusPercent: parseInt(maxBonusPercent, 10)
            };
        } catch (e) {
            console.error('[ZODIAC_WEB3] getBuybackConfig failed:', e);
            return null;
        }
    }

    // --- Cleanup on page unload or hash change (SPA) ---
    window.addEventListener('beforeunload', function() {
        clearAllEventListeners();
    });
    
    window.addEventListener('hashchange', function() {
        clearAllEventListeners();
    });

    return {
        // Core
        initWeb3,
        getWeb3,
        getAccount,
        isConnected,
        getChainIdDecimal,
        getContract,
        getUserWeight,

        // Events
        on,
        off,
        emit,

        // Contract Pause Check
        isContractPaused,
        checkAndWarnPaused,
        
        // Gas & Transactions
        estimateGas,
        trackTransaction,
        getPendingTransactions,
        getTransactionHistory,
        sendAndTrackTransaction,

        // Event Listeners
        listenToEvent,
        listenToEvents,
        listenToAllEvents,
        clearAllEventListeners,
        getEventListeners,
        startEventCleanup,
        stopEventCleanup,
        cleanupOrphanedListeners,
        removeEventListeners,

        // Network
        isCorrectNetwork,
        getNetworkName,
        showNetworkError,
        checkAndSwitchNetwork,
        switchToNetwork,

        // Trading
        listNFT,
        buyNFT,
        delistNFT,
        setNFTApprovalForAll,
        listNFTBatch,

        // Arena
        stakeArenaNFTs,
        unstakeArenaNFTs,
        clearArenaTeam,

        // Staking
        stakeNFTs,
        unstakeNFTs,
        claimStakingReward,
        claimStakingRewardBatch,
        getStakingInfo,
        
        // Alias functions for backward compatibility
        stake,
        unstake,
        claimReward,
        claimDividend,
        claimTokenRewards,

        // Token Staking
        stakeTokens,
        unstakeTokens,
        claimTokenStakingReward,
        approveToken,

        // Token Burner (Mint)
        burnAndMint,
        burnAndMintTen,
        burnAndMintTargeted,

        // Breeding
        createSelfBreedingPair,
        completeBreeding,
        cancelBreeding,
        listForMarketBreeding,
        createMarketBreedingPairPublic,
        delistFromMarketBreeding,
        getBreedingConfig,

        // Arena
        challengeMockPlayer,
        challengeRealPlayer,
        claimSeasonReward,
        setArenaRewardType,
        getArenaRewardType,

        // Upgrade
        upgradeWithNFT,
        upgradeWithToken,
        upgradeWithUSDValue,

        // RewardManager DEX Functions
        setDEXRouter,
        distributeBNB,
        getDEXRouter,
        getActiveDEX,
        setAutoSwapEnabled,
        setSlippage,

        // PriceOracle DEX Functions
        setPriceOracleDEXRouters,
        setPriceOracleActiveDEX,
        fetchPriceFromDEX,
        fetchPriceFromAllDEX,
        getPriceOracleActiveDEX,
        isTokenPriceValid,

        // Buyback
        sellNFTWithGrowthPrice,
        sellNFTWithFixedPrice,
        sellNFTWithBalanceRatioPrice,
        calculateBuybackPrice,
        calculateBalanceRatioPrice,
        getBuybackConfig
    };
})();