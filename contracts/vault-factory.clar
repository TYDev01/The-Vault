;; vault-factory.clar
;; Factory contract for creating and managing savings vaults
;; Handles vault creation, configuration, and lifecycle management

;; Constants - Error codes
(define-constant err-unauthorized (err u403))
(define-constant err-invalid-amount (err u400))
(define-constant err-invalid-lock-period (err u401))
(define-constant err-vault-not-found (err u404))
(define-constant err-vault-exists (err u409))
(define-constant err-invalid-adapter (err u402))

(define-constant contract-owner tx-sender)

;; Vault counter for unique IDs
(define-data-var vault-nonce uint u0)

;; Vault registry
(define-map vaults uint {
  owner: principal,
  balance: uint,
  lock-period: uint,
  lock-until: uint,
  created-at: uint,
  adapter: principal,
  is-perpetual: bool,
  yield-accrued: uint,
  total-deposited: uint,
  total-withdrawn: uint,
  status: (string-ascii 20)
})

;; User vault mapping (owner -> list of vault IDs)
(define-map user-vaults principal (list 100 uint))

;; Adapter whitelist
(define-map approved-adapters principal bool)

;; Token configuration
(define-data-var token-contract principal .mock-sbtc)

;; Initialize contract
(map-set approved-adapters .arkadiko-yield-adapter true)

;; Admin functions

(define-public (set-token-contract (new-token principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (var-set token-contract new-token))
  )
)

(define-public (add-approved-adapter (adapter principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (map-set approved-adapters adapter true))
  )
)

(define-public (remove-approved-adapter (adapter principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (map-delete approved-adapters adapter))
  )
)

;; Vault creation

(define-public (create-vault 
  (initial-deposit uint)
  (lock-period uint)
  (adapter principal)
  (is-perpetual bool)
)
  (let
    (
      (vault-id (+ (var-get vault-nonce) u1))
      (owner tx-sender)
      (current-height block-height)
      (lock-until (+ current-height lock-period))
    )
    ;; Validations
    (asserts! (> initial-deposit u0) err-invalid-amount)
    (asserts! (> lock-period u0) err-invalid-lock-period)
    (asserts! (default-to false (map-get? approved-adapters adapter)) err-invalid-adapter)
    
    ;; Create vault record
    (map-set vaults vault-id {
      owner: owner,
      balance: initial-deposit,
      lock-period: lock-period,
      lock-until: lock-until,
      created-at: current-height,
      adapter: adapter,
      is-perpetual: is-perpetual,
      yield-accrued: u0,
      total-deposited: initial-deposit,
      total-withdrawn: u0,
      status: "active"
    })
    
    ;; Add to user's vault list
    (add-vault-to-user owner vault-id)
    
    ;; Create time-lock entry
    (try! (contract-call? .time-lock create-lock vault-id lock-period is-perpetual owner))
    
    ;; Increment nonce
    (var-set vault-nonce vault-id)
    
    ;; Note: Token transfer happens in the calling contract (main-vault)
    
    (print {
      event: "vault-created",
      vault-id: vault-id,
      owner: owner,
      initial-deposit: initial-deposit,
      lock-period: lock-period,
      lock-until: lock-until,
      adapter: adapter,
      is-perpetual: is-perpetual,
      created-at: current-height
    })
    
    (ok vault-id)
  )
)

(define-public (create-vault-preset
  (initial-deposit uint)
  (lock-preset (string-ascii 10))
  (adapter principal)
  (is-perpetual bool)
)
  (let
    (
      (lock-period (unwrap! (contract-call? .time-lock get-lock-period-preset lock-preset) err-invalid-lock-period))
    )
    (create-vault initial-deposit lock-period adapter is-perpetual)
  )
)

;; Vault management

(define-public (close-vault (vault-id uint))
  (let
    (
      (vault-data (unwrap! (map-get? vaults vault-id) err-vault-not-found))
    )
    (asserts! (is-eq tx-sender (get owner vault-data)) err-unauthorized)
    (asserts! (is-eq (get balance vault-data) u0) err-invalid-amount)
    
    (map-set vaults vault-id (merge vault-data {
      status: "closed"
    }))
    
    (print {
      event: "vault-closed",
      vault-id: vault-id,
      owner: tx-sender
    })
    
    (ok true)
  )
)

(define-public (update-vault-balance (vault-id uint) (new-balance uint))
  (let
    (
      (vault-data (unwrap! (map-get? vaults vault-id) err-vault-not-found))
    )
    ;; Only authorized contracts can update balance
    (asserts! (or 
      (is-eq contract-caller .main-vault)
      (is-eq contract-caller .auto-yield-engine)
      (is-eq tx-sender contract-owner)
    ) err-unauthorized)
    
    (map-set vaults vault-id (merge vault-data {
      balance: new-balance
    }))
    
    (ok true)
  )
)

(define-public (update-vault-yield (vault-id uint) (yield-amount uint))
  (let
    (
      (vault-data (unwrap! (map-get? vaults vault-id) err-vault-not-found))
      (new-yield (+ (get yield-accrued vault-data) yield-amount))
    )
    ;; Only authorized contracts can update yield
    (asserts! (or 
      (is-eq contract-caller .auto-yield-engine)
      (is-eq tx-sender contract-owner)
    ) err-unauthorized)
    
    (map-set vaults vault-id (merge vault-data {
      yield-accrued: new-yield
    }))
    
    (ok true)
  )
)

(define-public (reset-vault-yield (vault-id uint))
  (let
    (
      (vault-data (unwrap! (map-get? vaults vault-id) err-vault-not-found))
    )
    ;; Only authorized contracts can reset yield
    (asserts! (or 
      (is-eq contract-caller .auto-yield-engine)
      (is-eq tx-sender contract-owner)
    ) err-unauthorized)
    
    (map-set vaults vault-id (merge vault-data {
      yield-accrued: u0
    }))
    
    (ok true)
  )
)

(define-public (record-deposit (vault-id uint) (amount uint))
  (let
    (
      (vault-data (unwrap! (map-get? vaults vault-id) err-vault-not-found))
      (new-balance (+ (get balance vault-data) amount))
      (new-total-deposited (+ (get total-deposited vault-data) amount))
    )
    (asserts! (or 
      (is-eq contract-caller .main-vault)
      (is-eq tx-sender contract-owner)
    ) err-unauthorized)
    
    (map-set vaults vault-id (merge vault-data {
      balance: new-balance,
      total-deposited: new-total-deposited
    }))
    
    (ok true)
  )
)

(define-public (record-withdrawal (vault-id uint) (amount uint))
  (let
    (
      (vault-data (unwrap! (map-get? vaults vault-id) err-vault-not-found))
      (current-balance (get balance vault-data))
      (new-balance (if (>= current-balance amount) (- current-balance amount) u0))
      (new-total-withdrawn (+ (get total-withdrawn vault-data) amount))
    )
    (asserts! (or 
      (is-eq contract-caller .main-vault)
      (is-eq tx-sender contract-owner)
    ) err-unauthorized)
    
    (map-set vaults vault-id (merge vault-data {
      balance: new-balance,
      total-withdrawn: new-total-withdrawn
    }))
    
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-vault-info (vault-id uint))
  (map-get? vaults vault-id)
)

(define-read-only (get-user-vaults (user principal))
  (default-to (list) (map-get? user-vaults user))
)

(define-read-only (get-vault-count)
  (var-get vault-nonce)
)

(define-read-only (is-vault-owner (vault-id uint) (user principal))
  (match (map-get? vaults vault-id)
    vault-data (ok (is-eq user (get owner vault-data)))
    err-vault-not-found
  )
)

(define-read-only (is-adapter-approved (adapter principal))
  (default-to false (map-get? approved-adapters adapter))
)

(define-read-only (get-token-contract)
  (var-get token-contract)
)

;; Helper functions

(define-private (add-vault-to-user (user principal) (vault-id uint))
  (let
    (
      (current-vaults (default-to (list) (map-get? user-vaults user)))
    )
    (map-set user-vaults user (unwrap-panic (as-max-len? (append current-vaults vault-id) u100)))
  )
)

;; Batch operations

(define-read-only (get-multiple-vaults (vault-ids (list 20 uint)))
  (map get-vault-info vault-ids)
)

(define-read-only (get-vault-summary (vault-id uint))
  (match (map-get? vaults vault-id)
    vault-data
      (let
        (
          (lock-info (contract-call? .time-lock get-lock-info vault-id))
        )
        (ok {
          vault-id: vault-id,
          owner: (get owner vault-data),
          balance: (get balance vault-data),
          yield-accrued: (get yield-accrued vault-data),
          status: (get status vault-data),
          is-perpetual: (get is-perpetual vault-data),
          adapter: (get adapter vault-data),
          lock-info: lock-info
        })
      )
    err-vault-not-found
  )
)
