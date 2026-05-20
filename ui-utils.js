window.ZODIAC_UI = (function() {
    const eventListeners = {};

    const ERROR_CONFIG = {
        MAX_TOASTS: 5,
        TOAST_TIMEOUT: 5000,
        RETRY_DELAY: 3000,
        MAX_RETRIES: 3
    };

    const UI_ERROR_CODES = ZODIAC_CONFIG && ZODIAC_CONFIG.UI_ERROR_CODES || {
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

    const UI_ERROR_PATTERNS = [
        { pattern: /insufficient funds/i, msg: UI_ERROR_CODES.INSUFFICIENT_FUNDS },
        { pattern: /User rejected/i, msg: UI_ERROR_CODES.USER_REJECTED },
        { pattern: /Wallet not connected/i, msg: UI_ERROR_CODES.WALLET_NOT_CONNECTED },
        { pattern: /Web3 not initialized/i, msg: UI_ERROR_CODES.WEB3_NOT_INITIALIZED },
        { pattern: /invalid address/i, msg: UI_ERROR_CODES.INVALID_ADDRESS },
        { pattern: /Network error/i, msg: UI_ERROR_CODES.NETWORK_ERROR },
        { pattern: /timeout/i, msg: UI_ERROR_CODES.TIMEOUT },
        { pattern: /reverted/i, msg: '交易执行失败，合约调用被拒绝' },
        { pattern: /out of gas/i, msg: 'Gas不足，交易失败' }
    ];

    let toastQueue = [];
    let isShowingToast = false;

    function showNextToast() {
        if (isShowingToast || toastQueue.length === 0) return;
        
        isShowingToast = true;
        const { message, type, duration } = toastQueue.shift();
        const actualDuration = duration || ERROR_CONFIG.TOAST_TIMEOUT;
        
        let toast = document.getElementById('toastNotification');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'toastNotification';
            toast.className = 'toast';
            document.body.appendChild(toast);
        }
        
        toast.textContent = message;
        toast.className = `toast toast-${type} toast-active`;
        
        setTimeout(() => {
            toast.classList.remove('toast-active');
            isShowingToast = false;
            setTimeout(showNextToast, 300);
        }, actualDuration);
    }

    function queueToast(message, type = 'info', duration = ERROR_CONFIG.TOAST_TIMEOUT) {
        if (toastQueue.length >= ERROR_CONFIG.MAX_TOASTS) {
            toastQueue.shift();
        }
        toastQueue.push({ message, type, duration });
        showNextToast();
    }

    function emitEvent(eventName, data) {
        if (!eventListeners[eventName]) return;
        eventListeners[eventName].forEach(callback => {
            try {
                callback(data);
            } catch (error) {
                console.error('UI Event listener error:', error);
            }
        });
    }

    function on(eventName, callback) {
        if (!eventListeners[eventName]) {
            eventListeners[eventName] = [];
        }
        eventListeners[eventName].push(callback);
    }

    function showToast(message, type = 'info', duration = 3000) {
        queueToast(message, type, duration);
    }

    function handleError(error, context = '') {
        console.error(`Error in ${context}:`, error);

        let message;
        if (ZODIAC_CONFIG && typeof ZODIAC_CONFIG.getErrorMessage === 'function') {
            message = ZODIAC_CONFIG.getErrorMessage(error);
        } else if (error.code && UI_ERROR_CODES[error.code]) {
            message = UI_ERROR_CODES[error.code];
        } else if (error.message) {
            const patternMatch = UI_ERROR_PATTERNS.find(({ pattern }) => pattern.test(error.message));
            if (patternMatch) {
                message = patternMatch.msg;
            } else {
                message = error.message || error.error || '操作失败';
            }
        } else {
            message = error.message || error.error || '操作失败';
        }

        showToast(message, 'error');
        emitEvent('error', { error, context, userMessage: message });
    }

    async function withRetry(fn, options = {}) {
        const { maxRetries = ERROR_CONFIG.MAX_RETRIES, delay = ERROR_CONFIG.RETRY_DELAY, context = '' } = options;
        
        let attempts = 0;
        let lastError = null;
        
        while (attempts < maxRetries) {
            try {
                return await fn();
            } catch (error) {
                lastError = error;
                attempts++;
                
                if (attempts < maxRetries) {
                    showToast(`操作失败，正在重试 (${attempts}/${maxRetries})...`, 'warning');
                    await new Promise(resolve => setTimeout(resolve, delay * attempts));
                }
            }
        }
        
        handleError(lastError, context);
        throw lastError;
    }

    function showLoading(message = '处理中...', subText = '') {
        let loadingOverlay = document.getElementById('loadingOverlay');
        if (!loadingOverlay) {
            loadingOverlay = document.createElement('div');
            loadingOverlay.id = 'loadingOverlay';
            loadingOverlay.className = 'loading-overlay';
            loadingOverlay.innerHTML = `
                <div class="loading-container">
                    <div class="loading-spinner"></div>
                    <div class="loading-text">${message}</div>
                    <div class="loading-subtext" style="${subText ? '' : 'display: none;'}">${subText}</div>
                    <div class="loading-progress">
                        <div class="loading-progress-bar"></div>
                    </div>
                </div>
            `;
            document.body.appendChild(loadingOverlay);
        } else {
            const textEl = loadingOverlay.querySelector('.loading-text');
            const subTextEl = loadingOverlay.querySelector('.loading-subtext');
            if (textEl) textEl.textContent = message;
            if (subTextEl) {
                subTextEl.textContent = subText;
                subTextEl.style.display = subText ? '' : 'none';
            }
        }
        loadingOverlay.classList.add('loading-active');
    }

    function hideLoading() {
        const loadingOverlay = document.getElementById('loadingOverlay');
        if (loadingOverlay) {
            loadingOverlay.classList.remove('loading-active');
        }
    }

    function showConfirmModal(title, message, confirmText = '确定', cancelText = '取消') {
        return new Promise((resolve) => {
            let modal = document.getElementById('confirmModal');
            if (!modal) {
                modal = document.createElement('div');
                modal.id = 'confirmModal';
                modal.className = 'modal-overlay';
                modal.innerHTML = `
                    <div class="modal-content">
                        <div class="modal-header">
                            <h3 class="modal-title"></h3>
                            <button class="modal-close">×</button>
                        </div>
                        <div class="modal-body">
                            <p class="modal-message"></p>
                        </div>
                        <div class="modal-footer">
                            <button class="btn-cancel">${cancelText}</button>
                            <button class="btn-confirm">${confirmText}</button>
                        </div>
                    </div>
                `;
                document.body.appendChild(modal);
            }

            modal.querySelector('.modal-title').textContent = title;
            modal.querySelector('.modal-message').textContent = message;
            modal.classList.add('modal-active');
            
            const confirmBtn = modal.querySelector('.btn-confirm');
            const cancelBtn = modal.querySelector('.btn-cancel');
            const closeBtn = modal.querySelector('.modal-close');
            
            const handleConfirm = () => {
                resolve(true);
                cleanup();
            };
            
            const handleCancel = () => {
                resolve(false);
                cleanup();
            };
            
            const cleanup = () => {
                modal.classList.remove('modal-active');
                confirmBtn.removeEventListener('click', handleConfirm);
                cancelBtn.removeEventListener('click', handleCancel);
                closeBtn.removeEventListener('click', handleCancel);
            };
            
            confirmBtn.addEventListener('click', handleConfirm);
            cancelBtn.addEventListener('click', handleCancel);
            closeBtn.addEventListener('click', handleCancel);
        });
    }

    function hideConfirmModal(result) {
        const modal = document.getElementById('confirmModal');
        if (modal) {
            modal.classList.remove('modal-active');
        }
        if (typeof result === 'boolean') {
            emitEvent('confirmModalClosed', { result });
        }
    }

    const transactionHistory = [];

    async function sendTransaction(txPromise, options = {}) {
        const account = window.ZODIAC_WEB3 ? window.ZODIAC_WEB3.getAccount() : null;
        const { 
            successMessage = '交易成功', 
            errorMessage = '交易失败',
            onSuccess = null,
            onError = null,
            rollbackActions = [],
            confirmMessage = null
        } = options;

        if (confirmMessage) {
            const confirmed = await showConfirmModal('确认交易', confirmMessage);
            if (!confirmed) {
                return { success: false, error: '用户取消交易' };
            }
        }

        if (!txPromise || typeof txPromise.then !== 'function') {
            showToast('无效的交易Promise', 'error');
            console.error('Invalid txPromise:', txPromise);
            return { success: false, error: '无效的交易Promise' };
        }

        showLoading();
        
        const startTime = Date.now();
        const transactionId = `tx_${startTime}_${Math.random().toString(36).substr(2, 9)}`;
        
        try {
            const result = await txPromise;
            const txHash = result.transactionHash || result.hash;
            
            transactionHistory.push({
                id: transactionId,
                txHash,
                status: 'success',
                timestamp: startTime,
                duration: Date.now() - startTime
            });
            
            hideLoading();
            showToast(successMessage, 'success');
            
            if (typeof onSuccess === 'function') {
                try {
                    onSuccess(result);
                } catch (callbackError) {
                    console.error('onSuccess callback error:', callbackError);
                }
            }
            
            return { success: true, result, txHash, transactionId };
            
        } catch (error) {
            const errorMsg = error.message || error.error || errorMessage;
            
            transactionHistory.push({
                id: transactionId,
                status: 'failed',
                timestamp: startTime,
                duration: Date.now() - startTime,
                error: errorMsg
            });
            
            hideLoading();
            showToast(errorMsg, 'error');
            console.error('Transaction error:', error);
            
            for (const action of rollbackActions) {
                try {
                    await action();
                    console.log('Rollback action executed:', action.name || 'anonymous');
                } catch (rollbackError) {
                    console.error('Rollback action failed:', rollbackError);
                    showToast('回滚操作失败，请手动检查状态', 'warning');
                }
            }
            
            if (typeof onError === 'function') {
                try {
                    onError(error);
                } catch (callbackError) {
                    console.error('onError callback error:', callbackError);
                }
            }
            
            return { success: false, error: errorMsg, transactionId };
        }
    }

    function getTransactionHistory() {
        return [...transactionHistory];
    }

    function clearTransactionHistory() {
        transactionHistory.length = 0;
    }

    async function initWalletButton(btnId, addrId, statusId) {
        const btn = document.getElementById(btnId);
        const addrEl = document.getElementById(addrId);
        const statusEl = document.getElementById(statusId);

        if (!btn) {
            console.warn(`Wallet button with id "${btnId}" not found`);
            return;
        }

        const updateUI = (isConnected, account) => {
            if (isConnected && account) {
                btn.innerHTML = '<i class="fas fa-check mr-1"></i> 已连接';
                btn.classList.add('btn-connected');
                btn.classList.remove('btn-primary');
                if (addrEl) {
                    addrEl.textContent = ZODIAC_UTILS.formatAddress(account);
                }
                if (statusEl) {
                    statusEl.textContent = '钱包已连接';
                }
            } else {
                btn.innerHTML = '<i class="fas fa-plug mr-1"></i> 连接钱包';
                btn.classList.remove('btn-connected');
                btn.classList.add('btn-primary');
                if (addrEl) {
                    addrEl.textContent = '未连接钱包';
                }
                if (statusEl) {
                    statusEl.textContent = '请点击连接钱包';
                }
            }
        };

        btn.addEventListener('click', async () => {
            if (ZODIAC_WEB3.isWalletConnected()) {
                ZODIAC_WEB3.disconnectWallet();
            } else {
                const result = await ZODIAC_WEB3.connectWallet();
                if (!result.success) {
                    showToast(result.error || '连接失败', 'error');
                }
            }
        });

        ZODIAC_WEB3.on('connect', ({ account }) => {
            updateUI(true, account);
        });

        ZODIAC_WEB3.on('disconnect', () => {
            updateUI(false, null);
        });

        ZODIAC_WEB3.on('accountChange', ({ account }) => {
            updateUI(true, account);
        });

        updateUI(ZODIAC_WEB3.isWalletConnected(), ZODIAC_WEB3.getAccount());
    }

    function initRefreshButton(btnId, refreshFn) {
        const btn = document.getElementById(btnId);
        if (btn) {
            btn.addEventListener('click', async () => {
                try {
                    await refreshFn();
                } catch (error) {
                    showToast('刷新失败', 'error');
                    console.error('Refresh error:', error);
                }
            });
        }
    }

    function initNavigation(activePage) {
        ZODIAC_COMPONENTS.initNavigation(activePage);
    }

    function renderNavigation(activePage) {
        const mobileNavbar = ZODIAC_COMPONENTS.renderMobileNavbar(activePage);
        const mobileMenu = ZODIAC_COMPONENTS.renderMobileMenu();
        const desktopSidebar = ZODIAC_COMPONENTS.renderDesktopSidebar(activePage);
        
        return {
            mobileNavbar,
            mobileMenu,
            desktopSidebar
        };
    }

    function renderWalletInfo() {
        return ZODIAC_COMPONENTS.renderWalletInfo();
    }

    function renderFooter() {
        return ZODIAC_COMPONENTS.renderFooter();
    }

    function formatCurrency(value, decimals = 4) {
        if (!value) return '0';
        return parseFloat(value).toFixed(decimals);
    }

    function isValidAddress(address) {
        if (!address) return false;
        return /^0x[a-fA-F0-9]{40}$/.test(address);
    }

    async function withErrorHandling(fn, context = '') {
        try {
            return await fn();
        } catch (error) {
            handleError(error, context);
            throw error;
        }
    }

    return {
        showToast,
        showLoading,
        hideLoading,
        showConfirmModal,
        hideConfirmModal,
        sendTransaction,
        getTransactionHistory,
        clearTransactionHistory,
        initWalletButton,
        initRefreshButton,
        initNavigation,
        renderNavigation,
        renderWalletInfo,
        renderFooter,
        formatCurrency,
        isValidAddress,
        handleError,
        withErrorHandling,
        withRetry,
        ERROR_CODES: UI_ERROR_CODES,
        on,
        emitEvent
    };
})();