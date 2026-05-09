// 十二生肖NFT项目统一UI工具函数
window.ZODIAC_UI = (function() {
    const WEB3_UTILS = window.ZODIAC_WEB3;

    function initWalletButton(btnId, addressId, statusId) {
        const btn = document.getElementById(btnId);
        const addressEl = document.getElementById(addressId);
        const statusEl = document.getElementById(statusId);

        async function updateWalletUI(account = null) {
            if (account) {
                const shortAddress = account.substring(0, 4) + '...' + account.substring(account.length - 4);
                if (addressEl) addressEl.textContent = shortAddress;
                if (btn) {
                    btn.textContent = shortAddress;
                    btn.disabled = true;
                    btn.style.background = 'linear-gradient(135deg, #4338ca 0%, #3730a3 100%)';
                }
                if (statusEl) {
                    statusEl.textContent = '钱包已连接';
                    statusEl.style.color = '#4CAF50';
                }
            } else {
                if (addressEl) addressEl.textContent = '未连接钱包';
                if (btn) {
                    btn.textContent = '连接钱包';
                    btn.disabled = false;
                    btn.style.background = '';
                }
                if (statusEl) {
                    statusEl.textContent = '请点击连接钱包';
                    statusEl.style.color = '#666';
                }
            }
        }

        async function handleConnect() {
            if (btn) btn.disabled = true;
            if (statusEl) {
                statusEl.textContent = '连接中...';
                statusEl.style.color = '#ff9800';
            }

            try {
                const result = await WEB3_UTILS.connectWallet();
                if (result.success) {
                    updateWalletUI(result.account);
                    emitEvent('walletConnected', { account: result.account });
                } else {
                    updateWalletUI(null);
                    showToast('连接失败: ' + result.error, 'error');
                }
            } catch (error) {
                updateWalletUI(null);
                showToast('连接失败: ' + error.message, 'error');
            }
        }

        if (btn) {
            btn.addEventListener('click', handleConnect);
        }

        WEB3_UTILS.on('connect', (data) => {
            updateWalletUI(data.account);
        });

        WEB3_UTILS.on('disconnect', () => {
            updateWalletUI(null);
        });

        WEB3_UTILS.on('accountChange', (data) => {
            updateWalletUI(data.account);
        });

        return { updateWalletUI, handleConnect };
    }

    function showToast(message, type = 'info', duration = 3000) {
        let toast = document.getElementById('zodiacToast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'zodiacToast';
            toast.className = 'fixed bottom-24 left-1/2 -translate-x-1/2 px-6 py-3 rounded-lg text-white font-medium z-50 opacity-0 transition-all duration-300 max-w-90% text-center';
            toast.style.cssText = `
                position: fixed;
                bottom: 120px;
                left: 50%;
                transform: translateX(-50%) translateY(10px);
                padding: 12px 24px;
                border-radius: 8px;
                color: white;
                font-weight: 500;
                z-index: 1001;
                opacity: 0;
                transition: all 0.3s ease;
                max-width: 90%;
                text-align: center;
            `;
            document.body.appendChild(toast);
        }

        const colors = {
            success: '#4CAF50',
            error: '#dc3545',
            warning: '#ff9800',
            info: '#4f46e5'
        };

        toast.textContent = message;
        toast.style.backgroundColor = colors[type] || colors.info;
        toast.style.opacity = '1';
        toast.style.transform = 'translateX(-50%) translateY(0)';

        setTimeout(() => {
            toast.style.opacity = '0';
            toast.style.transform = 'translateX(-50%) translateY(10px)';
        }, duration);
    }

    function showLoading(message = '处理中...') {
        let loading = document.getElementById('zodiacLoading');
        if (!loading) {
            loading = document.createElement('div');
            loading.id = 'zodiacLoading';
            loading.className = 'fixed inset-0 bg-black/50 flex flex-col items-center justify-center z-50';
            loading.style.display = 'none';
            loading.innerHTML = `
                <div class="w-12 h-12 border-4 border-white/20 border-t-white rounded-full animate-spin"></div>
                <div class="mt-4 text-white font-medium">${message}</div>
            `;
            document.body.appendChild(loading);
        }
        loading.style.display = 'flex';
    }

    function hideLoading() {
        const loading = document.getElementById('zodiacLoading');
        if (loading) {
            loading.style.display = 'none';
        }
    }

    function showConfirmModal(title, message, confirmText = '确认', cancelText = '取消') {
        return new Promise((resolve) => {
            let modal = document.getElementById('zodiacConfirmModal');
            if (!modal) {
                modal = document.createElement('div');
                modal.id = 'zodiacConfirmModal';
                modal.className = 'fixed inset-0 bg-black/50 flex items-center justify-center z-50';
                modal.style.display = 'none';
                modal.innerHTML = `
                    <div class="bg-white rounded-xl p-6 max-w-md w-full mx-4 shadow-xl">
                        <h3 class="text-xl font-bold text-gray-800 mb-3">${title}</h3>
                        <p class="text-gray-600 mb-6">${message}</p>
                        <div class="flex gap-4">
                            <button id="modalCancel" class="flex-1 bg-gray-200 text-gray-800 py-2 rounded-lg font-medium">${cancelText}</button>
                            <button id="modalConfirm" class="flex-1 bg-primary text-white py-2 rounded-lg font-medium">${confirmText}</button>
                        </div>
                    </div>
                `;
                document.body.appendChild(modal);

                document.getElementById('modalCancel').addEventListener('click', () => {
                    modal.style.display = 'none';
                    resolve(false);
                });

                document.getElementById('modalConfirm').addEventListener('click', () => {
                    modal.style.display = 'none';
                    resolve(true);
                });

                modal.addEventListener('click', (e) => {
                    if (e.target === modal) {
                        modal.style.display = 'none';
                        resolve(false);
                    }
                });
            }
            modal.style.display = 'flex';
        });
    }

    async function sendTransaction(txPromise, onSuccess, onError, loadingMessage = '处理中...') {
        showLoading(loadingMessage);
        try {
            const tx = await txPromise;
            hideLoading();
            showToast('操作成功！', 'success');
            if (onSuccess) onSuccess(tx);
            return tx;
        } catch (error) {
            hideLoading();
            let errorMsg = '操作失败';
            if (error.code === 4001) {
                errorMsg = '用户取消了操作';
            } else if (error.message && error.message.includes('insufficient funds')) {
                errorMsg = 'Gas费用不足，请确保钱包中有足够的BNB';
            } else if (error.message && error.message.includes('reverted')) {
                errorMsg = '合约执行失败: ' + (error.reason || error.message);
            } else if (error.message) {
                errorMsg = error.message;
            }
            showToast(errorMsg, 'error');
            if (onError) onError(error);
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

    const eventListeners = {};

    function on(eventName, callback) {
        if (!eventListeners[eventName]) {
            eventListeners[eventName] = [];
        }
        eventListeners[eventName].push(callback);
    }

    function emitEvent(eventName, data) {
        if (eventListeners[eventName]) {
            eventListeners[eventName].forEach(callback => callback(data));
        }
    }

    return {
        initWalletButton,
        showToast,
        showLoading,
        hideLoading,
        showConfirmModal,
        sendTransaction,
        estimateGas,
        on,
        emitEvent
    };
})();