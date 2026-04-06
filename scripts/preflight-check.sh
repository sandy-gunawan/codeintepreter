#!/bin/bash
# =============================================================================
# Preflight Check Script
# Validates prerequisites before deploying the Code Interpreter platform
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); }
check_fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); }
check_warn() { echo -e "  ${YELLOW}!${NC} $1"; ((WARN++)); }

echo "============================================="
echo "  Code Interpreter Platform — Preflight Check"
echo "============================================="
echo ""

# --- CLI Tools ---
echo "Checking CLI tools..."

if command -v az &>/dev/null; then
    AZ_VERSION=$(az version --output tsv --query '"azure-cli"' 2>/dev/null || echo "unknown")
    check_pass "Azure CLI installed (v${AZ_VERSION})"
else
    check_fail "Azure CLI not installed — https://learn.microsoft.com/cli/azure/install-azure-cli"
fi

if command -v kubectl &>/dev/null; then
    check_pass "kubectl installed"
else
    check_fail "kubectl not installed — https://kubernetes.io/docs/tasks/tools/"
fi

if command -v docker &>/dev/null; then
    check_pass "Docker installed"
else
    check_fail "Docker not installed — required for building images"
fi

if command -v jq &>/dev/null; then
    check_pass "jq installed"
else
    check_warn "jq not installed — some scripts may fail. Install: apt-get install jq / brew install jq"
fi

echo ""

# --- Azure Login ---
echo "Checking Azure authentication..."

if az account show &>/dev/null; then
    ACCOUNT=$(az account show --query name -o tsv)
    SUB_ID=$(az account show --query id -o tsv)
    check_pass "Logged in to Azure: ${ACCOUNT}"
    check_pass "Subscription: ${SUB_ID}"
else
    check_fail "Not logged in to Azure — run: az login"
fi

echo ""

# --- Resource Providers ---
echo "Checking resource provider registrations..."

PROVIDERS=("Microsoft.ContainerService" "Microsoft.CognitiveServices" "Microsoft.ContainerRegistry" "Microsoft.Storage" "Microsoft.OperationalInsights")

for PROVIDER in "${PROVIDERS[@]}"; do
    STATE=$(az provider show --namespace "$PROVIDER" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
    if [ "$STATE" = "Registered" ]; then
        check_pass "$PROVIDER: Registered"
    else
        check_warn "$PROVIDER: ${STATE} — run: az provider register --namespace $PROVIDER"
    fi
done

echo ""

# --- Region Availability ---
echo "Checking region availability..."

PRIMARY_LOCATION="${PRIMARY_LOCATION:-indonesiacentral}"
OPENAI_LOCATION="${OPENAI_LOCATION:-southeastasia}"

if az account list-locations --query "[?name=='${PRIMARY_LOCATION}'].name" -o tsv | grep -q "${PRIMARY_LOCATION}"; then
    check_pass "Primary location '${PRIMARY_LOCATION}' is available"
else
    check_fail "Primary location '${PRIMARY_LOCATION}' not available on this subscription"
fi

if az account list-locations --query "[?name=='${OPENAI_LOCATION}'].name" -o tsv | grep -q "${OPENAI_LOCATION}"; then
    check_pass "OpenAI location '${OPENAI_LOCATION}' is available"
else
    check_fail "OpenAI location '${OPENAI_LOCATION}' not available"
fi

echo ""

# --- VM Quota ---
echo "Checking VM quota for AKS node pools..."

if command -v az &>/dev/null && az account show &>/dev/null; then
    # Check DSv3 family quota
    DSV3_LIMIT=$(az vm list-usage --location "${PRIMARY_LOCATION}" --query "[?contains(name.value, 'standardDSv3Family')].limit" -o tsv 2>/dev/null || echo "0")
    DSV3_USED=$(az vm list-usage --location "${PRIMARY_LOCATION}" --query "[?contains(name.value, 'standardDSv3Family')].currentValue" -o tsv 2>/dev/null || echo "0")
    DSV3_AVAIL=$((${DSV3_LIMIT:-0} - ${DSV3_USED:-0}))

    if [ "${DSV3_AVAIL}" -ge 12 ]; then
        check_pass "DSv3 VM quota: ${DSV3_AVAIL} vCPUs available (need ~12)"
    elif [ "${DSV3_AVAIL}" -gt 0 ]; then
        check_warn "DSv3 VM quota: only ${DSV3_AVAIL} vCPUs available (recommended: 12+)"
    else
        check_fail "DSv3 VM quota: 0 vCPUs available — request increase via Azure Portal"
    fi
fi

echo ""

# --- Summary ---
echo "============================================="
echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
echo "============================================="

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo -e "${RED}Preflight check FAILED. Fix the above issues before deploying.${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}Preflight check PASSED. Ready to deploy.${NC}"
    exit 0
fi
