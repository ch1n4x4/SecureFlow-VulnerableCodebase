# Per-service least-privilege policy for frontend
path "secureflow/data/frontend" {
  capabilities = ["read"]
}