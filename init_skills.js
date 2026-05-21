const Web3 = require('web3');

const BATTLE_ABI = [
    {
        "inputs": [
            { "internalType": "uint256", "name": "elementIndex", "type": "uint256" },
            { "internalType": "uint256", "name": "zodiacIndex", "type": "uint256" },
            { "internalType": "uint256", "name": "gender", "type": "uint256" },
            {
                "components": [
                    { "internalType": "string", "name": "name", "type": "string" },
                    { "internalType": "uint8", "name": "skillType", "type": "uint8" },
                    { "internalType": "uint256", "name": "value", "type": "uint256" },
                    { "internalType": "uint256", "name": "cooldown", "type": "uint256" },
                    { "internalType": "uint256", "name": "duration", "type": "uint256" },
                    { "internalType": "bool", "name": "isAoe", "type": "bool" }
                ],
                "internalType": "struct BattleSkills.FullSkill",
                "name": "skill",
                "type": "tuple"
            }
        ],
        "name": "setSkill",
        "outputs": [],
        "type": "function"
    }
];

const SKILL_TYPES = {
    ATTACK: 0,
    DEFENSE: 1,
    HEAL: 2,
    SPECIAL: 3,
    BUFF: 4,
    DEBUFF: 5,
    COUNTER: 6,
    LIFESTEAL: 7,
    SHIELD: 8
};

const SKILLS = [
    { element: 0, zodiac: 0, gender: 0, name: "烈焰穿梭", type: SKILL_TYPES.ATTACK, value: 125, cooldown: 3, duration: 0, isAoe: false },
    { element: 0, zodiac: 0, gender: 1, name: "炎影反击", type: SKILL_TYPES.COUNTER, value: 110, cooldown: 4, duration: 0, isAoe: false },
    { element: 0, zodiac: 1, gender: 0, name: "焚天巨力", type: SKILL_TYPES.ATTACK, value: 145, cooldown: 5, duration: 0, isAoe: false },
    { element: 0, zodiac: 1, gender: 1, name: "炽焰守护", type: SKILL_TYPES.SHIELD, value: 95, cooldown: 4, duration: 2, isAoe: false },
    { element: 0, zodiac: 2, gender: 0, name: "爆炎猛击", type: SKILL_TYPES.ATTACK, value: 165, cooldown: 5, duration: 0, isAoe: false },
    { element: 0, zodiac: 2, gender: 1, name: "烈焰威慑", type: SKILL_TYPES.DEBUFF, value: 85, cooldown: 4, duration: 2, isAoe: false },
    { element: 0, zodiac: 3, gender: 0, name: "疾风烈焰", type: SKILL_TYPES.ATTACK, value: 130, cooldown: 3, duration: 0, isAoe: false },
    { element: 0, zodiac: 3, gender: 1, name: "火焰跃闪", type: SKILL_TYPES.DEFENSE, value: 80, cooldown: 3, duration: 0, isAoe: false },
    { element: 0, zodiac: 4, gender: 0, name: "龙焰焚天", type: SKILL_TYPES.SPECIAL, value: 220, cooldown: 6, duration: 0, isAoe: true },
    { element: 0, zodiac: 4, gender: 1, name: "炎龙守护", type: SKILL_TYPES.SHIELD, value: 120, cooldown: 5, duration: 2, isAoe: false },
    { element: 0, zodiac: 5, gender: 0, name: "火毒噬咬", type: SKILL_TYPES.LIFESTEAL, value: 115, cooldown: 4, duration: 0, isAoe: false },
    { element: 0, zodiac: 5, gender: 1, name: "烈焰反击", type: SKILL_TYPES.COUNTER, value: 125, cooldown: 4, duration: 0, isAoe: false },
    { element: 0, zodiac: 6, gender: 0, name: "燎原奔踏", type: SKILL_TYPES.ATTACK, value: 140, cooldown: 3, duration: 0, isAoe: false },
    { element: 0, zodiac: 6, gender: 1, name: "火云疾驰", type: SKILL_TYPES.BUFF, value: 85, cooldown: 4, duration: 2, isAoe: false },
    { element: 0, zodiac: 7, gender: 0, name: "圣火治愈", type: SKILL_TYPES.HEAL, value: 110, cooldown: 5, duration: 0, isAoe: false },
    { element: 0, zodiac: 7, gender: 1, name: "烈焰祈福", type: SKILL_TYPES.HEAL, value: 130, cooldown: 6, duration: 0, isAoe: false },
    { element: 0, zodiac: 8, gender: 0, name: "火舞戏耍", type: SKILL_TYPES.ATTACK, value: 115, cooldown: 2, duration: 0, isAoe: false },
    { element: 0, zodiac: 8, gender: 1, name: "赤炎变幻", type: SKILL_TYPES.DEFENSE, value: 90, cooldown: 3, duration: 0, isAoe: false },
    { element: 0, zodiac: 9, gender: 0, name: "火羽锐击", type: SKILL_TYPES.ATTACK, value: 105, cooldown: 3, duration: 0, isAoe: false },
    { element: 0, zodiac: 9, gender: 1, name: "烈焰警戒", type: SKILL_TYPES.BUFF, value: 75, cooldown: 3, duration: 2, isAoe: false },
    { element: 0, zodiac: 10, gender: 0, name: "火獒追击", type: SKILL_TYPES.ATTACK, value: 120, cooldown: 4, duration: 0, isAoe: false },
    { element: 0, zodiac: 10, gender: 1, name: "炎犬反击", type: SKILL_TYPES.COUNTER, value: 115, cooldown: 4, duration: 0, isAoe: false },
    { element: 0, zodiac: 11, gender: 0, name: "火猪纳福", type: SKILL_TYPES.HEAL, value: 140, cooldown: 6, duration: 0, isAoe: false },
    { element: 0, zodiac: 11, gender: 1, name: "烈焰厚积", type: SKILL_TYPES.DEFENSE, value: 100, cooldown: 5, duration: 0, isAoe: false },

    { element: 1, zodiac: 0, gender: 0, name: "疾风穿梭", type: SKILL_TYPES.ATTACK, value: 135, cooldown: 3, duration: 0, isAoe: false },
    { element: 1, zodiac: 0, gender: 1, name: "风影反击", type: SKILL_TYPES.COUNTER, value: 115, cooldown: 4, duration: 0, isAoe: false },
    { element: 1, zodiac: 1, gender: 0, name: "旋风巨力", type: SKILL_TYPES.ATTACK, value: 130, cooldown: 5, duration: 0, isAoe: false },
    { element: 1, zodiac: 1, gender: 1, name: "风之壁垒", type: SKILL_TYPES.SHIELD, value: 105, cooldown: 4, duration: 2, isAoe: false },
    { element: 1, zodiac: 2, gender: 0, name: "暴风猛击", type: SKILL_TYPES.ATTACK, value: 155, cooldown: 5, duration: 0, isAoe: false },
    { element: 1, zodiac: 2, gender: 1, name: "风啸威慑", type: SKILL_TYPES.DEBUFF, value: 90, cooldown: 4, duration: 2, isAoe: false },
    { element: 1, zodiac: 3, gender: 0, name: "风跃突袭", type: SKILL_TYPES.ATTACK, value: 140, cooldown: 3, duration: 0, isAoe: false },
    { element: 1, zodiac: 3, gender: 1, name: "疾风闪避", type: SKILL_TYPES.DEFENSE, value: 100, cooldown: 3, duration: 0, isAoe: false },
    { element: 1, zodiac: 4, gender: 0, name: "风暴龙吟", type: SKILL_TYPES.SPECIAL, value: 210, cooldown: 6, duration: 0, isAoe: true },
    { element: 1, zodiac: 4, gender: 1, name: "风龙护盾", type: SKILL_TYPES.SHIELD, value: 115, cooldown: 5, duration: 2, isAoe: false },
    { element: 1, zodiac: 5, gender: 0, name: "风刃穿刺", type: SKILL_TYPES.ATTACK, value: 125, cooldown: 4, duration: 0, isAoe: false },
    { element: 1, zodiac: 5, gender: 1, name: "旋风反击", type: SKILL_TYPES.COUNTER, value: 120, cooldown: 4, duration: 0, isAoe: false },
    { element: 1, zodiac: 6, gender: 0, name: "追风踏燕", type: SKILL_TYPES.ATTACK, value: 150, cooldown: 3, duration: 0, isAoe: false },
    { element: 1, zodiac: 6, gender: 1, name: "风驰电掣", type: SKILL_TYPES.BUFF, value: 90, cooldown: 3, duration: 2, isAoe: false },
    { element: 1, zodiac: 7, gender: 0, name: "清风治愈", type: SKILL_TYPES.HEAL, value: 105, cooldown: 5, duration: 0, isAoe: false },
    { element: 1, zodiac: 7, gender: 1, name: "风之祈福", type: SKILL_TYPES.HEAL, value: 120, cooldown: 6, duration: 0, isAoe: false },
    { element: 1, zodiac: 8, gender: 0, name: "风猴戏耍", type: SKILL_TYPES.ATTACK, value: 120, cooldown: 2, duration: 0, isAoe: false },
    { element: 1, zodiac: 8, gender: 1, name: "疾风变幻", type: SKILL_TYPES.DEFENSE, value: 95, cooldown: 3, duration: 0, isAoe: false },
    { element: 1, zodiac: 9, gender: 0, name: "风羽振翅", type: SKILL_TYPES.ATTACK, value: 110, cooldown: 3, duration: 0, isAoe: false },
    { element: 1, zodiac: 9, gender: 1, name: "风之警戒", type: SKILL_TYPES.BUFF, value: 80, cooldown: 3, duration: 2, isAoe: false },
    { element: 1, zodiac: 10, gender: 0, name: "风犬追击", type: SKILL_TYPES.ATTACK, value: 125, cooldown: 4, duration: 0, isAoe: false },
    { element: 1, zodiac: 10, gender: 1, name: "疾风反击", type: SKILL_TYPES.COUNTER, value: 110, cooldown: 4, duration: 0, isAoe: false },
    { element: 1, zodiac: 11, gender: 0, name: "风猪纳福", type: SKILL_TYPES.HEAL, value: 130, cooldown: 6, duration: 0, isAoe: false },
    { element: 1, zodiac: 11, gender: 1, name: "风之厚积", type: SKILL_TYPES.DEFENSE, value: 95, cooldown: 5, duration: 0, isAoe: false },

    { element: 2, zodiac: 0, gender: 0, name: "潮涌穿梭", type: SKILL_TYPES.ATTACK, value: 120, cooldown: 3, duration: 0, isAoe: false },
    { element: 2, zodiac: 0, gender: 1, name: "水影反击", type: SKILL_TYPES.COUNTER, value: 105, cooldown: 4, duration: 0, isAoe: false },
    { element: 2, zodiac: 1, gender: 0, name: "巨浪冲击", type: SKILL_TYPES.ATTACK, value: 140, cooldown: 5, duration: 0, isAoe: false },
    { element: 2, zodiac: 1, gender: 1, name: "水之磐石", type: SKILL_TYPES.SHIELD, value: 110, cooldown: 4, duration: 2, isAoe: false },
    { element: 2, zodiac: 2, gender: 0, name: "海啸猛击", type: SKILL_TYPES.ATTACK, value: 160, cooldown: 5, duration: 0, isAoe: false },
    { element: 2, zodiac: 2, gender: 1, name: "寒水威慑", type: SKILL_TYPES.DEBUFF, value: 85, cooldown: 4, duration: 2, isAoe: false },
    { element: 2, zodiac: 3, gender: 0, name: "水跃突袭", type: SKILL_TYPES.ATTACK, value: 135, cooldown: 3, duration: 0, isAoe: false },
    { element: 2, zodiac: 3, gender: 1, name: "碧水闪避", type: SKILL_TYPES.DEFENSE, value: 95, cooldown: 3, duration: 0, isAoe: false },
    { element: 2, zodiac: 4, gender: 0, name: "海啸龙吟", type: SKILL_TYPES.SPECIAL, value: 200, cooldown: 6, duration: 0, isAoe: true },
    { element: 2, zodiac: 4, gender: 1, name: "水龙护盾", type: SKILL_TYPES.SHIELD, value: 110, cooldown: 5, duration: 2, isAoe: false },
    { element: 2, zodiac: 5, gender: 0, name: "毒水噬咬", type: SKILL_TYPES.LIFESTEAL, value: 120, cooldown: 4, duration: 0, isAoe: false },
    { element: 2, zodiac: 5, gender: 1, name: "寒水反击", type: SKILL_TYPES.COUNTER, value: 115, cooldown: 4, duration: 0, isAoe: false },
    { element: 2, zodiac: 6, gender: 0, name: "踏浪奔腾", type: SKILL_TYPES.ATTACK, value: 145, cooldown: 3, duration: 0, isAoe: false },
    { element: 2, zodiac: 6, gender: 1, name: "水之疾驰", type: SKILL_TYPES.BUFF, value: 85, cooldown: 3, duration: 2, isAoe: false },
    { element: 2, zodiac: 7, gender: 0, name: "净水治愈", type: SKILL_TYPES.HEAL, value: 115, cooldown: 5, duration: 0, isAoe: false },
    { element: 2, zodiac: 7, gender: 1, name: "水之祈福", type: SKILL_TYPES.HEAL, value: 135, cooldown: 6, duration: 0, isAoe: false },
    { element: 2, zodiac: 8, gender: 0, name: "水猴戏耍", type: SKILL_TYPES.ATTACK, value: 115, cooldown: 2, duration: 0, isAoe: false },
    { element: 2, zodiac: 8, gender: 1, name: "碧水变幻", type: SKILL_TYPES.DEFENSE, value: 90, cooldown: 3, duration: 0, isAoe: false },
    { element: 2, zodiac: 9, gender: 0, name: "水羽振翅", type: SKILL_TYPES.ATTACK, value: 105, cooldown: 3, duration: 0, isAoe: false },
    { element: 2, zodiac: 9, gender: 1, name: "水之警戒", type: SKILL_TYPES.BUFF, value: 75, cooldown: 3, duration: 2, isAoe: false },
    { element: 2, zodiac: 10, gender: 0, name: "水犬追击", type: SKILL_TYPES.ATTACK, value: 115, cooldown: 4, duration: 0, isAoe: false },
    { element: 2, zodiac: 10, gender: 1, name: "碧水反击", type: SKILL_TYPES.COUNTER, value: 100, cooldown: 4, duration: 0, isAoe: false },
    { element: 2, zodiac: 11, gender: 0, name: "水猪纳福", type: SKILL_TYPES.HEAL, value: 145, cooldown: 6, duration: 0, isAoe: false },
    { element: 2, zodiac: 11, gender: 1, name: "水之厚积", type: SKILL_TYPES.DEFENSE, value: 105, cooldown: 5, duration: 0, isAoe: false },

    { element: 3, zodiac: 0, gender: 0, name: "圣光穿梭", type: SKILL_TYPES.ATTACK, value: 145, cooldown: 3, duration: 0, isAoe: false },
    { element: 3, zodiac: 0, gender: 1, name: "光影反击", type: SKILL_TYPES.COUNTER, value: 135, cooldown: 4, duration: 0, isAoe: false },
    { element: 3, zodiac: 1, gender: 0, name: "光耀巨力", type: SKILL_TYPES.ATTACK, value: 150, cooldown: 5, duration: 0, isAoe: false },
    { element: 3, zodiac: 1, gender: 1, name: "光之壁垒", type: SKILL_TYPES.SHIELD, value: 115, cooldown: 4, duration: 2, isAoe: false },
    { element: 3, zodiac: 2, gender: 0, name: "圣光猛击", type: SKILL_TYPES.ATTACK, value: 165, cooldown: 5, duration: 0, isAoe: false },
    { element: 3, zodiac: 2, gender: 1, name: "光明威慑", type: SKILL_TYPES.DEBUFF, value: 90, cooldown: 4, duration: 2, isAoe: false },
    { element: 3, zodiac: 3, gender: 0, name: "光跃突袭", type: SKILL_TYPES.ATTACK, value: 145, cooldown: 3, duration: 0, isAoe: false },
    { element: 3, zodiac: 3, gender: 1, name: "圣光闪避", type: SKILL_TYPES.DEFENSE, value: 110, cooldown: 3, duration: 0, isAoe: false },
    { element: 3, zodiac: 4, gender: 0, name: "圣光龙吟", type: SKILL_TYPES.SPECIAL, value: 245, cooldown: 6, duration: 0, isAoe: true },
    { element: 3, zodiac: 4, gender: 1, name: "光龙护盾", type: SKILL_TYPES.SHIELD, value: 140, cooldown: 5, duration: 2, isAoe: false },
    { element: 3, zodiac: 5, gender: 0, name: "光刃穿刺", type: SKILL_TYPES.ATTACK, value: 135, cooldown: 4, duration: 0, isAoe: false },
    { element: 3, zodiac: 5, gender: 1, name: "圣光反击", type: SKILL_TYPES.COUNTER, value: 140, cooldown: 4, duration: 0, isAoe: false },
    { element: 3, zodiac: 6, gender: 0, name: "踏光而行", type: SKILL_TYPES.ATTACK, value: 160, cooldown: 3, duration: 0, isAoe: false },
    { element: 3, zodiac: 6, gender: 1, name: "光明疾驰", type: SKILL_TYPES.BUFF, value: 100, cooldown: 3, duration: 2, isAoe: false },
    { element: 3, zodiac: 7, gender: 0, name: "圣光治愈", type: SKILL_TYPES.HEAL, value: 140, cooldown: 5, duration: 0, isAoe: false },
    { element: 3, zodiac: 7, gender: 1, name: "光之祈福", type: SKILL_TYPES.HEAL, value: 160, cooldown: 6, duration: 0, isAoe: false },
    { element: 3, zodiac: 8, gender: 0, name: "灵猴戏耍", type: SKILL_TYPES.ATTACK, value: 140, cooldown: 2, duration: 0, isAoe: false },
    { element: 3, zodiac: 8, gender: 1, name: "圣光变幻", type: SKILL_TYPES.DEFENSE, value: 115, cooldown: 3, duration: 0, isAoe: false },
    { element: 3, zodiac: 9, gender: 0, name: "光羽振翅", type: SKILL_TYPES.ATTACK, value: 130, cooldown: 3, duration: 0, isAoe: false },
    { element: 3, zodiac: 9, gender: 1, name: "光之警戒", type: SKILL_TYPES.BUFF, value: 95, cooldown: 3, duration: 2, isAoe: false },
    { element: 3, zodiac: 10, gender: 0, name: "圣犬追击", type: SKILL_TYPES.ATTACK, value: 145, cooldown: 4, duration: 0, isAoe: false },
    { element: 3, zodiac: 10, gender: 1, name: "圣光反击", type: SKILL_TYPES.COUNTER, value: 130, cooldown: 4, duration: 0, isAoe: false },
    { element: 3, zodiac: 11, gender: 0, name: "圣猪纳福", type: SKILL_TYPES.HEAL, value: 165, cooldown: 6, duration: 0, isAoe: false },
    { element: 3, zodiac: 11, gender: 1, name: "光之厚积", type: SKILL_TYPES.DEFENSE, value: 115, cooldown: 5, duration: 0, isAoe: false },

    { element: 4, zodiac: 0, gender: 0, name: "暗影穿梭", type: SKILL_TYPES.ATTACK, value: 150, cooldown: 3, duration: 0, isAoe: false },
    { element: 4, zodiac: 0, gender: 1, name: "幽冥反击", type: SKILL_TYPES.COUNTER, value: 140, cooldown: 4, duration: 0, isAoe: false },
    { element: 4, zodiac: 1, gender: 0, name: "暗影重击", type: SKILL_TYPES.ATTACK, value: 155, cooldown: 5, duration: 0, isAoe: false },
    { element: 4, zodiac: 1, gender: 1, name: "冥之壁垒", type: SKILL_TYPES.SHIELD, value: 110, cooldown: 4, duration: 2, isAoe: false },
    { element: 4, zodiac: 2, gender: 0, name: "暗影猛击", type: SKILL_TYPES.ATTACK, value: 170, cooldown: 5, duration: 0, isAoe: false },
    { element: 4, zodiac: 2, gender: 1, name: "幽冥威慑", type: SKILL_TYPES.DEBUFF, value: 100, cooldown: 4, duration: 2, isAoe: false },
    { element: 4, zodiac: 3, gender: 0, name: "暗跃突袭", type: SKILL_TYPES.ATTACK, value: 155, cooldown: 3, duration: 0, isAoe: false },
    { element: 4, zodiac: 3, gender: 1, name: "暗影闪避", type: SKILL_TYPES.DEFENSE, value: 115, cooldown: 3, duration: 0, isAoe: false },
    { element: 4, zodiac: 4, gender: 0, name: "暗影龙吟", type: SKILL_TYPES.SPECIAL, value: 255, cooldown: 6, duration: 0, isAoe: true },
    { element: 4, zodiac: 4, gender: 1, name: "暗龙护盾", type: SKILL_TYPES.SHIELD, value: 130, cooldown: 5, duration: 2, isAoe: false },
    { element: 4, zodiac: 5, gender: 0, name: "暗影吞噬", type: SKILL_TYPES.LIFESTEAL, value: 145, cooldown: 4, duration: 0, isAoe: false },
    { element: 4, zodiac: 5, gender: 1, name: "幽冥反击", type: SKILL_TYPES.COUNTER, value: 145, cooldown: 4, duration: 0, isAoe: false },
    { element: 4, zodiac: 6, gender: 0, name: "踏冥奔腾", type: SKILL_TYPES.ATTACK, value: 165, cooldown: 3, duration: 0, isAoe: false },
    { element: 4, zodiac: 6, gender: 1, name: "暗影疾驰", type: SKILL_TYPES.BUFF, value: 105, cooldown: 3, duration: 2, isAoe: false },
    { element: 4, zodiac: 7, gender: 0, name: "暗影治愈", type: SKILL_TYPES.HEAL, value: 125, cooldown: 5, duration: 0, isAoe: false },
    { element: 4, zodiac: 7, gender: 1, name: "冥之祈福", type: SKILL_TYPES.HEAL, value: 140, cooldown: 6, duration: 0, isAoe: false },
    { element: 4, zodiac: 8, gender: 0, name: "冥猴戏耍", type: SKILL_TYPES.ATTACK, value: 135, cooldown: 2, duration: 0, isAoe: false },
    { element: 4, zodiac: 8, gender: 1, name: "暗影变幻", type: SKILL_TYPES.DEFENSE, value: 110, cooldown: 3, duration: 0, isAoe: false },
    { element: 4, zodiac: 9, gender: 0, name: "暗羽振翅", type: SKILL_TYPES.ATTACK, value: 125, cooldown: 3, duration: 0, isAoe: false },
    { element: 4, zodiac: 9, gender: 1, name: "冥之警戒", type: SKILL_TYPES.BUFF, value: 95, cooldown: 3, duration: 2, isAoe: false },
    { element: 4, zodiac: 10, gender: 0, name: "冥犬追击", type: SKILL_TYPES.ATTACK, value: 150, cooldown: 4, duration: 0, isAoe: false },
    { element: 4, zodiac: 10, gender: 1, name: "暗影反击", type: SKILL_TYPES.COUNTER, value: 135, cooldown: 4, duration: 0, isAoe: false },
    { element: 4, zodiac: 11, gender: 0, name: "冥猪纳福", type: SKILL_TYPES.HEAL, value: 150, cooldown: 6, duration: 0, isAoe: false },
    { element: 4, zodiac: 11, gender: 1, name: "冥之厚积", type: SKILL_TYPES.DEFENSE, value: 110, cooldown: 5, duration: 0, isAoe: false }
];

async function initSkills() {
    const web3 = new Web3('http://localhost:8545');
    const battleContractAddress = '0xYourBattleContractAddress';
    const ownerPrivateKey = '0xYourOwnerPrivateKey';
    
    const account = web3.eth.accounts.privateKeyToAccount(ownerPrivateKey);
    web3.eth.accounts.wallet.add(account);
    
    const battleContract = new web3.eth.Contract(BATTLE_ABI, battleContractAddress);
    
    console.log('Initializing skills...');
    let count = 0;
    
    for (const skill of SKILLS) {
        try {
            const tx = await battleContract.methods.setSkill(
                skill.element,
                skill.zodiac,
                skill.gender,
                [skill.name, skill.type, skill.value, skill.cooldown, skill.duration, skill.isAoe]
            ).send({
                from: account.address,
                gas: 100000
            });
            
            count++;
            if (count % 10 === 0) {
                console.log(`Initialized ${count}/120 skills`);
            }
        } catch (error) {
            console.error(`Failed to set skill ${skill.name}:`, error.message);
        }
    }
    
    console.log(`Successfully initialized ${count}/120 skills`);
}

initSkills().catch(console.error);
