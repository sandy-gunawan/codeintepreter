#!/bin/bash
# =============================================================================
# All-in-One Deployment Script
# Runs preflight check, infrastructure deployment, and app deployment
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================="
echo "  Code Interpreter Platform — Full Deploy"
echo "============================================="
echo ""

# Step 1: Preflight Check
echo ">>> Step 1: Preflight Check"
echo "-------------------------------------------"
bash "${SCRIPT_DIR}/preflight-check.sh"
echo ""

# Step 2: Infrastructure
echo ">>> Step 2: Infrastructure Deployment"
echo "-------------------------------------------"
bash "${SCRIPT_DIR}/deploy-infra.sh"
echo ""

# Step 3: Applications
echo ">>> Step 3: Application Deployment"
echo "-------------------------------------------"
bash "${SCRIPT_DIR}/deploy-apps.sh"
echo ""

echo "============================================="
echo "  Full deployment complete!"
echo "============================================="
