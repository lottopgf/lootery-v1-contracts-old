// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Lootery} from "./Lootery.sol";

/// @title LooteryFactory
/// @notice Launch your own lottos to fund your Troop!
contract LooteryFactory is UUPSUpgradeable, AccessControlUpgradeable {
    using StorageSlot for bytes32;

    // keccak256("troops.lootery_factory.lootery_master_copy");
    bytes32 public constant LOOTERY_MASTER_COPY_SLOT =
        0x15244694a038682b3dfdfc9a7b4d57f194bac87a538c298bbb15836f93f3d08e;
    // keccak256("troops.lootery_factory.randomiser");
    bytes32 public constant RANDOMISER_SLOT =
        0x7fd620ff951c5553351af243f95586d6c40fbde77386fa401565df721194304b;
    // keccak256("troops.lootery_factory.nonce");
    bytes32 public constant NONCE_SLOT =
        0xb673313ff65da5deee919e9043f9d191abd6721ce5d457fcf870135fe1bceb99;

    event LooteryLaunched(
        address indexed looteryProxy,
        address indexed looteryImplementation,
        address indexed deployer,
        string name
    );
    event RandomiserUpdated(address oldRandomiser, address newRandomiser);

    constructor() {
        _disableInitializers();
    }

    /// @notice Initialisoooooor!!! NB: Caller becomes admin.
    /// @param looteryMasterCopy Initial mastercopy of the Lootery contract
    /// @param randomiser The randomiser to be deployed with each Lootery
    function init(
        address looteryMasterCopy,
        address randomiser
    ) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();

        LOOTERY_MASTER_COPY_SLOT.getAddressSlot().value = looteryMasterCopy;
        RANDOMISER_SLOT.getAddressSlot().value = randomiser;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice See {UUPSUpgradeable-_authorizeUpgrade}
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function setRandomiser(
        address randomiser
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldRandomiser = RANDOMISER_SLOT.getAddressSlot().value;
        RANDOMISER_SLOT.getAddressSlot().value = randomiser;
        emit RandomiserUpdated(oldRandomiser, randomiser);
    }

    function getRandomiser() external view returns (address) {
        return RANDOMISER_SLOT.getAddressSlot().value;
    }

    /// @notice Compute salt used in computing deployment addresses
    function computeSalt(uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(nonce, "lootery"));
    }

    /// @notice Compute the address at which the next lotto will be deployed
    function computeNextAddress() external view returns (address) {
        uint256 nonce = NONCE_SLOT.getUint256Slot().value;
        bytes32 salt = computeSalt(nonce);
        return
            Clones.predictDeterministicAddress(
                LOOTERY_MASTER_COPY_SLOT.getAddressSlot().value,
                salt
            );
    }

    /// @notice Launch your own lotto
    /// @param name Name of the lotto (also used for ticket NFTs)
    /// @param symbol Symbol of the lotto (used for ticket NFTs)
    /// @param numPicks Number of balls that must be picked per draw
    /// @param maxBallValue Maximum value that a picked ball can have
    ///     (excludes 0)
    /// @param gamePeriod The number of seconds that must pass before a draw
    ///     can be initiated.
    /// @param ticketPrice Price per ticket
    /// @param communityFeeBps The percentage of the ticket price that should
    ///     be taken and accrued for the lotto owner.
    /// @param prizeToken The ERC-20 token that will be used as the prize token
    ///     and also the token that will be used to pay for tickets.
    /// @param seedJackpotDelay The number of seconds that must pass before the
    ///     jackpot can be seeded again.
    /// @param seedJackpotMinValue The minimum value that the jackpot must be
    ///     seeded with.
    function create(
        string memory name,
        string memory symbol,
        uint8 numPicks,
        uint8 maxBallValue,
        uint256 gamePeriod,
        uint256 ticketPrice,
        uint256 communityFeeBps,
        address prizeToken,
        uint256 seedJackpotDelay,
        uint256 seedJackpotMinValue
    ) external returns (address) {
        uint256 nonce = NONCE_SLOT.getUint256Slot().value++;
        bytes32 salt = computeSalt(nonce);
        address looteryMasterCopy = LOOTERY_MASTER_COPY_SLOT
            .getAddressSlot()
            .value;
        // Deploy & init proxy
        address payable looteryProxy = payable(
            Clones.cloneDeterministic(looteryMasterCopy, salt)
        );
        Lootery(looteryProxy).init(
            Lootery.InitConfig({
                owner: msg.sender,
                name: name,
                symbol: symbol,
                numPicks: numPicks,
                maxBallValue: maxBallValue,
                gamePeriod: gamePeriod,
                ticketPrice: ticketPrice,
                communityFeeBps: communityFeeBps,
                randomiser: RANDOMISER_SLOT.getAddressSlot().value,
                prizeToken: prizeToken,
                seedJackpotDelay: seedJackpotDelay,
                seedJackpotMinValue: seedJackpotMinValue
            })
        );
        emit LooteryLaunched(looteryProxy, looteryMasterCopy, msg.sender, name);
        return looteryProxy;
    }
}
