window.ZODIAC_UTILS = (function() {
    const GLOBAL_CONFIG = window.ZODIAC_CONFIG || {};
    
    const CONFIG = {
        ZODIAC_NAMES: GLOBAL_CONFIG.ZODIAC_NAMES || ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'],
        ATTR_NAMES: GLOBAL_CONFIG.ATTR_NAMES || { water: '水', wind: '风', fire: '火', dark: '暗', light: '光' },
        ATTR_PREFIXES: GLOBAL_CONFIG.ATTR_PREFIXES || { water: 'shui', wind: 'feng', fire: 'huo', dark: 'an', light: 'guang' },
        ANIMAL_KEYS: GLOBAL_CONFIG.ANIMAL_KEYS || ['shu', 'niu', 'hu', 'tu', 'long', 'she', 'ma', 'yang', 'hou', 'ji', 'gou', 'zhu'],
        IPFS_BASES: GLOBAL_CONFIG.IPFS_BASES || {
            water: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
            wind: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
            fire: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
            dark: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/',
            light: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/'
        },
        UPGRADE_COSTS: GLOBAL_CONFIG.UPGRADE_COSTS || {
            1: { nft: 1, tokens: 10000, usdtValue: 1 },
            2: { nft: 2, tokens: 40000, usdtValue: 4 },
            3: { nft: 3, tokens: 120000, usdtValue: 12 },
            4: { nft: 4, tokens: 480000, usdtValue: 48 }
        },
        WEIGHTS: GLOBAL_CONFIG.WEIGHTS || {
            normal: { 1: 1, 2: 2, 3: 6, 4: 18, 5: 66 },
            rare: { 1: 10, 2: 12, 3: 16, 4: 28, 5: 76 }
        }
    };

    function validateNumber(value, min, max, defaultValue = 0) {
        const num = parseInt(value);
        if (isNaN(num)) {
            console.warn(`Invalid number value: ${value}, using default: ${defaultValue}`);
            return defaultValue;
        }
        if (min !== undefined && num < min) {
            console.warn(`Number ${num} is below minimum ${min}, using ${min}`);
            return min;
        }
        if (max !== undefined && num > max) {
            console.warn(`Number ${num} is above maximum ${max}, using ${max}`);
            return max;
        }
        return num;
    }

    function validateBoolean(value, defaultValue = false) {
        if (typeof value === 'boolean') {
            return value;
        }
        if (value === 'true' || value === '1') {
            return true;
        }
        if (value === 'false' || value === '0') {
            return false;
        }
        console.warn(`Invalid boolean value: ${value}, using default: ${defaultValue}`);
        return defaultValue;
    }

    function validateAddress(address) {
        if (!address || typeof address !== 'string') {
            return null;
        }
        const cleanAddr = address.trim().toLowerCase();
        if (/^0x[a-f0-9]{40}$/.test(cleanAddr)) {
            return cleanAddr;
        }
        console.warn(`Invalid address format: ${address}`);
        return null;
    }

    function validateString(value, defaultValue = '') {
        if (typeof value === 'string') {
            return value.trim();
        }
        console.warn(`Invalid string value: ${value}, using default: "${defaultValue}"`);
        return defaultValue;
    }

    function getNFTInfo(typeId) {
        const validatedTypeId = validateNumber(typeId, 0, 119, 0);
        const attrIndex = Math.floor(validatedTypeId / 24);
        const remainder = validatedTypeId % 24;
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
                attrName: '水',
                zodiac: '鼠',
                imagePath: 'images/fu-cards/shuishu_1.png',
                isRare: false,
                zodiacIndex: 0,
                attrIndex: 0,
                typeId: validatedTypeId
            };
        }

        const attr = attrs[attrIndex];
        const prefix = CONFIG.ATTR_PREFIXES[attr];
        const animal = CONFIG.ANIMAL_KEYS[zodiacIndex];
        const ipfsBase = CONFIG.IPFS_BASES[attr];

        return {
            name: CONFIG.ATTR_NAMES[attr] + CONFIG.ZODIAC_NAMES[zodiacIndex] + '（' + gender + '）',
            prefix: prefix,
            animal: animal,
            gender: gender,
            attr: attr,
            attrName: CONFIG.ATTR_NAMES[attr],
            zodiac: CONFIG.ZODIAC_NAMES[zodiacIndex],
            imagePath: ipfsBase + prefix + animal + genderSuffix + '.png',
            ipfsBase: ipfsBase,
            zodiacIndex: zodiacIndex,
            attrIndex: attrIndex,
            isRare: attrIndex >= 3,
            typeId: validatedTypeId
        };
    }

    function getUpgradeCost(level) {
        const validatedLevel = validateNumber(level, 1, 4, 1);
        return CONFIG.UPGRADE_COSTS[validatedLevel] || { nft: 0, tokens: 0, usdtValue: 0 };
    }

    function getStars(level) {
        const validatedLevel = validateNumber(level, 1, 5, 1);
        return '⭐'.repeat(validatedLevel);
    }

    function getWeight(level, isRare = false) {
        const validatedLevel = validateNumber(level, 1, 5, 1);
        const validatedIsRare = validateBoolean(isRare, false);
        const weights = validatedIsRare ? CONFIG.WEIGHTS.rare : CONFIG.WEIGHTS.normal;
        return weights[validatedLevel] || 0;
    }

    function formatAddress(address) {
        const validatedAddr = validateAddress(address);
        if (!validatedAddr) return '未连接';
        return validatedAddr.substring(0, 4) + '...' + validatedAddr.substring(validatedAddr.length - 4);
    }

    function formatWeiToEther(wei) {
        if (wei === null || wei === undefined || wei === '') {
            return '0.0000';
        }
        
        const weiStr = String(wei);
        
        if (!/^\d+$/.test(weiStr)) {
            console.warn(`Invalid wei value: ${wei}, using 0`);
            return '0.0000';
        }
        
        const etherStr = weiStr.padStart(19, '0');
        const integerPart = etherStr.slice(0, -18);
        const decimalPart = etherStr.slice(-18).slice(0, 4);
        
        const formattedInteger = integerPart === '' ? '0' : integerPart.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        const formattedDecimal = decimalPart.padEnd(4, '0');
        
        return `${formattedInteger}.${formattedDecimal}`;
    }

    function calculateDividend(userWeight, totalWeight, dividendPool) {
        const validatedUserWeight = validateNumber(userWeight, 0, undefined, 0);
        const validatedTotalWeight = validateNumber(totalWeight, 0, undefined, 1);
        const validatedDividendPool = validateNumber(dividendPool, 0, undefined, 0);
        
        if (validatedTotalWeight === 0) return 0;
        return (validatedDividendPool * validatedUserWeight) / validatedTotalWeight;
    }

    function getAttributeType(attrIndex) {
        const validatedIndex = validateNumber(attrIndex, 0, 4, 0);
        const attrs = ['water', 'wind', 'fire', 'dark', 'light'];
        return attrs[validatedIndex] || 'water';
    }

    function getAttributeName(attr) {
        const validatedAttr = validateString(attr, 'water');
        return CONFIG.ATTR_NAMES[validatedAttr] || validatedAttr;
    }

    function getNFTImageUrl(imagePath, ipfsBase) {
        if (!imagePath) return 'https://via.placeholder.com/40';
        if (imagePath.indexOf('http') === 0) return imagePath;
        const defaultGateway = 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/';
        const base = ipfsBase !== undefined && ipfsBase !== null ? ipfsBase : defaultGateway;
        return `${base}${imagePath}`;
    }

    function getElementAdvantage(attackerElement, defenderElement) {
        const attacker = attackerElement.toLowerCase();
        const defender = defenderElement.toLowerCase();
        const advantages = { 
            fire: 'wind', 
            wind: 'water', 
            water: 'fire', 
            light: 'dark', 
            dark: 'light' 
        };
        return advantages[attacker] === defender;
    }

    function getElementDisadvantage(attackerElement, defenderElement) {
        const attacker = attackerElement.toLowerCase();
        const defender = defenderElement.toLowerCase();
        const disadvantages = { 
            wind: 'fire', 
            water: 'wind', 
            fire: 'water', 
            dark: 'light', 
            light: 'dark' 
        };
        return disadvantages[attacker] === defender;
    }

    function generateRandomId() {
        return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
    }

    function debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    }

    function throttle(func, limit) {
        let inThrottle;
        return function executedFunction(...args) {
            if (!inThrottle) {
                func(...args);
                inThrottle = true;
                setTimeout(() => (inThrottle = false), limit);
            }
        };
    }

    return {
        getNFTInfo: getNFTInfo,
        getUpgradeCost: getUpgradeCost,
        getStars: getStars,
        getWeight: getWeight,
        formatAddress: formatAddress,
        formatWeiToEther: formatWeiToEther,
        calculateDividend: calculateDividend,
        getAttributeType: getAttributeType,
        getAttributeName: getAttributeName,
        getNFTImageUrl: getNFTImageUrl,
        getElementAdvantage: getElementAdvantage,
        getElementDisadvantage: getElementDisadvantage,
        generateRandomId: generateRandomId,
        debounce: debounce,
        throttle: throttle,
        validateNumber: validateNumber,
        validateBoolean: validateBoolean,
        validateAddress: validateAddress,
        validateString: validateString,
        CONFIG: CONFIG
    };
})();