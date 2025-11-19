# Secret Synchronization Analysis

## Problem Statement

The cluster has a systemic issue where different components become desynchronized on password/secret values,
leading to authentication failures. This violates the PRIMARY DIRECTIVE of achieving reliable turnkey bootstrap.

## Root Cause

**ESO Password Generator Volatility**: ExternalSecrets Operator (ESO) Password generators regenerate values on
every `refreshInterval`, but applications that have already consumed and persisted those values don't
automatically update.

## Affected Systems

### 1. PowerDNS API Key

**Current Configuration:**

- Password generator: `powerdns-api-key-generator` (dns-system namespace)
- Refresh interval: **1 hour**
- Secret: `powerdns-api-key` (dns-system, reflected to cert-manager/external-dns/powerdns-operator)

**Synchronization Points:**

1. ESO generates password → Kubernetes Secret (`PDNS_API_KEY`)
2. PowerDNS pod reads secret via environment variable → `PDNS_api_key` env var
3. PowerDNS **writes to PostgreSQL DB on init** (first boot with empty PVC)
4. External consumers (webhook, external-dns, operator) read from reflected secret

**Failure Mode:**

- PowerDNS pod starts: 05:49 UTC (reads password: `NDPEfQ44KYK8FE3Yj3x7Rv7MW8RR93mp`)
- PostgreSQL DB initialized with this password
- ESO refreshes secret: 08:52 UTC (regenerates NEW password)
- Secret updated with new value
- PowerDNS still running with old env var (no restart)
- **But DB has old password, new password in env var won't work for DB connection**
- Webhook reads NEW password from secret → authentication fails (401 Unauthorized)

**Critical Issue**: PowerDNS only applies password to DB on init (empty PVC). After that, the DB password is
immutable unless you manually ALTER USER or destroy the PVC.

### 2. Authentik Bootstrap Token

**Current Configuration:**

- Password generator: `authentik-bootstrap-password` (authentik namespace)
- Refresh interval: **24 hours**
- Secret: `authentik-bootstrap` → consumed by Job and Authentik pods

**Synchronization Points:**

1. ESO generates token → Secret `authentik-bootstrap`
2. Authentik pods read secret → Bootstrap token in application DB
3. Kubernetes Job reads secret → Posts token to `/api/v3/core/tokens/`
4. Terraform reads secret → Uses token for Authentik provider authentication

**Failure Mode:**

- Bootstrap Job runs at cluster creation → writes token A to Authentik DB
- 24 hours later: ESO refreshes → secret now has token B
- Authentik pods still running with token A loaded
- Terraform reads token B from secret → 403 "Token invalid/expired"
- **Job immutability**: Can't update Job to re-run with new token

### 3. Authentik PostgreSQL Password

**Current Configuration:**

- Password generator: `authentik-postgres-password-generator`
- Refresh interval: **1 hour** (most volatile!)
- Secret: `authentik-postgres` → consumed by Authentik and PostgreSQL

**Synchronization Points:**

1. ESO generates password → Secret
2. PostgreSQL init: Sets postgres user password on first boot (empty PVC)
3. Authentik connection string reads from secret

**Failure Mode:**

- PostgreSQL initializes with password at 10:00
- ESO refreshes at 11:00 → new password in secret
- Authentik pods restart → connection string uses NEW password
- PostgreSQL DB still has OLD password
- **Result**: Authentik can't connect to database (FATAL: password authentication failed)

## Dependency Chain Analysis

```text
┌─────────────────────────────────────────────────────────────────────┐
│ ESO Password Generator (volatile, regenerates every refresh)       │
└──────────────────┬──────────────────────────────────────────────────┘
                   │
                   ▼
         ┌─────────────────────┐
         │ Kubernetes Secret   │
         │  (mutable, changes) │
         └──────┬──────────────┘
                │
        ┌───────┴───────────────────────┐
        │                               │
        ▼                               ▼
┌──────────────────┐          ┌────────────────────┐
│ Application Pod  │          │ Init Script/Job    │
│ (reads at start) │          │ (writes to DB)     │
└────────┬─────────┘          └─────────┬──────────┘
         │                              │
         │ No auto-restart              │ Runs once, immutable
         │                              │
         ▼                              ▼
┌──────────────────┐          ┌────────────────────┐
│ Environment Var  │          │ PostgreSQL Database│
│ (stale)          │          │ (persisted, stable)│
└──────────────────┘          └────────────────────┘
         │                              │
         └──────────┬───────────────────┘
                    │
                    ▼
             Desynchronized!
     Pod env var ≠ DB password ≠ Secret value
```

## Why This Is Critical

**Violates PRIMARY DIRECTIVE**: The turnkey bootstrap requirement means `terraform destroy && bootstrap.sh` must
result in working cluster. But with volatile passwords:

1. First bootstrap: Works (everything uses same initial password)
2. Wait 1-24 hours
3. ESO refreshes → passwords change
4. Services break → authentication failures
5. `terraform destroy && bootstrap.sh` again → Works temporarily
6. Cycle repeats

**This is not acceptable for production** - services should not spontaneously break after 1-24 hours of uptime.

## Solution Options

### Option 1: Make Passwords Immutable (Simplest)

**Change refresh intervals from `1h`/`24h` to `never` or very long (1 year)**

Pros:

- Simple declarative fix
- No architectural changes
- Passwords stable across cluster lifetime

Cons:

- No automatic password rotation
- If secret deleted, new password generated (desync risk on secret recreation)

### Option 2: Use Vault Backing for ESO (Best)

#### Configure Password generators to store values in Vault

ESO should pull from Vault instead of regenerating values.

Currently:

```yaml
spec:
  dataFrom:
    - sourceRef:
        generatorRef:
          kind: Password  # Regenerates every refresh!
```

Change to:

```yaml
spec:
  data:
    - secretKey: password
      remoteRef:
        key: secret/powerdns-api-key  # Stable value in Vault
```

With initial generation via Terraform:

```hcl
resource "vault_kv_secret_v2" "powerdns_api_key" {
  mount = "secret"
  name  = "powerdns-api-key"
  data_json = jsonencode({
    password = random_password.powerdns_api_key.result
  })
}

resource "random_password" "powerdns_api_key" {
  length  = 32
  special = false
}
```

Pros:

- Passwords persist in Vault across cluster destroy/recreate
- ESO syncs stable values (no regeneration)
- Enables password rotation when needed (update Vault value → ESO syncs → restart pods)
- Single source of truth for secrets

Cons:

- Requires Vault Terraform resources for each secret
- More complex than Option 1

### Option 3: Add Restart Triggers (Incomplete Solution)

#### Use Reloader or similar to restart pods when secrets change

Pros:

- Keeps passwords rotating
- Pods automatically pick up new values

Cons:

- **Doesn't solve DB init problem**: Restarting pod doesn't re-run init scripts
- **Service disruption**: Constant restarts every 1-24 hours
- Still breaks for init-once patterns (Job, DB schema)

### Option 4: Remove Init-Time Password Applications

#### Make applications reload passwords dynamically

Applications should accept password changes without restart.

Pros:

- True dynamic secret rotation

Cons:

- Requires application support (PostgreSQL doesn't support this)
- Not viable for third-party applications
- Complex to implement

## Recommended Solution

**Hybrid Approach:**

1. **Short term (immediate fix)**: Change refresh intervals to `never` or `8760h` (1 year)
   - Stops ongoing authentication failures
   - Achieves stable turnkey bootstrap

2. **Long term (proper architecture)**: Migrate to Vault-backed secrets
   - Use Terraform to generate initial passwords and store in Vault
   - Configure ESO to pull from Vault (stable values)
   - Enable controlled rotation when needed

## Implementation Plan

### Phase 1: Immediate Stabilization (This PR)

Change all volatile password generators to stable intervals:

```yaml
# Before
spec:
  refreshInterval: 1h  # or 24h

# After
spec:
  refreshInterval: never  # or 8760h for annual rotation
```

Files to update:

- `charts/powerdns/templates/externalsecret.yaml` (powerdns-api-key)
- `charts/authentik/templates/externalsecret.yaml` (bootstrap token, postgres password)

### Phase 2: Vault Migration (Future Work)

1. Create Terraform module for secret generation:

   ```text
   terraform/gitops/secrets/
   ├── main.tf           # Vault KV secrets
   ├── passwords.tf      # random_password resources
   └── outputs.tf        # Secret paths
   ```

2. Update ExternalSecret resources to use Vault remoteRef instead of generators

3. Remove Password generator resources

4. Document rotation procedure in OPERATIONS.md

## Webhook Namespace Issue (Separate Problem)

**Issue**: ClusterIssuer `apiKeySecretRef` without explicit namespace causes cert-manager to look in Certificate
namespace (e.g., `monitoring`) instead of where secret exists (`cert-manager`).

**Fix**: Always specify namespace in `apiKeySecretRef`:

```yaml
apiKeySecretRef:
  name: powerdns-api-key
  key: PDNS_API_KEY
  namespace: cert-manager  # Explicit namespace required!
```

**Why**: Secrets are created in `dns-system` and reflected to `cert-manager`. If namespace not specified,
cert-manager defaults to the Certificate resource's namespace, causing "secret not found" errors.

**Resolution stored in**: Will add to CLAUDE.md troubleshooting section.
