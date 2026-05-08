// 十二生肖NFT项目共享工具函数
window.ZODIAC_UTILS = (function() {
    const ZODIAC_NAMES = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];
    const ATTR_NAMES = { water: '水', wind: '风', fire: '火', dark: '暗', light: '光' };
    const ATTR_PREFIXES = { water: 'shui', wind: 'feng', fire: 'huo', dark: 'an', light: 'guang' };
    const ANIMAL_KEYS = ['shu', 'niu', 'hu', 'tu', 'long', 'she', 'ma', 'yang', 'hou', 'ji', 'gou', 'zhu'];
    
    const IPFS_BASES = {
        water: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
        wind: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
        fire: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeifxtqzcstmdvrqghlrqppikcedzushbtucagc7nhnykg2pjl25qvi/',
        dark: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/',
        light: 'https://gold-fascinating-ermine-925.mypinata.cloud/ipfs/bafybeidyidmnm7uk3qr3i3aa5azxjwhdlmlaca3h5p6ppjoj2fz27rhud4/'
    };

    function getNFTInfo(typeId) {
        const zodiacIndex = typeId % 12;
        const attrIndex = Math.floor(typeId / 24);
        const gender = typeId % 2 === 1 ? '公' : '母';
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
        const genderSuffix = typeId % 2 === 1 ? '_1' : '_0';
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
        return {
            nftCount: level,
            tokens: level * 10000 * Math.pow(3, level - 1),
            usdtValue: Math.pow(4, level - 1)
        };
    }

    function getStars(level) {
        return '⭐'.repeat(Math.min(level, 5));
    }

    function getWeight(level) {
        return Math.min(4 + (level - 1), 8);
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
        ZODIAC_NAMES: ZODIAC_NAMES,
        ATTR_NAMES: ATTR_NAMES,
        ATTR_PREFIXES: ATTR_PREFIXES,
        ANIMAL_KEYS: ANIMAL_KEYS,
        IPFS_BASES: IPFS_BASES
    };
})();