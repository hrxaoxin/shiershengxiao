/**
 * ZODIAC_UI - 十二生肖 UI 工具
 * 提供 Toast 通知、Loading 遮罩、钱包按钮绑定、事件系统等 UI 功能
 */
window.ZODIAC_UI = (function() {
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

    function emitEvent(event, data) {
        if (!listeners[event]) return;
        listeners[event].forEach(cb => {
            try { cb(data); } catch (e) { console.error(`[ZODIAC_UI] Event handler error for "${event}":`, e); }
        });
    }

    // --- Toast ---
    let toastTimer = null;

    function showToast(message, type) {
        type = type || 'info';
        let toast = document.getElementById('zodiacToast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'zodiacToast';
            toast.className = 'toast';
            document.body.appendChild(toast);
        }

        toast.textContent = message;
        toast.className = `toast toast-${type} toast-active`;

        if (toastTimer) clearTimeout(toastTimer);
        toastTimer = setTimeout(function() {
            toast.classList.remove('toast-active');
        }, 3000);
    }

    // --- Loading ---
    let loadingOverlay = null;

    function getLoadingOverlay() {
        if (!loadingOverlay) {
            loadingOverlay = document.querySelector('.loading-overlay');
            if (!loadingOverlay) {
                loadingOverlay = document.createElement('div');
                loadingOverlay.className = 'loading-overlay';
                loadingOverlay.innerHTML = `
                    <div class="loading-content">
                        <div class="loading-spinner"></div>
                        <div class="loading-text">处理中...</div>
                    </div>
                `;
                document.body.appendChild(loadingOverlay);
            }
        }
        return loadingOverlay;
    }

    function showLoading(message) {
        const overlay = getLoadingOverlay();
        const textEl = overlay.querySelector('.loading-text');
        if (textEl && message) {
            textEl.textContent = message;
        }
        overlay.classList.add('loading-active');
        document.body.style.cursor = 'wait';
    }

    function hideLoading() {
        const overlay = getLoadingOverlay();
        overlay.classList.remove('loading-active');
        document.body.style.cursor = '';
    }

    // --- Wallet Button ---
    function initWalletButton(buttonId, addressDisplayId, statusDisplayId) {
        const btn = document.getElementById(buttonId);
        if (!btn) return;

        const web3Module = window.ZODIAC_WEB3;
        let isConnecting = false;

        function updateButtonState() {
            const connected = web3Module ? web3Module.isConnected() : false;
            const account = web3Module ? web3Module.getAccount() : null;

            if (connected && account) {
                btn.innerHTML = '<i class="fas fa-check-circle mr-1"></i> ' + account.substring(0, 6) + '...' + account.substring(38);
                btn.classList.add('connected');
            } else {
                btn.innerHTML = '<i class="fas fa-plug mr-1"></i> 连接';
                btn.classList.remove('connected');
            }

            if (addressDisplayId) {
                const addrEl = document.getElementById(addressDisplayId);
                if (addrEl) {
                    addrEl.textContent = connected && account ? account : '未连接钱包';
                }
            }
            if (statusDisplayId) {
                const statusEl = document.getElementById(statusDisplayId);
                if (statusEl) {
                    statusEl.textContent = connected ? '已连接' : '请点击连接钱包按钮';
                }
            }
        }

        btn.addEventListener('click', async function() {
            if (isConnecting) return;
            if (web3Module && web3Module.isConnected()) {
                // Already connected - do nothing
                return;
            }

            isConnecting = true;
            btn.disabled = true;
            btn.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> 连接中...';

            try {
                if (web3Module) {
                    await web3Module.initWeb3();
                }
                updateButtonState();
            } catch (error) {
                console.error('[ZODIAC_UI] Wallet connection failed:', error);
                showToast('连接失败: ' + (error.message || '未知错误'), 'error');
            } finally {
                isConnecting = false;
                btn.disabled = false;
                updateButtonState();
            }
        });

        // Subscribe to web3 events for auto-update
        if (web3Module) {
            web3Module.on('connect', updateButtonState);
            web3Module.on('disconnect', updateButtonState);
        }

        updateButtonState();
    }

    // --- Confirmation Dialog ---
    function showConfirmation(message, onConfirm) {
        if (confirm(message)) {
            if (typeof onConfirm === 'function') {
                onConfirm();
            }
        }
    }

    // --- Copy to Clipboard ---
    function copyToClipboard(text) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(function() {
                showToast('已复制到剪贴板', 'success');
            }).catch(function() {
                fallbackCopy(text);
            });
        } else {
            fallbackCopy(text);
        }
    }

    function fallbackCopy(text) {
        const textarea = document.createElement('textarea');
        textarea.value = text;
        textarea.style.position = 'fixed';
        textarea.style.opacity = '0';
        document.body.appendChild(textarea);
        textarea.select();
        try {
            document.execCommand('copy');
            showToast('已复制到剪贴板', 'success');
        } catch (e) {
            showToast('复制失败', 'error');
        }
        document.body.removeChild(textarea);
    }

    return {
        on,
        off,
        emitEvent,
        showToast,
        showLoading,
        hideLoading,
        initWalletButton,
        showConfirmation,
        copyToClipboard
    };
})();
