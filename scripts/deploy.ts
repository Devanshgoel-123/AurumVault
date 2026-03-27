import { Deployer, IConfig, Network } from "@strkfarm/sdk";
import { Account, CallData, RpcProvider, uint256 } from "starknet";
import dotenv from "dotenv";

dotenv.config();

const CONTRACT_NAMES = {
    stoneBtc: "StoneBTC",
    aurumToken: "aurumtoken",
    vault: "vault",
} as const;

function getRequiredEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required env var: ${name}`);
    }
    return value;
}

function getNetwork(value: string | undefined): Network {
    const normalized = (value ?? "sepolia").toLowerCase();
    if (normalized === "mainnet") {
        return Network.mainnet;
    }
    return Network.sepolia;
}

function toU256(value: bigint | number | string) {
    return uint256.bnToUint256(value.toString());
}

const rpcUrl =
    process.env.RPC_URL
const config: IConfig = {
    provider: new RpcProvider({ nodeUrl: rpcUrl }),
    network: getNetwork(process.env.NETWORK),
    stage: "production",
};

const account = new Account({
    provider: config.provider as any,
    address: getRequiredEnv("ACCOUNT_ADDRESS"),
    signer: getRequiredEnv("ACCOUNT_PK"),
    cairoVersion: undefined,
    transactionVersion: "0x3",
});

const packageName = "aurumvault";
const oracleAddress = getRequiredEnv("ORACLE_ADDRESS");
const btcUsdAssetId = getRequiredEnv("BTC_USD_ASSET_ID");
const depositFeeBps = Number(process.env.VAULT_DEPOSIT_FEE_BPS ?? "50");
const minDepositUsd = BigInt(process.env.MINIMUM_DEPOSIT_IN_USD ?? "10");
const stoneBtcInitialSupply = BigInt(
    process.env.STONE_BTC_INITIAL_SUPPLY ?? "2100000000000000",
);
const stoneBtcRecipient = process.env.STONE_BTC_RECIPIENT ?? account.address;



async function declareAndDeploy(contractName: string, constructorData: any) {
    console.log(`\n=== Declaring ${contractName} ===`);
    const declaration = await Deployer.myDeclare(contractName, packageName, config, account);
    console.log(`Declare tx: ${declaration.transaction_hash}`);
    console.log(`Class hash: ${declaration.class_hash}`);
    await Deployer.myWaitForTransaction(
        declaration.transaction_hash,
        config.provider as RpcProvider,
    );
    const classHash = "0x5558c6b39fa1c1c0a098a1d9c54b20d142b5251d2eb5df7333adc438a141ee0";
    console.log(`=== Deploying ${contractName} ===`);
    const deployTx = await Deployer.deployContract(
        contractName,
        classHash,
        constructorData,
        config,
        account,
    );
    const txHash = (deployTx as any).transaction_hash as string;
    console.log(`Deploy tx: ${txHash}`);
    await Deployer.myWaitForTransaction(txHash, config.provider as RpcProvider);

    const deployedAddress =
        (deployTx as any).contract_address ??
        (deployTx as any).deployed_address ??
        (deployTx as any).address;

    if (!deployedAddress) {
        throw new Error(`Unable to resolve deployed address for ${contractName}`);
    }

    console.log(`${contractName} address: ${deployedAddress}`);
    return String(deployedAddress);
}

async function wireAurumTokenVault(aurumTokenAddress: string, vaultAddress: string) {
    console.log("\n=== Wiring aurumtoken -> vault ===");
    const setVaultTx = await account.execute({
        contractAddress: aurumTokenAddress,
        entrypoint: "set_vault",
        calldata: CallData.compile({ new_vault: vaultAddress }),
    });

    console.log(`set_vault tx: ${setVaultTx.transaction_hash}`);
    await Deployer.myWaitForTransaction(
        setVaultTx.transaction_hash,
        config.provider as RpcProvider,
    );
}

async function deployAll() {
    console.log(`Using network: ${config.network}`);
    console.log(`Using deployer: ${account.address}`);
    console.log(`Using package_name: ${packageName ?? "(auto)"}`);

    const stoneBtcAddress = await declareAndDeploy(CONTRACT_NAMES.stoneBtc, {
        name: "Stone BTC",
        symbol: "SBTC",
        decimals: 8,
        initial_supply: toU256(stoneBtcInitialSupply),
        recipient: stoneBtcRecipient,
    });

    //   const aurumTokenAddress = await declareAndDeploy(CONTRACT_NAMES.aurumToken, {});

    //   const vaultAddress = await declareAndDeploy(CONTRACT_NAMES.vault, {
    //     owner: account.address,
    //     stonebtc_address: stoneBtcAddress,
    //     aurum_token_address: aurumTokenAddress,
    //     oracle_address: oracleAddress,
    //     deposit_fee: depositFeeBps,
    //     minimum_deposit_in_usd: toU256(minDepositUsd),
    //     btc_usd_asset_id: btcUsdAssetId,
    //   });

    // await wireAurumTokenVault(aurumTokenAddress, vaultAddress);

    console.log("\n=== Deployment complete ===");
    console.log(`StoneBTC:   ${stoneBtcAddress}`);
    //   console.log(`AurumToken: ${aurumTokenAddress}`);
    //   console.log(`Vault:      ${vaultAddress}`);
}

deployAll().catch((error) => {
    console.error("Deployment failed:", error);
    process.exit(1);
});