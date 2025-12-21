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
  created-at: uint
})

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
    (asserts! (> lock-period u0) err-invalid-lock-period)
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
        created-at: block-height
      })
      (var-set vault-nonce vault-id)
      (print {event: "vault-created", vault-id: vault-id, owner: tx-sender, lock-until: lock-until})
      (ok vault-id)
    )
  )
)

(define-public (deposit (vault-id uint) (amount uint))
  (let
    (
      (vault (unwrap! (map-get? vaults vault-id) err-vault-not-found))
      (owner (get owner vault))
      (balance (get balance vault))
    )
    (asserts! (not (var-get contract-paused)) err-paused)
    (asserts! (is-eq tx-sender owner) err-unauthorized)
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
    )
    (asserts! (not (var-get contract-paused)) err-paused)
    (asserts! (is-eq tx-sender owner) err-unauthorized)
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
      (penalty-bps (var-get early-withdrawal-penalty))
      (penalty (if locked (/ (* amount penalty-bps) basis-points) u0))
      (received (if (>= amount penalty) (- amount penalty) u0))
    )
    (asserts! (not (var-get contract-paused)) err-paused)
    (asserts! (is-eq tx-sender owner) err-unauthorized)
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
