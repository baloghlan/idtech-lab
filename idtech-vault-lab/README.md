# HashiCorp Vault HA Lab

This project demonstrates a three-node HashiCorp Vault High Availability cluster using Integrated Storage (Raft).

The lab covers:

- Three-node Vault HA architecture
- Integrated Raft storage
- Manual Shamir initialization and unsealing
- KV v2 secrets engine
- Development and production secret separation
- ACL policies based on least privilege
- Developer and administrator tokens
- Vault HTTP API access using cURL
- Raft cluster joining and replication
- Leader election and failover

> **Warning**
>
> TLS is intentionally disabled for the Vault API listeners in this lab.
> This configuration is suitable only for an isolated local laboratory environment.
> Production Vault deployments must use properly configured TLS.

---

## 1. Architecture

The environment consists of three Ubuntu 22.04 virtual machines managed by Incus.

```text
                         Host Machine
                      Arch Linux + Incus
                              |
                         incusbr0
                       192.168.56.1/24
                              |
          +-------------------+-------------------+
          |                   |                   |
          |                   |                   |
   +------v------+      +-----v-------+     +-----v-------+
   |   vault-1   |      |   vault-2   |     |   vault-3   |
   |             |      |             |     |             |
   | 192.168.56.11      | 192.168.56.12     | 192.168.56.13
   |             |      |             |     |             |
   | API  :8200  |      | API  :8200  |     | API  :8200  |
   | Raft :8201  |<---->| Raft :8201  |<--->| Raft :8201  |
   +-------------+      +-------------+     +-------------+
          \                   |                   /
           \__________________|__________________/
                              |
                      Integrated Storage
                         Raft Cluster
```

All nodes use the same Incus network:

```text
Network: 192.168.56.0/24
Gateway: 192.168.56.1
DNS:     192.168.56.1
```

Incus provides NAT connectivity for the virtual machines.

---

## 2. Node Information

| Node | IP Address | API Address | Cluster Address | Raft Node ID |
|---|---|---|---|---|
| vault-1 | `192.168.56.11` | `http://192.168.56.11:8200` | `https://192.168.56.11:8201` | `vault-1` |
| vault-2 | `192.168.56.12` | `http://192.168.56.12:8200` | `https://192.168.56.12:8201` | `vault-2` |
| vault-3 | `192.168.56.13` | `http://192.168.56.13:8200` | `https://192.168.56.13:8201` | `vault-3` |

Port usage:

| Port | Purpose |
|---|---|
| `8200` | Vault HTTP API and Web UI |
| `8201` | Vault internal cluster communication |

---

## 3. Vault Server Configuration

Each node uses Integrated Storage with its own unique Raft `node_id`.

Example configuration for `vault-1`:

```hcl
ui = true

disable_mlock = true

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address         = "192.168.56.11:8200"
  cluster_address = "192.168.56.11:8201"

  tls_disable = 1
}

api_addr     = "http://192.168.56.11:8200"
cluster_addr = "https://192.168.56.11:8201"
```

The follower nodes use the same configuration structure with their own IP addresses and node IDs.

For example, `vault-2` uses:

```text
node_id      = vault-2
API          = 192.168.56.12:8200
Cluster      = 192.168.56.12:8201
```

and `vault-3` uses:

```text
node_id      = vault-3
API          = 192.168.56.13:8200
Cluster      = 192.168.56.13:8201
```

### TLS Note

The API listener uses:

```hcl
tls_disable = 1
```

TLS is disabled because this is an isolated local lab running on an internal Incus network.

This configuration must **not** be used for production deployments.

Although TLS is disabled on the API listener, the `cluster_addr` uses `https`. Vault protects its internal cluster communication separately.

---

## 4. Vault Service

Vault runs as a systemd service under the `vault` user.

Enable and start Vault:

```bash
systemctl enable vault
systemctl start vault
```

Check the service:

```bash
systemctl status vault --no-pager
```

Expected state:

```text
Active: active (running)
Storage: raft (HA available)
```

The Raft data directory is:

```text
/opt/vault/data
```

and is owned by:

```text
vault:vault
```

---

## 5. Initializing the First Node

Set the Vault API address:

```bash
export VAULT_ADDR='http://192.168.56.11:8200'
```

Before initialization:

```bash
vault status
```

The expected initial state is:

```text
Initialized    false
Sealed         true
Storage Type   raft
HA Enabled     true
```

Initialize Vault using five key shares with an unseal threshold of three:

```bash
vault operator init \
  -key-shares=5 \
  -key-threshold=3
```

This generates:

- 5 unseal key shares
- 1 initial root token

These values must be stored securely and must never be committed to this repository.

Three different key shares are required to unseal the node:

```bash
vault operator unseal
vault operator unseal
vault operator unseal
```

After unsealing:

```bash
vault status
```

The expected state is:

```text
Initialized    true
Sealed         false
HA Mode        active
```

Administrative access can be verified using:

```bash
vault login
vault token lookup
```

---

## 6. KV v2 Secrets Engine

A dedicated KV v2 secrets engine is mounted at:

```text
idtech/
```

It can be enabled using:

```bash
vault secrets enable -path=idtech kv-v2
```

The logical secret structure is:

```text
idtech/
├── dev/
│   ├── database
│   └── external-api
└── prod/
    └── database
```

Example test data:

```text
idtech/dev/database
  username = dev_idtech_user
  password = <fake-development-password>

idtech/dev/external-api
  api_key = <fake-development-api-key>

idtech/prod/database
  username = prod_idtech_user
  password = <fake-production-password>
```

All credentials used in this lab are fake test values.

Read the development database secret:

```bash
vault kv get idtech/dev/database
```

Create a new version by updating a field:

```bash
vault kv patch idtech/dev/database \
  password="<new-fake-development-password>"
```

Inspect version history:

```bash
vault kv metadata get idtech/dev/database
```

Read a specific previous version:

```bash
vault kv get -version=1 idtech/dev/database
```

This demonstrates KV v2 secret versioning.

---

## 7. ACL Policies

Two ACL policies are used:

```text
developer
admin
```

### Developer Policy

The `developer` policy follows the least-privilege principle.

The developer can:

- Read development secrets
- List development secret metadata

The developer cannot:

- Create or modify secrets
- Delete secrets
- Read production secrets
- Access Vault system administration endpoints

Policy:

```hcl
path "idtech/data/dev/*" {
  capabilities = ["read"]
}

path "idtech/metadata/dev" {
  capabilities = ["list"]
}

path "idtech/metadata/dev/*" {
  capabilities = ["read", "list"]
}
```

KV v2 uses different API paths for secret data and metadata:

```text
idtech/data/...       Secret values
idtech/metadata/...   Metadata and secret listing
```

The developer policy deliberately does **not** contain a broad rule such as:

```hcl
path "idtech/data/*"
```

because such a wildcard would also grant access to production secrets.

### Administrator Policy

The `admin` policy provides full secret management inside the selected `idtech` secrets engine without granting system-level root privileges.

```hcl
path "idtech/data/*" {
  capabilities = ["create", "read", "update", "patch", "delete"]
}

path "idtech/metadata" {
  capabilities = ["list"]
}

path "idtech/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
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
```

The administrator policy does not grant unrestricted access to paths such as:

```text
sys/*
auth/*
identity/*
```

and does not grant the `sudo` capability.

### Installing Policies

```bash
vault policy write developer developer.hcl
vault policy write admin admin.hcl
```

List policies:

```bash
vault policy list
```

Inspect the policies stored in Vault:

```bash
vault policy read developer
vault policy read admin
```

---

## 8. Token Tests

Two limited tokens are used:

```text
developer-token
admin-token
```

A one-hour TTL is used for the lab. One hour is sufficient to perform the required tests while avoiding unnecessarily long-lived credentials.

### Developer Token

```bash
vault token create \
  -policy=developer \
  -ttl=1h \
  -display-name="developer-token"
```

Login from a separate shell:

```bash
export VAULT_ADDR='http://192.168.56.11:8200'
vault login
```

Verify token information:

```bash
vault token lookup
```

Development access succeeds:

```bash
vault kv get idtech/dev/database
```

Production access must fail:

```bash
vault kv get idtech/prod/database
```

Expected result:

```text
Code: 403
permission denied
```

Attempting to modify a development secret must also fail:

```bash
vault kv patch idtech/dev/database \
  password="unauthorized-change"
```

Expected result:

```text
Code: 403
permission denied
```

### Administrator Token

```bash
vault token create \
  -policy=admin \
  -ttl=1h \
  -display-name="admin-token"
```

After logging in with the administrator token, updating the development secret succeeds:

```bash
vault kv patch idtech/dev/database \
  password="<new-fake-password>"
```

Token TTL and assigned policies can be checked with:

```bash
vault token lookup
```

Important fields include:

```text
display_name
creation_ttl
ttl
policies
```

---

## 9. Vault HTTP API and cURL

Vault exposes its HTTP API on port `8200`.

For KV v2, reading a secret uses the following endpoint structure:

```text
GET /v1/<mount>/data/<secret-path>
```

Therefore the development database endpoint is:

```text
GET /v1/idtech/data/dev/database
```

Vault token authentication uses the HTTP header:

```text
X-Vault-Token
```

### Secure Token Input

The developer token is not written directly into the shell command.

Instead:

```bash
export VAULT_ADDR='http://192.168.56.11:8200'

read -s -p "Developer token: " VAULT_TOKEN
export VAULT_TOKEN
echo
```

### Development Secret

```bash
curl -sS \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -w '\nHTTP Status: %{http_code}\n' \
  "$VAULT_ADDR/v1/idtech/data/dev/database"
```

Expected HTTP status:

```text
HTTP Status: 200
```

### Production Secret

Using the same developer token:

```bash
curl -sS \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -w '\nHTTP Status: %{http_code}\n' \
  "$VAULT_ADDR/v1/idtech/data/prod/database"
```

Expected response:

```json
{
  "errors": [
    "permission denied"
  ]
}
```

Expected HTTP status:

```text
HTTP Status: 403
```

After the API tests, remove the token from the shell:

```bash
unset VAULT_TOKEN
```

Verify:

```bash
printenv VAULT_TOKEN
```

No value should be returned.

---

## 10. Building the Raft HA Cluster

Only `vault-1` is initialized.

`vault-2` and `vault-3` must **not** be independently initialized.

Start Vault on both follower nodes:

```bash
systemctl enable --now vault
```

### Join vault-2

On `vault-2`:

```bash
export VAULT_ADDR='http://192.168.56.12:8200'

vault operator raft join \
  http://192.168.56.11:8200
```

### Join vault-3

On `vault-3`:

```bash
export VAULT_ADDR='http://192.168.56.13:8200'

vault operator raft join \
  http://192.168.56.11:8200
```

The expected result is:

```text
Joined    true
```

Both follower nodes are then unsealed using three of the same unseal key shares generated during the initialization of `vault-1`:

```bash
vault operator unseal
vault operator unseal
vault operator unseal
```

Follower status should show:

```text
Initialized    true
Sealed         false
HA Enabled     true
HA Mode        standby
```

### Raft Peer Verification

From an authenticated administrative session:

```bash
vault operator raft list-peers
```

A healthy cluster contains three unique nodes and exactly one leader:

```text
Node       Address               State       Voter
----       -------               -----       -----
vault-1    192.168.56.11:8201    leader      true
vault-2    192.168.56.12:8201    follower    true
vault-3    192.168.56.13:8201    follower    true
```

The actual leader may change after an election.

A development secret can also be requested through a follower API address:

```bash
export VAULT_ADDR='http://192.168.56.12:8200'
vault kv get idtech/dev/database
```

This demonstrates that the Vault service remains accessible through the HA cluster.

---

## 11. Leader Failover Test

First determine the current leader:

```bash
vault operator raft list-peers
```

Assuming `vault-1` is the current leader, stop its Vault service:

```bash
systemctl stop vault
```

The remaining two nodes maintain Raft quorum and elect a new leader.

Check another node:

```bash
export VAULT_ADDR='http://192.168.56.12:8200'
vault status
```

The elected leader reports:

```text
HA Mode    active
```

The new cluster state can be inspected with:

```bash
vault operator raft list-peers
```

A development secret is then read through the newly elected leader:

```bash
vault kv get idtech/dev/database
```

This proves that Vault remains operational after losing the original leader.

### Recovering the Stopped Node

Restart the old leader:

```bash
systemctl start vault
```

Check its status:

```bash
vault status
```

If the node is sealed after restart, unseal it using three valid key shares:

```bash
vault operator unseal
vault operator unseal
vault operator unseal
```

The recovered node normally rejoins as a follower. It does not need to become leader again.

Do **not** run `raft join` again because its existing Raft membership and persistent data are retained.

Finally:

```bash
vault operator raft list-peers
```

The expected final state is:

```text
3 Raft peers
1 leader
2 followers
All nodes are voters
```

---

## 12. Useful Commands

### Incus

List virtual machines:

```bash
incus list
```

Open a shell on a node:

```bash
incus exec vault-1 -- bash
```

Check VM information:

```bash
incus info vault-1
```

### Vault Service

```bash
systemctl status vault
systemctl start vault
systemctl stop vault
systemctl restart vault
```

Logs:

```bash
journalctl -u vault -n 100 --no-pager
```

### Vault Status

```bash
vault status
```

### Raft

```bash
vault operator raft list-peers
```

### Policies

```bash
vault policy list
vault policy read developer
vault policy read admin
```

### KV v2

```bash
vault kv get idtech/dev/database
vault kv metadata get idtech/dev/database
vault kv get -version=1 idtech/dev/database
```

### Token

```bash
vault token lookup
```

---

## 13. Security Considerations

This project is designed for educational use in an isolated lab environment.

The following choices are intentionally unsuitable for production:

- Vault API TLS is disabled.
- Manual Shamir unseal is used.
- Test credentials are stored in the KV engine.
- Root access is used during initial configuration.
- The virtual machines communicate over a private lab network.

A production deployment should use TLS, secure key management or an appropriate auto-unseal mechanism, strict network controls, auditing, short-lived credentials, carefully scoped policies, and secure handling of recovery/root credentials.

The following sensitive values must never be committed to Git:

```text
Unseal key shares
Initial root token
developer-token value
admin-token value
Any real credentials
```

---

## 14. Final Result

The completed environment provides:

- Three Ubuntu 22.04 Vault nodes
- Integrated Raft storage
- A three-node HA cluster
- One active leader and two standby/follower nodes
- KV v2 secret versioning
- Separate development and production paths
- Least-privilege `developer` policy
- Scoped `admin` policy
- Limited-lifetime `developer-token`
- Limited-lifetime `admin-token`
- HTTP API authorization tests
- Successful Raft leader failover
- Successful recovery of the stopped node

The lab demonstrates both Vault secret-management functionality and the basic availability characteristics of a three-node Integrated Storage cluster.