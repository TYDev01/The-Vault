"use client";

import { useEffect, useRef, useState } from "react";
import { cvToHex, stringAsciiCV, uintCV } from "@stacks/transactions";
import {
  callStacksContract,
  getStacksAddresses,
  getUniversalConnector,
  openWalletConnectModal
} from "./lib/reown";

type ChainhookStatus = "idle" | "checking" | "ok" | "error";
type WalletSession = {
  namespaces?: Record<string, { accounts?: string[] }>;
  peer?: { name?: string };
};

export default function Home() {
  const builderRef = useRef<HTMLElement | null>(null);
  const vaultContractAddress = process.env.NEXT_PUBLIC_VAULT_CONTRACT_ADDRESS ?? "";
  const vaultContractName = process.env.NEXT_PUBLIC_VAULT_CONTRACT_NAME ?? "savings-vault";
  const vaultNetwork = (process.env.NEXT_PUBLIC_VAULT_NETWORK as "mainnet" | "testnet" | undefined) ?? "testnet";
  const [status, setStatus] = useState<ChainhookStatus>("idle");
  const [statusNote, setStatusNote] = useState("Not checked");
  const [lastChecked, setLastChecked] = useState<string | null>(null);
  const [amount, setAmount] = useState("");
  const [duration, setDuration] = useState("");
  const [label, setLabel] = useState("");
  const [activeFilter, setActiveFilter] = useState("All");
  const [baseUrl, setBaseUrl] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [walletState, setWalletState] = useState<{
    connected: boolean;
    stxAddress?: string;
    btcAddress?: string;
    provider?: string;
  }>({ connected: false });
  const [walletError, setWalletError] = useState<string | null>(null);
  const [connectorReady, setConnectorReady] = useState(false);
  const [walletSession, setWalletSession] = useState<WalletSession | null>(null);
  const [vaultSubmitting, setVaultSubmitting] = useState(false);
  const [lastVaultTx, setLastVaultTx] = useState<string | null>(null);
  const parsedAmount = Number(amount.replace(/,/g, ""));
  const estimatedPenalty = Number.isFinite(parsedAmount) ? Math.round(parsedAmount * 0.08) : null;
  const parsedDuration = Number(duration);
  const estimatedUnlock =
    Number.isFinite(parsedDuration) && parsedDuration > 0
      ? new Date(Date.now() + parsedDuration * 24 * 60 * 60 * 1000).toLocaleDateString()
      : null;
  const canSubmitVault =
    !vaultSubmitting &&
    Boolean(vaultContractAddress) &&
    Boolean(amount) &&
    Boolean(duration) &&
    Number.isFinite(parsedAmount) &&
    parsedAmount > 0 &&
    Number.isFinite(parsedDuration) &&
    parsedDuration > 0;
  const [vaults, setVaults] = useState([
    { name: "Focus Fund", amount: 8200, unlock: "90 days", status: "On track" },
    { name: "Voyage Buffer", amount: 3450, unlock: "21 days", status: "Near unlock" },
    { name: "Launch Reserve", amount: 12000, unlock: "180 days", status: "Locked" }
  ]);
  const totalLocked = vaults.reduce((sum, vault) => sum + vault.amount, 0);
  const vaultStatuses = ["All", "On track", "Near unlock", "Locked"];
  const [vaultFilter, setVaultFilter] = useState("All");
  const visibleVaults =
    vaultFilter === "All" ? vaults : vaults.filter((vault) => vault.status === vaultFilter);
  const [activity, setActivity] = useState<
    { type: string; vault: string; amount: string; time: string }[]
  >([]);
  const [activityState, setActivityState] = useState<"idle" | "loading" | "error" | "ready">(
    "idle"
  );
  const filters = ["All", "Deposit", "Withdrawal", "Penalty"];
  const visibleActivity =
    activeFilter === "All" ? activity : activity.filter((item) => item.type === activeFilter);

  const formatAmountInput = (value: string) => {
    const digits = value.replace(/[^\d]/g, "");
    if (!digits) {
      return "";
    }
    const asNumber = Number(digits);
    if (!Number.isFinite(asNumber)) {
      return "";
    }
    return asNumber.toLocaleString();
  };

  const formatDurationInput = (value: string) => value.replace(/[^\d]/g, "");
  const explorerBaseUrl =
    vaultNetwork === "mainnet" ? "https://explorer.hiro.so/txid/" : "https://explorer.hiro.so/txid/";
  const explorerSuffix = vaultNetwork === "mainnet" ? "" : "?chain=testnet";
  const getExplorerUrl = (txid: string) => `${explorerBaseUrl}${txid}${explorerSuffix}`;

  useEffect(() => {
    let active = true;
    const initConnector = async () => {
      try {
        const connector = await getUniversalConnector();
        if (!active) {
          return;
        }
        setConnectorReady(true);
        if (connector.session) {
          setWalletSession(connector.session as WalletSession);
        }
      } catch (error) {
        if (active) {
          setWalletError("Unable to initialize Reown WalletConnect.");
        }
      }
    };

    initConnector();

    const loadActivity = async () => {
      setActivityState("loading");
      try {
        const response = await fetch("/api/chainhooks/activity");
        const payload = (await response.json()) as {
          ok: boolean;
          activity?: { type: string; vault: string; amount: string; time: string }[];
        };
        if (!payload.ok || !payload.activity) {
          throw new Error("Activity fetch failed");
        }
        setActivity(payload.activity);
        setActivityState("ready");
      } catch (error) {
        setActivityState("error");
      }
    };
    loadActivity();
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!walletSession) {
      setWalletState({ connected: false });
      return;
    }
    const namespaces = walletSession.namespaces ?? {};
    const account = Object.values(namespaces)
      .flatMap((namespace) => namespace.accounts ?? [])
      .map((entry) => entry.split(":")[2] ?? entry)
      .find(Boolean);
    setWalletState({
      connected: true,
      stxAddress: account,
      provider: walletSession.peer?.name ?? "Reown WalletConnect"
    });
  }, [walletSession]);

  const handlePlaceholderAction = (message: string) => {
    setActionMessage(message);
    window.setTimeout(() => setActionMessage(null), 2400);
  };

  const handleJumpToBuilder = () => {
    builderRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const handleConnectWallet = async () => {
    setWalletError(null);
    try {
      if (!connectorReady) {
        setWalletError("Wallet connector is still loading.");
        return;
      }
      if (walletSession) {
        setActionMessage("Already connected");
        return;
      }
      const { connector, session } = (await openWalletConnectModal()) as {
        connector: ReturnType<typeof getUniversalConnector> extends Promise<infer T> ? T : never;
        session?: WalletSession;
      };
      setWalletSession(session ?? null);
      const addresses = await getStacksAddresses();
      if (addresses[0]) {
        setWalletState((prev) => ({
          ...prev,
          connected: true,
          stxAddress: addresses[0],
          provider: session?.peer?.name ?? "Reown WalletConnect"
        }));
      }
      setActionMessage("Wallet connected");
    } catch (error) {
      setWalletError("Unable to connect wallet. Try again or check your WalletConnect app.");
    }
  };

  const handleDisconnectWallet = async () => {
    try {
      const connector = await getUniversalConnector();
      await connector.disconnect();
    } catch (error) {
      setWalletError("Unable to disconnect wallet.");
    }
    setWalletSession(null);
    setActionMessage("Wallet disconnected");
  };

  const handleRefreshAccount = async () => {
    setWalletError(null);
    try {
      const connector = await getUniversalConnector();
      const session = (connector.session ?? null) as WalletSession | null;
      if (!session) {
        setWalletError("No active wallet session.");
        return;
      }
      setWalletSession(session);
      const addresses = await getStacksAddresses();
      if (addresses[0]) {
        setWalletState((prev) => ({
          ...prev,
          connected: true,
          stxAddress: addresses[0]
        }));
      }
      setActionMessage("Account refreshed");
    } catch (error) {
      setWalletError("Unable to refresh account.");
    }
  };

  const handleCreateVault = async () => {
    setWalletError(null);
    setLastVaultTx(null);
    if (!vaultContractAddress) {
      setWalletError("Missing vault contract address. Set NEXT_PUBLIC_VAULT_CONTRACT_ADDRESS.");
      return;
    }
    if (!amount || !duration) {
      setWalletError("Enter an amount and lock duration.");
      return;
    }
    if (vaultSubmitting) {
      return;
    }
    const parsedDays = Number(duration);
    if (!Number.isFinite(parsedDays) || parsedDays <= 0) {
      setWalletError("Lock duration must be a positive number of days.");
      return;
    }
    const parsedDeposit = Number(amount.replace(/,/g, ""));
    if (!Number.isFinite(parsedDeposit) || parsedDeposit <= 0) {
      setWalletError("Amount must be a positive number.");
      return;
    }
    try {
      setVaultSubmitting(true);
      if (!walletSession) {
        await handleConnectWallet();
      }
      const blocksPerDay = 144;
      const initialDeposit = BigInt(Math.round(parsedDeposit * 1e6));
      const presetMap: Record<number, string> = { 7: "7d", 30: "30d", 90: "90d", 180: "180d" };
      const preset = presetMap[Math.round(parsedDays)];
      const functionName = preset ? "create-vault-preset" : "create-vault";
      const functionArgs = preset
        ? [cvToHex(uintCV(initialDeposit)), cvToHex(stringAsciiCV(preset))]
        : [cvToHex(uintCV(initialDeposit)), cvToHex(uintCV(BigInt(Math.round(parsedDays * blocksPerDay))))];
      const response = await callStacksContract({
        contractAddress: vaultContractAddress,
        contractName: vaultContractName,
        functionName,
        functionArgs,
        network: vaultNetwork
      });
      const txResult = response.result as { txid?: string } | string | undefined;
      const txid = typeof txResult === "string" ? txResult : txResult?.txid;
      if (txid || response.result) {
        setActionMessage("Vault creation submitted");
        setLastVaultTx(txid ?? null);
        setVaults((prev) => [
          ...prev,
          {
            name: label || `Vault ${prev.length + 1}`,
            amount: Math.round(parsedDeposit),
            unlock: `${parsedDays} days`,
            status: "Locked"
          }
        ]);
        setLabel("");
        setAmount("");
        setDuration("");
      } else {
        setWalletError("Vault creation rejected.");
      }
    } catch (error) {
      setWalletError("Unable to submit vault creation.");
    } finally {
      setVaultSubmitting(false);
    }
  };

  const handleCheckStatus = async () => {
    setStatus("checking");
    setStatusNote("Checking Chainhooks API...");
    try {
      const response = await fetch("/api/chainhooks/status");
      const payload = (await response.json()) as { ok: boolean; baseUrl?: string };
      if (!payload.ok) {
        throw new Error("Chainhooks check failed");
      }
      setStatus("ok");
      setStatusNote("Chainhooks API reachable");
      setBaseUrl(payload.baseUrl ?? null);
      setLastChecked(new Date().toLocaleTimeString());
    } catch (error) {
      setStatus("error");
      setStatusNote("Unable to reach Chainhooks API");
      setLastChecked(new Date().toLocaleTimeString());
    }
  };

  return (
    <main className="page">
      <nav className="nav reveal">
        <div className="brand">
          <span className="brand-mark" aria-hidden />
          SavingVault
        </div>
        <div className="nav-actions">
          <button className="pill" type="button" onClick={() => handlePlaceholderAction("Docs coming soon")}>
            Docs
          </button>
          <button className="pill" type="button" onClick={() => handlePlaceholderAction("Vaults view coming soon")}>
            Vaults
          </button>
          <button
            className="pill primary"
            type="button"
            onClick={walletState.connected ? handleDisconnectWallet : handleConnectWallet}
          >
            {walletState.stxAddress
              ? `Disconnect ${walletState.stxAddress.slice(0, 6)}...${walletState.stxAddress.slice(-4)}`
              : "Launch App"}
          </button>
        </div>
      </nav>

      <section className="hero">
        <div className="reveal">
          <p className="label">Time-locked savings</p>
          <h1>Architect calm, programmatic saving on Stacks.</h1>
          <p>
            Build vaults with clear lock schedules, predictable penalties, and indexed activity through
            Chainhooks. SavingVault turns long-term goals into on-chain rituals.
          </p>
          <div className="nav-actions">
            <button
              className="pill primary"
              type="button"
              onClick={handleJumpToBuilder}
            >
              Create vault
            </button>
            <button
              className="pill"
              type="button"
              onClick={() => handlePlaceholderAction("Penalty preview coming soon")}
            >
              Preview penalties
            </button>
          </div>
        </div>
        <div className="hero-card reveal">
          <p className="label">Vault preview</p>
          <div className="amount">24,500 STX</div>
          <p className="status">
            <span className="status-dot ok" aria-hidden />
            Locking until block 154,920
          </p>
          <div className="details">
            <span>
              <strong>Deposit</strong> <span>12 Oct 2024</span>
            </span>
            <span>
              <strong>Unlock</strong> <span>20 Jan 2025</span>
            </span>
            <span>
              <strong>Penalty</strong> <span>8% early exit</span>
            </span>
          </div>
        </div>
      </section>

      <section className="grid">
        <div className="card reveal">
          <h3>Purpose-built lock presets</h3>
          <p>Quick 7/30/90/180 day options guide users toward consistent vault cadences.</p>
        </div>
        <div className="card reveal">
          <h3>Event-ready indexing</h3>
          <p>Chainhook streams power dashboards, portfolio summaries, and compliance alerts.</p>
        </div>
        <div className="card reveal">
          <h3>Flexible penalty math</h3>
          <p>Simulate exit conditions and preview penalties before you commit funds.</p>
        </div>
        <div className="card reveal">
          <h3>Safety-first lifecycle</h3>
          <p>Vaults can close cleanly after withdrawal, preventing reuse and dust attacks.</p>
        </div>
      </section>

      <section className="builder reveal" ref={builderRef}>
        <div>
          <p className="label">Vault builder</p>
          <h2 className="section-title">Model your next savings vault.</h2>
          <p className="status">
            <span className={`status-dot ${status === "ok" ? "ok" : status === "error" ? "error" : ""}`} />
            {statusNote}
          </p>
          <p className="status">
            Contract: {vaultContractAddress ? `${vaultContractAddress}.${vaultContractName}` : "Not configured"} (
            {vaultNetwork})
          </p>
        </div>
        <div className="builder-row">
          <input
            className="input"
            placeholder="Amount (STX)"
            value={amount}
            onChange={(event) => setAmount(formatAmountInput(event.target.value))}
          />
          <input
            className="input"
            placeholder="Lock duration (days)"
            value={duration}
            onChange={(event) => setDuration(formatDurationInput(event.target.value))}
          />
          <input
            className="input"
            placeholder="Vault label"
            value={label}
            onChange={(event) => setLabel(event.target.value)}
          />
        </div>
        <div className="builder-row presets">
          {["7", "30", "90", "180"].map((preset) => (
            <button
              key={preset}
              className={`pill ${duration === preset ? "primary" : ""}`}
              type="button"
              onClick={() => setDuration(preset)}
            >
              {preset} days
            </button>
          ))}
        </div>
        <div className="builder-row">
          <button
            className="pill primary"
            type="button"
            onClick={handleCreateVault}
            disabled={!canSubmitVault}
          >
            {vaultSubmitting ? "Submitting..." : "Save vault plan"}
          </button>
          <button className="pill" type="button" onClick={handleCheckStatus}>
            Check Chainhooks API
          </button>
          <button className="pill" type="button" onClick={handleRefreshAccount}>
            Refresh wallet
          </button>
          <div className="summary">
            <p className="card-kicker">Penalty estimate</p>
            <p className="card-value">
              {estimatedPenalty === null ? "--" : `${estimatedPenalty.toLocaleString()} STX`}
            </p>
          </div>
          <div className="summary">
            <p className="card-kicker">Estimated unlock</p>
            <p className="card-value">{estimatedUnlock ?? "--"}</p>
          </div>
        </div>
      </section>

      <section className="pulse reveal">
        <div>
          <p className="label">Network pulse</p>
          <h2 className="section-title">Chainhooks readiness</h2>
          <p className="status">
            <span className={`status-dot ${status === "ok" ? "ok" : status === "error" ? "error" : ""}`} />
            {statusNote}
          </p>
        </div>
        <div className="pulse-card">
          <div>
            <p className="card-kicker">Active endpoint</p>
            <p className="card-value">{baseUrl ?? "Not checked"}</p>
          </div>
          <div>
            <p className="card-kicker">Last check</p>
            <p className="card-value">{lastChecked ?? "Not run"}</p>
          </div>
          <button className="pill" type="button" onClick={handleCheckStatus}>
            Ping Chainhooks
          </button>
        </div>
      </section>

      <section className="vaults reveal">
        <div>
          <p className="label">Vault inventory</p>
          <h2 className="section-title">Your active vaults</h2>
          <div className="vault-metrics">
            <div>
              <p className="card-kicker">Total locked</p>
              <p className="card-value">{totalLocked.toLocaleString()} STX</p>
            </div>
            <div>
              <p className="card-kicker">Vault count</p>
              <p className="card-value">{vaults.length}</p>
            </div>
          </div>
        </div>
        <div className="vault-filters">
          {vaultStatuses.map((filter) => (
            <button
              key={filter}
              className={`pill ${vaultFilter === filter ? "primary" : ""}`}
              type="button"
              onClick={() => setVaultFilter(filter)}
            >
              {filter}
            </button>
          ))}
        </div>
        <div className="vault-list">
          {visibleVaults.map((vault) => (
            <div key={vault.name} className="vault-row">
              <div>
                <p className="card-kicker">{vault.name}</p>
                <p className="card-value">{vault.amount.toLocaleString()} STX</p>
              </div>
              <div>
                <p className="card-kicker">Unlock</p>
                <p className="card-value">{vault.unlock}</p>
              </div>
              <span className="vault-chip">{vault.status}</span>
            </div>
          ))}
        </div>
      </section>

      <section className="activity reveal">
        <div>
          <p className="label">Activity feed</p>
          <h2 className="section-title">Indexed vault activity</h2>
          <p className="status">Filter events streamed from Chainhooks and grouped by vault.</p>
        </div>
        <div className="activity-filters">
          {filters.map((filter) => (
            <button
              key={filter}
              className={`pill ${activeFilter === filter ? "primary" : ""}`}
              type="button"
              onClick={() => setActiveFilter(filter)}
            >
              {filter}
            </button>
          ))}
        </div>
        <div className="event-list">
          {activityState === "loading" && <div className="event-empty">Loading activity...</div>}
          {activityState === "error" && (
            <div className="event-empty">Unable to load Chainhooks activity.</div>
          )}
          {activityState === "ready" &&
            visibleActivity.map((item) => (
              <div key={`${item.type}-${item.vault}-${item.time}`} className="event-item">
                <span className={`event-badge ${item.type.toLowerCase()}`}>{item.type}</span>
                <div>
                  <p className="card-kicker">{item.vault}</p>
                  <p className="card-value">{item.amount}</p>
                </div>
                <p className="event-time">{item.time}</p>
              </div>
            ))}
        </div>
      </section>
      {lastVaultTx && (
        <div className="toast">
          Vault tx: {lastVaultTx.slice(0, 10)}...
          {" "}
          <a href={getExplorerUrl(lastVaultTx)} target="_blank" rel="noreferrer">
            View
          </a>
        </div>
      )}
      {actionMessage && <div className="toast">{actionMessage}</div>}
      {walletError && <div className="toast">{walletError}</div>}
    </main>
  );
}
