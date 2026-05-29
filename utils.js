window.ZODIAC_UTILS = (function() {
    const ZODIAC_NAMES = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];
    const ATTR_NAMES = { 0: '水', 1: '风', 2: '火', 3: '暗', 4: '光' };
    const ATTR_KEYS = ['water', 'wind', 'fire', 'dark', 'light'];
    const ATTR_PREFIXES = ['shui', 'feng', 'huo', 'an', 'guang'];
    const ANIMAL_KEYS = ['shu', 'niu', 'hu', 'tu', 'long', 'she', 'ma', 'yang', 'hou', 'ji', 'gou', 'zhu'];
    const GENDER_NAMES = ['公', '母'];

    /**
     * 根据 tokenType 解析 NFT 元信息
     * tokenType = element * 24 + zodiac * 2 + gender
     */
    function getNFTInfo(tokenType) {
        const t = parseInt(tokenType, 10);
        const element = Math.floor(t / 24);
        const remainder = t % 24;
        const zodiac = Math.floor(remainder / 2);
        const gender = remainder % 2;

        const elementName = ATTR_NAMES[element] || '水';
        const elementKey = ATTR_KEYS[element] || 'water';
        const elementPrefix = ATTR_PREFIXES[element] || 'shui';
        const zodiacName = ZODIAC_NAMES[zodiac] || '鼠';
        const animalKey = ANIMAL_KEYS[zodiac] || 'shu';
        const genderName = GENDER_NAMES[gender] || '公';

        const name = elementName + '·' + zodiacName + '·' + genderName;

        const imagePath = `images/fu-cards/${elementPrefix}${animalKey}_${gender}.png`;

        return {
            name: name,
            element: element,
            elementName: elementName,
            elementKey: elementKey,
            elementPrefix: elementPrefix,
            zodiac: zodiac,
            zodiacName: zodiacName,
            animalKey: animalKey,
            gender: gender,
            genderName: genderName,
            tokenType: t,
            imagePath: imagePath,
            // 兼容旧的属性名
            attr: elementKey,
            attrName: elementName,
            zodiacIndex: zodiac
        };
    }

    function getStars(level) {
        const lv = parseInt(level, 10);
        if (isNaN(lv) || lv < 1) return '';
        return '⭐'.repeat(Math.min(lv, 5));
    }

    function formatAddress(address) {
        if (!address || typeof address !== 'string') return '未连接';
        if (address.length <= 10) return address;
        return address.substring(0, 6) + '...' + address.substring(address.length - 4);
    }

    function fromWei(value, unit) {
        if (typeof window !== 'undefined' && window.web3 && window.web3.utils) {
            return window.web3.utils.fromWei(String(value), unit || 'ether');
        }
        // 简单 fallback
        const val = typeof value === 'string' ? value : String(value);
        const num = parseFloat(val) / 1e18;
        return num.toString();
    }

    function toWei(value, unit) {
        if (typeof window !== 'undefined' && window.web3 && window.web3.utils) {
            return window.web3.utils.toWei(String(value), unit || 'ether');
        }
        // 简单 fallback
        const num = parseFloat(value);
        return String(Math.floor(num * 1e18));
    }

    function sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    return {
        ZODIAC_NAMES,
        ATTR_NAMES,
        ATTR_KEYS,
        ATTR_PREFIXES,
        ANIMAL_KEYS,
        getNFTInfo,
        getStars,
        formatAddress,
        fromWei,
        toWei,
        sleep
    };
})();
