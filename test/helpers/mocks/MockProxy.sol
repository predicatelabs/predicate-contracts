// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockProxyAdmin} from "./MockProxyAdmin.sol";

contract MockProxy is TransparentUpgradeableProxy {
    constructor(
        address _implementation,
        address _admin
    ) TransparentUpgradeableProxy(_implementation, _admin, bytes("")) {}
}
