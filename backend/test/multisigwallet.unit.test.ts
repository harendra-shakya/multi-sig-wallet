import { BigNumber, Contract, ContractFactory } from "ethers";
import { expect, assert } from "chai";
const { ethers, network } = require("hardhat");

describe("contract tests", function () {
    const amount = ethers.utils.parseEther("1");
    let wallet: Contract, user: Contract, user2: Contract;

    beforeEach(async function () {
        const accounts = await ethers.getSigners(2);
        user = accounts[0];
        user2 = accounts[1];

        const walletFactory: ContractFactory = await ethers.getContractFactory("MultiSigWallet");
        wallet = await walletFactory.deploy(["0x7f6311AdEb83cB825250B2222656D26223D7EcB4"], 1);
        // prettier-ignore
        await wallet.deployed();
    });

    describe("function", function () {
        it("", async function () {});
    });
});
