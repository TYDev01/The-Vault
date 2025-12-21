;; savings-vault.clar
;; Minimal savings protocol with time-locked vaults and optional early withdrawal penalty.

(define-constant err-unauthorized (err u403))
(define-constant err-vault-not-found (err u404))
(define-constant err-invalid-amount (err u101))
(define-constant err-invalid-lock-period (err u406))
(define-constant err-still-locked (err u405))
(define-constant err-insufficient-balance (err u100))
(define-constant err-paused (err u410))
(define-constant err-invalid-penalty (err u407))

(define-constant contract-owner tx-sender)
(define-constant token-contract .mock-sbtc)
(define-constant basis-points u10000)

;; Config
(define-data-var early-withdrawal-penalty uint u100) ;; 1% default
(define-data-var contract-paused bool false)
(define-data-var vault-nonce uint u0)

;; Vault data
(define-map vaults uint {
  owner: principal,
  balance: uint,
  lock-until: uint,
  created-at: uint,
  status: (string-ascii 10)
})

;; Lock period presets (in blocks, ~10 min per block)
(define-constant lock-7-days u1008)
(define-constant lock-30-days u4320)
(define-constant lock-90-days u12960)
(define-constant lock-180-days u25920)
(define-constant max-lock-period lock-180-days)

;; Lock period helpers
(define-read-only (is-valid-lock-period (period uint))
  (and (> period u0) (<= period max-lock-period))
)

(define-read-only (get-lock-period-preset (preset (string-ascii 10)))
  (if (is-eq preset "7d")
    (some lock-7-days)
    (if (is-eq preset "30d")
      (some lock-30-days)
      (if (is-eq preset "90d")
        (some lock-90-days)
        (if (is-eq preset "180d")
          (some lock-180-days)
          none
        )
      )
    )
  )
)

;; Admin functions
(define-public (set-contract-paused (paused bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (var-set contract-paused paused))
  )
)

(define-public (set-early-withdrawal-penalty (new-penalty uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (<= new-penalty u1000) err-invalid-penalty)
    (ok (var-set early-withdrawal-penalty new-penalty))
  )
)

;; Vault lifecycle
(define-public (create-vault (initial-deposit uint) (lock-period uint))
  (begin
    (asserts! (not (var-get contract-paused)) err-paused)
    (asserts! (> initial-deposit u0) err-invalid-amount)
    (asserts! (is-valid-lock-period lock-period) err-invalid-lock-period)
    (let
      (
        (vault-id (+ (var-get vault-nonce) u1))
        (lock-until (+ block-height lock-period))
      )
      (try! (contract-call? token-contract transfer initial-deposit tx-sender (as-contract tx-sender) none))
      (map-set vaults vault-id {
        owner: tx-sender,
        balance: initial-deposit,
        lock-until: lock-until,
        created-at: block-height,
        status: "active"
      })
      (var-set vault-nonce vault-id)
      (print {event: "vault-created", vault-id: vault-id, owner: tx-sender, lock-until: lock-until})
      (ok vault-id)
    )
  )
)

(define-public (create-vault-preset (initial-deposit uint) (lock-preset (string-ascii 10)))
  (let
    (
      (lock-period (unwrap! (get-lock-period-preset lock-preset) err-invalid-lock-period))
    )
    (create-vault initial-deposit lock-period)
  )
)

(define-public (deposit (vault-id uint) (amount uint))
  (let
    (
      (vault (unwrap! (map-get? vaults vault-id) err-vault-not-found))
      (owner (get owner vault))
      (balance (get balance vault))
      (status (get status vault))
    )
    (asserts! (not (var-get contract-paused)) err-paused)
    (asserts! (is-eq tx-sender owner) err-unauthorized)
    (asserts! (is-eq status "active") err-unauthorized)
    (asserts! (> amount u0) err-invalid-amount)
    (try! (contract-call? token-contract transfer amount tx-sender (as-contract tx-sender) none))
    (map-set vaults vault-id (merge vault { balance: (+ balance amount) }))
    (print {event: "deposit", vault-id: vault-id, amount: amount, new-balance: (+ balance amount)})
    (ok true)
  )
)

(define-public (withdraw (vault-id uint) (amount uint))
  (let
    (
      (vault (unwrap! (map-get? vaults vault-id) err-vault-not-found))
      (owner (get owner vault))
      (balance (get balance vault))
      (lock-until (get lock-until vault))
      (status (get status vault))
    )
    (asserts! (not (var-get contract-paused)) err-paused)
    (asserts! (is-eq tx-sender owner) err-unauthorized)
    (asserts! (is-eq status "active") err-unauthorized)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= block-height lock-until) err-still-locked)
    (asserts! (>= balance amount) err-insufficient-balance)
    (try! (as-contract (contract-call? token-contract transfer amount tx-sender owner none)))
    (map-set vaults vault-id (merge vault { balance: (- balance amount) }))
    (print {event: "withdraw", vault-id: vault-id, amount: amount, new-balance: (- balance amount)})
    (ok true)
  )
)

(define-public (early-withdraw (vault-id uint) (amount uint))
  (let
    (
      (vault (unwrap! (map-get? vaults vault-id) err-vault-not-found))
      (owner (get owner vault))
      (balance (get balance vault))
      (locked (< block-height (get lock-until vault)))
      (status (get status vault))
      (penalty-bps (var-get early-withdrawal-penalty))
      (penalty (if locked (/ (* amount penalty-bps) basis-points) u0))
      (received (if (>= amount penalty) (- amount penalty) u0))
    )
    (asserts! (not (var-get contract-paused)) err-paused)
    (asserts! (is-eq tx-sender owner) err-unauthorized)
    (asserts! (is-eq status "active") err-unauthorized)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= balance amount) err-insufficient-balance)
    (try! (as-contract (contract-call? token-contract transfer received tx-sender owner none)))
    (if (> penalty u0)
      (try! (as-contract (contract-call? token-contract transfer penalty tx-sender contract-owner none)))
      true
    )
    (map-set vaults vault-id (merge vault { balance: (- balance amount) }))
    (print {event: "early-withdraw", vault-id: vault-id, amount: amount, penalty: penalty, received: received})
    (ok {penalty: penalty, received: received})
  )
)

;; Vault close
(define-public (close-vault (vault-id uint))
  (let
    (
      (vault (unwrap! (map-get? vaults vault-id) err-vault-not-found))
      (owner (get owner vault))
      (balance (get balance vault))
      (status (get status vault))
    )
    (asserts! (is-eq tx-sender owner) err-unauthorized)
    (asserts! (is-eq status "active") err-unauthorized)
    (asserts! (is-eq balance u0) err-invalid-amount)
    (map-set vaults vault-id (merge vault { status: "closed" }))
    (print {event: "vault-closed", vault-id: vault-id, owner: owner})
    (ok true)
  )
)

;; Read-only helpers
(define-read-only (get-vault (vault-id uint))
  (map-get? vaults vault-id)
)

(define-read-only (is-locked (vault-id uint))
  (match (map-get? vaults vault-id)
    vault (ok (< block-height (get lock-until vault)))
    err-vault-not-found
  )
)

(define-read-only (get-withdrawal-info (vault-id uint) (amount uint))
  (match (map-get? vaults vault-id)
    vault
      (let
        (
          (locked (< block-height (get lock-until vault)))
          (penalty-bps (var-get early-withdrawal-penalty))
          (penalty (if locked (/ (* amount penalty-bps) basis-points) u0))
          (received (if (>= amount penalty) (- amount penalty) u0))
        )
        (ok {
          locked: locked,
          penalty: penalty,
          received: received,
          lock-until: (get lock-until vault)
        })
      )
    err-vault-not-found
  )
)

(define-read-only (get-vault-count)
  (var-get vault-nonce)
)

(define-read-only (get-early-withdrawal-penalty)
  (var-get early-withdrawal-penalty)
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)
