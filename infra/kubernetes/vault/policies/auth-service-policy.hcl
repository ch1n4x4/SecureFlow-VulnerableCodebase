# Per-service least-privilege policy for auth-service
path "secureflow/data/auth-service" {
  capabilities = ["read"]
}