// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract MockProxyAdmin is ProxyAdmin {
    constructor(
        address _owner
    ) ProxyAdmin(_owner) {}
}
