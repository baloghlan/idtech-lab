path "idtech/data/dev/*" {
  capabilities = ["read"]
}

path "idtech/metadata/dev" {
  capabilities = ["list"]
}

path "idtech/metadata/dev/*" {
  capabilities = ["read", "list"]
}