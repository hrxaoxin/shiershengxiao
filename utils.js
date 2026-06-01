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
     * element: 0-4 (水、风、火、暗、光)
     * zodiac: 0-11 (鼠、牛、虎、兔、龙、蛇、马、羊、猴、鸡、狗、猪)
     * gender: 0-1 (公、母)
     * valid tokenType: 0-119 (5 * 24 - 1)
     */
    function getNFTInfo(tokenType) {
        const t = parseInt(tokenType, 10);
        if (isNaN(t) || t < 0 || t >= 120) {
            return {
                name: '未知NFT',
                element: -1,
                elementName: '未知',
                elementKey: 'unknown',
                elementPrefix: 'unknown',
                zodiac: -1,
                zodiacName: '未知',
                animalKey: 'unknown',
                gender: -1,
                genderName: '未知',
                tokenType: t,
                imagePath: 'images/fu-cards/unknown.png',
                attr: 'unknown',
                attrName: '未知',
                zodiacIndex: -1,
                isValid: false
            };
        }

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
            attr: elementKey,
            attrName: elementName,
            zodiacIndex: zodiac,
            isValid: true
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
        const val = typeof value === 'string' ? value : String(value);
        const parts = val.split('.');
        if (parts.length === 2) {
            const intPart = parts[0];
            const decPart = parts[1].substring(0, 18);
            return (BigInt(intPart) * BigInt(10 ** 18) + BigInt(decPart.padEnd(18, '0'))) / BigInt(10 ** 18);
        }
        return (BigInt(val) / BigInt(10 ** 18)).toString();
    }

    function toWei(value, unit) {
        if (typeof window !== 'undefined' && window.web3 && window.web3.utils) {
            return window.web3.utils.toWei(String(value), unit || 'ether');
        }
        const num = parseFloat(value);
        if (isNaN(num)) return '0';
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
