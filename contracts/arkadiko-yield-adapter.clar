;; arkadiko-yield-adapter.clar
;; Mock Arkadiko yield adapter for testing and testnet deployments
;; Simulates deterministic yield generation through lending protocol

(impl-trait .arkadiko-yield-adapter-trait.arkadiko-yield-adapter-trait)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u403))
(define-constant err-insufficient-balance (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-vault-not-found (err u102))
(define-constant err-transfer-failed (err u103))

;; Simulated APY: 500 basis points = 5%
(define-constant simulated-apy u500)
(define-constant basis-points u10000)

;; Blocks per year on Stacks (approximately 52,560 blocks at ~10 min/block)
(define-constant blocks-per-year u52560)

;; Data storage
(define-map vault-deposits uint {
  principal-amount: uint,
  deposit-height: uint,
  last-harvest-height: uint,
  accrued-yield: uint
})

(define-data-var total-deposits uint u0)
(define-data-var total-yield-paid uint u0)
(define-data-var adapter-name (string-ascii 50) "Mock Arkadiko Lending Adapter")

;; Authorization
(define-data-var authorized-caller principal contract-owner)

(define-public (set-authorized-caller (new-caller principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (var-set authorized-caller new-caller))
  )
)

;; Calculate yield based on time elapsed
(define-private (calculate-yield (principal-amt uint) (blocks-elapsed uint))
  (let
    (
      (annual-yield (/ (* principal-amt simulated-apy) basis-points))
      (yield-per-block (/ annual-yield blocks-per-year))
      (total-yield (* yield-per-block blocks-elapsed))
    )
    total-yield
  )
)

;; Implement trait functions

(define-public (deposit (amount uint) (from principal))
  (let
    (
      ;; Use a global pool vault-id for all deposits from main-vault
      (vault-id u1)
      (current-height block-height)
      (existing-deposit (default-to 
        {principal-amount: u0, deposit-height: current-height, last-harvest-height: current-height, accrued-yield: u0}
        (map-get? vault-deposits vault-id)
      ))
    )
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (or (is-eq contract-caller (var-get authorized-caller)) (is-eq tx-sender contract-owner)) err-unauthorized)
    
    ;; Transfer tokens from user to this contract
    (try! (contract-call? .mock-sbtc transfer-from amount from (as-contract tx-sender)))
    
    ;; Update vault deposit record - pool all deposits together
    (map-set vault-deposits vault-id {
      principal-amount: (+ (get principal-amount existing-deposit) amount),
      deposit-height: current-height,
      last-harvest-height: current-height,
      accrued-yield: (get accrued-yield existing-deposit)
    })
    
    ;; Update total deposits
    (var-set total-deposits (+ (var-get total-deposits) amount))
    
    (print {
      event: "deposit",
      vault-id: vault-id,
      amount: amount,
      from: from,
      block-height: current-height
    })
    
    (ok true)
  )
)

(define-public (withdraw (amount uint) (to principal))
  (let
    (
      ;; Use the global pool vault-id
      (vault-id u1)
      (vault-data (unwrap! (map-get? vault-deposits vault-id) err-vault-not-found))
      (principal-amt (get principal-amount vault-data))
      (accrued (get accrued-yield vault-data))
      (blocks-elapsed (- block-height (get last-harvest-height vault-data)))
      (new-yield (calculate-yield principal-amt blocks-elapsed))
      (total-available (+ principal-amt (+ accrued new-yield)))
    )
    (asserts! (>= total-available amount) err-insufficient-balance)
    (asserts! (or (is-eq contract-caller (var-get authorized-caller)) (is-eq tx-sender contract-owner)) err-unauthorized)
    
    ;; Transfer tokens from this contract to user
    (try! (as-contract (contract-call? .mock-sbtc transfer amount tx-sender to none)))
    
    ;; Calculate remaining balance
    (let
      (
        (remaining-total (- total-available amount))
      )
      ;; Update or delete vault record
      (if (is-eq remaining-total u0)
        (map-delete vault-deposits vault-id)
        (map-set vault-deposits vault-id {
          principal-amount: remaining-total,
          deposit-height: block-height,
          last-harvest-height: block-height,
          accrued-yield: u0
        })
      )
    )
    
    ;; Update total deposits
    (var-set total-deposits (if (>= (var-get total-deposits) amount) (- (var-get total-deposits) amount) u0))
    
    (print {
      event: "withdraw",
      vault-id: vault-id,
      amount: amount,
      to: to,
      block-height: block-height
    })
    
    (ok amount)
  )
)

(define-public (harvest (vault-id uint))
  (let
    (
      ;; Always use the global pool vault-id
      (pool-vault-id u1)
      (vault-data (unwrap! (map-get? vault-deposits pool-vault-id) err-vault-not-found))
      (principal-amt (get principal-amount vault-data))
      (accrued (get accrued-yield vault-data))
      (blocks-elapsed (- block-height (get last-harvest-height vault-data)))
      (new-yield (calculate-yield principal-amt blocks-elapsed))
      (total-yield (+ accrued new-yield))
    )
    (asserts! (or (is-eq contract-caller (var-get authorized-caller)) (is-eq tx-sender contract-owner)) err-unauthorized)
    
    ;; Update vault with harvested yield added to accrued
    (map-set vault-deposits pool-vault-id {
      principal-amount: principal-amt,
      deposit-height: (get deposit-height vault-data),
      last-harvest-height: block-height,
      accrued-yield: u0
    })
    
    ;; Track total yield paid
    (var-set total-yield-paid (+ (var-get total-yield-paid) total-yield))
    
    (print {
      event: "harvest",
      vault-id: vault-id,
      yield-amount: total-yield,
      block-height: block-height
    })
    
    (ok total-yield)
  )
)

(define-public (compound-yield (vault-id uint) (yield-amount uint))
  (let
    (
      ;; Always use the global pool vault-id
      (pool-vault-id u1)
      (vault-data (unwrap! (map-get? vault-deposits pool-vault-id) err-vault-not-found))
    )
    (asserts! (or (is-eq contract-caller (var-get authorized-caller)) (is-eq tx-sender contract-owner)) err-unauthorized)
    
    ;; Add yield to principal (virtual compounding - no token transfer needed)
    (map-set vault-deposits pool-vault-id (merge vault-data {
      principal-amount: (+ (get principal-amount vault-data) yield-amount)
    }))
    
    ;; Update total deposits
    (var-set total-deposits (+ (var-get total-deposits) yield-amount))
    
    (print {
      event: "compound",
      vault-id: vault-id,
      yield-amount: yield-amount,
      new-principal: (+ (get principal-amount vault-data) yield-amount),
      block-height: block-height
    })
    
    (ok true)
  )
)

(define-public (get-balance (vault-id uint))
  (let
    (
      ;; Always use the global pool vault-id
      (pool-vault-id u1)
      (vault-data (unwrap! (map-get? vault-deposits pool-vault-id) err-vault-not-found))
      (principal-amt (get principal-amount vault-data))
      (accrued (get accrued-yield vault-data))
      (blocks-elapsed (- block-height (get last-harvest-height vault-data)))
      (new-yield (calculate-yield principal-amt blocks-elapsed))
      (total-balance (+ principal-amt (+ accrued new-yield)))
    )
    (ok total-balance)
  )
)

(define-public (get-metadata)
  (ok {
    name: (var-get adapter-name),
    estimated-apy: simulated-apy,
    total-deposits: (var-get total-deposits)
  })
)

;; Read-only functions for testing

(define-read-only (get-vault-info (vault-id uint))
  (map-get? vault-deposits vault-id)
)

(define-read-only (get-total-deposits)
  (var-get total-deposits)
)

(define-read-only (get-total-yield-paid)
  (var-get total-yield-paid)
)
