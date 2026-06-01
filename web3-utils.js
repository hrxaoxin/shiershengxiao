window.ZODIAC_WEB3 = (function() {
    let web3Instance = null;
    let currentAccount = null;
    let chainId = null;
    const listeners = {};
    const pendingNonces = new Map();

    function getConfig() {
        if (typeof ZODIAC_CONFIG === 'undefined') {
            console.error('ZODIAC_CONFIG is not defined');
            return null;
        }

        if (!ZODIAC_CONFIG.NETWORK_ID || !ZODIAC_CONFIG.CONTRACT_ADDRESSES || !ZODIAC_CONFIG.ABIS) {
            console.error('ZODIAC_CONFIG is missing required fields');
            return null;
        }

        return ZODIAC_CONFIG;
    }

    /**
     * 初始化 Web3（连接 MetaMask）
     */
    async function initWeb3() {
        const config = getConfig();
        if (!config) {
            throw new Error('ZODIAC_CONFIG 未加载');
        }

        // 检测 MetaMask
        if (typeof window.ethereum === 'undefined') {
            throw new Error('未检测到MetaMask钱包，请安装后重试');
        }

        web3Instance = new Web3(window.ethereum);
        window.web3 = web3Instance;

        try {
            const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
            currentAccount = accounts[0];
            chainId = await window.ethereum.request({ method: 'eth_chainId' });

            // 监听账户切换
            window.ethereum.on('accountsChanged', (accounts) => {
                if (accounts.length === 0) {
                    currentAccount = null;
                    emit('accountsChanged', { account: null });
                } else if (accounts[0] !== currentAccount) {
                    currentAccount = accounts[0];
                    contracts = {};
                    emit('accountsChanged', { account: currentAccount });
                }
            });

            // 监听链切换
            window.ethereum.on('chainChanged', (id) => {
                chainId = id;
                contracts = {};
                emit('chainChanged', { chainId: id });
            });

            emit('connect', { account: currentAccount, chainId: chainId });

            startEventCleanup();

            return { account: currentAccount, chainId: chainId };
        } catch (error) {
            if (error.code === 4001) {
                throw new Error('用户拒绝了连接请求');
            }
            throw error;
        }
    }

    /**
     * 获取当前账户
     */
    function getAccount() {
        return currentAccount;
    }

    /**
     * 获取 Web3 实例
     */
    function getWeb3() {
        if (!web3Instance) {
            throw new Error('Web3未初始化，请先连接钱包');
        }
        return web3Instance;
    }

    /**
     * 根据名称获取合约实例
     */
    function getContract(name) {
        const config = getConfig();
        if (!config) throw new Error('ZODIAC_CONFIG 未加载');

        const addresses = config.CONTRACT_ADDRESSES;
        const abis = config.ABIS;

        const address = addresses[name];
        if (!address) {
            throw new Error(`合约地址未找到: ${name}`);
        }
        
        if (address === '0x0000000000000000000000000000000000000000') {
            throw new Error(`合约 ${name} 的地址未配置（为零地址）`);
        }
        
        if (!address.startsWith('0x') || address.length !== 42) {
            throw new Error(`合约 ${name} 的地址格式无效: ${address}`);
        }

        // 映射合约名称到 ABI 名称
        const abiMap = {
            'tokenContract': 'tokenABI',
            'rewardManager': 'rewardManagerABI',
            'dividendManager': 'dividendManagerABI',
            'tokenBurner': 'tokenBurnerABI',
            'nftMint': 'nftMintABI',
            'nftData': 'nftDataABI',
            'nftUpdate': 'nftUpdateABI',
            'nftTrading': 'NFTTradingABI',
            'nftTradingContract': 'NFTTradingABI',
            'breeding': 'breedingABI',
            'breedingContract': 'breedingABI',
            'staking': 'stakingABI',
            'stakingContract': 'stakingABI',
            'tokenStaking': 'tokenStakingABI',
            'arena': 'arenaABI',
            'arenaRanking': 'arenaABI',
            'arenaRankingContract': 'arenaABI',
            'battle': 'battleABI',
            'battleContract': 'battleABI',
            'priceOracle': 'priceOracleABI',
            'poolManager': 'poolManagerABI',
            'weightManager': 'weightManagerABI',
            'authorizer': 'authorizerABI',
            'authorizerContract': 'authorizerABI',
            'battleHistory': 'battleHistoryABI',
            'battleHistoryContract': 'battleHistoryABI',
            'dividend': 'dividendManagerABI',
            'trading': 'NFTTradingABI',
            'upgrade': 'nftUpdateABI'
        };

        const abiKey = abiMap[name] || (name + 'ABI');
        const abi = abis[abiKey];

        if (!abi) {
            throw new Error(`合约ABI未找到: ${name} (${abiKey})`);
        }

        const web3 = getWeb3();
        return new web3.eth.Contract(abi, address);
    }

    /**
     * 估算Gas
     * @param {Object} contract - 合约实例
     * @param {string} methodName - 方法名
     * @param {Array} args - 参数
     * @param {string} from - 发送地址
     * @returns {Promise<number>} 估算的gas值
     */
    async function estimateGas(contract, methodName, args, from) {
        const method = contract.methods[methodName](...args);
        try {
            const gasEstimate = await method.estimateGas({ from });
            return Math.floor(Number(gasEstimate) * 1.5);
        } catch (error) {
            console.warn(`Gas estimation failed for ${methodName}:`, error.message);
            const DEFAULT_GAS_LIMITS = {
                'clearBattleTeam': 100000,
                'setBattleTeam': 150000,
                'rechargeChallengeAttempts': 100000,
                'claimRewards': 200000,
                'createBreedingPair': 300000,
                'listForMarketBreeding': 200000,
                'default': 700000
            };
            return DEFAULT_GAS_LIMITS[methodName] || DEFAULT_GAS_LIMITS['default'];
        }
    }

    /**
     * 事件系统
     */
    function on(event, callback) {
        if (!listeners[event]) {
            listeners[event] = [];
        }
        listeners[event].push(callback);
    }

    function off(event, callback) {
        if (!listeners[event]) return;
        listeners[event] = listeners[event].filter(cb => cb !== callback);
    }

    function emit(event, data) {
        if (!listeners[event]) return;
        listeners[event].forEach(cb => {
            try {
                cb(data);
            } catch (e) {
                console.error(`事件 ${event} 回调错误:`, e);
            }
        });
    }

    /**
     * 检查钱包是否连接
     */
    function isConnected() {
        return currentAccount !== null && web3Instance !== null;
    }

    /**
     * 切换网络到 BSC 主网
     * @param {number} retries - 重试次数（默认3次）
     * @param {number} delayMs - 重试间隔（默认1000ms）
     */
    async function switchToBSC(retries = 3, delayMs = 1000) {
        const config = getConfig();
        if (!window.ethereum) throw new Error('未检测到MetaMask');

        for (let attempt = 1; attempt <= retries; attempt++) {
            try {
                await window.ethereum.request({
                    method: 'wallet_switchEthereumChain',
                    params: [{ chainId: '0x38' }]
                });
                return true;
            } catch (switchError) {
                if (switchError.code === 4902) {
                    try {
                        await window.ethereum.request({
                            method: 'wallet_addEthereumChain',
                            params: [{
                                chainId: '0x38',
                                chainName: 'Binance Smart Chain Mainnet',
                                nativeCurrency: { name: 'BNB', symbol: 'BNB', decimals: 18 },
                                rpcUrls: ['https://bsc-dataseed.binance.org/'],
                                blockExplorerUrls: ['https://bscscan.com/']
                            }]
                        });
                        return true;
                    } catch (addError) {
                        if (attempt < retries) {
                            await new Promise(resolve => setTimeout(resolve, delayMs));
                            continue;
                        }
                        throw addError;
                    }
                } else if (attempt < retries) {
                    await new Promise(resolve => setTimeout(resolve, delayMs));
                    continue;
                } else {
                    throw switchError;
                }
            }
        }
        return false;
    }

    /**
     * 检查当前网络是否匹配配置
     */
    function isCorrectNetwork() {
        const config = getConfig();
        if (!config) return false;
        
        const expectedChainId = '0x' + config.NETWORK_ID.toString(16);
        return chainId === expectedChainId;
    }

    /**
     * 获取网络名称
     */
    function getNetworkName(chainIdHex) {
        const networks = {
            '0x1': 'Ethereum Mainnet',
            '0x38': 'Binance Smart Chain Mainnet',
            '0x56': 'BNB Smart Chain Mainnet',
            '0x61': 'BSC Testnet',
            '0x97': 'BSC Testnet',
            '0x5': 'Goerli Testnet',
            '0xaa36a7': 'Sepolia Testnet'
        };
        return networks[chainIdHex] || `Chain ID: ${chainIdHex}`;
    }

    /**
     * 显示网络错误提示
     */
    function showNetworkError(expectedNetwork) {
        const currentNetwork = getNetworkName(chainId);
        const expected = expectedNetwork || 'Binance Smart Chain Mainnet';
        
        const errorMsg = `请切换到正确的网络\n\n当前网络: ${currentNetwork}\n需要的网络: ${expected}`;
        
        if (typeof window.ZODIAC_UI !== 'undefined') {
            window.ZODIAC_UI.showToast(errorMsg, 'warning');
        } else {
            alert(errorMsg);
        }
    }

    /**
     * 强制检查网络并提示切换
     * @param {boolean} forceSwitch - 是否强制切换
     * @returns {Promise<boolean>} 是否成功切换到正确网络
     */
    async function checkAndSwitchNetwork(forceSwitch = true) {
        if (isCorrectNetwork()) {
            return { success: true, switched: false };
        }

        const config = getConfig();
        const currentNetwork = getNetworkName(chainId);
        const expectedNetwork = config.NETWORK_LABEL || 'BSC主网';

        let confirmed = false;
        let userCancelled = false;

        if (typeof window.ZODIAC_UI !== 'undefined') {
            confirmed = await window.ZODIAC_UI.showConfirmModal(
                '网络不匹配',
                `当前网络: ${currentNetwork}\n需要网络: ${expectedNetwork}\n\n是否立即切换？`
            );
        } else {
            confirmed = confirm(`当前网络: ${currentNetwork}\n需要网络: ${expectedNetwork}\n\n是否立即切换？`);
        }

        if (!confirmed) {
            userCancelled = true;
            if (typeof window.ZODIAC_UI !== 'undefined') {
                window.ZODIAC_UI.showToast('已取消网络切换', 'warning');
            }
            return { success: false, switched: false, cancelled: userCancelled };
        }

        try {
            await switchToBSC();
            return { success: true, switched: true };
        } catch (error) {
            console.error('Failed to switch network:', error);

            if (error.code === 4001 || error.message?.includes('rejected')) {
                userCancelled = true;
                if (typeof window.ZODIAC_UI !== 'undefined') {
                    window.ZODIAC_UI.showToast('用户取消了网络切换', 'warning');
                }
                return { success: false, switched: false, cancelled: true };
            }

            if (typeof window.ZODIAC_UI !== 'undefined') {
                window.ZODIAC_UI.showToast('网络切换失败，请手动切换到 ' + expectedNetwork, 'error', 5000);
            }
            return { success: false, switched: false, cancelled: false, error };
        }
    }

    /**
     * 获取链ID的十进制值
     */
    function getChainIdDecimal() {
        if (!chainId) return null;
        return parseInt(chainId, 16);
    }

    /**
     * 合约事件监听器管理
     */
    const eventListeners = {};
    let eventCleanupInterval = null;

    /**
     * 启动事件监听器定期清理
     * @param {number} intervalMs - 清理间隔（毫秒，默认5分钟）
     */
    function startEventCleanup(intervalMs = 300000) {
        if (eventCleanupInterval) {
            clearInterval(eventCleanupInterval);
        }
        
        eventCleanupInterval = setInterval(() => {
            cleanupOrphanedListeners();
        }, intervalMs);
    }

    /**
     * 停止事件监听器定期清理
     */
    function stopEventCleanup() {
        if (eventCleanupInterval) {
            clearInterval(eventCleanupInterval);
            eventCleanupInterval = null;
        }
    }

    /**
     * 清理孤立的事件监听器
     */
    function cleanupOrphanedListeners() {
        const keys = Object.keys(eventListeners);
        const now = Date.now();
        const maxAge = 3600000; // 1小时
        
        for (const key of keys) {
            const listener = eventListeners[key];
            if (!listener || !listener.timestamp) continue;
            
            if (now - listener.timestamp > maxAge) {
                try {
                    if (listener.listener && typeof listener.listener.unsubscribe === 'function') {
                        listener.listener.unsubscribe();
                    }
                    delete eventListeners[key];
                    console.log(`Cleaned up orphaned event listener: ${key}`);
                } catch (error) {
                    console.warn(`Failed to cleanup listener ${key}:`, error);
                }
            }
        }
    }

    /**
     * 监听合约事件（带自动重连）
     * @param {string} contractName - 合约名称
     * @param {string} eventName - 事件名称
     * @param {Function} callback - 回调函数
     * @param {Object} options - 选项
     * @param {number} options.maxRetries - 最大重试次数（默认5次）
     * @param {number} options.retryDelayMs - 重试间隔（默认3000ms）
     * @param {number|string} options.fromBlock - 起始区块号（默认'latest'）
     * @returns {Function} 取消监听函数
     */
    function listenToEvent(contractName, eventName, callback, options = {}) {
        const maxRetries = options.maxRetries || 5;
        const retryDelayMs = options.retryDelayMs || 3000;
        const fromBlock = options.fromBlock || 'latest';
        let retries = 0;
        let currentListener = null;
        let isUnsubscribed = false;
        const key = `${contractName}_${eventName}_${Date.now()}`;

        const setupListener = async () => {
            if (isUnsubscribed) return;

            if (currentListener) {
                try {
                    currentListener.unsubscribe();
                } catch (e) {
                    console.warn(`Previous listener unsubscribe failed: ${e.message}`);
                }
                currentListener = null;
            }

            try {
                const contract = await getContract(contractName);
                const event = contract.events[eventName];
                
                if (!event) {
                    console.warn(`Event ${eventName} not found in ${contractName}`);
                    return;
                }

                currentListener = event({ fromBlock: fromBlock }, (error, eventResult) => {
                    if (error) {
                        console.error(`Event ${eventName} error, attempting reconnect (${retries + 1}/${maxRetries}):`, error);
                        retries++;
                        if (retries < maxRetries) {
                            setTimeout(setupListener, retryDelayMs);
                        } else {
                            console.error(`Event ${eventName} max retries reached, stopping`);
                        }
                        return;
                    }
                    retries = 0;
                    callback(eventResult);
                });

                eventListeners[key] = { listener: currentListener, contractName, eventName, timestamp: Date.now() };
            } catch (error) {
                console.error(`Failed to listen to ${eventName} (${retries + 1}/${maxRetries}):`, error);
                retries++;
                if (retries < maxRetries) {
                    setTimeout(setupListener, retryDelayMs);
                } else {
                    console.error(`Event ${eventName} max retries reached, stopping`);
                }
            }
        };

        setupListener();

        const unsubscribe = () => {
            isUnsubscribed = true;
            if (currentListener) {
                try {
                    currentListener.unsubscribe();
                    delete eventListeners[key];
                } catch (e) {
                    console.warn(`Unsubscribe warning: ${e.message}`);
                }
                currentListener = null;
            }
        };

        return {
            then: (resolve, reject) => {
                return Promise.resolve().then(resolve).catch(reject);
            },
            finally: (callback) => {
                Promise.resolve().finally(callback);
                return unsubscribe();
            },
            unsubscribe: unsubscribe,
            cancel: unsubscribe
        };
    }

    /**
     * 批量监听合约事件
     * @param {Array} events - 事件配置数组
     * @example [{ contractName: 'arena', eventName: 'ChallengeResult', callback: fn }]
     */
    async function listenToEvents(events) {
        const unsubscribeFns = [];
        for (const { contractName, eventName, callback } of events) {
            const unsubscribe = await listenToEvent(contractName, eventName, callback);
            unsubscribeFns.push(unsubscribe);
        }
        return () => unsubscribeFns.forEach(fn => fn());
    }

    /**
     * 监听所有关键事件
     * @param {Object} callbacks - 回调函数对象
     * @returns {Function} 取消监听函数
     */
    async function listenToAllEvents(callbacks = {}) {
        const events = [
            { contractName: 'nftTrading', eventName: 'NFTListed', callback: callbacks.onNFTListed || defaultEventCallback },
            { contractName: 'nftTrading', eventName: 'NFTDelisted', callback: callbacks.onNFTDelisted || defaultEventCallback },
            { contractName: 'nftTrading', eventName: 'NFTBought', callback: callbacks.onNFTBought || defaultEventCallback },
            { contractName: 'nftTrading', eventName: 'EmergencyBNBWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'nftTrading', eventName: 'EmergencyNFTWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'breeding', eventName: 'BreedingPairCreated', callback: callbacks.onBreedingPairCreated || defaultEventCallback },
            { contractName: 'breeding', eventName: 'BreedingCompleted', callback: callbacks.onBreedingCompleted || defaultEventCallback },
            { contractName: 'breeding', eventName: 'BreedingCancelled', callback: callbacks.onBreedingCancelled || defaultEventCallback },
            { contractName: 'breeding', eventName: 'BreedingRewardsClaimed', callback: callbacks.onBreedingRewardsClaimed || defaultEventCallback },
            { contractName: 'breeding', eventName: 'MarketListingCreated', callback: callbacks.onMarketListingCreated || defaultEventCallback },
            { contractName: 'breeding', eventName: 'MarketListingRemoved', callback: callbacks.onMarketListingRemoved || defaultEventCallback },
            { contractName: 'breeding', eventName: 'EmergencyBNBWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'breeding', eventName: 'EmergencyTokensWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'breeding', eventName: 'EmergencyNFTWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'staking', eventName: 'Staked', callback: callbacks.onStaked || defaultEventCallback },
            { contractName: 'staking', eventName: 'Unstaked', callback: callbacks.onUnstaked || defaultEventCallback },
            { contractName: 'staking', eventName: 'RewardClaimed', callback: callbacks.onRewardClaimed || defaultEventCallback },
            { contractName: 'staking', eventName: 'EmergencyBNBWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'staking', eventName: 'EmergencyTokensWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'rewardManager', eventName: 'EmergencyTokensWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'dividendManager', eventName: 'EmergencyBNBWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'dividendManager', eventName: 'EmergencyTokensWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'tokenStaking', eventName: 'EmergencyBNBWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'tokenStaking', eventName: 'EmergencyTokensWithdrawn', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'battle', eventName: 'BattleStarted', callback: callbacks.onBattleStarted || defaultEventCallback },
            { contractName: 'battle', eventName: 'BattleEnded', callback: callbacks.onBattleEnded || defaultEventCallback },
            { contractName: 'arena', eventName: 'ChallengeResult', callback: callbacks.onChallengeResult || defaultEventCallback },
            { contractName: 'arena', eventName: 'ScoreUpdated', callback: callbacks.onScoreUpdated || defaultEventCallback },
            { contractName: 'arena', eventName: 'SeasonStarted', callback: callbacks.onSeasonStarted || defaultEventCallback },
            { contractName: 'arena', eventName: 'SeasonSettled', callback: callbacks.onSeasonSettled || defaultEventCallback },
            { contractName: 'arena', eventName: 'RewardClaimed', callback: callbacks.onArenaRewardClaimed || defaultEventCallback },
            { contractName: 'arena', eventName: 'SeasonRewardClaimed', callback: callbacks.onSeasonRewardClaimed || defaultEventCallback },
            { contractName: 'priceOracle', eventName: 'PriceUpdated', callback: callbacks.onPriceUpdated || defaultEventCallback },
            { contractName: 'priceOracle', eventName: 'PriceChangeProposed', callback: callbacks.onPriceChangeProposed || defaultEventCallback },
            { contractName: 'poolManager', eventName: 'EmergencyWithdraw', callback: callbacks.onEmergencyWithdraw || defaultEventCallback },
            { contractName: 'poolManager', eventName: 'PoolDeposited', callback: callbacks.onPoolDeposited || defaultEventCallback },
            { contractName: 'poolManager', eventName: 'PoolWithdrawn', callback: callbacks.onPoolWithdrawn || defaultEventCallback }
        ];
        return await listenToEvents(events);
    }

    function defaultEventCallback(eventResult) {
        console.log(`Event received: ${eventResult.event}`, eventResult.returnValues);
        emit('contractEvent', eventResult);
    }

    /**
     * 清理所有事件监听器
     */
    function clearAllEventListeners() {
        Object.values(eventListeners).forEach(({ listener }) => {
            listener.unsubscribe();
        });
        Object.keys(eventListeners).forEach(key => delete eventListeners[key]);
    }

    /**
     * 交易状态管理
     */
    const pendingTransactions = new Map();
    const transactionHistory = [];

    /**
     * 获取当前nonce
     * @param {string} address - 用户地址
     * @returns {Promise<number>} 当前nonce
     */
    async function getCurrentNonce(address) {
        const web3 = getWeb3();
        return await web3.eth.getTransactionCount(address, 'pending');
    }

    /**
     * 跟踪交易状态
     * @param {string} txHash - 交易哈希
     * @param {Object} options - 选项
     * @param {Function} options.onPending - 待确认回调
     * @param {Function} options.onSuccess - 成功回调
     * @param {Function} options.onError - 错误回调
     * @param {number} options.timeoutMs - 超时时间（默认300秒）
     * @param {number} options.maxRetries - 最大重试次数（默认3次）
     */
    async function trackTransaction(txHash, options = {}) {
        const { onPending, onSuccess, onError, timeoutMs = 300000, maxRetries = 3 } = options;
        const web3 = getWeb3();

        const txRecord = {
            hash: txHash,
            status: 'pending',
            createdAt: Date.now(),
            receipt: null,
            error: null
        };

        pendingTransactions.set(txHash, txRecord);
        transactionHistory.unshift(txRecord);

        if (onPending) {
            onPending(txHash);
        }

        let timeoutId;
        const timeoutPromise = new Promise((_, reject) => {
            timeoutId = setTimeout(() => reject(new Error('Transaction timeout')), timeoutMs);
        });

        const waitForReceipt = async (retries = 0) => {
            return new Promise((resolve, reject) => {
                const checkReceipt = async () => {
                    try {
                        const receipt = await web3.eth.getTransactionReceipt(txHash);
                        if (receipt) {
                            if (receipt.status) {
                                resolve(receipt);
                            } else {
                                reject(new Error('Transaction reverted'));
                            }
                        } else if (retries < maxRetries) {
                            setTimeout(checkReceipt, 2000);
                        } else {
                            reject(new Error('Transaction not confirmed after retries'));
                        }
                    } catch (error) {
                        if (retries < maxRetries) {
                            setTimeout(checkReceipt, 2000);
                        } else {
                            reject(error);
                        }
                    }
                };
                checkReceipt();
            });
        };

        try {
            const receipt = await Promise.race([waitForReceipt(), timeoutPromise]);

            txRecord.status = 'success';
            txRecord.receipt = receipt;

            if (onSuccess) {
                onSuccess(receipt);
            }

            return receipt;
        } catch (error) {
            txRecord.status = 'error';
            txRecord.error = error.message;

            if (onError) {
                onError(error);
            }

            throw error;
        } finally {
            clearTimeout(timeoutId);
            pendingTransactions.delete(txHash);
        }
    }

    /**
     * 获取待处理交易
     * @returns {Array} 待处理交易列表
     */
    function getPendingTransactions() {
        return Array.from(pendingTransactions.values());
    }

    /**
     * 获取交易历史
     * @param {number} limit - 返回数量限制
     * @returns {Array} 交易历史
     */
    function getTransactionHistory(limit = 20) {
        return transactionHistory.slice(0, limit);
    }

    /**
     * 发送交易并自动跟踪状态
     * @param {Object} contract - 合约实例
     * @param {string} methodName - 方法名
     * @param {Array} args - 参数
     * @param {Object} options - 交易选项
     * @returns {Promise<Object>} 交易收据
     */
    async function sendAndTrackTransaction(contract, methodName, args, options = {}) {
        await checkAndSwitchNetwork();

        const from = currentAccount;
        const method = contract.methods[methodName](...args);

        // 估算gas
        let gasLimit;
        try {
            gasLimit = await estimateGas(contract, methodName, args, from);
        } catch (error) {
            console.warn('Gas estimation failed, using default:', error.message);
            gasLimit = 700000;
        }

        // 获取nonce并跟踪
        const nonce = await getCurrentNonce(from);
        pendingNonces.set(`${from}-${nonce}`, true);

        // 发送交易
        const tx = await method.send({
            from,
            gas: gasLimit,
            nonce,
            ...options
        }).on('transactionHash', () => {
            pendingNonces.delete(`${from}-${nonce}`);
        }).on('error', () => {
            pendingNonces.delete(`${from}-${nonce}`);
        });

        // 跟踪交易
        return await trackTransaction(tx.transactionHash, {
            onPending: (hash) => console.log('Transaction pending:', hash),
            onSuccess: (receipt) => console.log('Transaction succeeded:', receipt),
            onError: (error) => console.error('Transaction failed:', error)
        });
    }

    /**
     * 获取事件监听器状态
     */
    function getEventListeners() {
        return Object.keys(eventListeners).length;
    }

    async function challenge(challengerId, challengedId, challengerTeam, challengedTeam, challengedAddress) {
        await checkAndSwitchNetwork();
        const contract = await getContract('battle');
        return await contract.methods.challenge(challengerId, challengedId, challengerTeam, challengedTeam, challengedAddress).send({ from: currentAccount });
    }

    async function simulateBattle(team1, team2) {
        const contract = await getContract('battle');
        return await contract.methods.simulateBattle(team1, team2).call();
    }

    async function battle(attackerTeam, defenderTeam) {
        await checkAndSwitchNetwork();
        const contract = await getContract('battle');
        return await contract.methods.battle(attackerTeam, defenderTeam).call();
    }

    async function stake(tokenIds) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('staking');
            return await contract.methods.stake(tokenIds).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '质押NFT');
            throw error;
        }
    }

    async function unstake(tokenIds) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('staking');
            return await contract.methods.unstake(tokenIds).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '解除质押');
            throw error;
        }
    }

    async function claimReward() {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('staking');
            return await contract.methods.claimReward().send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '领取奖励');
            throw error;
        }
    }

    async function createSelfBreedingPair(fatherId, motherId, coOwnerId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('breeding');
            return await contract.methods.createSelfBreedingPair(fatherId, motherId, coOwnerId).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '创建繁殖对');
            throw error;
        }
    }

    async function stakeArenaNFTs(tokenIds) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('arena');
            return await contract.methods.stakeNFTs(tokenIds).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '质押竞技场NFT');
            throw error;
        }
    }

    async function unstakeArenaNFTs(tokenIds) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('arena');
            return await contract.methods.unstakeNFTs(tokenIds).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '解除竞技场NFT质押');
            throw error;
        }
    }

    async function isNFTStaked(tokenId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('arena');
            const stakedOwner = await contract.methods.nftStakedOwner(tokenId).call();
            return stakedOwner !== '0x0000000000000000000000000000000000000000';
        } catch (error) {
            handleContractError(error, '检查NFT质押状态');
            throw error;
        }
    }

    async function areNFTsStaked(tokenIds) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('arena');
            const results = [];
            for (const tokenId of tokenIds) {
                const stakedOwner = await contract.methods.nftStakedOwner(tokenId).call();
                results.push(stakedOwner !== '0x0000000000000000000000000000000000000000');
            }
            return results;
        } catch (error) {
            handleContractError(error, '批量检查NFT质押状态');
            throw error;
        }
    }

    async function clearArenaTeam() {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('arena');
            return await contract.methods.clearBattleTeam().send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '清除竞技场战队');
            throw error;
        }
    }

    async function completeBreeding(pairId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('breeding');
            return await contract.methods.completeBreeding(pairId).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '完成繁殖');
            throw error;
        }
    }

    async function cancelBreeding(pairId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('breeding');
            return await contract.methods.cancelBreeding(pairId).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '取消繁殖');
            throw error;
        }
    }

    async function listForMarketBreeding(tokenId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('breeding');
            return await contract.methods.listForMarketBreeding(tokenId).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '上架市场繁殖');
            throw error;
        }
    }

    async function delistFromMarketBreeding(tokenId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('breeding');
            return await contract.methods.delistFromMarketBreeding(tokenId).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '下架市场繁殖');
            throw error;
        }
    }

    async function createMarketBreedingPairPublic(fatherId, motherId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('breeding');
            return await contract.methods.createMarketBreedingPairPublic(fatherId, motherId).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '创建市场繁殖对');
            throw error;
        }
    }

    async function listNFT(tokenId, priceWei) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('nftTrading');
            return await contract.methods.listNFT(tokenId, priceWei).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '上架NFT');
            throw error;
        }
    }

    async function buyNFT(tokenId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('nftTrading');
            const web3 = await getWeb3();
            const listing = await contract.methods.getListingInfo(tokenId).call();
            const priceWei = listing.priceWei;
            const value = web3.utils.toBN(priceWei).toString();
            return await contract.methods.buyNFT(tokenId).send({ from: currentAccount, value: value });
        } catch (error) {
            handleContractError(error, '购买NFT');
            throw error;
        }
    }

    async function delistNFT(tokenId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('nftTrading');
            return await contract.methods.delistNFT(tokenId).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '下架NFT');
            throw error;
        }
    }

    async function mintNormal(to) {
        console.warn('警告: mintNormal 直接铸造NFT，绕过了 TokenBurner 流程。仅供管理员测试使用。');
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.mintNormal(to).send({ from: currentAccount });
    }

    async function mintRare(to) {
        console.warn('警告: mintRare 直接铸造NFT，绕过了 TokenBurner 流程。仅供管理员测试使用。');
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.mintRare(to).send({ from: currentAccount });
    }

    async function mintNormalTen(to) {
        console.warn('警告: mintNormalTen 直接铸造NFT，绕过了 TokenBurner 流程。仅供管理员测试使用。');
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.mintNormalTen(to).send({ from: currentAccount });
    }

    async function mintRareTen(to) {
        console.warn('警告: mintRareTen 直接铸造NFT，绕过了 TokenBurner 流程。仅供管理员测试使用。');
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.mintRareTen(to).send({ from: currentAccount });
    }

    async function mintTargeted(to, baseZodiac) {
        console.warn('警告: mintTargeted 直接铸造NFT，绕过了 TokenBurner 流程。仅供管理员测试使用。');
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.mintTargeted(to, baseZodiac).send({ from: currentAccount });
    }

    async function adminSetNFTLevel(tokenId, newLevel) {
        console.warn('警告: adminSetNFTLevel 是管理员函数，仅限授权地址调用。');
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.adminSetNFTLevel(tokenId, newLevel).send({ from: currentAccount });
    }

    async function challengeMockPlayer(team, mockPlayerId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('arena');
            return await contract.methods.challengeMockPlayer(team, mockPlayerId).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '挑战模拟玩家');
            throw error;
        }
    }

    async function challengeRealPlayer(team, playerAddress) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('arena');
            return await contract.methods.challengeRealPlayer(team, playerAddress).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '挑战真实玩家');
            throw error;
        }
    }

    async function claimSeasonReward() {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('arena');
            return await contract.methods.claimSeasonReward().send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '领取赛季奖励');
            throw error;
        }
    }

    async function stakeTokens(amount) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('tokenStaking');
            return await contract.methods.stakeTokens(amount).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '代币质押');
            throw error;
        }
    }
    
    async function unstakeTokens(amount) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('tokenStaking');
            return await contract.methods.unstakeTokens(amount).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '代币解除质押');
            throw error;
        }
    }

    async function claimTokenRewards() {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('tokenStaking');
            return await contract.methods.claimRewards().send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '领取代币奖励');
            throw error;
        }
    }

    async function getNFTBatch(tokenIds) {
        if (!Array.isArray(tokenIds) || tokenIds.length === 0) {
            return [];
        }
        
        const contract = await getContract('nftMint');
        const promises = tokenIds.map(id => contract.methods.getNFTData(id).call().catch(() => null));
        return await Promise.all(promises);
    }
    
    async function getStakingBatch(tokenIds) {
        if (!Array.isArray(tokenIds) || tokenIds.length === 0) {
            return [];
        }
        
        const contract = await getContract('staking');
        const promises = tokenIds.map(id => contract.methods.stakingInfo(id).call().catch(() => null));
        return await Promise.all(promises);
    }
    
    async function getBreedingBatch(pairIds) {
        if (!Array.isArray(pairIds) || pairIds.length === 0) {
            return [];
        }
        
        const contract = await getContract('breeding');
        const promises = pairIds.map(id => contract.methods.breedingPairs(id).call().catch(() => null));
        return await Promise.all(promises);
    }
    
    async function listNFTBatch(tokenIds, prices) {
        if (!Array.isArray(tokenIds) || tokenIds.length === 0) {
            throw new Error('tokenIds 不能为空');
        }
        
        const contract = await getContract('nftTrading');
        const promises = tokenIds.map((id, index) => {
            const price = prices && prices[index];
            if (!price) {
                return Promise.reject(new Error(`价格未提供 for tokenId: ${id}`));
            }
            return contract.methods.listNFT(id, price).send({ from: currentAccount }).catch(() => null);
        });
        return await Promise.all(promises);
    }

    async function approveToken(spender, amount) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('tokenContract');
            return await contract.methods.approve(spender, amount).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '授权代币');
            throw error;
        }
    }

    async function setNFTApprovalForAll(operator, approved) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('nftMint');
            return await contract.methods.setApprovalForAll(operator, approved).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '授权NFT');
            throw error;
        }
    }

    async function upgradeWithNFT(tokenId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('nftUpdate');
            return await contract.methods.upgradeWithNFT(tokenId).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '升级NFT(NFT消耗)');
            throw error;
        }
    }

    async function upgradeWithToken(tokenId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('nftUpdate');
            return await contract.methods.upgradeWithToken(tokenId).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '升级NFT(代币消耗)');
            throw error;
        }
    }

    async function upgradeWithUSDValue(tokenId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('nftUpdate');
            return await contract.methods.upgradeWithUSDValue(tokenId).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '升级NFT(USD价值)');
            throw error;
        }
    }

    async function getBreedingConfig() {
        try {
            const contract = await getContract('breeding');
            const selfBreedingCooldown = await contract.methods.selfBreedingCooldown().call();
            const marketBreedingCooldown = await contract.methods.marketBreedingCooldown().call();
            const selfBreedingFee = await contract.methods.selfBreedingFee().call();
            const marketBreedingFee = await contract.methods.marketBreedingFee().call();
            return {
                selfBreedingCooldown: selfBreedingCooldown,
                marketBreedingCooldown: marketBreedingCooldown,
                selfBreedingFee: selfBreedingFee,
                marketBreedingFee: marketBreedingFee
            };
        } catch (error) {
            handleContractError(error, '获取繁殖配置');
            throw error;
        }
    }

    async function claimDividend() {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('dividendManager');
            return await contract.methods.claim().send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '领取分红');
            throw error;
        }
    }

    async function getClaimableDividend(user) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('dividendManager');
            return await contract.methods.getClaimableDividend(user).call();
        } catch (error) {
            handleContractError(error, '查询可领取分红');
            throw error;
        }
    }

    async function burnAndMint(isRare) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('tokenBurner');
            return await contract.methods.burnAndMint(currentAccount, isRare).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '销毁铸造');
            throw error;
        }
    }

    async function burnAndMintTen(isRare) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('tokenBurner');
            return await contract.methods.burnAndMintTen(currentAccount, isRare).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '销毁铸造10个');
            throw error;
        }
    }

    async function burnAndMintTargeted(zodiac) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('tokenBurner');
            return await contract.methods.burnAndMintTargeted(currentAccount, zodiac).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '定向销毁铸造');
            throw error;
        }
    }

    async function getPoolBalance(poolType) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('poolManager');
            return await contract.methods.getPoolBalance(poolType).call();
        } catch (error) {
            handleContractError(error, '获取池子余额');
            throw error;
        }
    }

    async function getUserWeight(user) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('weightManager');
            return await contract.methods.getUserWeight(user).call();
        } catch (error) {
            handleContractError(error, '获取用户权重');
            throw error;
        }
    }

    async function refreshUserWeightCache(user) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('weightManager');
            return await contract.methods.refreshUserWeightCache(user).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '刷新用户权重缓存');
            throw error;
        }
    }

    async function getBattleHistory(user) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('battleHistory');
            return await contract.methods.getUserBattleHistory(user).call();
        } catch (error) {
            handleContractError(error, '获取用户战斗历史');
            throw error;
        }
    }

    async function getRecentBattles() {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('battleHistory');
            return await contract.methods.getRecentBattles().call();
        } catch (error) {
            handleContractError(error, '获取最近战斗');
            throw error;
        }
    }

    async function getBattleRecord(battleId) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('battleHistory');
            return await contract.methods.getBattleRecord(battleId).call();
        } catch (error) {
            handleContractError(error, '获取战斗记录');
            throw error;
        }
    }

    async function getAuthorizerAddresses() {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('authorizer');
            const addresses = await contract.methods.tokenAddress().call();
            return {
                tokenAddress: addresses,
                usdtAddress: await contract.methods.usdtAddress().call(),
                battleAddress: await contract.methods.battleAddress().call(),
                breedingAddress: await contract.methods.breedingAddress().call(),
                stakingAddress: await contract.methods.stakingAddress().call(),
                rewardManagerAddress: await contract.methods.rewardManagerAddress().call(),
                dividendManagerAddress: await contract.methods.dividendManagerAddress().call(),
                priceOracleAddress: await contract.methods.priceOracleAddress().call(),
                arenaRankingAddress: await contract.methods.arenaRankingAddress().call(),
                nftDataAddress: await contract.methods.nftDataAddress().call(),
                poolManagerAddress: await contract.methods.poolManagerAddress().call(),
                weightManagerAddress: await contract.methods.weightManagerAddress().call(),
                battleHistoryAddress: await contract.methods.battleHistoryAddress().call(),
                nftTradingAddress: await contract.methods.nftTradingAddress().call(),
                nftMintAddress: await contract.methods.nftMintAddress().call()
            };
        } catch (error) {
            handleContractError(error, '获取授权者地址');
            throw error;
        }
    }

    return {
        initWeb3,
        getAccount,
        getWeb3,
        getContract,
        estimateGas,
        on,
        off,
        emit,
        isConnected,
        switchToBSC,
        isCorrectNetwork,
        getNetworkName,
        showNetworkError,
        checkAndSwitchNetwork,
        getChainIdDecimal,
        listenToEvent,
        listenToEvents,
        listenToAllEvents,
        clearAllEventListeners,
        startEventCleanup,
        stopEventCleanup,
        cleanupOrphanedListeners,
        getEventListeners,
        getCurrentNonce,
        trackTransaction,
        getPendingTransactions,
        getTransactionHistory,
        sendAndTrackTransaction,
        challenge,
        stakeArenaNFTs,
        unstakeArenaNFTs,
        isNFTStaked,
        areNFTsStaked,
        clearArenaTeam,
        simulateBattle,
        battle,
        stake,
        unstake,
        claimReward,
        createSelfBreedingPair,
        completeBreeding,
        cancelBreeding,
        listForMarketBreeding,
        delistFromMarketBreeding,
        createMarketBreedingPairPublic,
        listNFT,
        buyNFT,
        delistNFT,
        mintNormal,
        mintRare,
        mintNormalTen,
        mintRareTen,
        mintTargeted,
        adminSetNFTLevel,
        challengeMockPlayer,
        challengeRealPlayer,
        claimSeasonReward,
        stakeTokens,
        unstakeTokens,
        claimTokenRewards,
        getNFTBatch,
        getStakingBatch,
        getBreedingBatch,
        listNFTBatch,
        approveToken,
        setNFTApprovalForAll,
        upgradeWithNFT,
        upgradeWithToken,
        upgradeWithUSDValue,
        getBreedingConfig,
        claimDividend,
        getClaimableDividend,
        burnAndMint,
        burnAndMintTen,
        burnAndMintTargeted,
        getPoolBalance,
        getUserWeight,
        refreshUserWeightCache,
        getBattleHistory,
        getRecentBattles,
        getBattleRecord,
        getAuthorizerAddresses
    };
})();
