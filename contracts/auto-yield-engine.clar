;; auto-yield-engine.clar
;; Orchestrator for automatic yield allocation, harvesting, and compounding
;; Uses adapter trait to interact with various yield strategies

;; Constants - Error codes
(define-constant err-unauthorized (err u403))
(define-constant err-vault-not-found (err u404))
(define-constant err-invalid-amount (err u101))
(define-constant err-adapter-error (err u500))
(define-constant err-insufficient-yield (err u501))
(define-constant err-allocation-failed (err u502))

(define-constant contract-owner tx-sender)

;; Yield tracking per vault
(define-map vault-yield-state uint {
  total-allocated: uint,
  total-harvested: uint,
  total-compounded: uint,
  last-harvest-height: uint,
  last-compound-height: uint,
  adapter: principal
})

;; Auto-compound settings
(define-data-var auto-compound-enabled bool true)
(define-data-var min-compound-amount uint u1000000) ;; 0.01 sBTC (assuming 8 decimals)

;; Admin functions

(define-public (set-auto-compound-enabled (enabled bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (var-set auto-compound-enabled enabled))
  )
)

(define-public (set-min-compound-amount (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (var-set min-compound-amount amount))
  )
)

;; Authorization helper
(define-private (is-authorized-caller)
  (or 
    (is-eq tx-sender contract-owner)
    (is-eq contract-caller .main-vault)
    (is-eq contract-caller .vault-factory)
  )
)

;; Yield allocation

(define-public (allocate-to-adapter (vault-id uint) (amount uint))
  (let
    (
      (vault-info (unwrap! (contract-call? .vault-factory get-vault-info vault-id) err-vault-not-found))
      (adapter (get adapter vault-info))
      (current-state (default-to
        {total-allocated: u0, total-harvested: u0, total-compounded: u0, last-harvest-height: block-height, last-compound-height: block-height, adapter: adapter}
        (map-get? vault-yield-state vault-id)
      ))
    )
    ;; Validations
    (asserts! (is-authorized-caller) err-unauthorized)
    (asserts! (> amount u0) err-invalid-amount)
    
    ;; Call adapter's deposit function via trait
    ;; Use contract-caller (main-vault) as the source of funds
    (match (contract-call? .arkadiko-yield-adapter deposit amount contract-caller)
      success
        (begin
          ;; Update yield state
          (map-set vault-yield-state vault-id (merge current-state {
            total-allocated: (+ (get total-allocated current-state) amount),
            adapter: adapter
          }))
          
          (print {
            event: "allocated-to-adapter",
            vault-id: vault-id,
            amount: amount,
            adapter: adapter,
            block-height: block-height
          })
          
          (ok success)
        )
      error-code (err error-code)
    )
  )
)

;; Yield harvesting

(define-public (harvest-yield (vault-id uint))
  (let
    (
      (vault-info (unwrap! (contract-call? .vault-factory get-vault-info vault-id) err-vault-not-found))
      (adapter (get adapter vault-info))
      (current-state (unwrap! (map-get? vault-yield-state vault-id) err-vault-not-found))
    )
    ;; Validations
    (asserts! (is-authorized-caller) err-unauthorized)
    
    ;; Call adapter's harvest function via trait
    (match (contract-call? .arkadiko-yield-adapter harvest vault-id)
      yield-amount
        (begin
          ;; Update yield state
          (map-set vault-yield-state vault-id (merge current-state {
            total-harvested: (+ (get total-harvested current-state) yield-amount),
            last-harvest-height: block-height
          }))
          
          ;; Update vault's accrued yield in factory
          (try! (contract-call? .vault-factory update-vault-yield vault-id yield-amount))
          
          (print {
            event: "yield-harvested",
            vault-id: vault-id,
            yield-amount: yield-amount,
            adapter: adapter,
            block-height: block-height
          })
          
          (ok yield-amount)
        )
      error-code (err error-code)
    )
  )
)

;; Auto-compounding

(define-public (compound-yield (vault-id uint))
  (let
    (
      (vault-info (unwrap! (contract-call? .vault-factory get-vault-info vault-id) err-vault-not-found))
      (yield-accrued (get yield-accrued vault-info))
      (adapter (get adapter vault-info))
      (current-state (unwrap! (map-get? vault-yield-state vault-id) err-vault-not-found))
    )
    ;; Validations
    (asserts! (is-authorized-caller) err-unauthorized)
    (asserts! (>= yield-accrued (var-get min-compound-amount)) err-insufficient-yield)
    
    ;; Compound accrued yield in adapter (virtual - no token transfer)
    (match (contract-call? .arkadiko-yield-adapter compound-yield vault-id yield-accrued)
      success
        (begin
          ;; Update yield state
          (map-set vault-yield-state vault-id (merge current-state {
            total-allocated: (+ (get total-allocated current-state) yield-accrued),
            total-compounded: (+ (get total-compounded current-state) yield-accrued),
            last-compound-height: block-height
          }))
          
          ;; Update vault balance (add yield to principal)
          (try! (contract-call? .vault-factory update-vault-balance vault-id 
            (+ (get balance vault-info) yield-accrued)))
          
          ;; Reset accrued yield to 0
          (try! (contract-call? .vault-factory reset-vault-yield vault-id))
          
          (print {
            event: "yield-compounded",
            vault-id: vault-id,
            compounded-amount: yield-accrued,
            adapter: adapter,
            block-height: block-height
          })
          
          (ok yield-accrued)
        )
      error-code (err error-code)
    )
  )
)

;; Withdrawal from adapter

(define-public (withdraw-from-adapter (vault-id uint) (amount uint))
  (let
    (
      (vault-info (unwrap! (contract-call? .vault-factory get-vault-info vault-id) err-vault-not-found))
      (adapter (get adapter vault-info))
      (vault-owner (get owner vault-info))
      (caller contract-caller)
    )
    ;; Validations
    (asserts! (is-authorized-caller) err-unauthorized)
    (asserts! (> amount u0) err-invalid-amount)
    
    ;; Call adapter's withdraw function via trait
    (match (contract-call? .arkadiko-yield-adapter withdraw amount (as-contract tx-sender))
      withdrawn-amount
        (begin
          ;; Transfer tokens from auto-yield-engine back to main-vault
          (try! (as-contract (contract-call? .mock-sbtc transfer withdrawn-amount tx-sender caller none)))
          
          (print {
            event: "withdrawn-from-adapter",
            vault-id: vault-id,
            amount: withdrawn-amount,
            adapter: adapter,
            block-height: block-height
          })
          
          (ok withdrawn-amount)
        )
      error-code (err error-code)
    )
  )
)

;; Batch operations

(define-public (harvest-multiple-vaults (vault-ids (list 10 uint)))
  (begin
    (asserts! (is-authorized-caller) err-unauthorized)
    (ok (map harvest-yield-internal vault-ids))
  )
)

(define-private (harvest-yield-internal (vault-id uint))
  (match (harvest-yield vault-id)
    success-value true
    error-value false
  )
)

(define-public (compound-multiple-vaults (vault-ids (list 10 uint)))
  (begin
    (asserts! (is-authorized-caller) err-unauthorized)
    (ok (map compound-yield-internal vault-ids))
  )
)

(define-private (compound-yield-internal (vault-id uint))
  (match (compound-yield vault-id)
    success-value true
    error-value false
  )
)

;; Automated harvest and compound (can be called by anyone if enabled)

(define-public (auto-harvest-and-compound (vault-id uint))
  (begin
    (asserts! (var-get auto-compound-enabled) err-unauthorized)
    
    ;; Harvest first
    (match (harvest-yield vault-id)
      yield-amount
        ;; Then compound if sufficient yield
        (if (>= yield-amount (var-get min-compound-amount))
          (compound-yield vault-id)
          (ok yield-amount)
        )
      error-code (err error-code)
    )
  )
)

;; Read-only functions

(define-read-only (get-vault-yield-state (vault-id uint))
  (map-get? vault-yield-state vault-id)
)

(define-public (get-adapter-balance (vault-id uint))
  (contract-call? .arkadiko-yield-adapter get-balance vault-id)
)

(define-public (get-adapter-metadata (vault-id uint))
  (contract-call? .arkadiko-yield-adapter get-metadata)
)

(define-public (calculate-pending-yield (vault-id uint))
  (match (get-adapter-balance vault-id)
    adapter-balance
      (match (map-get? vault-yield-state vault-id)
        yield-state
          (let
            (
              (total-allocated (get total-allocated yield-state))
            )
            (if (> adapter-balance total-allocated)
              (ok (- adapter-balance total-allocated))
              (ok u0)
            )
          )
        (ok u0)
      )
    error-code (err error-code)
  )
)

(define-read-only (get-auto-compound-settings)
  (ok {
    enabled: (var-get auto-compound-enabled),
    min-amount: (var-get min-compound-amount)
  })
)

(define-read-only (should-compound (vault-id uint))
  (match (contract-call? .vault-factory get-vault-info vault-id)
    vault-info
      (let
        (
          (yield-accrued (get yield-accrued vault-info))
        )
        (ok (>= yield-accrued (var-get min-compound-amount)))
      )
    err-vault-not-found
  )
)

;; Statistics

(define-read-only (get-vault-yield-summary (vault-id uint))
  (match (map-get? vault-yield-state vault-id)
    yield-state
      (match (contract-call? .vault-factory get-vault-info vault-id)
        vault-info
          (ok {
            vault-id: vault-id,
            total-allocated: (get total-allocated yield-state),
            total-harvested: (get total-harvested yield-state),
            total-compounded: (get total-compounded yield-state),
            yield-accrued: (get yield-accrued vault-info),
            last-harvest-height: (get last-harvest-height yield-state),
            last-compound-height: (get last-compound-height yield-state),
            adapter: (get adapter yield-state)
          })
        err-vault-not-found
      )
    err-vault-not-found
  )
)
