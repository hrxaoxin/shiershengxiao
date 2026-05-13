// 十二生肖NFT项目共享工具函数
window.ZODIAC_UTILS = (function() {
    const ZODIAC_NAMES = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];
    const ATTR_NAMES = { water: '水', wind: '风', fire: '火', dark: '暗', light: '光' };
    const ATTR_PREFIXES = { water: 'shui', wind: 'feng', fire: 'huo', dark: 'an', light: 'guang' };
    const ANIMAL_KEYS = ['shu', 'niu', 'hu', 'tu', 'long', 'she', 'ma', 'yang', 'hou', 'ji', 'gou', 'zhu'];
    
    function showLoading(message = '加载中...') {
        let loadingOverlay = document.getElementById('loadingOverlay');
        if (!loadingOverlay) {
            loadingOverlay = document.createElement('div');
            loadingOverlay.id = 'loadingOverlay';
            loadingOverlay.className = 'loading-overlay';
            loadingOverlay.innerHTML = `
                <div class="flex flex-col items-center">
                    <div class="loading-spinner"></div>
                    <div class="loading-text">${message}</div>
                </div>
            `;
            document.body.appendChild(loadingOverlay);
        }
        loadingOverlay.classList.add('active');
    }

    function hideLoading() {
        const loadingOverlay = document.getElementById('loadingOverlay');
        if (loadingOverlay) {
            loadingOverlay.classList.remove('active');
        }
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
        toast.className = `toast ${type} active`;
        
        setTimeout(() => {
            toast.classList.remove('active');
        }, duration);
    }
    
    const IPFS_BASES = {
        water: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
        wind: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
        fire: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
        dark: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/',
        light: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/'
    };

    function getNFTInfo(typeId) {
        const attrIndex = Math.floor(typeId / 24);
        const remainder = typeId % 24;
        const zodiacIndex = Math.floor(remainder / 2);
        const genderValue = remainder % 2;
        const gender = genderValue === 0 ? '母' : '公';
        const genderSuffix = genderValue === 0 ? '_0' : '_1';
        const attrs = ['water', 'wind', 'fire', 'dark', 'light'];

        if (attrIndex < 0 || attrIndex >= attrs.length) {
            return { 
                name: '未知', 
                prefix: '', 
                animal: '', 
                gender: gender, 
                attr: 'water',
                imagePath: 'images/fu-cards/shuishu_1.png' 
            };
        }

        const attr = attrs[attrIndex];
        const prefix = ATTR_PREFIXES[attr];
        const animal = ANIMAL_KEYS[zodiacIndex];
        const ipfsBase = IPFS_BASES[attr];

        return {
            name: ATTR_NAMES[attr] + ZODIAC_NAMES[zodiacIndex] + '（' + gender + '）',
            prefix: prefix,
            animal: animal,
            gender: gender,
            attr: attr,
            attrName: ATTR_NAMES[attr],
            zodiac: ZODIAC_NAMES[zodiacIndex],
            imagePath: ipfsBase + prefix + animal + genderSuffix + '.png',
            ipfsBase: ipfsBase,
            zodiacIndex: zodiacIndex,
            attrIndex: attrIndex
        };
    }

    function getUpgradeCost(level) {
        const tokenCosts = {
            1: 10000,
            2: 40000,
            3: 120000,
            4: 480000
        };
        const usdtValues = {
            1: 1,
            2: 4,
            3: 12,
            4: 48
        };
        return {
            nftCount: level,
            tokens: tokenCosts[level] || 0,
            usdtValue: usdtValues[level] || 0
        };
    }

    function getStars(level) {
        return '⭐'.repeat(Math.min(level, 5));
    }

    function getWeight(level) {
        const weights = { 1: 1, 2: 2, 3: 4, 4: 12, 5: 48 };
        return weights[level] || 0;
    }

    function formatAddress(address) {
        if (!address) return '未连接';
        return address.substring(0, 4) + '...' + address.substring(address.length - 4);
    }

    function formatWeiToEther(wei) {
        if (!wei) return '0';
        return (parseInt(wei) / 1e18).toFixed(4);
    }

    return {
        getNFTInfo: getNFTInfo,
        getUpgradeCost: getUpgradeCost,
        getStars: getStars,
        getWeight: getWeight,
        formatAddress: formatAddress,
        formatWeiToEther: formatWeiToEther,
        showLoading: showLoading,
        hideLoading: hideLoading,
        showToast: showToast,
        ZODIAC_NAMES: ZODIAC_NAMES,
        ATTR_NAMES: ATTR_NAMES,
        ATTR_PREFIXES: ATTR_PREFIXES,
        ANIMAL_KEYS: ANIMAL_KEYS,
        IPFS_BASES: IPFS_BASES
    };
})();