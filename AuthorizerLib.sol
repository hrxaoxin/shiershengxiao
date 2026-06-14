// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";

library AuthorizerLib {
    /**
     * @dev 批量设置多个合约的 authorizer
     * @param addrs 合约地址数组
     * @param names 合约名称数组（用于事件日志）
     * @param newAuthorizer 新的 authorizer 地址
     */
    function batchSetAuthorizer(
        address[] memory addrs,
        string[] memory names,
        address newAuthorizer
    ) internal {
        uint256 len = addrs.length;
        for (uint256 i = 0; i < len; i++) {
            if (addrs[i] != address(0)) {
                try ISetAuthorizer(addrs[i]).setAuthorizer(newAuthorizer) {
                    emit ContractSetupSuccess(names[i]);
                } catch Error(string memory reason) {
                    emit ContractSetupFailed(names[i], reason);
                } catch {
                    emit ContractSetupFailed(names[i], "Unknown");
                }
            }
        }
    }

    /**
     * @dev 设置单个合约的 authorizer
     * @param addr 合约地址
     * @param name 合约名称
     * @param newAuthorizer 新的 authorizer 地址
     */
    function setSingleAuthorizer(
        address addr,
        string memory name,
        address newAuthorizer
    ) internal {
        if (addr != address(0)) {
            try ISetAuthorizer(addr).setAuthorizer(newAuthorizer) {
                emit ContractSetupSuccess(name);
            } catch Error(string memory reason) {
                emit ContractSetupFailed(name, reason);
            } catch {
                emit ContractSetupFailed(name, "Unknown");
            }
        }
    }

    event ContractSetupSuccess(string contractName);
    event ContractSetupFailed(string contractName, string reason);
}