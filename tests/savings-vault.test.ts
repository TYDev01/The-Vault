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
});
