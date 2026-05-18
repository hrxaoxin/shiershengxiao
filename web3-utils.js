window.ZODIAC_WEB3 = (function() {
    let web3;
    let account = null;
    let isConnected = false;
    let contracts = {};
    let cacheData = {};
    let cacheExpiryTime = 5 * 60 * 1000;

    function getCache(key) {
        const item = cacheData[key];
        if (!item) return null;
        
        if (Date.now() > item.expiry) {
            delete cacheData[key];
            return null;
        }
        
        return item.value;
    }

    function setCache(key, value, ttl = cacheExpiryTime) {
        cacheData[key] = {
            value,
            expiry: Date.now() + ttl,
            timestamp: Date.now()
        };
    }

    function clearCache(key) {
        if (key) {
            delete cacheData[key];
        } else {
            cacheData = {};
        }
    }

    function isCacheValid(key) {
        const item = cacheData[key];
        if (!item) return false;
        return Date.now() <= item.expiry;
    }
    
    const eventListeners = {
        'connect': [],
        'disconnect': [],
        'accountChange': [],
        'chainChange': []
    };

    const registeredListeners = new Map();

    const ERROR_CODES = {
        4001: '用户拒绝了操作',
        -32000: 'RPC错误',
        -32601: '方法不存在',
        -32602: '参数无效'
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

    function getErrorMessage(error) {
        const errorStr = error.message || error.toString();
        
        if (error.code && ERROR_CODES[error.code]) {
            return ERROR_CODES[error.code];
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

    function emitEvent(eventName, data) {
        eventListeners[eventName].forEach(callback => {
            try {
                callback(data);
            } catch (error) {
                console.error('Event listener error:', error);
            }
        });
    }

    function on(eventName, callback) {
        if (!eventListeners[eventName]) {
            eventListeners[eventName] = [];
        }
        
        const callbackId = callback.name || Symbol().toString();
        const key = `${eventName}:${callbackId}`;
        
        if (registeredListeners.has(key)) {
            console.warn(`Listener already registered for event "${eventName}" with callback "${callbackId}"`);
            return;
        }
        
        eventListeners[eventName].push(callback);
        registeredListeners.set(key, callback);
    }

    function off(eventName, callback) {
        if (!eventListeners[eventName]) return;
        
        const callbackId = callback.name || Symbol().toString();
        const key = `${eventName}:${callbackId}`;
        
        const index = eventListeners[eventName].indexOf(callback);
        if (index > -1) {
            eventListeners[eventName].splice(index, 1);
            registeredListeners.delete(key);
        }
    }

    function clearListeners(eventName) {
        if (eventListeners[eventName]) {
            eventListeners[eventName].forEach(callback => {
                const callbackId = callback.name || Symbol().toString();
                registeredListeners.delete(`${eventName}:${callbackId}`);
            });
            eventListeners[eventName] = [];
        }
    }

    async function initWeb3() {
        try {
            if (typeof window.ethereum !== 'undefined') {
                web3 = new Web3(window.ethereum);
                const accounts = await window.ethereum.request({ method: 'eth_accounts' });
                if (accounts.length > 0) {
                    account = accounts[0];
                    isConnected = true;
                    emitEvent('connect', { account });
                }
            } else {
                console.error('MetaMask not detected');
                throw new Error('未检测到钱包，请安装MetaMask');
            }
        } catch (error) {
            console.error('Web3 initialization error:', error);
            throw error;
        }
        return isConnected;
    }

    async function connectWallet() {
        try {
            if (!web3) {
                await initWeb3();
            }
            const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
            if (accounts.length > 0) {
                account = accounts[0];
                isConnected = true;
                contracts = {};
                emitEvent('connect', { account });
                return { success: true, account };
            }
        } catch (error) {
            console.error('Wallet connection error:', error);
            return { success: false, error: error.message };
        }
        return { success: false, error: 'No accounts found' };
    }

    function disconnectWallet() {
        account = null;
        isConnected = false;
        contracts = {};
        emitEvent('disconnect', {});
    }

    function getAccount() {
        return account;
    }

    function isWalletConnected() {
        return isConnected;
    }

    function getWeb3() {
        return web3;
    }

    function createContract(abi, address) {
        if (!web3) {
            throw new Error('Web3 not initialized');
        }
        return new web3.eth.Contract(abi, address);
    }

    async function getContract(contractName) {
        if (!isConnected) {
            throw new Error('Wallet not connected');
        }
        
        if (contracts[contractName]) {
            return contracts[contractName];
        }

        const config = window.ZODIAC_CONFIG || {};
        const addresses = config.CONTRACT_ADDRESSES || window.contractAddresses || {};
        const abis = config.ABIS || {};
        
        const abiMap = {
            tokenContract: abis.tokenABI,
            rewardManager: abis.rewardManagerABI,
            tokenBurner: abis.tokenBurnerABI,
            nftMint: abis.nftMintABI,
            nftUpdate: abis.nftUpdateABI,
            nftTrading: abis.NFTTradingABI,
            breeding: abis.breedingABI,
            staking: abis.stakingABI,
            tokenStaking: abis.tokenStakingABI,
            arena: abis.arenaABI,
            battle: abis.battleABI
        };

        const contractAddress = addresses[contractName];
        const abi = abiMap[contractName];
        
        if (!abi) {
            throw new Error(`Unknown contract: ${contractName}`);
        }

        if (!contractAddress || contractAddress === '0x0000000000000000000000000000000000000000') {
            throw new Error(`Contract ${contractName} address not configured`);
        }

        contracts[contractName] = createContract(abi, contractAddress);
        return contracts[contractName];
    }

    async function getBalance() {
        if (!isConnected || !account) return '0';
        try {
            const balance = await web3.eth.getBalance(account);
            return web3.utils.fromWei(balance, 'ether');
        } catch (error) {
            console.error('Get balance error:', error);
            return '0';
        }
    }

    async function getTokenBalance() {
        if (!isConnected || !account) return '0';
        try {
            const tokenContract = await getContract('tokenContract');
            const balance = await tokenContract.methods.balanceOf(account).call();
            return (parseInt(balance) / 1e18).toFixed(4);
        } catch (error) {
            console.error('Token balance error:', error);
            return '0';
        }
    }

    async function approveToken(spender, amount) {
        if (!isConnected || !account) {
            throw new Error('Wallet not connected');
        }
        try {
            const tokenContract = await getContract('tokenContract');
            const tx = await tokenContract.methods.approve(spender, amount).send({ from: account });
            return tx;
        } catch (error) {
            console.error('Approve token error:', error);
            throw error;
        }
    }

    async function checkApproval(spender, amount) {
        if (!isConnected || !account) return false;
        try {
            const tokenContract = await getContract('tokenContract');
            const allowance = await tokenContract.methods.allowance(account, spender).call();
            return parseInt(allowance) >= parseInt(amount);
        } catch (error) {
            console.error('Check approval error:', error);
            return false;
        }
    }

    async function checkApprovalForAll(spender) {
        if (!isConnected || !account) return false;
        try {
            const nftContract = await getContract('nftMint');
            const approval = await nftContract.methods.isApprovedForAll(account, spender).call();
            return approval;
        } catch (error) {
            console.error('Check approval for all error:', error);
            return false;
        }
    }

    async function approveForAll(spender, approved = true) {
        if (!isConnected || !account) {
            throw new Error('Wallet not connected');
        }
        try {
            const nftContract = await getContract('nftMint');
            const tx = await nftContract.methods.setApprovalForAll(spender, approved).send({ from: account });
            return tx;
        } catch (error) {
            console.error('Approve for all error:', error);
            throw error;
        }
    }

    async function estimateGas(contract, method, args, from) {
        try {
            const gas = await contract.methods[method](...args).estimateGas({ from });
            return Math.floor(gas * 1.5);
        } catch (error) {
            console.warn('Gas estimation failed, using fallback:', error);
            return 3000000;
        }
    }

    async function getChainId() {
        if (!web3) return null;
        try {
            return await web3.eth.getChainId();
        } catch (error) {
            console.error('Get chain ID error:', error);
            return null;
        }
    }

    async function getNetworkName() {
        const chainId = await getChainId();
        const networks = {
            1: '以太坊主网',
            5: 'Goerli测试网',
            56: 'BSC主网',
            97: 'BSC测试网'
        };
        return networks[chainId] || '未知网络';
    }

    window.ethereum?.on('accountsChanged', async (accounts) => {
        try {
            if (accounts.length > 0) {
                account = accounts[0];
                isConnected = true;
                contracts = {};
                emitEvent('accountChange', { account });
            } else {
                disconnectWallet();
            }
        } catch (error) {
            console.error('Accounts changed error:', error);
        }
    });

    window.ethereum?.on('chainChanged', (chainId) => {
        try {
            console.warn(`Chain changed to ${chainId}. Please refresh the page to continue.`);
            emitEvent('chainChange', { chainId });
        } catch (error) {
            console.error('Chain changed error:', error);
        }
    });

    function withErrorHandling(fn, context) {
        return async function(...args) {
            try {
                return await fn.apply(context || this, args);
            } catch (error) {
                console.error('ZODIAC_WEB3 Error:', error);
                const friendlyMessage = getErrorMessage(error);
                const wrappedError = new Error(friendlyMessage);
                wrappedError.originalError = error;
                wrappedError.code = error.code;
                throw wrappedError;
            }
        };
    }

    async function callContractMethod(contractName, methodName, args = [], options = {}) {
        try {
            const contract = await getContract(contractName);
            const method = contract.methods[methodName];
            
            if (typeof method !== 'function') {
                throw new Error(`Contract method not found: ${methodName}`);
            }

            const { send = false, from = account, value = 0, gas = null } = options;
            
            if (send) {
                const gasLimit = gas || await estimateGas(contract, methodName, args, from);
                const txOptions = { from };
                if (value > 0) txOptions.value = web3.utils.toWei(value.toString(), 'ether');
                if (gasLimit) txOptions.gas = gasLimit;
                
                return await method(...args).send(txOptions);
            } else {
                return await method(...args).call({ from });
            }
        } catch (error) {
            console.error(`Contract call error (${contractName}.${methodName}):`, error);
            const friendlyMessage = getErrorMessage(error);
            const wrappedError = new Error(friendlyMessage);
            wrappedError.originalError = error;
            wrappedError.contract = contractName;
            wrappedError.method = methodName;
            throw wrappedError;
        }
    }

    return {
        initWeb3: withErrorHandling(initWeb3),
        connectWallet: withErrorHandling(connectWallet),
        disconnectWallet: withErrorHandling(disconnectWallet),
        getAccount,
        isWalletConnected,
        getWeb3,
        getContract: withErrorHandling(getContract),
        getBalance: withErrorHandling(getBalance),
        getTokenBalance: withErrorHandling(getTokenBalance),
        approveToken: withErrorHandling(approveToken),
        checkApproval: withErrorHandling(checkApproval),
        checkApprovalForAll: withErrorHandling(checkApprovalForAll),
        approveForAll: withErrorHandling(approveForAll),
        estimateGas: withErrorHandling(estimateGas),
        getChainId: withErrorHandling(getChainId),
        getNetworkName: withErrorHandling(getNetworkName),
        callContractMethod: withErrorHandling(callContractMethod),
        on,
        off,
        clearListeners,
        emitEvent,
        withErrorHandling,
        getCache,
        setCache,
        clearCache,
        isCacheValid
    };
})();