;; main-vault.clar
;; Main vault contract handling user deposits, withdrawals, and yield tracking
;; Orchestrates interactions with time-lock, vault-factory, and auto-yield-engine

;; Constants - Error codes
(define-constant err-unauthorized (err u403))
(define-constant err-vault-not-found (err u404))
(define-constant err-insufficient-balance (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-still-locked (err u405))
(define-constant err-transfer-failed (err u102))
(define-constant err-vault-inactive (err u408))

(define-constant contract-owner tx-sender)

;; Token contract reference
(define-data-var token-contract principal .mock-sbtc)

;; Emergency pause
(define-data-var contract-paused bool false)

;; Admin functions

(define-public (set-token-contract (new-token principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (var-set token-contract new-token))
  )
)

(define-public (set-contract-paused (paused bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (var-set contract-paused paused))
  )
)

(define-public (authorize-time-lock-caller)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (contract-call? .time-lock-v3 add-authorized-caller .main-vault-v3)
  )
)

;; Vault creation

(define-public (create-vault-with-deposit
  (initial-deposit uint)
  (lock-period uint)
  (adapter principal)
  (is-perpetual bool)
)
  (let
    (
      (vault-id-response (try! (contract-call? .vault-factory-v3 create-vault initial-deposit lock-period adapter is-perpetual)))
    )
    ;; Transfer initial deposit to this contract
    (try! (contract-call? .mock-sbtc transfer initial-deposit tx-sender (as-contract tx-sender) none))
    
    ;; Allocate funds to adapter
    (try! (contract-call? .auto-yield-engine-v3 allocate-to-adapter vault-id-response initial-deposit))
    
    (ok vault-id-response)
  )
)

;; Deposit functions

(define-public (deposit (vault-id uint) (amount uint))
  (let
    (
      (vault-info (unwrap! (contract-call? .vault-factory-v3 get-vault-info vault-id) err-vault-not-found))
      (vault-owner (get owner vault-info))
      (current-balance (get balance vault-info))
      (vault-status (get status vault-info))
    )
    ;; Validations
    (asserts! (not (var-get contract-paused)) err-unauthorized)
    (asserts! (is-eq tx-sender vault-owner) err-unauthorized)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (is-eq vault-status "active") err-vault-inactive)
    
    ;; Transfer tokens from user to this contract
    (try! (contract-call? .mock-sbtc transfer amount tx-sender (as-contract tx-sender) none))
    
    ;; Record deposit in vault-factory
    (try! (contract-call? .vault-factory-v3 record-deposit vault-id amount))
    
    ;; Allocate to yield adapter via auto-yield-engine
    (try! (contract-call? .auto-yield-engine-v3 allocate-to-adapter vault-id amount))
    
    (print {
      event: "deposit",
      vault-id: vault-id,
      amount: amount,
      owner: vault-owner,
      new-balance: (+ current-balance amount),
      block-height: block-height
    })
    
    (ok true)
  )
)

;; Withdrawal functions

(define-public (withdraw (vault-id uint) (amount uint))
  (let
    (
      (vault-info (unwrap! (contract-call? .vault-factory-v3 get-vault-info vault-id) err-vault-not-found))
      (vault-owner (get owner vault-info))
      (current-balance (get balance vault-info))
      (vault-status (get status vault-info))
      (is-locked-result (unwrap! (contract-call? .time-lock-v3 is-locked vault-id) err-vault-not-found))
    )
    ;; Validations
    (asserts! (not (var-get contract-paused)) err-unauthorized)
    (asserts! (is-eq tx-sender vault-owner) err-unauthorized)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (not is-locked-result) err-still-locked)
    (asserts! (is-eq vault-status "active") err-vault-inactive)
    (asserts! (>= current-balance amount) err-insufficient-balance)
    
    ;; Withdraw from yield adapter
    (try! (contract-call? .auto-yield-engine-v3 withdraw-from-adapter vault-id amount))
    
    ;; Transfer tokens from this contract to user
    (try! (as-contract (contract-call? .mock-sbtc transfer amount tx-sender vault-owner none)))
    
    ;; Record withdrawal in vault-factory
    (try! (contract-call? .vault-factory-v3 record-withdrawal vault-id amount))
    
    (print {
      event: "withdraw",
      vault-id: vault-id,
      amount: amount,
      owner: vault-owner,
      new-balance: (- current-balance amount),
      block-height: block-height
    })
    
    (ok true)
  )
)

(define-public (early-withdraw (vault-id uint) (amount uint))
  (let
    (
      (vault-info (unwrap! (contract-call? .vault-factory-v3 get-vault-info vault-id) err-vault-not-found))
      (vault-owner (get owner vault-info))
      (current-balance (get balance vault-info))
      (vault-status (get status vault-info))
      (penalty-info (unwrap! (contract-call? .time-lock-v3 apply-penalty vault-id amount) err-vault-not-found))
      (penalty-amount (get penalty penalty-info))
      (amount-after-penalty (get amount-after-penalty penalty-info))
    )
    ;; Validations
    (asserts! (not (var-get contract-paused)) err-unauthorized)
    (asserts! (is-eq tx-sender vault-owner) err-unauthorized)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (is-eq vault-status "active") err-vault-inactive)
    (asserts! (>= current-balance amount) err-insufficient-balance)
    
    ;; Withdraw from yield adapter
    (try! (contract-call? .auto-yield-engine-v3 withdraw-from-adapter vault-id amount))
    
    ;; Transfer tokens (minus penalty) to user
    (try! (as-contract (contract-call? .mock-sbtc transfer amount-after-penalty tx-sender vault-owner none)))
    
    ;; Transfer penalty to contract owner (protocol fee)
    (if (> penalty-amount u0)
      (try! (as-contract (contract-call? .mock-sbtc transfer penalty-amount tx-sender contract-owner none)))
      true
    )
    
    ;; Record withdrawal in vault-factory
    (try! (contract-call? .vault-factory-v3 record-withdrawal vault-id amount))
    
    (print {
      event: "early-withdraw",
      vault-id: vault-id,
      amount: amount,
      penalty: penalty-amount,
      amount-after-penalty: amount-after-penalty,
      owner: vault-owner,
      new-balance: (- current-balance amount),
      block-height: block-height
    })
    
    (ok {penalty: penalty-amount, received: amount-after-penalty})
  )
)

;; Yield management functions

(define-public (harvest-yield (vault-id uint))
  (let
    (
      (vault-info (unwrap! (contract-call? .vault-factory-v3 get-vault-info vault-id) err-vault-not-found))
      (vault-owner (get owner vault-info))
    )
    ;; Validations
    (asserts! (not (var-get contract-paused)) err-unauthorized)
    (asserts! (or (is-eq tx-sender vault-owner) (is-eq tx-sender contract-owner)) err-unauthorized)
    
    ;; Harvest via auto-yield-engine
    (contract-call? .auto-yield-engine-v3 harvest-yield vault-id)
  )
)

(define-public (compound-yield (vault-id uint))
  (let
    (
      (vault-info (unwrap! (contract-call? .vault-factory-v3 get-vault-info vault-id) err-vault-not-found))
      (vault-owner (get owner vault-info))
    )
    ;; Validations
    (asserts! (not (var-get contract-paused)) err-unauthorized)
    (asserts! (or (is-eq tx-sender vault-owner) (is-eq tx-sender contract-owner)) err-unauthorized)
    
    ;; Compound via auto-yield-engine
    (contract-call? .auto-yield-engine-v3 compound-yield vault-id)
  )
)

;; Auto-renew for perpetual vaults

(define-public (renew-perpetual-vault (vault-id uint))
  (let
    (
      (vault-info (unwrap! (contract-call? .vault-factory-v3 get-vault-info vault-id) err-vault-not-found))
      (vault-owner (get owner vault-info))
      (is-perpetual (get is-perpetual vault-info))
    )
    ;; Validations
    (asserts! (not (var-get contract-paused)) err-unauthorized)
    (asserts! (or (is-eq tx-sender vault-owner) (is-eq tx-sender contract-owner)) err-unauthorized)
    (asserts! is-perpetual err-unauthorized)
    
    ;; Check if lock has expired
    (let
      (
        (is-expired (unwrap! (contract-call? .time-lock-v3 check-lock-expiry vault-id) err-vault-not-found))
      )
      (asserts! is-expired err-still-locked)
      
      ;; Harvest and compound before renewing
      (try! (contract-call? .auto-yield-engine-v3 harvest-yield vault-id))
      (try! (contract-call? .auto-yield-engine-v3 compound-yield vault-id))
      
      ;; Renew lock
      (try! (contract-call? .time-lock-v3 renew-lock vault-id))
      
      (print {
        event: "vault-renewed",
        vault-id: vault-id,
        owner: vault-owner,
        block-height: block-height
      })
      
      (ok true)
    )
  )
)

;; Read-only functions

(define-read-only (get-vault-balance (vault-id uint))
  (match (contract-call? .vault-factory-v3 get-vault-info vault-id)
    vault-info (ok (get balance vault-info))
    err-vault-not-found
  )
)

(define-read-only (get-vault-total-value (vault-id uint))
  (match (contract-call? .vault-factory-v3 get-vault-info vault-id)
    vault-info
      (let
        (
          (balance (get balance vault-info))
          (yield-accrued (get yield-accrued vault-info))
        )
        (ok (+ balance yield-accrued))
      )
    err-vault-not-found
  )
)

(define-read-only (can-withdraw-now (vault-id uint))
  (match (contract-call? .time-lock-v3 is-locked vault-id)
    is-locked (ok (not is-locked))
    error-code (err error-code)
  )
)

(define-read-only (get-withdrawal-info (vault-id uint) (amount uint))
  (let
    (
      (vault-info (unwrap! (contract-call? .vault-factory-v3 get-vault-info vault-id) err-vault-not-found))
      (is-locked-result (unwrap! (contract-call? .time-lock-v3 is-locked vault-id) err-vault-not-found))
    )
    (if is-locked-result
      ;; Still locked, show penalty info
      (let
        (
          (penalty-info (unwrap! (contract-call? .time-lock-v3 apply-penalty vault-id amount) err-vault-not-found))
        )
        (ok {
          can-withdraw: false,
          requires-penalty: true,
          penalty: (get penalty penalty-info),
          amount-after-penalty: (get amount-after-penalty penalty-info),
          blocks-until-unlock: (unwrap! (contract-call? .time-lock-v3 blocks-until-unlock vault-id) err-vault-not-found)
        })
      )
      ;; Lock expired, no penalty
      (ok {
        can-withdraw: true,
        requires-penalty: false,
        penalty: u0,
        amount-after-penalty: amount,
        blocks-until-unlock: u0
      })
    )
  )
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

;; Emergency functions

(define-public (emergency-withdraw-tokens (token principal) (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (var-get contract-paused) err-unauthorized)
    (as-contract (contract-call? .mock-sbtc transfer amount tx-sender recipient none))
  )
)
