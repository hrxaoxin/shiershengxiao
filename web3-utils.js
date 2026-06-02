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

    function setupEventListeners() {
        if (!window.ethereum) return;

        window.ethereum.on('accountsChanged', function(accounts) {
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
        });

        window.ethereum.on('chainChanged', function(chainId) {
            web3 = new window.Web3(window.ethereum);
            contracts = {};
            initContracts();
            checkNetwork();
            emit('chainChanged', { chainId });
        });

        window.ethereum.on('disconnect', function() {
            account = null;
            isInitialized = false;
            contracts = {};
            emit('disconnect', {});
        });
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
        'tokenStaking': ABIS.tokenStakingABI,
        'breeding': ABIS.breedingABI,
        'rewardManager': ABIS.rewardManagerABI,
        'dividendManager': ABIS.dividendManagerABI,
        'poolManager': ABIS.poolManagerABI,
        'tokenBurner': ABIS.tokenBurnerABI,
        'nftUpdate': ABIS.nftUpdateABI,
        'battle': ABIS.battleABI,
        'arena': ABIS.arenaABI,
        'battleHistory': ABIS.battleHistoryABI,
        'priceOracle': ABIS.priceOracleABI,
        'nftData': ABIS.nftDataABI,
        'weightManager': ABIS.weightManagerABI,
        'authorizer': ABIS.authorizerABI
    };

    function initContracts() {
        if (!web3 || !account) return;
        contracts = {};
        for (const [name, abi] of Object.entries(ABI_MAP)) {
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

    async function getContract(name) {
        if (contracts[name]) return contracts[name];
        if (!web3 || !account) {
            await initWeb3();
        }
        if (contracts[name]) return contracts[name];

        const abi = ABI_MAP[name];
        const addr = CONTRACT_ADDRESSES[name];
        if (!abi) throw new Error(`[ZODIAC_WEB3] No ABI for contract: ${name}`);
        if (!addr || addr === '0x0000000000000000000000000000000000000000') {
            throw new Error(`[ZODIAC_WEB3] Contract address not configured: ${name}`);
        }
        contracts[name] = new web3.eth.Contract(abi, addr);
        return contracts[name];
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
            const result = await contract.methods.calcUserDividend(userAddress).call();
            return result['1'] || 0;
        } catch (e) {
            console.error('[ZODIAC_WEB3] getUserWeight failed:', e);
            return 0;
        }
    }

    // --- Staking Methods ---
    async function stakeNFTs(tokenIds) {
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
            const receipt = await sendAndTrackTransaction(contract, 'claimReward', []);
            return receipt;
        } catch (e) {
            console.error('[ZODIAC_WEB3] claimStakingReward failed:', e);
            throw e;
        }
    }

    async function claimStakingRewardBatch(tokenIds) {
        try {
            const contract = await getContract('staking');
            const receipt = await sendAndTrackTransaction(contract, 'claimRewards', [tokenIds]);
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

    // --- Gas Estimation ---
    async function estimateGas(contract, methodName, args, from) {
        try {
            const gas = await contract.methods[methodName](...args).estimateGas({ from: from || account });
            return Math.ceil(gas * 1.2);
        } catch (e) {
            console.warn(`[ZODIAC_WEB3] Gas estimation failed for ${methodName}:`, e);
            const gasLimits = {
                'mint': 2000000,
                'mintBatch': 5000000,
                'stake': 1500000,
                'unstake': 1500000,
                'rechargeChallengeAttempts': 300000,
                'challengeMockPlayer': 800000,
                'challengeRealPlayer': 1000000,
                'listNFT': 300000,
                'buyNFT': 400000,
                'delistNFT': 200000,
                'completeBreeding': 1500000,
                'claimReward': 200000
            };
            return gasLimits[methodName] || 800000;
        }
    }

    // --- Event Listening ---
    let activeEventSubscriptions = [];

    function listenToEvent(contractName, eventName, callback, options) {
        getContract(contractName).then(contract => {
            if (!contract) return;
            const eventOptions = Object.assign({ fromBlock: 'latest' }, options || {});
            const subscription = contract.events[eventName](eventOptions, callback);
            activeEventSubscriptions.push({ contractName, eventName, subscription });
        }).catch(e => {
            console.warn(`[ZODIAC_WEB3] Failed to subscribe to ${contractName}.${eventName}:`, e);
        });
    }

    function listenToEvents(events) {
        events.forEach(ev => {
            listenToEvent(ev.contract, ev.event, ev.callback, ev.options);
        });
    }

    function listenToAllEvents(callbacks) {
        const events = [];
        if (callbacks.onTransfer) {
            events.push({ contract: 'nftMint', event: 'Transfer', callback: callbacks.onTransfer });
        }
        if (callbacks.onBattleEnded) {
            events.push({ contract: 'battle', event: 'BattleEnded', callback: callbacks.onBattleEnded });
        }
        listenToEvents(events);
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
        maxAttempts = maxAttempts || 60;
        intervalMs = intervalMs || 2000;
        for (let i = 0; i < maxAttempts; i++) {
            try {
                const receipt = await web3.eth.getTransactionReceipt(txHash);
                if (receipt) return receipt;
            } catch (e) {}
            await new Promise(resolve => setTimeout(resolve, intervalMs));
        }
        throw new Error(`Transaction ${txHash} not confirmed after ${maxAttempts * intervalMs / 1000}s`);
    }

    function getPendingTransactions() { return Array.from(pendingTransactions.values()); }
    function getTransactionHistory(limit) {
        return transactionHistory.slice(0, limit || 50);
    }

    async function sendAndTrackTransaction(contract, methodName, args, options) {
        const opts = options || {};
        const from = opts.from || account;
        const sendArgs = [methodName, ...args];
        const gas = opts.gas || await estimateGas(contract, methodName, args, from);

        try {
            const receipt = await new Promise((resolve, reject) => {
                contract.methods[methodName](...args).send({
                    from,
                    gas,
                    value: opts.value || 0
                })
                .on('transactionHash', function(txHash) {
                    trackTransaction(txHash, {
                        contractName: contract._address || 'unknown',
                        methodName,
                        onSuccess: opts.onSuccess,
                        onError: opts.onError
                    });
                    if (opts.onTransactionHash) opts.onTransactionHash(txHash);
                })
                .on('receipt', resolve)
                .on('error', reject);
            });
            return receipt;
        } catch (error) {
            console.error(`[ZODIAC_WEB3] Transaction failed: ${methodName}`, error);
            if (window.ZODIAC_UI) {
                const errorMessage = error.message || '交易失败';
                ZODIAC_UI.showToast(errorMessage, 'error');
            }
            throw error;
        }
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
                if (e.code === 4902) {
                    try {
                        // 提供多个 RPC 节点，提高连接更稳定
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
        const contract = await getContract('nftTrading');
        const receipt = await sendAndTrackTransaction(contract, 'listNFT', [tokenId, priceWei]);
        return receipt;
    }

    async function buyNFT(tokenId) {
        const contract = await getContract('nftTrading');
        const listing = await contract.methods.listings(tokenId).call();
        const price = listing.priceWei || listing['1'];
        const receipt = await sendAndTrackTransaction(contract, 'buyNFT', [tokenId], { value: price });
        return receipt;
    }

    async function delistNFT(tokenId) {
        const contract = await getContract('nftTrading');
        const receipt = await sendAndTrackTransaction(contract, 'delistNFT', [tokenId]);
        return receipt;
    }

    async function setNFTApprovalForAll(operator, approved) {
        const contract = await getContract('nftMint');
        const receipt = await sendAndTrackTransaction(contract, 'setApprovalForAll', [operator, approved]);
        return receipt;
    }

    function listNFTBatch(tokenIds, prices) {
        return Promise.all(tokenIds.map((id, i) => listNFT(id, prices[i])));
    }

    // --- Arena Methods ---
    async function stakeArenaNFTs(tokenIds) {
        const contract = await getContract('arena');
        const receipt = await sendAndTrackTransaction(contract, 'stakeNFTs', [tokenIds]);
        return receipt;
    }

    async function unstakeArenaNFTs(tokenIds) {
        const contract = await getContract('arena');
        const receipt = await sendAndTrackTransaction(contract, 'unstakeNFTs', [tokenIds]);
        return receipt;
    }

    async function clearArenaTeam() {
        const contract = await getContract('arena');
        const receipt = await sendAndTrackTransaction(contract, 'clearBattleTeam', []);
        return receipt;
    }

    // --- Cleanup on page unload ---
    window.addEventListener('beforeunload', function() {
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

        // Token Staking
        stakeTokens,
        unstakeTokens,
        claimTokenStakingReward
    };
})();
