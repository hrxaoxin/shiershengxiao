window.ZODIAC_INIT = (function() {
    let initialized = false;
    let eventUnsubscribe = null;

    async function initApp(options = {}) {
        if (initialized) {
            console.log('App already initialized');
            return;
        }

        const { 
            onConnect, 
            onAccountsChanged, 
            onChainChanged, 
            autoConnect = true 
        } = options;

        try {
            if (autoConnect) {
                await window.ZODIAC_WEB3.initWeb3();
            }

            window.ZODIAC_WEB3.on('connect', async (data) => {
                console.log('Wallet connected:', data);
                await ZODIAC_STATE.updateFromWeb3(data.account, data.chainId);
                
                if (onConnect) {
                    try {
                        await onConnect(data);
                    } catch (error) {
                        console.error('onConnect callback error:', error);
                    }
                }
            });

            window.ZODIAC_WEB3.on('accountsChanged', (data) => {
                console.log('Accounts changed:', data);
                ZODIAC_STATE.updateFromWeb3(data.account, null);
                
                if (onAccountsChanged) {
                    try {
                        onAccountsChanged(data);
                    } catch (error) {
                        console.error('onAccountsChanged callback error:', error);
                    }
                }
            });

            window.ZODIAC_WEB3.on('chainChanged', (data) => {
                console.log('Chain changed:', data);
                ZODIAC_STATE.set('chainId', data.chainId);
                
                if (onChainChanged) {
                    try {
                        onChainChanged(data);
                    } catch (error) {
                        console.error('onChainChanged callback error:', error);
                    }
                }
            });

            eventUnsubscribe = await window.ZODIAC_WEB3.listenToAllEvents({
                onNFTTransfer: handleNFTTransfer,
                onTokenTransfer: handleTokenTransfer,
                onStaked: handleStaked,
                onUnstaked: handleUnstaked,
                onBattleEnded: handleBattleEnded,
                onChallengeResult: handleChallengeResult
            });

            initialized = true;
            console.log('App initialization completed');

        } catch (error) {
            console.error('App initialization failed:', error);
            throw error;
        }
    }

    function handleNFTTransfer(event) {
        console.log('NFT Transfer:', event);
        ZODIAC_STATE.emit('nftTransfer', event);
    }

    function handleTokenTransfer(event) {
        console.log('Token Transfer:', event);
        ZODIAC_STATE.emit('tokenTransfer', event);
    }

    function handleStaked(event) {
        console.log('Staked:', event);
        ZODIAC_STATE.emit('staked', event);
    }

    function handleUnstaked(event) {
        console.log('Unstaked:', event);
        ZODIAC_STATE.emit('unstaked', event);
    }

    function handleBattleEnded(event) {
        console.log('Battle Ended:', event);
        ZODIAC_STATE.emit('battleEnded', event);
    }

    function handleChallengeResult(event) {
        console.log('Challenge Result:', event);
        ZODIAC_STATE.emit('challengeResult', event);
    }

    function cleanup() {
        if (eventUnsubscribe) {
            eventUnsubscribe();
            eventUnsubscribe = null;
        }
        initialized = false;
    }

    function getAccount() {
        return ZODIAC_STATE.get('account');
    }

    function isConnected() {
        return ZODIAC_STATE.get('isConnected');
    }

    return {
        initApp,
        cleanup,
        getAccount,
        isConnected
    };
})();