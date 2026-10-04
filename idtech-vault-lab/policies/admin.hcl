path "idtech/data/*" {
  capabilities = ["create", "read", "update", "patch", "delete"]
}

path "idtech/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "idtech/metadata" {
  capabilities = ["list"]
}

path "idtech/delete/*" {
  capabilities = ["update"]
}

path "idtech/undelete/*" {
  capabilities = ["update"]
}

path "idtech/destroy/*" {
  capabilities = ["update"]
}