window.ZODIAC_WEB3 = (function() {
    let web3;
    let account = null;
    let isConnected = false;
    let contracts = {};
    
    const eventListeners = {
        'connect': [],
        'disconnect': [],
        'accountChange': [],
        'chainChange': []
    };

    function emitEvent(eventName, data) {
        eventListeners[eventName].forEach(callback => callback(data));
    }

    function on(eventName, callback) {
        if (eventListeners[eventName]) {
            eventListeners[eventName].push(callback);
        }
    }

    async function initWeb3() {
        if (typeof window.ethereum !== 'undefined') {
            web3 = new Web3(window.ethereum);
            try {
                const accounts = await window.ethereum.request({ method: 'eth_accounts' });
                if (accounts.length > 0) {
                    account = accounts[0];
                    isConnected = true;
                    emitEvent('connect', { account });
                }
            } catch (error) {
                console.error('Web3 initialization error:', error);
            }
        } else {
            console.error('MetaMask not detected');
        }
        return isConnected;
    }

    async function connectWallet() {
        if (!web3) {
            await initWeb3();
        }
        try {
            const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
            if (accounts.length > 0) {
                account = accounts[0];
                isConnected = true;
                emitEvent('connect', { account });
                return { success: true, account };
            }
        } catch (error) {
            console.error('Wallet connection error:', error);
            return { success: false, error: error.message };
        }
        return { success: false, error: 'No accounts found' };
    }

    async function disconnectWallet() {
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
        return new web3.eth.Contract(abi, address);
    }

    async function getContract(contractName) {
        if (!isConnected) {
            throw new Error('Wallet not connected');
        }
        
        if (contracts[contractName]) {
            return contracts[contractName];
        }

        const abis = {
            tokenContract: window.tokenABI,
            rewardManager: window.rewardManagerABI,
            tokenBurner: window.tokenBurnerABI,
            nftMint: window.nftMintABI,
            nftUpdate: window.nftUpdateABI,
            nftTrading: window.NFTTradingABI,
            breeding: window.breedingABI,
            staking: window.stakingABI,
            tokenStaking: window.tokenStakingABI
        };

        const addresses = {
            tokenContract: window.tokenContractAddress,
            rewardManager: window.rewardManagerAddress,
            tokenBurner: window.tokenBurnerAddress,
            nftMint: window.nftMintAddress,
            nftUpdate: window.nftUpdateAddress,
            nftTrading: window.NFTTradingAddress,
            breeding: window.breedingAddress,
            staking: window.stakingAddress,
            tokenStaking: window.contractAddresses.tokenStaking
        };

        if (!abis[contractName]) {
            throw new Error(`Unknown contract: ${contractName}`);
        }

        if (!addresses[contractName] || addresses[contractName] === '0x0000000000000000000000000000000000000000') {
            throw new Error(`Contract ${contractName} address not configured`);
        }

        contracts[contractName] = createContract(abis[contractName], addresses[contractName]);
        return contracts[contractName];
    }

    async function getBalance() {
        if (!isConnected || !account) return '0';
        const balance = await web3.eth.getBalance(account);
        return web3.utils.fromWei(balance, 'ether');
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
        const tokenContract = await getContract('tokenContract');
        const tx = await tokenContract.methods.approve(spender, amount).send({ from: account });
        return tx;
    }

    async function checkApproval(spender, amount) {
        if (!isConnected || !account) return false;
        const tokenContract = await getContract('tokenContract');
        const allowance = await tokenContract.methods.allowance(account, spender).call();
        return parseInt(allowance) >= parseInt(amount);
    }

    window.ethereum?.on('accountsChanged', async (accounts) => {
        if (accounts.length > 0) {
            account = accounts[0];
            isConnected = true;
            contracts = {};
            emitEvent('accountChange', { account });
        } else {
            disconnectWallet();
        }
    });

    window.ethereum?.on('chainChanged', (chainId) => {
        console.warn(`Chain changed to ${chainId}. Please refresh the page to continue.`);
        emitEvent('chainChange', { chainId });
    });

    return {
        initWeb3,
        connectWallet,
        disconnectWallet,
        getAccount,
        isWalletConnected,
        getWeb3,
        getContract,
        getBalance,
        getTokenBalance,
        approveToken,
        checkApproval,
        on
    };
})();