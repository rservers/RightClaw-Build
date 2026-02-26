#!/bin/bash
# Lightweight encrypted secrets vault for OpenClaw
# Keys are encrypted at rest using AES-256-CBC with a machine-derived key
VAULT_FILE="/opt/openclaw-secure/.vault"
MACHINE_ID=$(cat /etc/machine-id)
VAULT_KEY=$(echo "${MACHINE_ID}openclaw" | sha256sum | cut -d' ' -f1)

vault_set() {
  local name="$1" value="$2"
  local encrypted=$(echo -n "$value" | openssl enc -aes-256-cbc -pbkdf2 -k "$VAULT_KEY" -base64 2>/dev/null)
  # Store in vault file as name=encrypted
  touch "$VAULT_FILE" && chmod 600 "$VAULT_FILE"
  grep -v "^${name}=" "$VAULT_FILE" > "${VAULT_FILE}.tmp" 2>/dev/null || true
  echo "${name}=${encrypted}" >> "${VAULT_FILE}.tmp"
  mv "${VAULT_FILE}.tmp" "$VAULT_FILE"
  echo "Stored: $name"
}

vault_get() {
  local name="$1"
  local encrypted=$(grep "^${name}=" "$VAULT_FILE" 2>/dev/null | cut -d'=' -f2-)
  if [ -z "$encrypted" ]; then echo "NOT_FOUND"; return 1; fi
  echo -n "$encrypted" | openssl enc -aes-256-cbc -pbkdf2 -d -k "$VAULT_KEY" -base64 2>/dev/null
}

vault_list() {
  grep -o '^[^=]*' "$VAULT_FILE" 2>/dev/null || echo '(empty)'
}

case "$1" in
  set)   vault_set "$2" "$3" ;;
  get)   vault_get "$2" ;;
  list)  vault_list ;;
  *)     echo "Usage: vault.sh set|get|list [name] [value]" ;;
esac
