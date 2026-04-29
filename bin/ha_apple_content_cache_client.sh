#!/bin/bash
set -euo pipefail

# Show help if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat << EOF
ha_apple_content_cache_client.sh - Home Assistant Apple Content Caching client

USAGE:
  ha_apple_content_cache_client.sh [--help|-h]

DESCRIPTION:
  Pushes Apple Content Caching metrics from macOS to Home Assistant via REST API.
  
CONFIGURATION:
  Set HA_URL, HA_TOKEN, and optionally CLIENT_ID and CACHE_NAME in:
  ${ENV_PATH:-/usr/local/etc/ha-apple_content_cache-client/.env}

EXAMPLES:
  ha_apple_content_cache_client.sh         # Run once
  brew services start ...                  # Run as service
EOF
  exit 0
fi

ENV_PATH="${ENV_PATH:-/usr/local/etc/ha-apple_content_cache-client/.env}"
if [ -f "$ENV_PATH" ]; then
  export $(grep -v '^#' "$ENV_PATH" | xargs)
fi

HA_URL="${HA_URL:-}"
HA_TOKEN="${HA_TOKEN:-}"
CACHE_NAME="${CACHE_NAME:-Apple Content Caching}"

if [ -z "$HA_URL" ] || [ -z "$HA_TOKEN" ]; then
  echo "Error: HA_URL and HA_TOKEN must be set in $ENV_PATH"
  exit 1
fi

if [ -n "${CLIENT_ID:-}" ]; then
  CLIENT_NAME="$CLIENT_ID"
else
  CLIENT_NAME=$(hostname -s)
fi

HOME="${HOME:-$(eval echo ~$(whoami))}"
LOG_FILE="$HOME/Library/Logs/ha-apple_content_cache-client.log"
mkdir -p "$(dirname "$LOG_FILE")"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# Debug: Log configuration (without exposing full token)
token_preview=$(echo "$HA_TOKEN" | cut -c1-8)
echo "[$(timestamp)] Config - URL: $HA_URL, Token: ${token_preview}..., Client: $CLIENT_NAME" >> "$LOG_FILE"

STATS_JSON=$(AssetCacheManagerUtil status -j 2>/dev/null || echo '{}')

# Only log JSON output on errors or first run of the day
current_date=$(date '+%Y-%m-%d')
if [ ! -f "$LOG_FILE" ] || ! grep -q "$current_date" "$LOG_FILE" 2>/dev/null; then
  echo "[$(timestamp)] Daily status check - AssetCacheManagerUtil working" >> "$LOG_FILE"
fi

# Check if we got valid JSON
if ! echo "$STATS_JSON" | jq empty 2>/dev/null; then
  echo "[$(timestamp)] ERROR: Invalid JSON from AssetCacheManagerUtil" >> "$LOG_FILE"
  exit 1
fi

# Helper function to safely extract numeric values and convert to MB
extract_mb() {
  local key="$1"
  local val
  val=$(echo "$STATS_JSON" | /usr/bin/jq -r "$key // 0" 2>/dev/null)
  awk "BEGIN {printf \"%.2f\", $val / 1024 / 1024}"
}

ACTIVE=$(echo "$STATS_JSON" | jq -r '.result.Active // false')
if [ "$ACTIVE" == "true" ]; then ACTIVE_STATE="on"; else ACTIVE_STATE="off"; fi

# Process each metric individually to avoid associative array issues
process_metric() {
  local key="$1"
  local jq_path="$2"
  local value=$(extract_mb "$jq_path")
  local safe_client_name=$(echo "$CLIENT_NAME" | tr '-' '_')
  local entity="sensor.${safe_client_name}_apple_content_caching_${key}"
  local friendly="${CLIENT_NAME} ${CACHE_NAME} (${key})"
  local payload=$(cat <<EOF
{
  "state": $value,
  "attributes": {
    "unit_of_measurement": "MB",
    "friendly_name": "$friendly"
  }
}
EOF
)
  # Send to Home Assistant and only log errors
  response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" -d "$payload" "$HA_URL/api/states/$entity" 2>&1)
  http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
  response_body=$(echo "$response" | sed 's/HTTPSTATUS:[0-9]*$//')
  
  if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
    echo "[$(timestamp)] ERROR: HTTP $http_code for $entity - Response: $response_body" >> "$LOG_FILE"
  fi
}

# Process each metric
process_metric "actual" ".result.ActualCacheUsed"
process_metric "free" ".result.CacheFree"
process_metric "used" ".result.CacheUsed"
process_metric "icloud" ".result.CacheDetails.iCloud"
process_metric "ios" '.result.CacheDetails["iOS Software"]'
process_metric "mac" '.result.CacheDetails["Mac Software"]'
process_metric "other" ".result.CacheDetails.Other"
process_metric "origin" ".result.TotalBytesStoredFromOrigin"
process_metric "clients" ".result.TotalBytesReturnedToClients"
process_metric "dropped" ".result.TotalBytesDropped"

# Active binary sensor
safe_client_name=$(echo "$CLIENT_NAME" | tr '-' '_')
binary_entity="binary_sensor.${safe_client_name}_apple_content_caching_active"
binary_payload=$(cat <<EOF
{
  "state": "$ACTIVE_STATE",
  "attributes": {
    "friendly_name": "${CLIENT_NAME} ${CACHE_NAME} Active"
  }
}
EOF
)
# Send binary sensor to Home Assistant and only log errors
response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" -d "$binary_payload" "$HA_URL/api/states/$binary_entity" 2>&1)
http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
response_body=$(echo "$response" | sed 's/HTTPSTATUS:[0-9]*$//')

if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
  echo "[$(timestamp)] ERROR: HTTP $http_code for $binary_entity - Response: $response_body" >> "$LOG_FILE"
fi
