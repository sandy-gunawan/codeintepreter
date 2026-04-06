#!/bin/bash
# =============================================================================
# Application Deployment Script
# Builds Docker images, pushes to ACR, and deploys to AKS
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load infrastructure outputs
INFRA_ENV="${PROJECT_ROOT}/.env.infra"
if [ ! -f "$INFRA_ENV" ]; then
    echo "ERROR: ${INFRA_ENV} not found. Run deploy-infra.sh first."
    exit 1
fi
# shellcheck source=/dev/null
source "$INFRA_ENV"

echo "============================================="
echo "  Code Interpreter — Application Deploy"
echo "============================================="
echo ""
echo "  ACR:     ${ACR_LOGIN_SERVER}"
echo "  AKS:     ${AKS_CLUSTER_NAME}"
echo "  Storage: ${STORAGE_ACCOUNT_NAME}"
echo ""

# Step 1: Login to ACR
echo "[1/6] Logging in to ACR..."
az acr login --name "${ACR_NAME}" --output none
echo "  ACR login successful."

# Step 2: Build and push Docker images
echo "[2/6] Building and pushing Docker images..."

echo "  Building sandbox image..."
docker build -t "${ACR_LOGIN_SERVER}/code-interpreter-sandbox:latest" \
    "${PROJECT_ROOT}/src/sandbox"
docker push "${ACR_LOGIN_SERVER}/code-interpreter-sandbox:latest"
echo "  Sandbox image pushed."

echo "  Building backend image..."
docker build -t "${ACR_LOGIN_SERVER}/code-interpreter-backend:latest" \
    "${PROJECT_ROOT}/src/backend"
docker push "${ACR_LOGIN_SERVER}/code-interpreter-backend:latest"
echo "  Backend image pushed."

echo "  Building frontend image..."
docker build -t "${ACR_LOGIN_SERVER}/code-interpreter-frontend:latest" \
    "${PROJECT_ROOT}/src/frontend"
docker push "${ACR_LOGIN_SERVER}/code-interpreter-frontend:latest"
echo "  Frontend image pushed."

# Step 3: Retrieve secrets for K8s
echo "[3/6] Retrieving secrets..."

OPENAI_KEY=$(az cognitiveservices account keys list \
    --resource-group "${RESOURCE_GROUP}" \
    --name "$(az cognitiveservices account list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)" \
    --query "key1" -o tsv)

STORAGE_ACCOUNT_KEY=$(az storage account keys list \
    --resource-group "${RESOURCE_GROUP}" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --query "[0].value" -o tsv)

STORAGE_CONN_STRING="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_ACCOUNT_KEY};EndpointSuffix=core.windows.net"

echo "  Secrets retrieved."

# Step 4: Apply Kubernetes manifests
echo "[4/6] Applying Kubernetes manifests..."

# Apply namespaces and RBAC
kubectl apply -f "${PROJECT_ROOT}/k8s/namespaces.yaml"
kubectl apply -f "${PROJECT_ROOT}/k8s/rbac.yaml"
kubectl apply -f "${PROJECT_ROOT}/k8s/sandbox-networkpolicy.yaml"

echo "  Namespaces, RBAC, and NetworkPolicies applied."

# Step 5: Substitute placeholders and apply app deployment
echo "[5/6] Deploying application..."

sed -e "s|__ACR_LOGIN_SERVER__|${ACR_LOGIN_SERVER}|g" \
    -e "s|__OPENAI_ENDPOINT__|${OPENAI_ENDPOINT}|g" \
    -e "s|__OPENAI_KEY__|${OPENAI_KEY}|g" \
    -e "s|__OPENAI_DEPLOYMENT__|${OPENAI_DEPLOYMENT_NAME}|g" \
    -e "s|__STORAGE_CONN_STRING__|${STORAGE_CONN_STRING}|g" \
    -e "s|__STORAGE_ACCOUNT_NAME__|${STORAGE_ACCOUNT_NAME}|g" \
    -e "s|__STORAGE_ACCOUNT_KEY__|${STORAGE_ACCOUNT_KEY}|g" \
    "${PROJECT_ROOT}/k8s/app-deployment.yaml" | kubectl apply -f -

echo "  Application manifests applied."

# Step 6: Wait for pods to be ready
echo "[6/6] Waiting for pods to be ready..."

kubectl rollout status deployment/backend -n codeinterpreter --timeout=120s || true
kubectl rollout status deployment/frontend -n codeinterpreter --timeout=120s || true

echo ""

# Get Ingress IP
echo "Waiting for Ingress external IP (may take 1-2 minutes)..."
for i in $(seq 1 30); do
    INGRESS_IP=$(kubectl get ingress code-interpreter-ingress -n codeinterpreter -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$INGRESS_IP" ]; then
        break
    fi
    sleep 5
done

echo ""
echo "============================================="
echo "  Application deployment complete!"
echo "============================================="
echo ""
if [ -n "${INGRESS_IP:-}" ]; then
    echo "  Access the application at: http://${INGRESS_IP}"
else
    echo "  Ingress IP not yet available. Check with:"
    echo "  kubectl get ingress -n codeinterpreter"
fi
echo ""
echo "  Backend API:  http://${INGRESS_IP:-<pending>}/api/health"
echo "  Frontend UI:  http://${INGRESS_IP:-<pending>}/"
echo ""
echo "  Useful commands:"
echo "    kubectl get pods -n codeinterpreter"
echo "    kubectl get pods -n sandbox"
echo "    kubectl logs -f deployment/backend -n codeinterpreter"
echo "============================================="
