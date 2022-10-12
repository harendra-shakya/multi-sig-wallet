import { DeployFunction } from "hardhat-deploy/types";
import { network } from "hardhat";
import { verify } from "../utils/verify";

const deployFunction: DeployFunction = async ({ getNamedAccounts, deployments }) => {
    const { deploy, log } = deployments;
    const { deployer } = await getNamedAccounts();
    const developmentChains: string[] = ["hardhat", "localhost"];
    const VERIFICATION_BLOCK_CONFIRMATIONS = 6;
    const chainId: number | undefined = network.config.chainId;
    if (!chainId) return;

    const waitConfirmations: number = developmentChains.includes(network.name)
        ? 1
        : VERIFICATION_BLOCK_CONFIRMATIONS;

    log("-----------------------------------------------------------");
    log("deploying......");

    const multiSigWallet = await deploy("MultiSigWallet", {
        from: deployer,
        log: true,
        args: [["0x7f6311AdEb83cB825250B2222656D26223D7EcB4"], 1],
        waitConfirmations: waitConfirmations,
    });

    if (!developmentChains.includes(network.name)) {
        await verify(multiSigWallet.address, [["0x7f6311AdEb83cB825250B2222656D26223D7EcB4"], 1]);
    }
};

export default deployFunction;
deployFunction.tags = ["all", "main"];
