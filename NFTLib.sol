// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTLib
 * @dev NFT工具库，提供字符串处理、数学运算等辅助函数
 */
library NFTLib {
    /**
     * @dev 将无符号整数转换为字符串
     * @param n 要转换的整数
     * @return string memory 转换后的字符串
     */
    function uint2str(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        uint256 temp = n;
        uint256 len;
        while (temp != 0) { len++; temp /= 10; }
        bytes memory buf = new bytes(len);
        while (n != 0) { len--; buf[len] = bytes1(uint8(48 + n % 10)); n /= 10; }
        return string(buf);
    }

    /**
     * @dev 将以太坊地址转换为十六进制字符串
     * @param _addr 要转换的地址
     * @return string memory 转换后的十六进制字符串（以0x开头）
     */
    function addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0'; str[1] = 'x';
        for (uint i = 0; i < 20; i++) {
            str[2+i*2] = alphabet[uint8(value[i+12] >> 4)];
            str[3+i*2] = alphabet[uint8(value[i+12] & 0x0f)];
        }
        return string(str);
    }

    /**
     * @dev Base64编码函数
     * @param data 要编码的原始字节数据
     * @return string memory Base64编码后的字符串
     */
    function base64Encode(bytes memory data) internal pure returns (string memory) {
        bytes memory base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        bytes memory result = new bytes((data.length + 2) / 3 * 4);
        uint cursor = 0;
        for (uint i = 0; i < data.length; i += 3) {
            uint b0 = uint8(data[i]);
            uint b1 = i+1 < data.length ? uint8(data[i+1]) : 0;
            uint b2 = i+2 < data.length ? uint8(data[i+2]) : 0;
            uint chunk = (b0 << 16) | (b1 << 8) | b2;
            result[cursor++] = base64[(chunk >> 18) & 0x3F];
            result[cursor++] = base64[(chunk >> 12) & 0x3F];
            result[cursor++] = base64[(chunk >> 6) & 0x3F];
            result[cursor++] = base64[chunk & 0x3F];
        }
        if (data.length % 3 == 1) { result[cursor-2] = '='; result[cursor-1] = '='; }
        else if (data.length % 3 == 2) { result[cursor-1] = '='; }
        return string(result);
    }

    /**
     * @dev 转义字符串中的特殊字符（双引号和反斜杠）
     * @param input 输入字符串
     * @return string memory 转义后的字符串
     */
    function escapeString(string memory input) internal pure returns (string memory) {
        bytes memory b = bytes(input);
        uint esc;
        for (uint i; i<b.length; i++) { if (b[i] == '"' || b[i] == '\\') esc++; }
        if (esc == 0) return input;
        bytes memory o = new bytes(b.length + esc);
        uint j;
        for (uint i; i<b.length; i++) {
            if (b[i] == '"' || b[i] == '\\') o[j++] = '\\';
            o[j++] = b[i];
        }
        return string(o);
    }

    /**
     * @dev 连接两个字符串
     * @param a 第一个字符串
     * @param b 第二个字符串
     * @return string memory 连接后的字符串
     */
    function concat(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    /**
     * @dev 连接三个字符串
     * @param a 第一个字符串
     * @param b 第二个字符串
     * @param c 第三个字符串
     * @return string memory 连接后的字符串
     */
    function concat3(string memory a, string memory b, string memory c) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b, c));
    }

    /**
     * @dev 安全减法，防止下溢
     * @param a 被减数
     * @param b 减数
     * @return uint256 差
     */
    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(a >= b, "NFTLib: Underflow in subtraction");
        return a - b;
    }

    /**
     * @dev 安全加法，防止溢出
     * @param a 被加数
     * @param b 加数
     * @return uint256 和
     */
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        require(a <= type(uint256).max - b, "NFTLib: Overflow in addition");
        return a + b;
    }

    /**
     * @dev 安全乘法，防止溢出
     * @param a 被乘数
     * @param b 乘数
     * @return uint256 积
     */
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        require(a <= type(uint256).max / b, "NFTLib: Overflow in multiplication");
        return a * b;
    }

    /**
     * @dev 返回两个数中的较小值
     * @param a 第一个数
     * @param b 第二个数
     * @return uint256 较小值
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev 返回两个数中的较大值
     * @param a 第一个数
     * @param b 第二个数
     * @return uint256 较大值
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev 计算NFT等级对应的权重增量
     * 权重规则：1阶=1, 2阶=2, 3阶=4, 4阶=12, 5阶=48
     * @param level NFT等级（1-5）
     * @return uint256 权重增量
     */
    function calculateWeightDelta(uint8 level) internal pure returns (uint256) {
        if (level == 1) return 1;
        if (level == 2) return 2;
        if (level == 3) return 4;
        if (level == 4) return 12;
        if (level == 5) return 48;
        return 0;
    }

    /**
     * @dev 更新用户权重值
     * @param currentWeight 当前权重
     * @param level NFT等级
     * @param add 是否增加权重（true增加，false减少）
     * @return uint256 更新后的权重
     */
    function updateUserWeightValue(uint256 currentWeight, uint8 level, bool add) internal pure returns (uint256) {
        uint256 weightDelta = calculateWeightDelta(level);
        if (add) {
            return currentWeight + weightDelta;
        } else {
            return currentWeight >= weightDelta ? currentWeight - weightDelta : 0;
        }
    }
}