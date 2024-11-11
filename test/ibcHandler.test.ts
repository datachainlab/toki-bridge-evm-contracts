import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("OwnableIBCHandlerUpgradeable", function () {
    it("Should be upgraded", async function () {
        const OwnableIBCHandlerUpgradeable = await ethers.getContractFactory("OwnableIBCHandlerUpgradeable");

        const ownableIBCHandlerUpgradeable = await upgrades.deployProxy(
            OwnableIBCHandlerUpgradeable,
            [],
            {
                kind: "uups",
                redeployImplementation: "always",
                unsafeAllow: ["constructor", "delegatecall", "state-variable-immutable"],
                constructorArgs: [ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress]
            });
        await ownableIBCHandlerUpgradeable.waitForDeployment();

        expect(await ownableIBCHandlerUpgradeable.getAddress()).to.not.empty;

        const upgradedOwnableIBCHandlerUpgradeable = await upgrades.upgradeProxy(
            await ownableIBCHandlerUpgradeable.getAddress(),
            OwnableIBCHandlerUpgradeable,
            {
                kind: "uups",
                redeployImplementation: "always",
                unsafeAllow: ["constructor", "delegatecall", "state-variable-immutable"],
                constructorArgs: [ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress]
            }
        );

        expect(await upgradedOwnableIBCHandlerUpgradeable.getAddress()).to.not.empty;
    });
});

