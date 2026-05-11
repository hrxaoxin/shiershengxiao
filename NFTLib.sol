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
}