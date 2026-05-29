window.ZODIAC_WEB3 = (function() {
    let web3Instance = null;
    let currentAccount = null;
    let chainId = null;
    const listeners = {};

    function getConfig() {
        return window.ZODIAC_CONFIG;
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

        try {
            const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
            currentAccount = accounts[0];
            chainId = await window.ethereum.request({ method: 'eth_chainId' });

            // 监听账户切换
            window.ethereum.on('accountsChanged', (accounts) => {
                currentAccount = accounts[0] || null;
                emit('accountsChanged', { account: currentAccount });
            });

            // 监听链切换
            window.ethereum.on('chainChanged', (id) => {
                chainId = id;
                emit('chainChanged', { chainId: id });
            });

            emit('connect', { account: currentAccount, chainId: chainId });

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
            'nftUpdate': 'nftUpdateABI',
            'nftTrading': 'NFTTradingABI',
            'breeding': 'breedingABI',
            'staking': 'stakingABI',
            'tokenStaking': 'tokenStakingABI',
            'arena': 'arenaABI',
            'battle': 'battleABI'
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
     * 估算 Gas
     */
    async function estimateGas(contract, methodName, args, from) {
        try {
            const gasEstimate = await contract.methods[methodName](...args).estimateGas({
                from: from || currentAccount
            });
            // 增加 30% 的 buffer
            const gasWithBuffer = Math.floor(Number(gasEstimate) * 1.3);
            return gasWithBuffer;
        } catch (error) {
            console.warn(`Gas估算失败 (${methodName}):`, error.message);
            // 返回默认 Gas 限制
            return 300000;
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
            return true;
        }

        const config = getConfig();
        const currentNetwork = getNetworkName(chainId);
        const expectedNetwork = config.NETWORK_LABEL || 'BSC主网';

        if (typeof window.ZODIAC_UI !== 'undefined') {
            const confirmed = await window.ZODIAC_UI.showConfirmModal(
                '网络不匹配',
                `当前网络: ${currentNetwork}\n需要网络: ${expectedNetwork}\n\n是否立即切换？`
            );

            if (confirmed) {
                try {
                    await switchToBSC();
                    return true;
                } catch (error) {
                    console.error('Failed to switch network:', error);
                    if (typeof window.ZODIAC_UI !== 'undefined') {
                        window.ZODIAC_UI.showToast('网络切换失败，请手动切换', 'error');
                    }
                    return false;
                }
            }
        } else {
            const confirmed = confirm(`当前网络: ${currentNetwork}\n需要网络: ${expectedNetwork}\n\n是否立即切换？`);
            if (confirmed) {
                try {
                    await switchToBSC();
                    return true;
                } catch (error) {
                    alert('网络切换失败，请手动切换');
                    return false;
                }
            }
        }
        return false;
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

    /**
     * 监听合约事件（带自动重连）
     * @param {string} contractName - 合约名称
     * @param {string} eventName - 事件名称
     * @param {Function} callback - 回调函数
     * @param {Object} options - 选项
     * @param {number} options.maxRetries - 最大重试次数（默认5次）
     * @param {number} options.retryDelayMs - 重试间隔（默认3000ms）
     * @returns {Function} 取消监听函数
     */
    function listenToEvent(contractName, eventName, callback, options = {}) {
        const maxRetries = options.maxRetries || 5;
        const retryDelayMs = options.retryDelayMs || 3000;
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

                currentListener = event({ fromBlock: 'latest' }, (error, eventResult) => {
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

                eventListeners[key] = { listener: currentListener, contractName, eventName };
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
                currentListener.unsubscribe((err, success) => {
                    if (success) {
                        delete eventListeners[key];
                    }
                });
            }
        };

        return Promise.resolve(unsubscribe);
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
            { contractName: 'breeding', eventName: 'BreedingPairCreated', callback: callbacks.onBreedingPairCreated || defaultEventCallback },
            { contractName: 'breeding', eventName: 'BreedingCompleted', callback: callbacks.onBreedingCompleted || defaultEventCallback },
            { contractName: 'breeding', eventName: 'BreedingCancelled', callback: callbacks.onBreedingCancelled || defaultEventCallback },
            { contractName: 'breeding', eventName: 'BreedingRewardsClaimed', callback: callbacks.onBreedingRewardsClaimed || defaultEventCallback },
            { contractName: 'breeding', eventName: 'MarketListingCreated', callback: callbacks.onMarketListingCreated || defaultEventCallback },
            { contractName: 'breeding', eventName: 'MarketListingRemoved', callback: callbacks.onMarketListingRemoved || defaultEventCallback },
            { contractName: 'staking', eventName: 'Staked', callback: callbacks.onStaked || defaultEventCallback },
            { contractName: 'staking', eventName: 'Unstaked', callback: callbacks.onUnstaked || defaultEventCallback },
            { contractName: 'staking', eventName: 'RewardClaimed', callback: callbacks.onRewardClaimed || defaultEventCallback },
            { contractName: 'battle', eventName: 'BattleStarted', callback: callbacks.onBattleStarted || defaultEventCallback },
            { contractName: 'battle', eventName: 'BattleEnded', callback: callbacks.onBattleEnded || defaultEventCallback },
            { contractName: 'arena', eventName: 'ChallengeResult', callback: callbacks.onChallengeResult || defaultEventCallback },
            { contractName: 'arena', eventName: 'ScoreUpdated', callback: callbacks.onScoreUpdated || defaultEventCallback },
            { contractName: 'arena', eventName: 'SeasonStarted', callback: callbacks.onSeasonStarted || defaultEventCallback },
            { contractName: 'arena', eventName: 'SeasonSettled', callback: callbacks.onSeasonSettled || defaultEventCallback },
            { contractName: 'arena', eventName: 'RewardClaimed', callback: callbacks.onArenaRewardClaimed || defaultEventCallback },
            { contractName: 'arena', eventName: 'SeasonRewardClaimed', callback: callbacks.onSeasonRewardClaimed || defaultEventCallback }
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
        const contract = await getContract('battle');
        return await contract.methods.battle(attackerTeam, defenderTeam).call();
    }

    async function stake(tokenIds) {
        await checkAndSwitchNetwork();
        const contract = await getContract('staking');
        return await contract.methods.stake(tokenIds).send({ from: currentAccount });
    }

    async function unstake(tokenIds) {
        await checkAndSwitchNetwork();
        const contract = await getContract('staking');
        return await contract.methods.unstake(tokenIds).send({ from: currentAccount });
    }

    async function claimReward() {
        await checkAndSwitchNetwork();
        const contract = await getContract('staking');
        return await contract.methods.claimReward().send({ from: currentAccount });
    }

    async function createBreedingPair(fatherId, motherId, coOwnerId) {
        await checkAndSwitchNetwork();
        const contract = await getContract('breeding');
        return await contract.methods.createSelfBreedingPair(fatherId, motherId, coOwnerId).send({ from: currentAccount });
    }

    async function completeBreeding(pairId) {
        await checkAndSwitchNetwork();
        const contract = await getContract('breeding');
        return await contract.methods.completeBreeding(pairId).send({ from: currentAccount });
    }

    async function cancelBreeding(pairId) {
        await checkAndSwitchNetwork();
        const contract = await getContract('breeding');
        return await contract.methods.cancelBreeding(pairId).send({ from: currentAccount });
    }

    async function claimBreedingRewards(pairId) {
        await checkAndSwitchNetwork();
        const contract = await getContract('breeding');
        return await contract.methods.claimBreedingRewards(pairId).send({ from: currentAccount });
    }

    async function listNFT(tokenId, priceWei) {
        await checkAndSwitchNetwork();
        const contract = await getContract('nftTrading');
        return await contract.methods.listNFT(tokenId, priceWei).send({ from: currentAccount });
    }

    async function buyNFT(tokenId, priceWei) {
        await checkAndSwitchNetwork();
        const contract = await getContract('nftTrading');
        const web3 = await getWeb3();
        const value = web3.utils.toBN(priceWei).toString();
        return await contract.methods.buyNFT(tokenId).send({ from: currentAccount, value: value });
    }

    async function delistNFT(tokenId) {
        await checkAndSwitchNetwork();
        const contract = await getContract('nftTrading');
        return await contract.methods.delistNFT(tokenId).send({ from: currentAccount });
    }

    async function mintNormal(to) {
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.mintNormal(to).send({ from: currentAccount });
    }

    async function mintRare(to) {
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.mintRare(to).send({ from: currentAccount });
    }

    async function mintNormalTen(to) {
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.mintNormalTen(to).send({ from: currentAccount });
    }

    async function mintRareTen(to) {
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.mintRareTen(to).send({ from: currentAccount });
    }

    async function mintTargeted(to, baseZodiac) {
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.mintTargeted(to, baseZodiac).send({ from: currentAccount });
    }

    async function setNFTLevel(tokenId, newLevel) {
        await checkAndSwitchNetwork();
        const contract = await getContract('nftMint');
        return await contract.methods.setNFTLevel(tokenId, newLevel).send({ from: currentAccount });
    }

    async function challengeMockPlayer(mockPlayerId, team) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('arena');
            return await contract.methods.challengeMockPlayer(mockPlayerId, team).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '挑战模拟玩家');
            throw error;
        }
    }

    async function challengeRealPlayer(playerAddress, team) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('arena');
            return await contract.methods.challengeRealPlayer(playerAddress, team).send({ from: currentAccount });
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
            const web3 = await getWeb3();
            const value = web3.utils.toBN(amount).toString();
            return await contract.methods.stake(value).send({ from: currentAccount });
        } catch (error) {
            handleContractError(error, '代币质押');
            throw error;
        }
    }

    async function unstakeTokens(amount) {
        try {
            await checkAndSwitchNetwork();
            const contract = await getContract('tokenStaking');
            const web3 = await getWeb3();
            const value = web3.utils.toBN(amount).toString();
            return await contract.methods.unstake(value).send({ from: currentAccount });
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
        const promises = tokenIds.map(id => contract.methods.getNFTInfo(id).call().catch(() => null));
        return await Promise.all(promises);
    }
    
    async function getStakingBatch(tokenIds) {
        if (!Array.isArray(tokenIds) || tokenIds.length === 0) {
            return [];
        }
        
        const contract = await getContract('staking');
        const promises = tokenIds.map(id => contract.methods.getStakingInfo(id).call().catch(() => null));
        return await Promise.all(promises);
    }
    
    async function getBreedingBatch(pairIds) {
        if (!Array.isArray(pairIds) || pairIds.length === 0) {
            return [];
        }
        
        const contract = await getContract('breeding');
        const promises = pairIds.map(id => contract.methods.getBreedingInfo(id).call().catch(() => null));
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
        getEventListeners,
        challenge,
        simulateBattle,
        battle,
        stake,
        unstake,
        claimReward,
        createBreedingPair,
        completeBreeding,
        cancelBreeding,
        claimBreedingRewards,
        listNFT,
        buyNFT,
        delistNFT,
        mintNormal,
        mintRare,
        mintNormalTen,
        mintRareTen,
        mintTargeted,
        setNFTLevel,
        challengeMockPlayer,
        challengeRealPlayer,
        claimSeasonReward,
        stakeTokens,
        unstakeTokens,
        claimTokenRewards,
        getNFTBatch,
        getStakingBatch,
        getBreedingBatch,
        listNFTBatch
    };
})();
