;; arkadiko-yield-adapter-trait.clar
;; Trait defining the standard interface for yield adapters
;; All yield adapters (Arkadiko, LP, PoX, etc.) must implement this trait

(define-trait arkadiko-yield-adapter-trait
  (
    ;; Deposit funds into the yield-generating protocol
    ;; @param amount: amount to deposit
    ;; @param from: principal depositing funds
    ;; @returns: (ok true) on success, (err uint) on failure
    (deposit (uint principal) (response bool uint))

    ;; Withdraw funds from the yield-generating protocol
    ;; @param amount: amount to withdraw
    ;; @param to: principal receiving funds
    ;; @returns: (ok uint) with actual withdrawn amount on success
    (withdraw (uint principal) (response uint uint))

    ;; Harvest accrued yield without withdrawing principal
    ;; @param vault-id: vault identifier
    ;; @returns: (ok uint) with harvested yield amount on success
    (harvest (uint) (response uint uint))

    ;; Get current balance including principal and accrued yield
    ;; @param vault-id: vault identifier
    ;; @returns: (ok uint) with total balance on success
    (get-balance (uint) (response uint uint))

    ;; Get adapter metadata (name, APY estimate, etc.)
    ;; @returns: (ok tuple) with adapter information
    (get-metadata () (response {name: (string-ascii 50), estimated-apy: uint, total-deposits: uint} uint))
  )
)
