/**
 * ZODIAC_UI - 十二生肖 UI 工具
 * 提供 Toast 通知、Loading 遮罩、钱包按钮绑定、事件系统等 UI 功能
 */
window.ZODIAC_UI = (function() {
    // --- Utility: extract error message from various error formats ---
    function extractErrorMessage(error) {
        if (!error) return '未知错误';
        if (typeof error === 'string') return error;
        
        if (error.message) {
            const revertMatch = error.message.match(/revert(ed)?:\s*(.*)/i);
            if (revertMatch && revertMatch[2]) return revertMatch[2].trim();
            
            const reasonMatch = error.message.match(/reason=['"`]([^'"`]+)['"`]/i);
            if (reasonMatch && reasonMatch[1]) return reasonMatch[1];
            
            if (error.message.includes('\"message\":')) {
                try {
                    const jsonMatch = error.message.match(/\{[\s\S]*"message"[:\s]*"([^"]+)"[\s\S]*\}/);
                    if (jsonMatch && jsonMatch[1]) return jsonMatch[1];
                } catch (e) {}
            }
            return error.message;
        }
        if (error.reason) return String(error.reason);
        if (error.data && error.data.message) return String(error.data.message);
        return '未知错误';
    }

    // --- Global Error Handling ---
    let isGlobalErrorHandlerInitialized = false;

    function initGlobalErrorHandler() {
        if (isGlobalErrorHandlerInitialized) return;
        isGlobalErrorHandlerInitialized = true;

        window.onerror = function(message, source, lineno, colno, error) {
            console.error('[ZODIAC_UI] Global error caught:', {
                message,
                source,
                lineno,
                colno,
                error
            });
            
            if (error && error.message) {
                if (error.message.includes('cancelled') || error.message.includes('User rejected')) {
                    showToast('用户取消了操作', 'info');
                } else {
                    const msg = extractErrorMessage(error);
                    showToast('发生错误: ' + (msg.length > 200 ? msg.substring(0, 200) + '...' : msg), 'error');
                }
            } else {
                showToast('发生未知错误', 'error');
            }
            
            return true;
        };

        window.addEventListener('unhandledrejection', function(event) {
            console.error('[ZODIAC_UI] Unhandled promise rejection:', event.reason);
            
            if (event.reason && event.reason.message) {
                if (event.reason.message.includes('cancelled') || event.reason.message.includes('User rejected')) {
                    showToast('用户取消了操作', 'info');
                } else {
                    const msg = extractErrorMessage(event.reason);
                    showToast('发生错误: ' + (msg.length > 200 ? msg.substring(0, 200) + '...' : msg), 'error');
                }
            } else if (event.reason && typeof event.reason === 'string') {
                const msg = event.reason;
                showToast('发生错误: ' + (msg.length > 200 ? msg.substring(0, 200) + '...' : msg), 'error');
            } else {
                showToast('发生未知错误', 'error');
            }
            
            event.preventDefault();
        });
    }

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

    function showToast(message, type, duration) {
        type = type || 'info';
        duration = duration || 3000;
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
        }, duration);
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

    function showConfirmModal(title, message, options) {
        return new Promise(function(resolve) {
            const confirmText = (options && options.confirmText) || '确认';
            const cancelText = (options && options.cancelText) || '取消';
            
            let modal = document.getElementById('zodiacConfirmModal');
            if (!modal) {
                modal = document.createElement('div');
                modal.id = 'zodiacConfirmModal';
                modal.className = 'fixed inset-0 bg-black/60 flex items-center justify-center z-50';
                modal.innerHTML = `
                    <div class="bg-white rounded-xl p-6 max-w-md w-full mx-4 shadow-xl">
                        <h3 id="zodiacModalTitle" class="text-xl font-bold text-gray-800 mb-4"></h3>
                        <p id="zodiacModalMessage" class="text-gray-600 mb-6 whitespace-pre-line"></p>
                        <div class="flex space-x-3">
                            <button id="confirmCancelBtn" class="flex-1 px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-colors">
                                取消
                            </button>
                            <button id="confirmOkBtn" class="flex-1 px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 transition-colors">
                                确认
                            </button>
                        </div>
                    </div>
                `;
                document.body.appendChild(modal);
            }

            const titleEl = modal.querySelector('#zodiacModalTitle');
            const messageEl = modal.querySelector('#zodiacModalMessage');
            const cancelBtn = modal.querySelector('#confirmCancelBtn');
            const okBtn = modal.querySelector('#confirmOkBtn');

            titleEl.textContent = title;
            messageEl.textContent = message;
            cancelBtn.textContent = cancelText;
            okBtn.textContent = confirmText;

            const handleCancel = function() {
                modal.style.display = 'none';
                cancelBtn.removeEventListener('click', handleCancel);
                okBtn.removeEventListener('click', handleOk);
                resolve(false);
            };

            const handleOk = function() {
                modal.style.display = 'none';
                cancelBtn.removeEventListener('click', handleCancel);
                okBtn.removeEventListener('click', handleOk);
                resolve(true);
            };

            cancelBtn.addEventListener('click', handleCancel);
            okBtn.addEventListener('click', handleOk);
            modal.style.display = 'flex';
        });
    }

    function handleContractError(error, actionName) {
        let errorMsg = actionName + '失败';
        if (error.code === 4001) {
            errorMsg = '用户取消了操作';
        } else if (error.message || error.reason) {
            const extracted = extractErrorMessage(error);
            const msg = extracted.toLowerCase();
            if (msg.includes('insufficient funds')) {
                errorMsg = '余额不足';
            } else if (msg.includes('reverted')) {
                // 从reverted错误中抽取更精确的原因
                const detail = extractErrorMessage(error);
                errorMsg = detail !== error.message ? detail : '合约执行失败';
            } else if (msg.includes('gas')) {
                errorMsg = 'Gas不足或Gas价格过低';
            } else if (msg.includes('user denied')) {
                errorMsg = '用户拒绝了操作';
            } else if (msg.includes('transaction underpriced')) {
                errorMsg = 'Gas价格过低，请重试';
            } else if (msg.includes('nonce')) {
                errorMsg = '交易Nonce错误，请稍后重试';
            } else {
                errorMsg += ': ' + (extracted.length > 300 ? extracted.substring(0, 300) + '...' : extracted);
            }
        }
        showToast(errorMsg, 'error');
    }

    function handleError(error, actionName) {
        handleContractError(error, actionName);
    }

    async function handleTransaction(transactionFactory, options) {
        const {
            actionName = '交易',
            loadingMessage = '处理中...',
            successMessage = '操作成功',
            showConfirmation = false,
            confirmationMessage = '确定要执行此操作吗？',
            onConfirmation = null,
            onError = null
        } = options || {};

        if (showConfirmation) {
            const confirm = await showConfirmModal(actionName, confirmationMessage);
            if (!confirm) {
                return;
            }
        }

        showLoading(loadingMessage);

        try {
            const transactionPromise = typeof transactionFactory === 'function' 
                ? transactionFactory() 
                : transactionFactory;
            const result = await transactionPromise;
            hideLoading();
            showToast(successMessage, 'success');
            
            if (typeof onConfirmation === 'function') {
                onConfirmation(result);
            }
            
            return result;
        } catch (error) {
            hideLoading();
            console.error(`[ZODIAC_UI] ${actionName}失败:`, error);
            
            if (typeof onError === 'function') {
                onError(error);
            } else {
                handleContractError(error, actionName);
            }
            
            throw error;
        }
    }

    // --- NFT Tooltip ---
    let nftTooltip = null;

    function initNFTTooltips() {
        const nftElements = document.querySelectorAll('[data-nft-typeid], [data-nft-tokenid]');
        nftElements.forEach(element => {
            element.addEventListener('mouseenter', showNFTTooltip);
            element.addEventListener('mouseleave', hideNFTTooltip);
        });
    }

    async function showNFTTooltip(event) {
        const element = event.currentTarget;
        const typeId = element.getAttribute('data-nft-typeid');
        const tokenId = element.getAttribute('data-nft-tokenid');
        const level = element.getAttribute('data-nft-level') || 1;
        const growth = element.getAttribute('data-nft-growth') || Math.floor(Math.random() * 91) + 10;

        if (!typeId) return;

        const nftInfo = window.ZODIAC_UTILS.getNFTInfo(typeId);
        
        if (!nftTooltip) {
            nftTooltip = document.createElement('div');
            nftTooltip.id = 'nftTooltip';
            nftTooltip.className = 'nft-tooltip';
            document.body.appendChild(nftTooltip);
        }

        const skills = getSkillsForNFT(nftInfo.elementKey, nftInfo.zodiac);

        const attack = calculateAttack(parseInt(level), parseInt(growth));
        const defense = calculateDefense(parseInt(level), parseInt(growth));
        const speed = calculateSpeed(parseInt(level), parseInt(growth), nftInfo.zodiac);
        const hp = calculateMaxHP(parseInt(level), parseInt(growth));
        const weight = await getWeight(level, nftInfo.isRare);

        nftTooltip.innerHTML = `
            <div class="nft-tooltip-content">
                <div class="nft-tooltip-header">
                    <img src="${nftInfo.imagePath}" alt="${nftInfo.name}" class="nft-tooltip-image" />
                    <div class="nft-tooltip-info">
                        <h4 class="nft-tooltip-name">${nftInfo.name}</h4>
                        <p class="nft-tooltip-type">${nftInfo.attrName}属性 · ${nftInfo.animalName} · ${nftInfo.genderName}</p>
                        ${tokenId ? `<p class="nft-tooltip-tokenid">Token ID: ${tokenId}</p>` : ''}
                    </div>
                </div>
                <div class="nft-tooltip-stats">
                    <div class="nft-stat">
                        <span class="stat-label">等级</span>
                        <span class="stat-value">${level}阶 ${'⭐'.repeat(Math.min(parseInt(level), 5))}</span>
                    </div>
                    <div class="nft-stat">
                        <span class="stat-label">成长值</span>
                        <span class="stat-value">${growth}</span>
                    </div>
                    <div class="nft-stat">
                        <span class="stat-label">权重</span>
                        <span class="stat-value">${weight}</span>
                    </div>
                </div>
                <div class="nft-tooltip-attributes">
                    <h5 class="attributes-title">属性</h5>
                    <div class="attribute-grid">
                        <div class="attribute-item">
                            <span class="attribute-icon">⚔️</span>
                            <span class="attribute-label">攻击</span>
                            <span class="attribute-value">${attack}</span>
                        </div>
                        <div class="attribute-item">
                            <span class="attribute-icon">🛡️</span>
                            <span class="attribute-label">防御</span>
                            <span class="attribute-value">${defense}</span>
                        </div>
                        <div class="attribute-item">
                            <span class="attribute-icon">💨</span>
                            <span class="attribute-label">速度</span>
                            <span class="attribute-value">${speed}</span>
                        </div>
                        <div class="attribute-item">
                            <span class="attribute-icon">❤️</span>
                            <span class="attribute-label">生命</span>
                            <span class="attribute-value">${hp}</span>
                        </div>
                    </div>
                </div>
                <div class="nft-tooltip-skills">
                    <h5 class="skills-title">技能</h5>
                    ${skills.map(skill => `
                        <div class="skill-item">
                            <span class="skill-name">${skill.name}</span>
                            <p class="skill-desc">${skill.description}</p>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;

        nftTooltip.style.display = 'block';
        updateTooltipPosition(event);
    }

    function hideNFTTooltip() {
        if (nftTooltip) {
            nftTooltip.style.display = 'none';
        }
    }

    function updateTooltipPosition(event) {
        if (!nftTooltip) return;
        
        const rect = event.currentTarget.getBoundingClientRect();
        let left = rect.left + rect.width / 2 - nftTooltip.offsetWidth / 2;
        let top = rect.top - nftTooltip.offsetHeight - 10;

        if (left < 10) left = 10;
        if (left + nftTooltip.offsetWidth > window.innerWidth - 10) {
            left = window.innerWidth - nftTooltip.offsetWidth - 10;
        }
        if (top < 10) {
            top = rect.bottom + 10;
        }

        nftTooltip.style.left = left + 'px';
        nftTooltip.style.top = top + 'px';
    }

    async function getWeight(level, isRare) {
        // 尝试从合约读取
        try {
            const web3Module = window.ZODIAC_WEB3;
            if (!web3Module || !web3Module.isConnected()) {
                console.debug('ZODIAC_WEB3 not initialized or not connected, using fallback weight');
                return getFallbackWeight(level, isRare);
            }
            
            const contract = await web3Module.getContract('dividendManager');
            if (contract) {
                const weight = await contract.methods.getNFTWeight(level, isRare).call();
                return parseInt(weight);
            }
        } catch (e) {
            console.warn('Failed to get weight from contract, using fallback:', e);
        }
        
        return getFallbackWeight(level, isRare);
    }
    
    function getFallbackWeight(level, isRare) {
        const weights = {
            1: isRare ? 10 : 1,
            2: isRare ? 12 : 2,
            3: isRare ? 16 : 6,
            4: isRare ? 28 : 18,
            5: isRare ? 76 : 66
        };
        return weights[parseInt(level)] || (isRare ? 10 : 1);
    }

    function getSkillsForNFT(element, zodiac) {
        const skills = {
            water: {
                default: [
                    { name: '水之守护', description: '提升防御力，减少受到的伤害' },
                    { name: '治愈之泉', description: '恢复自身生命值' }
                ]
            },
            wind: {
                default: [
                    { name: '疾风斩', description: '快速攻击，造成连续伤害' },
                    { name: '风之迅捷', description: '提升行动速度' }
                ]
            },
            fire: {
                default: [
                    { name: '烈焰击', description: '释放火焰造成大量伤害' },
                    { name: '燃烧', description: '使敌人持续受到伤害' }
                ]
            },
            dark: {
                default: [
                    { name: '暗影突袭', description: '隐身接近敌人发动致命攻击' },
                    { name: '黑暗诅咒', description: '削弱敌人属性' }
                ]
            },
            light: {
                default: [
                    { name: '圣光祝福', description: '提升全队属性' },
                    { name: '神圣打击', description: '对黑暗属性敌人造成额外伤害' }
                ]
            }
        };

        return skills[element]?.default || skills.water.default;
    }

    function calculateAttack(level, growth) {
        return Math.floor(level * 30 + level * growth * 0.5);
    }

    function calculateDefense(level, growth) {
        return Math.floor(level * 15 + level * growth * 0.2);
    }

    function calculateSpeed(level, growth, zodiac) {
        const baseSpeed = 60;
        const levelBonus = level * 5;
        const growthBonus = Math.floor(level * growth * 0.1);
        const zodiacSpeedBonus = [5, 25, 15, 5, 12, 8, 30, 20, 35, 5, 20, 22];
        const zodiacBonus = zodiacSpeedBonus[zodiac] || 0;
        return baseSpeed + levelBonus + growthBonus + zodiacBonus;
    }

    function calculateMaxHP(level, growth) {
        const baseHp = 100;
        const levelBonus = level * 30;
        const growthBonus = Math.floor(level * growth * 2);
        return baseHp + levelBonus + growthBonus;
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
        copyToClipboard,
        showConfirmModal,
        handleContractError,
        handleError,
        handleTransaction,
        initGlobalErrorHandler,
        initNFTTooltips,
        calculateAttack,
        calculateDefense,
        calculateSpeed,
        calculateMaxHP
    };
})();
