// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IDecimalConvertible.sol";

abstract contract DecimalConvertibleUpgradeable is
    IDecimalConvertible,
    Initializable
{
    /// @custom:storage-location erc7201:toki.storage.DecimalConvertibleUpgradeable
    struct DecimalConvertibleUpgradeableStorage {
        uint8 _globalDecimals; // the global decimals (lowest common decimals between chains).
        uint8 _localDecimals; // the local decimals for the token (eg. USDT: 6 decimals)
        uint256 _convertRate; // the decimals for the token (eg. USDT->globalDecimals: 12 decimals)
    }

    // keccak256(abi.encode(uint256(keccak256("toki.storage.DecimalConvertibleUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DECIMAL_CONVERTIBLE_UPGRADEABLE_STORAGE_LOCATION =
        0x363bd9d3ac01b05edede66fbb9c4f73d99f1481666c51eee8df34d23a61f4800;

    function globalDecimals() public view override returns (uint8) {
        return _getDecimalConvertibleUpgradeableStorage()._globalDecimals;
    }

    function localDecimals() public view override returns (uint8) {
        return _getDecimalConvertibleUpgradeableStorage()._localDecimals;
    }

    function convertRate() public view override returns (uint256) {
        return _getDecimalConvertibleUpgradeableStorage()._convertRate;
    }

    /* solhint-disable func-name-mixedcase */
    function __DecimalConvertible_init(
        uint8 globalDecimals_,
        uint8 localDecimals_
    ) internal onlyInitializing {
        __DecimalConvertible_init_unchained(globalDecimals_, localDecimals_);
    }

    function __DecimalConvertible_init_unchained(
        uint8 globalDecimals_,
        uint8 localDecimals_
    ) internal onlyInitializing {
        DecimalConvertibleUpgradeableStorage
            storage $ = _getDecimalConvertibleUpgradeableStorage();

        $._globalDecimals = globalDecimals_;
        $._localDecimals = localDecimals_;
        $._convertRate =
            10 ** ((uint256($._localDecimals) - uint256($._globalDecimals)));
    }

    function _GDToLD(uint256 _amountGD) internal view returns (uint256) {
        return
            _amountGD * _getDecimalConvertibleUpgradeableStorage()._convertRate;
    }

    function _LDToGD(uint256 _amountLD) internal view returns (uint256) {
        return
            _amountLD / _getDecimalConvertibleUpgradeableStorage()._convertRate;
    }

    function _getDecimalConvertibleUpgradeableStorage()
        private
        pure
        returns (DecimalConvertibleUpgradeableStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := DECIMAL_CONVERTIBLE_UPGRADEABLE_STORAGE_LOCATION
        }
    }
}
