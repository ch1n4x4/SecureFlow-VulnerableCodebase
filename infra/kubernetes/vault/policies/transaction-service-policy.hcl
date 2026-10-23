# Per-service least-privilege policy for transaction-service
path "secureflow/data/transaction-service" {
  capabilities = ["read"]
}