// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTInterface.sol";

/**
 * @title AuthorizerLib
 * @dev 授权管理器工具库，提供动态批量通知业务合约更新 authorizer 地址的辅助函数
 *
 * 注意：Authorizer 合约本身已内置 notifyAllContractsSetAuthorizer 一键函数，
 * 基于内部动态注册表遍历，推荐直接使用 Authorizer 合约的内置方法。
 * 本库提供的 setupAuthorizersDynamic 适用于需要外部离线批量设置的场景。
 */
library AuthorizerLib {
    /**
     * @dev 动态模式：使用地址数组一键通知所有业务合约更新 authorizer
     * 不依赖固定索引顺序，支持任意数量和顺序的合约
     * 每个合约如果实现了 ISetAuthorizer 接口，会自动调用 setAuthorizer
     * 不支持的合约会静默跳过（try/catch）
     * @param _newAuthorizer 新的 authorizer 地址
     * @param _addrs 合约地址数组
     */
    function setupAuthorizers(address _newAuthorizer, address[] calldata _addrs) external {
        for (uint256 i = 0; i < _addrs.length; i++) {
            if (_addrs[i] != address(0)) {
                try ISetAuthorizer(_addrs[i]).setAuthorizer(_newAuthorizer) {
                    // success
                } catch {
                    // skip contracts that don't support ISetAuthorizer
                }
            }
        }
    }
}
