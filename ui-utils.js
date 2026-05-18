window.ZODIAC_UI = (function() {
    const eventListeners = {};

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
        }, duration);
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
                            <button class="modal-close" onclick="ZODIAC_UI.hideConfirmModal()">×</button>
                        </div>
                        <div class="modal-body">
                            <p class="modal-message"></p>
                        </div>
                        <div class="modal-footer">
                            <button class="btn-cancel" onclick="ZODIAC_UI.hideConfirmModal(false)">${cancelText}</button>
                            <button class="btn-confirm" onclick="ZODIAC_UI.hideConfirmModal(true)">${confirmText}</button>
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
            };
            
            confirmBtn.addEventListener('click', handleConfirm);
            cancelBtn.addEventListener('click', handleCancel);
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

    function handleError(error, context = '') {
        console.error(`Error in ${context}:`, error);
        const message = error.message || error.error || '操作失败';
        showToast(message, 'error');
        emitEvent('error', { error, context });
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
        on,
        emitEvent
    };
})();