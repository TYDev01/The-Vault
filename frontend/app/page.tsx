"use client";

import { useMemo, useState } from "react";
import { CHAINHOOKS_BASE_URL, ChainhooksClient } from "@hirosystems/chainhooks-client";

type ChainhookStatus = "idle" | "checking" | "ok" | "error";

export default function Home() {
  const [status, setStatus] = useState<ChainhookStatus>("idle");
  const [statusNote, setStatusNote] = useState("Not checked");
  const baseUrl = process.env.NEXT_PUBLIC_CHAINHOOKS_API_URL ?? CHAINHOOKS_BASE_URL.testnet;
  const client = useMemo(() => new ChainhooksClient({ baseUrl }), [baseUrl]);

  const handleCheckStatus = async () => {
    setStatus("checking");
    setStatusNote("Checking Chainhooks API...");
    try {
      await client.getStatus();
      setStatus("ok");
      setStatusNote("Chainhooks API reachable");
    } catch (error) {
      setStatus("error");
      setStatusNote("Unable to reach Chainhooks API");
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
          <input className="input" placeholder="Amount (STX)" />
          <input className="input" placeholder="Lock duration" />
          <input className="input" placeholder="Vault label" />
        </div>
        <div className="builder-row">
          <button className="pill primary" type="button">
            Save vault plan
          </button>
          <button className="pill" type="button" onClick={handleCheckStatus}>
            Check Chainhooks API
          </button>
        </div>
      </section>
    </main>
  );
}
