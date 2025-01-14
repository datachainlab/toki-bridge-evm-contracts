// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardTransientUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import "./TokiToken.sol";
import "../DecimalConvertibleUpgradeable.sol";
import "../StaticFlowRateLimiter.sol";
import "../interfaces/ITokiErrors.sol";
import "./interfaces/ITokenEscrow.sol";

contract TokiEscrow is
    ITokiErrors,
    DecimalConvertibleUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    ITokenEscrow,
    StaticFlowRateLimiter
{
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    TokiToken public tokiToken;
    mapping(uint256 => bool) public acceptedDstChainIds;

    /* ========== EVENTS ========== */
    event TokiTokenSet(address indexed newTokiToken);

    event TransferToken(
        uint256 indexed dstChainId,
        address indexed from,
        uint256 amountLD
    );

    event ReceiveToken(address indexed to, uint256 amountLD);

    event SetAcceptedDstChainId(uint256 chainId, bool accepted);

    event SetDstFlowRateLimiter(address dstFlowRateLimiter);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        uint256 period,
        uint256 lockPeriod,
        uint256 limit,
        uint256 threshold
    ) StaticFlowRateLimiter(period, lockPeriod, limit, threshold) {}

    function initialize(
        TokiToken tokiToken_,
        address admin,
        address bridge,
        uint8 globalDecimals_,
        uint8 localDecimals_
    ) public initializer {
        __DecimalConvertible_init(globalDecimals_, localDecimals_);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuardTransient_init();
        __StaticFlowRateLimiter_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_ROLE, bridge);
        _setTokiToken(tokiToken_);
    }

    // ADMIN FUNCTIONS

    function setTokiToken(
        TokiToken tokiToken_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTokiToken(tokiToken_);
    }

    function setAcceptedDstChainId(
        uint256 chainId,
        bool accepted
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        acceptedDstChainIds[chainId] = accepted;
        emit SetAcceptedDstChainId(chainId, accepted);
    }

    // ROUTER FUNCTIONS
    // Source function
    // 1. Source: transferToken
    // ----------------
    // 2. Dest  : receiveToken
    function transferToken(
        uint256 dstChainId,
        address from,
        uint256 amountLD
    ) external nonReentrant onlyRole(BRIDGE_ROLE) returns (uint256 amountGD) {
        if (!acceptedDstChainIds[dstChainId]) {
            revert TokiDstChainIdNotAccepted(dstChainId);
        }
        uint256 balance = tokiToken.balanceOf(from);
        if (balance < amountLD) {
            revert TokiInsufficientAmount("balance", balance, amountLD);
        }
        amountGD = _LDToGD(amountLD);
        tokiToken.burn(from, amountLD);
        emit TransferToken(dstChainId, from, amountLD);
        return amountGD;
    }

    function receiveToken(
        address to,
        uint256 amountGD
    ) external nonReentrant onlyRole(BRIDGE_ROLE) {
        uint256 amountLD = _GDToLD(amountGD);

        if (!_checkAndUpdateFlowRateLimit(amountLD)) {
            revert TokiFlowRateLimitExceed(
                currentPeriodAmount(),
                amountLD,
                LIMIT
            );
        }
        tokiToken.mint(to, amountLD);
        emit ReceiveToken(to, amountLD);
    }

    function token() external view returns (address) {
        return address(tokiToken);
    }

    function _setTokiToken(TokiToken tokiToken_) internal {
        tokiToken = tokiToken_;
        emit TokiTokenSet(address(tokiToken_));
    }

    // UUPSUpgradeable
    function _authorizeUpgrade(
        address
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
