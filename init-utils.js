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

            // 初始化全局错误处理
            if (window.ZODIAC_UI && window.ZODIAC_UI.initGlobalErrorHandler) {
                window.ZODIAC_UI.initGlobalErrorHandler();
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

            // 初始化NFT悬停提示
            if (window.ZODIAC_UI && window.ZODIAC_UI.initNFTTooltips) {
                window.ZODIAC_UI.initNFTTooltips();
                
                // 监听DOM变化，动态初始化新添加的NFT元素
                const observer = new MutationObserver(() => {
                    if (window.ZODIAC_UI && window.ZODIAC_UI.initNFTTooltips) {
                        window.ZODIAC_UI.initNFTTooltips();
                    }
                });
                observer.observe(document.body, { childList: true, subtree: true });
            }

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