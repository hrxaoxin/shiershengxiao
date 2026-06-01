window.ZODIAC_UI = (function() {
    const listeners = {};
    let walletConnectedEmitted = false;

    /**
     * 显示 Loading 遮罩
     */
    function showLoading(message) {
        // 移除已有的 loading
        hideLoading();

        const overlay = document.createElement('div');
        overlay.id = 'zodiac-loading-overlay';
        overlay.className = 'fixed inset-0 bg-black/50 flex items-center justify-center z-[9999]';
        overlay.innerHTML = `
            <div class="bg-white rounded-2xl p-8 shadow-2xl text-center max-w-sm w-full mx-4">
                <div class="animate-spin rounded-full h-12 w-12 border-4 border-blue-500 border-t-transparent mx-auto mb-4"></div>
                <p class="text-gray-700 font-medium">${message || '加载中...'}</p>
            </div>
        `;
        document.body.appendChild(overlay);
    }

    /**
     * 隐藏 Loading 遮罩
     */
    function hideLoading() {
        const overlay = document.getElementById('zodiac-loading-overlay');
        if (overlay) {
            overlay.remove();
        }
    }

    /**
     * 显示 Toast 消息
     */
    function showToast(message, type) {
        const toast = document.createElement('div');
        const id = 'toast-' + Date.now();

        const bgColors = {
            success: 'bg-green-500',
            error: 'bg-red-500',
            warning: 'bg-yellow-500',
            info: 'bg-blue-500'
        };

        const icons = {
            success: '✓',
            error: '✕',
            warning: '⚠',
            info: 'ℹ'
        };

        const bgColor = bgColors[type] || bgColors.info;
        const icon = icons[type] || icons.info;

        // 确保有 toast 容器
        let container = document.getElementById('zodiac-toast-container');
        if (!container) {
            container = document.createElement('div');
            container.id = 'zodiac-toast-container';
            container.className = 'fixed top-4 right-4 z-[10000] flex flex-col gap-2 max-w-sm';
            document.body.appendChild(container);
        }

        toast.id = id;
        toast.className = `${bgColor} text-white px-5 py-3 rounded-xl shadow-lg flex items-center gap-3 transition-all duration-300 transform translate-x-full`;
        toast.innerHTML = `
            <span class="text-lg font-bold">${icon}</span>
            <span class="text-sm">${message}</span>
        `;
        container.appendChild(toast);

        // 动画入场
        requestAnimationFrame(() => {
            toast.style.transform = 'translateX(0)';
        });

        // 自动消失
        setTimeout(() => {
            toast.style.transform = 'translateX(120%)';
            toast.style.opacity = '0';
            setTimeout(() => toast.remove(), 300);
        }, 3000);
    }

    /**
     * 显示错误弹窗
     */
    function showErrorModal(message) {
        return new Promise((resolve) => {
            const overlay = document.createElement('div');
            overlay.id = 'zodiac-error-overlay';
            overlay.className = 'fixed inset-0 bg-black/50 flex items-center justify-center z-[9999]';
            overlay.innerHTML = `
                <div class="bg-white rounded-2xl p-6 shadow-2xl max-w-sm w-full mx-4">
                    <div class="flex items-center mb-4">
                        <div class="w-10 h-10 rounded-full bg-red-100 flex items-center justify-center mr-3">
                            <span class="text-red-500 text-xl">✕</span>
                        </div>
                        <h3 class="text-lg font-bold text-gray-800">操作失败</h3>
                    </div>
                    <p class="text-gray-600 mb-6 text-sm">${message}</p>
                    <div class="flex justify-end">
                        <button id="error-ok" class="px-5 py-2 rounded-lg bg-red-500 text-white hover:bg-red-600 transition-colors">确定</button>
                    </div>
                </div>
            `;
            document.body.appendChild(overlay);

            const cleanup = () => { overlay.remove(); resolve(); };

            overlay.querySelector('#error-ok').onclick = cleanup;
            overlay.onclick = (e) => { if (e.target === overlay) cleanup(); };
        });
    }

    /**
     * 显示成功弹窗
     */
    function showSuccessModal(title, message) {
        return new Promise((resolve) => {
            const overlay = document.createElement('div');
            overlay.id = 'zodiac-success-overlay';
            overlay.className = 'fixed inset-0 bg-black/50 flex items-center justify-center z-[9999]';
            overlay.innerHTML = `
                <div class="bg-white rounded-2xl p-6 shadow-2xl max-w-sm w-full mx-4">
                    <div class="flex items-center mb-4">
                        <div class="w-10 h-10 rounded-full bg-green-100 flex items-center justify-center mr-3">
                            <span class="text-green-500 text-xl">✓</span>
                        </div>
                        <h3 class="text-lg font-bold text-gray-800">${title || '操作成功'}</h3>
                    </div>
                    <p class="text-gray-600 mb-6 text-sm">${message || ''}</p>
                    <div class="flex justify-end">
                        <button id="success-ok" class="px-5 py-2 rounded-lg bg-green-500 text-white hover:bg-green-600 transition-colors">确定</button>
                    </div>
                </div>
            `;
            document.body.appendChild(overlay);

            const cleanup = () => { overlay.remove(); resolve(); };

            overlay.querySelector('#success-ok').onclick = cleanup;
            overlay.onclick = (e) => { if (e.target === overlay) cleanup(); };
        });
    }

    /**
     * 显示确认弹窗
     */
    function showConfirmModal(title, message) {
        return new Promise((resolve) => {
            const overlay = document.createElement('div');
            overlay.id = 'zodiac-confirm-overlay';
            overlay.className = 'fixed inset-0 bg-black/50 flex items-center justify-center z-[9999]';
            overlay.innerHTML = `
                <div class="bg-white rounded-2xl p-6 shadow-2xl max-w-sm w-full mx-4">
                    <h3 class="text-lg font-bold text-gray-800 mb-3">${title || '确认操作'}</h3>
                    <p class="text-gray-600 mb-6">${message || '确定要执行此操作吗？'}</p>
                    <div class="flex gap-3 justify-end">
                        <button id="confirm-cancel" class="px-5 py-2 rounded-lg border border-gray-300 text-gray-700 hover:bg-gray-100 transition-colors">取消</button>
                        <button id="confirm-ok" class="px-5 py-2 rounded-lg bg-blue-500 text-white hover:bg-blue-600 transition-colors">确认</button>
                    </div>
                </div>
            `;
            document.body.appendChild(overlay);

            const cleanup = () => {
                overlay.remove();
            };

            overlay.querySelector('#confirm-cancel').onclick = () => {
                cleanup();
                resolve(false);
            };

            overlay.querySelector('#confirm-ok').onclick = () => {
                cleanup();
                resolve(true);
            };

            // 点击遮罩关闭
            overlay.onclick = (e) => {
                if (e.target === overlay) {
                    cleanup();
                    resolve(false);
                }
            };
        });
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

    function emitEvent(event, data) {
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
     * 更新钱包显示信息
     */
    function updateWalletInfo(address, balance) {
        const walletAddressEl = document.getElementById('walletAddress');
        const walletAddressDesktopEl = document.getElementById('walletAddressDesktop');
        const connectionStatusEl = document.getElementById('connectionStatus');

        if (walletAddressEl) {
            walletAddressEl.textContent = address || '未连接钱包';
        }
        if (walletAddressDesktopEl) {
            walletAddressDesktopEl.textContent = address
                ? (address.substring(0, 6) + '...' + address.substring(address.length - 4))
                : '未连接';
        }
        if (connectionStatusEl) {
            connectionStatusEl.textContent = address ? '已连接' : '请点击连接钱包按钮';
        }
    }

    /**
     * 初始化钱包连接按钮
     * @param {string} btnId - 按钮元素 ID
     * @param {string|null} addressElId - 显示地址的元素 ID（可选）
     * @param {string|null} statusElId - 显示连接状态的元素 ID（可选）
     */
    function initWalletButton(btnId, addressElId, statusElId) {
        const btn = document.getElementById(btnId);
        if (!btn) return;

        // 更新按钮状态
        function updateButtonState(account) {
            if (account) {
                btn.innerHTML = '<i class="fas fa-wallet mr-2"></i>' +
                    account.substring(0, 6) + '...' + account.substring(account.length - 4);
                btn.classList.add('bg-green-500');
            } else {
                btn.innerHTML = '<i class="fas fa-wallet mr-2"></i>连接钱包';
                btn.classList.remove('bg-green-500');
            }

            // 更新地址显示
            if (addressElId) {
                const addrEl = document.getElementById(addressElId);
                if (addrEl) {
                    addrEl.textContent = account || '未连接钱包';
                }
            }

            // 更新状态显示
            if (statusElId) {
                const statusEl = document.getElementById(statusElId);
                if (statusEl) {
                    statusEl.textContent = account ? '已连接' : '请点击连接钱包按钮';
                }
            }
        }

        // 点击按钮触发连接
        btn.addEventListener('click', async () => {
            if (!window.ZODIAC_WEB3) {
                showToast('Web3 模块未加载', 'error');
                return;
            }

            try {
                if (ZODIAC_WEB3.isConnected()) {
                    // 如果已连接，不重复连接
                    return;
                }
                await ZODIAC_WEB3.initWeb3();
                updateButtonState(ZODIAC_WEB3.getAccount());
                // 触发 walletConnected 事件（确保只触发一次）
                if (!walletConnectedEmitted) {
                    walletConnectedEmitted = true;
                    emitEvent('walletConnected', { account: ZODIAC_WEB3.getAccount() });
                }
            } catch (error) {
                console.error('Wallet connection failed:', error);
                showToast(ZODIAC_CONFIG.getErrorMessage(error), 'error');
            }
        });

        // 监听连接/断开事件
        if (window.ZODIAC_WEB3) {
            ZODIAC_WEB3.on('connect', (data) => {
                updateButtonState(data.account);
                // 触发 walletConnected 事件（确保只触发一次）
                if (!walletConnectedEmitted) {
                    walletConnectedEmitted = true;
                    emitEvent('walletConnected', data);
                }
            });

            ZODIAC_WEB3.on('disconnect', () => {
                updateButtonState(null);
                walletConnectedEmitted = false;
            });

            ZODIAC_WEB3.on('accountsChanged', (data) => {
                updateButtonState(data.account);
            });
        }

        // 初始状态
        if (window.ZODIAC_WEB3 && ZODIAC_WEB3.isConnected()) {
            updateButtonState(ZODIAC_WEB3.getAccount());
        }
    }

    /**
     * 统一错误处理 - 显示错误 Toast
     * @param {Error|string} error - 错误对象或消息
     * @param {string} action - 操作名称（用于 Toast 文案）
     */
    function handleError(error, action) {
        const message = error.message || error.toString();
        const displayAction = action || '操作';
        showToast(`${displayAction}失败: ${message}`, 'error');
    }

    /**
     * 统一错误处理 - 显示确认弹窗
     * @param {Error|string} error - 错误对象或消息
     * @param {string} title - 弹窗标题
     * @param {string} action - 操作名称
     */
    function handleErrorWithConfirm(error, title, action) {
        const message = error.message || error.toString();
        const displayTitle = title || '操作失败';
        const displayAction = action || '操作';
        
        const overlay = document.createElement('div');
        overlay.id = 'zodiac-error-confirm-overlay';
        overlay.className = 'fixed inset-0 bg-black/50 flex items-center justify-center z-[9999]';
        overlay.innerHTML = `
            <div class="bg-white rounded-2xl p-6 shadow-2xl max-w-sm w-full mx-4">
                <div class="flex items-center mb-4">
                    <div class="w-10 h-10 rounded-full bg-red-100 flex items-center justify-center mr-3">
                        <span class="text-red-500 text-xl">✕</span>
                    </div>
                    <h3 class="text-lg font-bold text-gray-800">${displayTitle}</h3>
                </div>
                <p class="text-gray-600 mb-4 text-sm">${displayAction}失败</p>
                <p class="text-gray-500 mb-6 text-xs bg-gray-50 p-2 rounded">${message}</p>
                <div class="flex gap-3 justify-end">
                    <button id="error-confirm-ok" class="px-5 py-2 rounded-lg bg-red-500 text-white hover:bg-red-600 transition-colors">确定</button>
                </div>
            </div>
        `;
        document.body.appendChild(overlay);

        overlay.querySelector('#error-confirm-ok').onclick = () => overlay.remove();
        overlay.onclick = (e) => { if (e.target === overlay) overlay.remove(); };
    }

    /**
     * 处理合约错误
     * @param {Error} error - 错误对象
     * @param {string} operation - 操作名称
     */
    function handleContractError(error, operation) {
        const errorMessage = error.message || error.toString();
        let userMessage = `${operation}失败`;
        let errorCode = 'UNKNOWN';
        
        const errorPatterns = [
            { pattern: /User rejected|4001/, message: '用户取消了交易', code: 'USER_REJECTED' },
            { pattern: /insufficient funds|balance/, message: '余额不足，无法完成交易', code: 'INSUFFICIENT_FUNDS' },
            { pattern: /nonce too low/, message: '交易冲突，请稍后重试', code: 'NONCE_TOO_LOW' },
            { pattern: /gas required exceeds|out of gas/, message: 'Gas费用不足或估算失败', code: 'GAS_ERROR' },
            { pattern: /execution reverted/, message: handleRevertError(errorMessage), code: 'EXECUTION_REVERTED' },
            { pattern: /Not authorized|Unauthorized/, message: '未授权操作，请联系管理员', code: 'UNAUTHORIZED' },
            { pattern: /Paused/, message: '合约已暂停，请稍后再试', code: 'CONTRACT_PAUSED' },
            { pattern: /Invalid price/, message: '无效的价格设置', code: 'INVALID_PRICE' },
            { pattern: /Not token owner|ownerOf/, message: '您不是该NFT的所有者', code: 'NOT_OWNER' },
            { pattern: /Listing not found/, message: '商品不存在或已下架', code: 'LISTING_NOT_FOUND' },
            { pattern: /Seller no longer owns NFT/, message: '卖家不再拥有该NFT', code: 'SELLER_NO_OWNER' },
            { pattern: /Contract not approved|isApprovedForAll/, message: '合约未获得NFT授权', code: 'NOT_APPROVED' },
            { pattern: /Lock period|cooldown/, message: '锁定期未结束', code: 'LOCKED' },
            { pattern: /Already staked/, message: '该NFT已质押', code: 'ALREADY_STAKED' },
            { pattern: /Empty tokenIds|Empty array/, message: '请选择要操作的NFT', code: 'EMPTY_INPUT' },
            { pattern: /Chain ID|chainId/, message: '请切换到正确的网络', code: 'WRONG_NETWORK' },
            { pattern: /MetaMask not detected|ethereum is undefined/, message: '未检测到MetaMask钱包，请安装后重试', code: 'NO_WALLET' },
            { pattern: /Wallet not connected/, message: '钱包未连接，请先连接钱包', code: 'NOT_CONNECTED' },
            { pattern: /Web3 not initialized/, message: 'Web3初始化失败，请刷新页面重试', code: 'WEB3_ERROR' },
            { pattern: /Level < 5|level too low/, message: 'NFT等级不足，需要等级5', code: 'LEVEL_TOO_LOW' },
            { pattern: /Different zodiac|zodiac mismatch/, message: '生肖不匹配', code: 'ZODIAC_MISMATCH' },
            { pattern: /Same gender/, message: '性别相同，无法繁殖', code: 'SAME_GENDER' },
            { pattern: /Father in cooldown|Mother in cooldown/, message: 'NFT正在冷却期', code: 'BREEDING_COOLDOWN' },
            { pattern: /Cannot breed with self/, message: '不能与自己繁殖', code: 'SELF_BREEDING' },
            { pattern: /Invalid zodiac/, message: '无效的生肖类型', code: 'INVALID_ZODIAC' },
            { pattern: /No attempts left/, message: '剩余挑战次数不足', code: 'NO_ATTEMPTS' },
            { pattern: /Battle cooldown/, message: '战斗冷却中，请稍后再试', code: 'BATTLE_COOLDOWN' },
            { pattern: /Time lock not expired/, message: '时间锁未到期，请稍后重试', code: 'TIME_LOCK' },
            { pattern: /Max recharge limit/, message: '已达到最大充值次数限制', code: 'MAX_RECHARGE' },
            { pattern: /Exceeds.*limit/, message: '超过限制，请检查您的操作', code: 'EXCEEDS_LIMIT' },
            { pattern: /Insufficient.*allowance/, message: '代币授权额度不足', code: 'INSUFFICIENT_ALLOWANCE' },
            { pattern: /Transfer failed|transfer failed/, message: '转账失败，请稍后重试', code: 'TRANSFER_FAILED' },
            { pattern: /Already initialized/, message: '合约已初始化，不能重复操作', code: 'ALREADY_INITIALIZED' },
            { pattern: /Zero address/, message: '地址不能为零', code: 'ZERO_ADDRESS' },
            { pattern: /Invalid amount/, message: '无效的数量', code: 'INVALID_AMOUNT' },
            { pattern: /Token.*not set|Contract not set/, message: '合约未正确设置', code: 'CONTRACT_NOT_SET' },
            { pattern: /Threshold not met/, message: '未达到阈值要求', code: 'THRESHOLD_NOT_MET' },
            { pattern: /No pending action/, message: '没有待处理的操作', code: 'NO_PENDING_ACTION' },
            { pattern: /Invalid token address|Invalid address/, message: '无效的合约地址', code: 'INVALID_ADDRESS' },
            { pattern: /Token contract not set/, message: '代币合约未设置', code: 'TOKEN_CONTRACT_NOT_SET' },
            { pattern: /NFT contract not set/, message: 'NFT合约未设置', code: 'NFT_CONTRACT_NOT_SET' },
            { pattern: /transferFrom failed|transfer failed/, message: '转账失败', code: 'TRANSFER_FAILED' },
            { pattern: /replacement transaction underpriced/, message: '替换交易价格过低', code: 'UNDERPRICED' },
            { pattern: /block gas limit/, message: '区块Gas限制不足', code: 'BLOCK_GAS_LIMIT' },
            { pattern: /max priority fee/, message: 'Gas费用设置不合理', code: 'GAS_FEE_ERROR' },
            { pattern: /RPC error|network error/, message: '网络连接失败，请检查网络', code: 'NETWORK_ERROR' }
        ];
        
        for (const { pattern, message, code } of errorPatterns) {
            if (pattern.test(errorMessage)) {
                userMessage = message;
                errorCode = code;
                break;
            }
        }
        
        showToast(userMessage, 'error');
        logError(error, operation, errorCode);
    }

    function handleRevertError(errorMessage) {
        const revertMatch = errorMessage.match(/reverted with reason string '([^']+)'/);
        if (revertMatch) {
            const reason = revertMatch[1];
            const reasonMap = {
                'NFTTrading: Paused': '交易市场已暂停',
                'NFTTrading: Not token owner': '您不是该NFT的所有者',
                'NFTTrading: Listing not found': '商品不存在',
                'Staking: Paused': '质押合约已暂停',
                'Staking: Already staked': '该NFT已质押',
                'Staking: Lock period': '质押锁定期未结束',
                'Breeding: Level < 5': 'NFT等级不足，需要等级5',
                'Breeding: Different zodiac': '生肖不匹配',
                'Breeding: Same gender': '性别相同'
            };
            return reasonMap[reason] || `合约执行失败: ${reason}`;
        }
        return '合约执行失败';
    }

    function logError(error, operation, code) {
        const errorLog = {
            timestamp: new Date().toISOString(),
            operation: operation,
            code: code,
            message: error.message || error.toString(),
            stack: error.stack,
            account: window.ZODIAC_WEB3 ? ZODIAC_WEB3.getAccount() : null,
            chainId: window.ZODIAC_WEB3 ? ZODIAC_WEB3.getChainIdDecimal() : null
        };
        
        console.error('[ZODIAC_ERROR]', JSON.stringify(errorLog, null, 2));
    }

    /**
     * 格式化地址（委托给 ZODIAC_UTILS）
     */
    function formatAddress(address) {
        if (window.ZODIAC_UTILS && window.ZODIAC_UTILS.formatAddress) {
            return window.ZODIAC_UTILS.formatAddress(address);
        }
        if (!address) return '未连接';
        return address.substring(0, 6) + '...' + address.substring(address.length - 4);
    }

    /**
     * 增强的交易处理函数 - 提供完整的交易反馈
     * @param {Promise} transactionPromise - 交易Promise
     * @param {Object} options - 配置选项
     * @param {string} options.actionName - 操作名称
     * @param {string} options.loadingMessage - 加载中消息
     * @param {string} options.successMessage - 成功消息
     * @param {Function} options.onHash - 交易哈希回调
     * @param {Function} options.onConfirmation - 确认回调
     * @returns {Promise<Object>} 交易结果
     */
    async function handleTransaction(transactionPromise, options = {}) {
        const {
            actionName = '操作',
            loadingMessage = '交易处理中...',
            successMessage = '交易成功！',
            onHash,
            onConfirmation,
            showConfirmation = false,
            confirmations = 1,
            timeout = 300000
        } = options;

        showLoading(loadingMessage);

        let timeoutId;
        const timeoutPromise = new Promise((_, reject) => {
            timeoutId = setTimeout(() => {
                reject(new Error('Transaction timeout'));
            }, timeout);
        });

        try {
            const tx = await Promise.race([transactionPromise, timeoutPromise]);

            clearTimeout(timeoutId);

            if (tx && tx.hash) {
                const shortHash = tx.hash.substring(0, 10) + '...' + tx.hash.substring(tx.hash.length - 8);
                hideLoading();

                if (onHash) {
                    onHash(tx.hash, shortHash);
                }

                if (showConfirmation && typeof tx.wait === 'function') {
                    showLoading(`等待区块链确认 (${shortHash})...`);
                    const receipt = await tx.wait(confirmations);
                    if (onConfirmation) {
                        onConfirmation(receipt);
                    }
                    hideLoading();
                }

                showToast(`${successMessage} (${shortHash})`, 'success');
                return tx;
            }

            hideLoading();
            showToast(successMessage, 'success');
            return tx;

        } catch (error) {
            clearTimeout(timeoutId);
            hideLoading();

            if (error.message.includes('Transaction timeout')) {
                showToast(`${actionName}超时，请检查交易状态后重试`, 'warning');
            } else {
                handleError(error, actionName);
            }
            throw error;
        }
    }

    /**
     * 监听交易确认 - 用于长时间运行的交易
     * @param {string} txHash - 交易哈希
     * @param {Function} onUpdate - 更新回调
     * @param {number} confirmations - 需要确认数
     */
    async function monitorTransaction(txHash, onUpdate, confirmations = 1) {
        if (typeof window !== 'undefined' && window.web3) {
            const web3 = window.web3;
            let currentBlock = await web3.eth.getBlockNumber();
            const txReceipt = await web3.eth.getTransactionReceipt(txHash);

            if (!txReceipt) {
                throw new Error('交易未找到');
            }

            if (txReceipt.blockNumber) {
                const startBlock = txReceipt.blockNumber;
                const checkConfirmation = async () => {
                    const latestBlock = await web3.eth.getBlockNumber();
                    const confirmationsCount = latestBlock - startBlock + 1;

                    if (onUpdate) {
                        onUpdate({
                            confirmations: confirmationsCount,
                            latestBlock: latestBlock,
                            startBlock: startBlock,
                            status: confirmationsCount >= confirmations ? 'confirmed' : 'pending'
                        });
                    }

                    if (confirmationsCount < confirmations) {
                        setTimeout(checkConfirmation, 3000);
                    }
                };

                checkConfirmation();
            }
        }
    }

    return {
        showLoading,
        hideLoading,
        showToast,
        showConfirmModal,
        showErrorModal,
        showSuccessModal,
        on,
        emitEvent,
        updateWalletInfo,
        formatAddress,
        initWalletButton,
        handleError,
        handleTransaction,
        monitorTransaction
    };
})();
