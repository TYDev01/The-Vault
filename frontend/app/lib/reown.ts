import type { CustomCaipNetwork } from "@reown/appkit-common";
import { UniversalConnector } from "@reown/appkit-universal-connector";

const projectId = process.env.NEXT_PUBLIC_REOWN_PROJECT_ID ?? "";
const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";
const stacksChainId = "stacks:1";
const stacksMethods = [
  "stx_getAddresses",
  "stx_signMessage",
  "stx_signTransaction",
  "stx_callContract"
] as const;

const stacksMainnet: CustomCaipNetwork<"stacks"> = {
  id: 1,
  chainNamespace: "stacks",
  caipNetworkId: "stacks:1",
  name: "Stacks",
  nativeCurrency: { name: "Stacks", symbol: "STX", decimals: 6 },
  rpcUrls: { default: { http: ["https://api.mainnet.hiro.so"] } }
};

let connectorPromise: Promise<UniversalConnector> | null = null;

export const getUniversalConnector = async () => {
  if (!connectorPromise) {
    connectorPromise = UniversalConnector.init({
      projectId,
      metadata: {
        name: "SavingVault",
        description: "SavingVault Vault Builder",
        url: appUrl,
        icons: ["https://reown.com/icon.png"]
      },
      networks: [
        {
          namespace: "stacks",
          methods: [...stacksMethods],
          chains: [stacksMainnet],
          events: []
        }
      ]
    });
  }

  return connectorPromise;
};

export const openWalletConnectModal = async () => {
  const connector = await getUniversalConnector();
  const session = (await connector.connect({
    chains: [stacksChainId],
    methods: [...stacksMethods],
    events: []
  })) as { session?: unknown };

  return { connector, session };
};

export const requestStacksRpc = async (params: { method: (typeof stacksMethods)[number]; params?: unknown }) => {
  const connector = await getUniversalConnector();
  return connector.request(params, stacksChainId) as Promise<{ result?: { addresses?: string[] } }>;
};

export const getStacksAddresses = async () => {
  const response = await requestStacksRpc({ method: "stx_getAddresses", params: {} });
  return response.result?.addresses ?? [];
};

export const signStacksMessage = async (address: string, message: string) =>
  requestStacksRpc({
    method: "stx_signMessage",
    params: { address, message, messageType: "utf8" }
  });

export const signStacksTransaction = async (transaction: string, broadcast = true) =>
  requestStacksRpc({
    method: "stx_signTransaction",
    params: { transaction, broadcast }
  });

export const callStacksContract = async (params: {
  contractAddress: string;
  contractName: string;
  functionName: string;
  functionArgs: string[];
  network?: "mainnet" | "testnet";
}) =>
  requestStacksRpc({
    method: "stx_callContract",
    params
  });
