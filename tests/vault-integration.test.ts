import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

const LOCK_7_DAYS = 1008;
const LOCK_30_DAYS = 4320;
const LOCK_90_DAYS = 12960;
const INITIAL_MINT = 1000000000000; // 10,000 sBTC (8 decimals)

describe("Savings Vault Integration Tests", () => {
  beforeEach(() => {
    // Authorize contracts to call time-lock
    simnet.callPublicFn(
      "time-lock-v3",
      "add-authorized-caller",
      [Cl.principal(`${deployer}.vault-factory-v3`)],
      deployer
    );
    
    simnet.callPublicFn(
      "time-lock-v3",
      "add-authorized-caller",
      [Cl.principal(`${deployer}.main-vault-v3`)],
      deployer
    );
    
    // Approve the mock adapter in vault-factory
    simnet.callPublicFn(
      "vault-factory-v3",
      "add-approved-adapter",
      [Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`)],
      deployer
    );
    
    // Authorize auto-yield-engine to call the adapter
    simnet.callPublicFn(
      "arkadiko-yield-adapter-v3",
      "set-authorized-caller",
      [Cl.principal(`${deployer}.auto-yield-engine-v3`)],
      deployer
    );
    
    // Mint mock sBTC to test wallets
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

  describe("Vault Creation", () => {
    it("should create a vault with initial deposit", () => {
      const depositAmount = 100000000000; // 1,000 sBTC
      
      const result = simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(depositAmount),
          Cl.uint(LOCK_30_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(false),
        ],
        wallet1
      );

      expect(result.result).toBeOk(Cl.uint(1));
    });

    it("should fail to create vault with zero deposit", () => {
      const result = simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(0),
          Cl.uint(LOCK_30_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(false),
        ],
        wallet1
      );

      expect(result.result).toBeErr(Cl.uint(400)); // err-invalid-amount
    });
  });

  describe("Deposits", () => {
    it("should allow deposit to existing vault", () => {
      // Create vault first
      const initialDeposit = 100000000000;
      const createResult = simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(initialDeposit),
          Cl.uint(LOCK_30_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(false),
        ],
        wallet1
      );

      const vaultId = 1;
      const additionalDeposit = 50000000000; // 500 sBTC

      const depositResult = simnet.callPublicFn(
        "main-vault-v3",
        "deposit",
        [Cl.uint(vaultId), Cl.uint(additionalDeposit)],
        wallet1
      );

      expect(depositResult.result).toBeOk(Cl.bool(true));
    });
  });

  describe("Time Locks", () => {
    it("should prevent withdrawal before lock expires", () => {
      // Create vault
      const depositAmount = 100000000000;
      simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(depositAmount),
          Cl.uint(LOCK_30_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(false),
        ],
        wallet1
      );

      const vaultId = 1;

      // Try to withdraw immediately
      const withdrawResult = simnet.callPublicFn(
        "main-vault-v3",
        "withdraw",
        [Cl.uint(vaultId), Cl.uint(50000000000)],
        wallet1
      );

      expect(withdrawResult.result).toBeErr(Cl.uint(405)); // err-still-locked
    });

    it("should allow early withdrawal with penalty", () => {
      // Create vault
      const depositAmount = 100000000000;
      simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(depositAmount),
          Cl.uint(LOCK_30_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(false),
        ],
        wallet1
      );

      const vaultId = 1;
      const withdrawAmount = 50000000000;

      // Early withdraw with penalty
      const withdrawResult = simnet.callPublicFn(
        "main-vault-v3",
        "early-withdraw",
        [Cl.uint(vaultId), Cl.uint(withdrawAmount)],
        wallet1
      );

      expect(withdrawResult.result).toBeOk(Cl.tuple({
        penalty: Cl.uint(500000000), // 1% penalty (50,000,000,000 * 0.01)
        received: Cl.uint(49500000000),
      }));
    });

    it("should allow withdrawal after lock expires", () => {
      // Create vault
      const depositAmount = 100000000000;
      simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(depositAmount),
          Cl.uint(LOCK_7_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(false),
        ],
        wallet1
      );

      // Advance blockchain by more than 7 days worth of blocks
      simnet.mineEmptyBlocks(LOCK_7_DAYS + 1);

      const vaultId = 1;
      const withdrawAmount = 50000000000;

      const withdrawResult = simnet.callPublicFn(
        "main-vault-v3",
        "withdraw",
        [Cl.uint(vaultId), Cl.uint(withdrawAmount)],
        wallet1
      );

      expect(withdrawResult.result).toBeOk(Cl.bool(true));
    });
  });

  describe("Yield Generation", () => {
    it("should accumulate yield over time", () => {
      // Create vault
      const depositAmount = 100000000000;
      simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(depositAmount),
          Cl.uint(LOCK_30_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(false),
        ],
        wallet1
      );

      const vaultId = 1;

      // Mine blocks to simulate time passing (simulate 30 days)
      simnet.mineEmptyBlocks(LOCK_30_DAYS);

      // Harvest yield
      const harvestResult = simnet.callPublicFn(
        "main-vault-v3",
        "harvest-yield",
        [Cl.uint(vaultId)],
        wallet1
      );

      // Should have harvested some yield (exact amount depends on APY calculation)
      expect(harvestResult.result).toBeOk(expect.any(Object));
    });

    it("should compound yield when requested", () => {
      // Create vault
      const depositAmount = 100000000000;
      simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(depositAmount),
          Cl.uint(LOCK_90_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(false),
        ],
        wallet1
      );

      const vaultId = 1;

      // Mine blocks to accumulate yield
      simnet.mineEmptyBlocks(5000);

      // Harvest first
      simnet.callPublicFn(
        "main-vault-v3",
        "harvest-yield",
        [Cl.uint(vaultId)],
        wallet1
      );

      // Then compound
      const compoundResult = simnet.callPublicFn(
        "main-vault-v3",
        "compound-yield",
        [Cl.uint(vaultId)],
        wallet1
      );

      expect(compoundResult.result).toBeOk(expect.any(Object));
    });
  });

  describe("Perpetual Vaults", () => {
    it("should create and renew perpetual vault", () => {
      // Create perpetual vault
      const depositAmount = 100000000000;
      simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(depositAmount),
          Cl.uint(LOCK_30_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(true), // perpetual
        ],
        wallet1
      );

      const vaultId = 1;

      // Mine blocks past lock period
      simnet.mineEmptyBlocks(LOCK_30_DAYS + 1);

      // Renew vault
      const renewResult = simnet.callPublicFn(
        "main-vault-v3",
        "renew-perpetual-vault",
        [Cl.uint(vaultId)],
        wallet1
      );

      expect(renewResult.result).toBeOk(Cl.bool(true));
    });
  });

  describe("Access Control", () => {
    it("should prevent unauthorized withdrawal", () => {
      // Create vault with wallet1
      const depositAmount = 100000000000;
      simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(depositAmount),
          Cl.uint(LOCK_7_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(false),
        ],
        wallet1
      );

      const vaultId = 1;

      // Advance past lock
      simnet.mineEmptyBlocks(LOCK_7_DAYS + 1);

      // Try to withdraw with wallet2
      const withdrawResult = simnet.callPublicFn(
        "main-vault-v3",
        "withdraw",
        [Cl.uint(vaultId), Cl.uint(50000000000)],
        wallet2
      );

      expect(withdrawResult.result).toBeErr(Cl.uint(403)); // err-unauthorized
    });
  });

  describe("Vault Factory", () => {
    it("should retrieve vault information", () => {
      // Create vault
      const depositAmount = 100000000000;
      simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(depositAmount),
          Cl.uint(LOCK_30_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(false),
        ],
        wallet1
      );

      const vaultId = 1;

      // Get vault info
      const vaultInfo = simnet.callReadOnlyFn(
        "vault-factory-v3",
        "get-vault-info",
        [Cl.uint(vaultId)],
        wallet1
      );

      // Verify vault info is returned
      expect(vaultInfo.result).toBeSome(expect.any(Object));
    });

    it("should track user vaults", () => {
      // Create multiple vaults
      simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(100000000000),
          Cl.uint(LOCK_7_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(false),
        ],
        wallet1
      );

      simnet.callPublicFn(
        "main-vault-v3",
        "create-vault-with-deposit",
        [
          Cl.uint(200000000000),
          Cl.uint(LOCK_30_DAYS),
          Cl.principal(`${deployer}.arkadiko-yield-adapter-v3`),
          Cl.bool(true),
        ],
        wallet1
      );

      // Get user vaults
      const userVaults = simnet.callReadOnlyFn(
        "vault-factory-v3",
        "get-user-vaults",
        [Cl.principal(wallet1)],
        wallet1
      );

      expect(userVaults.result).toBeList([Cl.uint(1), Cl.uint(2)]);
    });
  });
});
