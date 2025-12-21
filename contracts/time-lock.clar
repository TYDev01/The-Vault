;; time-lock.clar
;; Time-lock management contract using block-height for vault lock periods
;; Enforces lock periods and calculates early withdrawal penalties

;; Constants - Error codes
(define-constant err-unauthorized (err u403))
(define-constant err-vault-not-found (err u404))
(define-constant err-still-locked (err u405))
(define-constant err-invalid-lock-period (err u406))
(define-constant err-invalid-penalty (err u407))

;; Contract owner
(define-constant contract-owner tx-sender)

;; Lock period presets (in blocks)
;; Assuming ~10 min per block
(define-constant lock-7-days u1008)      ;; ~7 days
(define-constant lock-30-days u4320)     ;; ~30 days
(define-constant lock-90-days u12960)    ;; ~90 days
(define-constant lock-180-days u25920)   ;; ~180 days

;; Early withdrawal penalty (basis points, e.g., 100 = 1%)
(define-data-var early-withdrawal-penalty uint u100)
(define-constant basis-points u10000)

;; Authorized callers (main-vault, vault-factory)
(define-map authorized-callers principal bool)

;; Vault lock data
(define-map vault-locks uint {
  lock-start: uint,
  lock-until: uint,
  lock-period: uint,
  is-perpetual: bool,
  owner: principal
})

;; Authorization functions

(define-public (add-authorized-caller (caller principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (map-set authorized-callers caller true))
  )
)

(define-public (remove-authorized-caller (caller principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (map-delete authorized-callers caller))
  )
)

(define-private (is-authorized-caller)
  (or 
    (is-eq tx-sender contract-owner)
    (default-to false (map-get? authorized-callers contract-caller))
  )
)

;; Lock management functions

(define-public (create-lock (vault-id uint) (lock-period uint) (is-perpetual bool) (owner principal))
  (begin
    (asserts! (is-authorized-caller) err-unauthorized)
    (asserts! (is-valid-lock-period lock-period) err-invalid-lock-period)
    
    (let
      (
        (lock-start block-height)
        (lock-until (+ block-height lock-period))
      )
      (map-set vault-locks vault-id {
        lock-start: lock-start,
        lock-until: lock-until,
        lock-period: lock-period,
        is-perpetual: is-perpetual,
        owner: owner
      })
      
      (print {
        event: "lock-created",
        vault-id: vault-id,
        lock-start: lock-start,
        lock-until: lock-until,
        lock-period: lock-period,
        is-perpetual: is-perpetual,
        owner: owner
      })
      
      (ok true)
    )
  )
)

(define-public (extend-lock (vault-id uint) (additional-blocks uint))
  (let
    (
      (lock-data (unwrap! (map-get? vault-locks vault-id) err-vault-not-found))
    )
    (asserts! (is-authorized-caller) err-unauthorized)
    (asserts! (> additional-blocks u0) err-invalid-lock-period)
    
    (map-set vault-locks vault-id (merge lock-data {
      lock-until: (+ (get lock-until lock-data) additional-blocks)
    }))
    
    (print {
      event: "lock-extended",
      vault-id: vault-id,
      new-lock-until: (+ (get lock-until lock-data) additional-blocks)
    })
    
    (ok true)
  )
)

(define-public (renew-lock (vault-id uint))
  (let
    (
      (lock-data (unwrap! (map-get? vault-locks vault-id) err-vault-not-found))
      (lock-period (get lock-period lock-data))
    )
    (asserts! (is-authorized-caller) err-unauthorized)
    (asserts! (get is-perpetual lock-data) err-unauthorized)
    
    (let
      (
        (new-lock-until (+ block-height lock-period))
      )
      (map-set vault-locks vault-id (merge lock-data {
        lock-start: block-height,
        lock-until: new-lock-until
      }))
      
      (print {
        event: "lock-renewed",
        vault-id: vault-id,
        new-lock-start: block-height,
        new-lock-until: new-lock-until
      })
      
      (ok true)
    )
  )
)

;; Read-only functions

(define-read-only (check-lock-expiry (vault-id uint))
  (match (map-get? vault-locks vault-id)
    lock-data (ok (>= block-height (get lock-until lock-data)))
    err-vault-not-found
  )
)

(define-read-only (is-locked (vault-id uint))
  (match (map-get? vault-locks vault-id)
    lock-data (ok (< block-height (get lock-until lock-data)))
    err-vault-not-found
  )
)

(define-read-only (get-lock-info (vault-id uint))
  (map-get? vault-locks vault-id)
)

(define-read-only (blocks-until-unlock (vault-id uint))
  (match (map-get? vault-locks vault-id)
    lock-data 
      (if (>= block-height (get lock-until lock-data))
        (ok u0)
        (ok (- (get lock-until lock-data) block-height))
      )
    err-vault-not-found
  )
)

;; Penalty calculation

(define-public (set-early-withdrawal-penalty (new-penalty uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (<= new-penalty u1000) err-invalid-penalty) ;; Max 10%
    (ok (var-set early-withdrawal-penalty new-penalty))
  )
)

(define-read-only (get-early-withdrawal-penalty)
  (var-get early-withdrawal-penalty)
)

(define-read-only (calculate-penalty (amount uint) (vault-id uint))
  (match (map-get? vault-locks vault-id)
    lock-data
      (if (>= block-height (get lock-until lock-data))
        ;; No penalty if lock expired
        (ok {penalty: u0, amount-after-penalty: amount})
        ;; Apply penalty
        (let
          (
            (penalty-amount (/ (* amount (var-get early-withdrawal-penalty)) basis-points))
            (amount-after-penalty (if (>= amount penalty-amount) (- amount penalty-amount) u0))
          )
          (ok {penalty: penalty-amount, amount-after-penalty: amount-after-penalty})
        )
      )
    err-vault-not-found
  )
)

(define-read-only (apply-penalty (vault-id uint) (amount uint))
  (calculate-penalty amount vault-id)
)

;; Helper functions

(define-read-only (is-valid-lock-period (period uint))
  (or
    (is-eq period lock-7-days)
    (is-eq period lock-30-days)
    (is-eq period lock-90-days)
    (is-eq period lock-180-days)
    (and (>= period lock-7-days) (<= period lock-180-days))
  )
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

;; Validation helpers

(define-read-only (can-withdraw (vault-id uint) (caller principal))
  (match (map-get? vault-locks vault-id)
    lock-data
      (ok (and 
        (is-eq caller (get owner lock-data))
        (>= block-height (get lock-until lock-data))
      ))
    err-vault-not-found
  )
)

(define-read-only (can-early-withdraw (vault-id uint) (caller principal))
  (match (map-get? vault-locks vault-id)
    lock-data
      (ok (is-eq caller (get owner lock-data)))
    err-vault-not-found
  )
)
