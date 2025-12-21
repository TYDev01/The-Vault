;; mock-sbtc.clar
;; Mock sBTC token for testing - SIP-010 compliant fungible token
;; Represents Bitcoin-backed token on Stacks blockchain

(impl-trait .sip-010-trait.sip-010-trait)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))

;; Token configuration
(define-fungible-token sbtc)
(define-data-var token-name (string-ascii 32) "Mock sBTC")
(define-data-var token-symbol (string-ascii 10) "mBTC")
(define-data-var token-decimals uint u8)
(define-data-var token-uri (optional (string-utf8 256)) (some u"https://example.com/sbtc.json"))

;; SIP-010 Standard Functions

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (or (is-eq tx-sender sender) (is-eq contract-caller sender)) err-not-token-owner)
    (asserts! (> amount u0) err-invalid-amount)
    (try! (ft-transfer? sbtc amount sender recipient))
    (print {event: "transfer", amount: amount, sender: sender, recipient: recipient})
    (ok true)
  )
)

(define-read-only (get-name)
  (ok (var-get token-name))
)

(define-read-only (get-symbol)
  (ok (var-get token-symbol))
)

(define-read-only (get-decimals)
  (ok (var-get token-decimals))
)

(define-read-only (get-balance (who principal))
  (ok (ft-get-balance sbtc who))
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply sbtc))
)

(define-read-only (get-token-uri)
  (ok (var-get token-uri))
)

;; Additional functions for testing

(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (ft-mint? sbtc amount recipient)
  )
)

(define-public (burn (amount uint) (owner principal))
  (begin
    (asserts! (or (is-eq tx-sender owner) (is-eq tx-sender contract-owner)) err-not-token-owner)
    (asserts! (> amount u0) err-invalid-amount)
    (ft-burn? sbtc amount owner)
  )
)

;; Helper function for contract-to-contract transfers
(define-public (transfer-from (amount uint) (sender principal) (recipient principal))
  (begin
    (asserts! (> amount u0) err-invalid-amount)
    (try! (ft-transfer? sbtc amount sender recipient))
    (print {event: "transfer-from", amount: amount, sender: sender, recipient: recipient})
    (ok true)
  )
)
