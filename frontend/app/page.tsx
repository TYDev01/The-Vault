"use client";

import { useState } from "react";

type ChainhookStatus = "idle" | "checking" | "ok" | "error";

export default function Home() {
  const [status, setStatus] = useState<ChainhookStatus>("idle");
  const [statusNote, setStatusNote] = useState("Not checked");
  const [lastChecked, setLastChecked] = useState<string | null>(null);
  const [amount, setAmount] = useState("");
  const [duration, setDuration] = useState("");
  const [label, setLabel] = useState("");
  const [activeFilter, setActiveFilter] = useState("All");
  const [baseUrl, setBaseUrl] = useState<string | null>(null);
  const parsedAmount = Number(amount.replace(/,/g, ""));
  const estimatedPenalty = Number.isFinite(parsedAmount) ? Math.round(parsedAmount * 0.08) : null;
  const activity = [
    { type: "Deposit", vault: "Focus Fund", amount: "4,200 STX", time: "2h ago" },
    { type: "Withdrawal", vault: "Voyage Buffer", amount: "1,200 STX", time: "1d ago" },
    { type: "Penalty", vault: "Launch Reserve", amount: "300 STX", time: "3d ago" },
    { type: "Deposit", vault: "Launch Reserve", amount: "6,500 STX", time: "1w ago" }
  ];
  const filters = ["All", "Deposit", "Withdrawal", "Penalty"];
  const visibleActivity =
    activeFilter === "All" ? activity : activity.filter((item) => item.type === activeFilter);

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
          <span className="pill">Docs</span>
          <span className="pill">Vaults</span>
          <button className="pill primary" type="button">
            Launch App
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
            <button className="pill primary" type="button">
              Create vault
            </button>
            <button className="pill" type="button">
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

      <section className="builder reveal">
        <div>
          <p className="label">Vault builder</p>
          <h2 className="section-title">Model your next savings vault.</h2>
          <p className="status">
            <span className={`status-dot ${status === "ok" ? "ok" : status === "error" ? "error" : ""}`} />
            {statusNote}
          </p>
        </div>
        <div className="builder-row">
          <input
            className="input"
            placeholder="Amount (STX)"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
          />
          <input
            className="input"
            placeholder="Lock duration (days)"
            value={duration}
            onChange={(event) => setDuration(event.target.value)}
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
          <button className="pill primary" type="button">
            Save vault plan
          </button>
          <button className="pill" type="button" onClick={handleCheckStatus}>
            Check Chainhooks API
          </button>
          <div className="summary">
            <p className="card-kicker">Penalty estimate</p>
            <p className="card-value">
              {estimatedPenalty === null ? "--" : `${estimatedPenalty.toLocaleString()} STX`}
            </p>
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
        </div>
        <div className="vault-list">
          {[
            { name: "Focus Fund", amount: "8,200 STX", unlock: "90 days", status: "On track" },
            { name: "Voyage Buffer", amount: "3,450 STX", unlock: "21 days", status: "Near unlock" },
            { name: "Launch Reserve", amount: "12,000 STX", unlock: "180 days", status: "Locked" }
          ].map((vault) => (
            <div key={vault.name} className="vault-row">
              <div>
                <p className="card-kicker">{vault.name}</p>
                <p className="card-value">{vault.amount}</p>
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
          {visibleActivity.map((item) => (
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
    </main>
  );
}
