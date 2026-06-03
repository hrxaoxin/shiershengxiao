/**
 * ZODIAC_UTILS - 十二生肖工具函数
 * 提供 NFT 信息解析、星级显示、地址格式化等通用工具
 */
window.ZODIAC_UTILS = (function() {
    const config = window.ZODIAC_CONFIG || {};
    const ZODIAC_NAMES = config.ZODIAC_NAMES || ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];
    const ATTR_NAMES = config.ATTR_NAMES || { water: '水', wind: '风', fire: '火', dark: '暗', light: '光' };
    const ATTR_PREFIXES = config.ATTR_PREFIXES || { water: 'shui', wind: 'feng', fire: 'huo', dark: 'an', light: 'guang' };
    const IPFS_BASES = config.IPFS_BASES || {};
    const ANIMAL_KEYS = ['shu', 'niu', 'hu', 'tu', 'long', 'she', 'ma', 'yang', 'hou', 'ji', 'gou', 'zhu'];
    const ATTR_KEYS = ['water', 'wind', 'fire', 'dark', 'light'];
    const GENDER_NAMES = ['母', '公'];

    /**
     * 根据 typeId 获取 NFT 信息
     * typeId 编码: elementIndex * 24 + zodiacIndex * 2 + gender
     */
    function getNFTInfo(typeId) {
        const typedId = parseInt(typeId, 10);
        if (isNaN(typedId) || typedId < 0 || typedId >= 120) {
            return {
                typeId: typedId,
                elementIndex: 0,
                zodiac: 0,
                gender: 0,
                elementKey: 'water',
                attrName: '水',
                animalName: '鼠',
                genderName: '母',
                imagePath: '',
                name: '未知NFT',
                isRare: false
            };
        }

        const elementIndex = Math.floor(typedId / 24);
        const remainder = typedId % 24;
        const zodiacIndex = Math.floor(remainder / 2);
        const gender = remainder % 2;

        const elementKey = ATTR_KEYS[elementIndex] || 'water';
        const attrName = ATTR_NAMES[elementKey] || '未知';
        const animalName = ZODIAC_NAMES[zodiacIndex] || '未知';
        const genderName = GENDER_NAMES[gender] || '?';
        const isRare = (elementKey === 'dark' || elementKey === 'light');

        const ipfsBase = IPFS_BASES[elementKey] || '';
        const prefix = ATTR_PREFIXES[elementKey] || elementKey;
        const animalKey = ANIMAL_KEYS[zodiacIndex] || 'shu';
        const imagePath = `${ipfsBase}${prefix}${animalKey}_${gender + 1}.png`;

        return {
            typeId: typedId,
            elementIndex,
            zodiac: zodiacIndex,
            gender,
            elementKey,
            attrName,
            animalName,
            genderName,
            imagePath,
            name: `${attrName}${animalName}（${genderName}）`,
            isRare
        };
    }

    /** 获取星级字符串 */
    function getStars(level) {
        const lv = parseInt(level, 10);
        if (isNaN(lv) || lv <= 0) return '';
        return '⭐'.repeat(Math.min(lv, 5));
    }

    /** 格式化地址显示 */
    function formatAddress(address) {
        if (!address) return '0x...';
        if (address.length <= 10) return address;
        return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
    }

    /** 获取生肖名称 */
    function getZodiacName(index) {
        return ZODIAC_NAMES[index] || '未知';
    }

    /** 获取属性名称 */
    function getAttrName(elementKey) {
        return ATTR_NAMES[elementKey] || '未知';
    }

    /** 判断 NFT 是否稀有 */
    function isRareToken(elementKey) {
        return elementKey === 'dark' || elementKey === 'light';
    }

    /** 获取属性索引 */
    function getAttrIndex(elementKey) {
        return ATTR_KEYS.indexOf(elementKey);
    }

    /** 获取 NFT 图片路径 */
    function getNFTImagePath(typeId) {
        const info = getNFTInfo(typeId);
        return info.imagePath;
    }

    /** 截断文本 */
    function truncateText(text, maxLength) {
        if (!text) return '';
        if (text.length <= maxLength) return text;
        return text.substring(0, maxLength) + '...';
    }

    /** 转换为可读数字 */
    function formatNumber(num, decimals) {
        if (num === undefined || num === null) return '0';
        const n = parseFloat(num);
        if (isNaN(n)) return '0';
        return n.toFixed(decimals || 2);
    }

    /** 获取元素对应的颜色 */
    function getElementColor(elementKey) {
        const colors = {
            water: '#0ea5e9',
            wind: '#22c55e',
            fire: '#ef4444',
            dark: '#8b5cf6',
            light: '#f59e0b'
        };
        return colors[elementKey] || '#6b7280';
    }

    /** 获取元素对应的 CSS 类名 */
    function getElementCardClass(elementKey) {
        return `${elementKey}-card`;
    }

    return {
        getNFTInfo,
        getStars,
        formatAddress,
        getZodiacName,
        getAttrName,
        isRareToken,
        getAttrIndex,
        getNFTImagePath,
        truncateText,
        formatNumber,
        getElementColor,
        getElementCardClass,
        ZODIAC_NAMES,
        ATTR_NAMES,
        ATTR_PREFIXES,
        ATTR_KEYS,
        ANIMAL_KEYS,
        GENDER_NAMES
    };
})();
