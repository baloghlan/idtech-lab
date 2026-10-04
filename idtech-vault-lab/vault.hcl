ui = true
disable_mlock = true

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address         = "192.168.56.11:8200"
  cluster_address = "192.168.56.11:8201"
  tls_disable     = 1
}

api_addr     = "http://192.168.56.11:8200"
cluster_addr = "https://192.168.56.11:8201"