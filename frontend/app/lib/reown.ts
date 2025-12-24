import type { CustomCaipNetwork } from "@reown/appkit-common";
import { UniversalConnector } from "@reown/appkit-universal-connector";

const projectId = process.env.NEXT_PUBLIC_REOWN_PROJECT_ID ?? "";
const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";

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
          methods: ["stx_signMessage"],
          chains: [stacksMainnet],
          events: []
        }
      ]
    });
  }

  return connectorPromise;
};
