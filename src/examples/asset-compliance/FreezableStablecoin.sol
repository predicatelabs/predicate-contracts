// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Freezable} from "../../Freezable.sol";

/**
 * @title FreezableStablecoin
 * @author Predicate Labs, Inc (https://predicate.io)
 * @notice Upgradeable ERC-20 with onchain freeze enforcement, pause, role-gated mint/burn, and
 *         a forced-transfer seize. Frozen accounts cannot send or receive.
 * @dev Implements {IFreezable} via the {Freezable} base; the freeze check lives in {_update}.
 *      FREEZE_MANAGER_ROLE (granted to Predicate) only freezes and unfreezes; seize, pause,
 *      mint, burn, and upgrades are separate, issuer-held roles. See docs/asset-compliance.md
 *      for the role model and integration steps.
 */
contract FreezableStablecoin is
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    Freezable
{
    /* ============ Roles ============ */

    /// @notice Role allowed to perform compliance seizures (forced transfers). Issuer-held; never granted to Predicate.
    bytes32 public constant FORCED_TRANSFER_MANAGER_ROLE = keccak256("FORCED_TRANSFER_MANAGER_ROLE");

    /// @notice Role allowed to pause/unpause all transfers.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role allowed to mint new supply.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role allowed to burn supply.
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /* ============ Events ============ */

    /**
     * @notice Emitted when a compliance seizure moves a frozen account's balance.
     * @param from The frozen account funds were seized from.
     * @param to The recipient of the seized funds (e.g. an issuer treasury).
     * @param amount The amount seized.
     */
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount);

    /* ============ Errors ============ */

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress();

    /// @notice Thrown when batch input arrays have mismatched lengths.
    error LengthMismatch();

    /* ============ Constructor / Initializer ============ */

    /// @dev Locks the implementation; state is initialized on the proxy via {initialize}.
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the token and assigns roles to distinct holders (least privilege).
     * @param name_ ERC-20 name.
     * @param symbol_ ERC-20 symbol.
     * @param admin DEFAULT_ADMIN_ROLE holder (role admin + upgrade authority).
     * @param freezeManager FREEZE_MANAGER_ROLE holder — grant this to Predicate's freezer.
     * @param pauser PAUSER_ROLE holder.
     * @param forcedTransferManager FORCED_TRANSFER_MANAGER_ROLE holder (seize) — keep issuer-side.
     * @param minter MINTER_ROLE holder.
     * @param burner BURNER_ROLE holder.
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address admin,
        address freezeManager,
        address pauser,
        address forcedTransferManager,
        address minter,
        address burner
    ) external initializer {
        if (admin == address(0)) revert ZeroAddress();

        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Freezable_init(freezeManager); // grants FREEZE_MANAGER_ROLE to `freezeManager`

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(FORCED_TRANSFER_MANAGER_ROLE, forcedTransferManager);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(BURNER_ROLE, burner);
    }

    /* ============ Supply Management (issuer-only) ============ */

    /**
     * @notice Mints `amount` to `to`. Reverts if `to` is frozen or the token is paused.
     * @dev Routes through {_update}, so compliance checks apply to minting.
     */
    function mint(
        address to,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burns `amount` from `from`. Reverts if `from` is frozen or the token is paused.
     * @dev To retire a sanctioned balance, first {forceTransfer} it to a treasury, then burn there.
     */
    function burn(
        address from,
        uint256 amount
    ) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    /* ============ Pause (issuer-only) ============ */

    /// @notice Pauses all ordinary transfers, mints, and burns.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes ordinary transfers.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /* ============ Seize / Forced Transfer (issuer-only) ============ */

    /**
     * @notice Seizes `amount` from a frozen `from` and moves it to `to`.
     * @dev The source MUST already be frozen — this enforces the freeze-then-seize workflow and
     *      keeps the two powers in different hands (Predicate freezes; the issuer seizes).
     *      Intentionally bypasses the pause and frozen checks (see {_forceTransfer}).
     */
    function forceTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyRole(FORCED_TRANSFER_MANAGER_ROLE) {
        _forceTransfer(from, to, amount);
    }

    /**
     * @notice Batch variant of {forceTransfer}.
     * @dev All input arrays must have equal length.
     */
    function forceTransfers(
        address[] calldata froms,
        address[] calldata tos,
        uint256[] calldata amounts
    ) external onlyRole(FORCED_TRANSFER_MANAGER_ROLE) {
        if (froms.length != tos.length || froms.length != amounts.length) revert LengthMismatch();
        for (uint256 i; i < froms.length; ++i) {
            _forceTransfer(froms[i], tos[i], amounts[i]);
        }
    }

    /* ============ Transfers ============ */

    /**
     * @notice ERC-20 `transferFrom` with an added check that the spender is not frozen.
     * @dev {_update} already blocks a frozen `from` or `to`; this additionally blocks a frozen
     *      spender from moving a third party's funds (a sanctioned operator must not be able to
     *      initiate transfers it has an allowance for).
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override returns (bool) {
        _revertIfFrozen(_msgSender());
        return super.transferFrom(from, to, value);
    }

    /* ============ View ============ */

    /// @inheritdoc ERC20Upgradeable
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /* ============ Internal ============ */

    /**
     * @dev Compliance hook for all balance movements (transfers, mints, burns).
     *      Blocks the movement when the token is paused or when either party is frozen.
     *      Seizures call `super._update` directly and therefore skip this override on purpose.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        _requireNotPaused();
        _revertIfFrozen(from);
        _revertIfFrozen(to);
        super._update(from, to, value);
    }

    /**
     * @dev Executes a seizure. Requires the source to be frozen, then calls `super._update`
     *      directly to bypass the pause/frozen guards in {_update} — a compliance seizure must
     *      succeed precisely when the account is frozen (and even while the token is paused).
     */
    function _forceTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        if (to == address(0)) revert ZeroAddress();
        _revertIfNotFrozen(from); // seize only operates on already-frozen accounts
        super._update(from, to, amount);
        emit ForcedTransfer(from, to, amount);
    }

    /// @dev Restricts upgrades to the admin (UUPS).
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
