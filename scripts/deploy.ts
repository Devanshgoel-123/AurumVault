import { Deployer, IConfig, Network } from "@strkfarm/sdk";
import { Account, CallData, RpcProvider, uint256 } from "starknet";
import dotenv from "dotenv";
import { byteArray } from "starknet";
import { shortString } from "starknet";
dotenv.config();

const CONTRACT_NAMES = {
    stoneBtc: "StoneBTC",
    aurumToken: "aurumtoken",
    vault: "vault",
} as const;

const STONE_BTC_ADDRESS = "0x6a16e97f978e88fbcead2129fde419fb6f41c8f3681825f8e2a962112c5f540";
const AURUM_TOKEN_ADDRESS = "0x37caceeb7ff2bc48f98b19df70fd55160f1ff6485f841f508935ae89ae0f904";
const VAULT_ADDRESS = ""
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
console.log("Rpc url ", rpcUrl)
const config: IConfig = {
    provider: new RpcProvider({ nodeUrl: rpcUrl }),
    network: getNetwork(process.env.NETWORK),
    stage: "staging",
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
const minDepositUsd = BigInt(process.env.MINIMUM_DEPOSIT_IN_USD ?? "11");
const stoneBtcInitialSupply = BigInt(
    process.env.STONE_BTC_INITIAL_SUPPLY ?? "2100000000000000",
);
const stoneBtcRecipient = process.env.STONE_BTC_RECIPIENT ?? account.address;



async function declareAndDeploy(contractName: string, constructorData: any, classHash: string) {
    console.log(`\n=== Declaring ${contractName} ===`);
    // const declaration = await Deployer.myDeclare(contractName, packageName, config, account);
    // console.log(`Declare tx: ${declaration.transaction_hash}`);
    // console.log(`Class hash: ${declaration.class_hash}`);
    // await Deployer.myWaitForTransaction(
    //     declaration.transaction_hash,
    //     config.provider as RpcProvider,
    // );
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

    // const stoneBtcClassHash = "0x00d073a35608e93f1d8ae17fd2104175782ff486e886b7f82433c1d1c514669a";

    // const aurumTokenClassHash = "0x02246e9f3059c957a35d636214ebafc9b3975ddaefcd11da94f2190b127938ab";

    const vaultClassHash = "0x604d3600894478a1d3cfe3bf2ef2b63217808960b671f1410d7d3a46752762d";
    // const stoneBtcAddress = await declareAndDeploy(CONTRACT_NAMES.stoneBtc, {
    //     name: byteArray.byteArrayFromString("StoneBTC"),
    //     symbol: byteArray.byteArrayFromString("SBTC"),
    //     decimals: 8,
    //     initial_supply: toU256(stoneBtcInitialSupply),
    //     recipient: stoneBtcRecipient,
    // },
    // );

    //  const aurumTokenAddress = await declareAndDeploy(CONTRACT_NAMES.aurumToken, {
    //     owner: account.address,
    //  },
    //  );
      const vaultAddress = await declareAndDeploy(CONTRACT_NAMES.vault, {
        owner: account.address,
        stonebtc_address: STONE_BTC_ADDRESS,
        aurum_token_address: AURUM_TOKEN_ADDRESS,
        oracle_address: oracleAddress,
        deposit_fee: depositFeeBps,
        minimum_deposit_in_usd: toU256(minDepositUsd),
        btc_usd_asset_id: btcUsdAssetId,
      }, vaultClassHash);

    await wireAurumTokenVault(AURUM_TOKEN_ADDRESS, VAULT_ADDRESS);

    console.log("\n=== Deployment complete ===");
    // console.log(`StoneBTC:   ${stoneBtcAddress}`);
      //console.log(`AurumToken: ${aurumTokenAddress}`);
}

deployAll().catch((error) => {
    console.error("Deployment failed:", error);
    process.exit(1);
});