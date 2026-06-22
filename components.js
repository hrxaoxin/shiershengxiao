window.ZODIAC_COMPONENTS = (function() {
    const NAV_ITEMS = [
        { id: 'home', icon: '🏠', name: '首页', url: 'index.html' },
        { id: 'mint', icon: '🃏', name: '铸造', url: 'mint.html' },
        { id: 'collection', icon: '🎁', name: '生肖', url: 'collection.html' },
        { id: 'rewards', icon: '🏆', name: '奖励', url: 'rewards.html' },
        { id: 'upgrade', icon: '⭐', name: '升阶', url: 'upgrade.html' },
        { id: 'trading', icon: '💰', name: '交易', url: 'trading.html' },
        { id: 'buyback', icon: '🔄', name: '回购', url: 'buyback.html' },
        { id: 'breeding', icon: '🐾', name: '孕育', url: 'breeding.html' },
        { id: 'staking', icon: '⚡', name: '挖矿', url: 'staking.html' },
        { id: 'arena', icon: '⚔️', name: '竞技', url: 'arena.html' }
    ];

    function renderMobileNavbar(activeId) {
        const items = NAV_ITEMS.slice(0, 4);
        items.push({ id: 'more', icon: '☰', name: '更多', url: '#' });
        
        return `
            <nav class="navbar fixed bottom-0 left-0 right-0 z-10 md:hidden">
                <div class="flex justify-around items-center py-2 px-4">
                    ${items.map(item => `
                        ${item.id === 'more' ? `
                            <button id="moreMenuBtn" class="flex flex-col items-center justify-center w-full py-2 px-4 rounded-xl transition-all duration-300 hover:bg-gray-100">
                                <div class="text-2xl mb-1">${item.icon}</div>
                                <span class="text-xs font-bold text-gray-700">${item.name}</span>
                            </button>
                        ` : `
                            <a href="${item.url}" class="flex flex-col items-center justify-center w-full py-2 px-4 rounded-xl transition-all duration-300 ${activeId === item.id ? 'bg-gray-100' : 'hover:bg-gray-100'}">
                                <div class="text-2xl mb-1">${item.icon}</div>
                                <span class="text-xs font-bold text-gray-700">${item.name}</span>
                            </a>
                        `}
                    `).join('')}
                </div>
            </nav>
        `;
    }

    function renderMobileMenu() {
        return `
            <div id="mobileMenuOverlay" class="fixed inset-0 bg-black/50 z-40 md:hidden hidden" onclick="ZODIAC_COMPONENTS.closeMobileMenu()"></div>
            <div id="mobileMenu" class="fixed right-0 top-0 bottom-0 w-64 bg-white shadow-xl z-50 md:hidden transform translate-x-full transition-transform duration-300 overflow-y-auto">
                <div class="p-4 border-b">
                    <div class="flex justify-between items-center">
                        <span class="font-bold text-gray-800">导航菜单</span>
                        <button id="closeMenuBtn" class="p-2 hover:bg-gray-100 rounded-lg" onclick="ZODIAC_COMPONENTS.closeMobileMenu()">
                            <i class="fas fa-times text-gray-600"></i>
                        </button>
                    </div>
                </div>
                <div class="p-4 space-y-2">
                    ${NAV_ITEMS.map(item => `
                        <a href="${item.url}" class="flex items-center px-4 py-3 rounded-lg hover:bg-gray-100 transition-colors">
                            <span class="text-xl mr-3">${item.icon}</span>
                            <span class="text-gray-700">${item.name}</span>
                        </a>
                    `).join('')}
                </div>
            </div>
        `;
    }

    function renderDesktopSidebar(activeId) {
        return `
            <div class="hidden md:block fixed left-0 top-0 bottom-0 w-20 bg-white shadow-lg z-20 overflow-y-auto">
                <div class="p-3">
                    <div class="text-center mb-4">
                        <div class="text-3xl mb-1">🐾</div>
                        <h1 class="text-sm font-bold text-gray-800">生肖</h1>
                    </div>
                    <div class="space-y-1">
                        ${NAV_ITEMS.map(item => `
                            <a href="${item.url}" class="flex flex-col items-center justify-center w-full py-2 px-1 rounded-lg transition-all duration-300 hover:bg-gray-100 ${activeId === item.id ? 'bg-blue-50 text-blue-600' : ''}" title="${item.name}">
                                <div class="text-2xl">${item.icon}</div>
                                <span class="text-[10px] font-medium mt-1 text-gray-700">${item.name}</span>
                            </a>
                        `).join('')}
                    </div>
                    <div class="mt-4 pt-3 border-t border-gray-200">
                        <button id="connectWalletBtnDesktop" class="w-full wallet-button py-2 rounded-lg text-white font-medium text-xs" onclick="ZODIAC_COMPONENTS.handleConnectWallet()">
                            <i class="fas fa-plug mr-1"></i> 连接
                        </button>
                    </div>
                </div>
            </div>
        `;
    }

    function renderWalletInfo() {
        return `
            <div class="bg-white rounded-xl p-6 shadow-md mb-8">
                <div class="flex items-center mb-6">
                    <div class="w-10 h-10 rounded-full bg-blue-100 flex items-center justify-center mr-4">
                        <i class="text-blue-500 text-xl">💰</i>
                    </div>
                    <div class="flex-1">
                        <h3 class="text-lg font-semibold text-gray-800">钱包信息</h3>
                        <p class="text-sm text-gray-500" id="walletAddress">未连接钱包</p>
                        <p class="text-xs text-gray-400" id="connectionStatus">请点击连接钱包按钮</p>
                    </div>
                    <div class="flex space-x-2">
                        <button class="btn-primary text-sm" id="connectWalletBtn">
                            <i class="fas fa-plug mr-1"></i> 连接
                        </button>
                        <button class="btn-secondary text-sm" id="refreshWallet">
                            <i class="fas fa-sync-alt mr-1"></i> 刷新
                        </button>
                    </div>
                </div>
            </div>
        `;
    }

    function renderFooter(marginLeft = '') {
        return `
            <footer class="text-center py-8 text-black/70${marginLeft ? ` ${marginLeft}` : ''}">
                <p>© 2026 十二生肖NFT系列 · Twelve Zodiacs Collection</p>
                <p class="mt-2">祝你心想事成，生肖大旺 🐾✨</p>
            </footer>
        `;
    }

    function renderNavigation(activeId) {
        const mobileNavbar = renderMobileNavbar(activeId);
        const mobileMenu = renderMobileMenu();
        const desktopSidebar = renderDesktopSidebar(activeId);
        
        return {
            mobileNavbar,
            mobileMenu,
            desktopSidebar
        };
    }

    function injectNavigation(activeId, options = {}) {
        const {
            mobileNavbarContainer = 'mobileNavbarContainer',
            mobileMenuContainer = 'mobileMenuContainer',
            desktopSidebarContainer = 'desktopSidebarContainer'
        } = options;

        const nav = renderNavigation(activeId);

        const mobileNavbarEl = document.getElementById(mobileNavbarContainer);
        const mobileMenuEl = document.getElementById(mobileMenuContainer);
        const desktopSidebarEl = document.getElementById(desktopSidebarContainer);

        if (mobileNavbarEl) {
            mobileNavbarEl.innerHTML = nav.mobileNavbar;
        }
        if (mobileMenuEl) {
            mobileMenuEl.innerHTML = nav.mobileMenu;
        }
        if (desktopSidebarEl) {
            desktopSidebarEl.innerHTML = nav.desktopSidebar;
        }

        const containersFound = (mobileNavbarEl || mobileMenuEl || desktopSidebarEl);
        if (!containersFound) {
            console.warn('No navigation containers found in the page');
            return false;
        }

        initNavigation(activeId);
        return true;
    }

    function openMobileMenu() {
        document.getElementById('mobileMenu').classList.remove('translate-x-full');
        document.getElementById('mobileMenuOverlay').classList.remove('hidden');
        document.body.style.overflow = 'hidden';
    }

    function closeMobileMenu() {
        document.getElementById('mobileMenu').classList.add('translate-x-full');
        document.getElementById('mobileMenuOverlay').classList.add('hidden');
        document.body.style.overflow = '';
    }

    function handleConnectWallet() {
        if (window.ZODIAC_WEB3) {
            ZODIAC_WEB3.initWeb3().then(success => {
                if (!success) {
                    if (window.ZODIAC_UI) {
                        ZODIAC_UI.showToast('连接钱包失败，请确保已安装MetaMask', 'error');
                    }
                }
            }).catch(err => {
                console.error('[ZODIAC_COMPONENTS] Wallet connection error:', err);
                if (window.ZODIAC_UI) {
                    ZODIAC_UI.showToast('连接钱包失败: ' + (err.message || '未知错误'), 'error');
                }
            });
        } else {
            console.error('[ZODIAC_COMPONENTS] ZODIAC_WEB3 not available');
            if (window.ZODIAC_UI) {
                ZODIAC_UI.showToast('钱包服务未初始化，请刷新页面', 'error');
            }
        }
    }

    let navigationInitialized = false;

    function initNavigation(activeId) {
        if (navigationInitialized) {
            console.warn('Navigation already initialized, skipping duplicate initialization');
            return;
        }
        
        const handleDOMContentLoaded = () => {
            document.getElementById('moreMenuBtn')?.addEventListener('click', openMobileMenu);
            document.getElementById('closeMenuBtn')?.addEventListener('click', closeMobileMenu);
            navigationInitialized = true;
        };
        
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', handleDOMContentLoaded);
        } else {
            handleDOMContentLoaded();
        }
    }

    return {
        NAV_ITEMS,
        renderMobileNavbar,
        renderMobileMenu,
        renderDesktopSidebar,
        renderWalletInfo,
        renderFooter,
        renderNavigation,
        injectNavigation,
        openMobileMenu,
        closeMobileMenu,
        handleConnectWallet,
        initNavigation
    };
})();