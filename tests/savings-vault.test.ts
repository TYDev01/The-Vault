import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

const LOCK_7_DAYS = 1008;
const LOCK_30_DAYS = 4320;
const INITIAL_MINT = 1000000000000; // 10,000 sBTC (8 decimals)

describe("Savings Vault", () => {
  beforeEach(() => {
    simnet.callPublicFn(
      "mock-sbtc",
      "mint",
      [Cl.uint(INITIAL_MINT), Cl.principal(wallet1)],
      deployer
    );

    simnet.callPublicFn(
      "mock-sbtc",
      "mint",
      [Cl.uint(INITIAL_MINT), Cl.principal(wallet2)],
      deployer
    );
  });

  it("creates a vault with an initial deposit", () => {
    const depositAmount = 100000000000;

    const result = simnet.callPublicFn(
      "savings-vault",
      "create-vault",
      [Cl.uint(depositAmount), Cl.uint(LOCK_30_DAYS)],
      wallet1
    );

    expect(result.result).toBeOk(Cl.uint(1));
  });

  it("rejects deposits below the minimum", () => {
    const result = simnet.callPublicFn(
      "savings-vault",
      "create-vault",
      [Cl.uint(0), Cl.uint(LOCK_30_DAYS)],
      wallet1
    );

    expect(result.result).toBeErr(Cl.uint(101));
  });

  it("creates a vault using a preset lock period", () => {
    const result = simnet.callPublicFn(
      "savings-vault",
      "create-vault-preset",
      [Cl.uint(100000000000), Cl.stringAscii("30d")],
      wallet1
    );

    expect(result.result).toBeOk(Cl.uint(1));
  });

  it("allows deposits to an existing vault", () => {
    simnet.callPublicFn(
      "savings-vault",
      "create-vault",
      [Cl.uint(100000000000), Cl.uint(LOCK_30_DAYS)],
      wallet1
    );

    const depositResult = simnet.callPublicFn(
      "savings-vault",
      "deposit",
      [Cl.uint(1), Cl.uint(50000000000)],
      wallet1
    );

    expect(depositResult.result).toBeOk(Cl.bool(true));
  });

  it("blocks withdrawals before lock expiry", () => {
    simnet.callPublicFn(
      "savings-vault",
      "create-vault",
      [Cl.uint(100000000000), Cl.uint(LOCK_30_DAYS)],
      wallet1
    );

    const withdrawResult = simnet.callPublicFn(
      "savings-vault",
      "withdraw",
      [Cl.uint(1), Cl.uint(50000000000)],
      wallet1
    );

    expect(withdrawResult.result).toBeErr(Cl.uint(405));
  });

  it("allows early withdrawal with penalty", () => {
    simnet.callPublicFn(
      "savings-vault",
      "create-vault",
      [Cl.uint(100000000000), Cl.uint(LOCK_30_DAYS)],
      wallet1
    );

    const withdrawResult = simnet.callPublicFn(
      "savings-vault",
      "early-withdraw",
      [Cl.uint(1), Cl.uint(50000000000)],
      wallet1
    );

    expect(withdrawResult.result).toBeOk(
      Cl.tuple({
        penalty: Cl.uint(500000000),
        received: Cl.uint(49500000000),
      })
    );
  });

  it("allows withdrawals after lock expiry", () => {
    simnet.callPublicFn(
      "savings-vault",
      "create-vault",
      [Cl.uint(100000000000), Cl.uint(LOCK_7_DAYS)],
      wallet1
    );

    simnet.mineEmptyBlocks(LOCK_7_DAYS + 1);

    const withdrawResult = simnet.callPublicFn(
      "savings-vault",
      "withdraw",
      [Cl.uint(1), Cl.uint(50000000000)],
      wallet1
    );

    expect(withdrawResult.result).toBeOk(Cl.bool(true));
  });

  it("prevents unauthorized withdrawals", () => {
    simnet.callPublicFn(
      "savings-vault",
      "create-vault",
      [Cl.uint(100000000000), Cl.uint(LOCK_7_DAYS)],
      wallet1
    );

    simnet.mineEmptyBlocks(LOCK_7_DAYS + 1);

    const withdrawResult = simnet.callPublicFn(
      "savings-vault",
      "withdraw",
      [Cl.uint(1), Cl.uint(50000000000)],
      wallet2
    );

    expect(withdrawResult.result).toBeErr(Cl.uint(403));
  });

  it("allows closing a vault after full withdrawal", () => {
    simnet.callPublicFn(
      "savings-vault",
      "create-vault",
      [Cl.uint(100000000000), Cl.uint(LOCK_7_DAYS)],
      wallet1
    );

    simnet.mineEmptyBlocks(LOCK_7_DAYS + 1);

    simnet.callPublicFn(
      "savings-vault",
      "withdraw",
      [Cl.uint(1), Cl.uint(100000000000)],
      wallet1
    );

    const closeResult = simnet.callPublicFn(
      "savings-vault",
      "close-vault",
      [Cl.uint(1)],
      wallet1
    );

    expect(closeResult.result).toBeOk(Cl.bool(true));
  });

  it("requires pause for rescue-token", () => {
    simnet.callPublicFn(
      "savings-vault",
      "create-vault",
      [Cl.uint(100000000000), Cl.uint(LOCK_30_DAYS)],
      wallet1
    );

    const rescueWhileActive = simnet.callPublicFn(
      "savings-vault",
      "rescue-token",
      [Cl.principal(`${deployer}.mock-sbtc`), Cl.uint(1), Cl.principal(wallet1)],
      deployer
    );

    expect(rescueWhileActive.result).toBeErr(Cl.uint(410));
  });

  it("rescues tokens when paused", () => {
    simnet.callPublicFn(
      "savings-vault",
      "create-vault",
      [Cl.uint(100000000000), Cl.uint(LOCK_30_DAYS)],
      wallet1
    );

    simnet.callPublicFn(
      "savings-vault",
      "set-contract-paused",
      [Cl.bool(true)],
      deployer
    );

    const rescueResult = simnet.callPublicFn(
      "savings-vault",
      "rescue-token",
      [Cl.principal(`${deployer}.mock-sbtc`), Cl.uint(1000), Cl.principal(wallet2)],
      deployer
    );

    const balanceAfter = simnet.callReadOnlyFn(
      "mock-sbtc",
      "get-balance",
      [Cl.principal(wallet2)],
      deployer
    );

    expect(rescueResult.result).toBeOk(Cl.bool(true));
    expect(balanceAfter.result).toBeOk(Cl.uint(INITIAL_MINT + 1000));
  });
});
