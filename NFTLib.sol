// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library NFTLib {
    function uint2str(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        uint256 temp = n;
        uint256 len;
        while (temp != 0) { len++; temp /= 10; }
        bytes memory buf = new bytes(len);
        while (n != 0) { len--; buf[len] = bytes1(uint8(48 + n % 10)); n /= 10; }
        return string(buf);
    }

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

    function concat(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function concat3(string memory a, string memory b, string memory c) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b, c));
    }

    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(a >= b, "NFTLib: Underflow in subtraction");
        return a - b;
    }

    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        require(a <= type(uint256).max - b, "NFTLib: Overflow in addition");
        return a + b;
    }

    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        require(a <= type(uint256).max / b, "NFTLib: Overflow in multiplication");
        return a * b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function calculateWeightDelta(uint8 level) internal pure returns (uint256) {
        if (level == 1) return 1;
        if (level == 2) return 2;
        if (level == 3) return 4;
        if (level == 4) return 12;
        if (level == 5) return 48;
        return 0;
    }

    function updateUserWeightValue(uint256 currentWeight, uint8 level, bool add) internal pure returns (uint256) {
        uint256 weightDelta = calculateWeightDelta(level);
        if (add) {
            return currentWeight + weightDelta;
        } else {
            return currentWeight >= weightDelta ? currentWeight - weightDelta : 0;
        }
    }
}