#!/bin/bash
# =============================================================================
# Create GCP Project + e2-micro VM for NanoClaw
# Usage: ./create-gcp-project.sh PROJECT_ID
#
# Prerequisites:
# - gcloud CLI installed and authenticated
# - Billing account linked
# =============================================================================

set -euo pipefail

PROJECT_ID="${1:?Usage: ./create-gcp-project.sh PROJECT_ID}"
ZONE="us-central1-a"
VM_NAME="nanoclaw-vm"
MACHINE_TYPE="e2-micro"
DISK_SIZE="30"
IMAGE_FAMILY="ubuntu-2404-lts-amd64"
IMAGE_PROJECT="ubuntu-os-cloud"

# SSH source IP restriction (set your IP for security, e.g., "203.0.113.50/32")
# Usage: SSH_SOURCE_IP="your.ip.here/32" ./create-gcp-project.sh PROJECT_ID
SSH_SOURCE_IP="${SSH_SOURCE_IP:-0.0.0.0/0}"

echo "=== Creating GCP Project: $PROJECT_ID ==="

# Create project (may fail if already exists)
gcloud projects create "$PROJECT_ID" --name="NanoClaw Assistant" 2>/dev/null || \
  echo "Project $PROJECT_ID already exists."

gcloud config set project "$PROJECT_ID"

# Enable required APIs
echo "[1/6] Enabling APIs..."
gcloud services enable \
  compute.googleapis.com \
  texttospeech.googleapis.com \
  secretmanager.googleapis.com

# Create firewall rule (SSH only, no inbound web ports needed)
echo "[2/6] Configuring firewall..."
gcloud compute firewall-rules create allow-ssh \
  --allow tcp:22 \
  --source-ranges "$SSH_SOURCE_IP" \
  --target-tags nanoclaw \
  --project "$PROJECT_ID" 2>/dev/null || echo "Firewall rule already exists."

# Create dedicated service account with minimal permissions
echo "[3/6] Creating service account..."
SA_NAME="nanoclaw-vm-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create "$SA_NAME" \
  --display-name="NanoClaw VM Service Account" \
  --project "$PROJECT_ID" 2>/dev/null || echo "Service account already exists."

# Grant only required roles (Secret Manager read + TTS)
for ROLE in roles/secretmanager.secretAccessor roles/texttospeech.client; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$ROLE" \
    --quiet 2>/dev/null
done

echo "[4/6] Creating e2-micro VM with restricted service account..."
gcloud compute instances create "$VM_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --boot-disk-size="${DISK_SIZE}GB" \
  --boot-disk-type=pd-standard \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --tags=nanoclaw \
  --service-account="$SA_EMAIL" \
  --scopes=cloud-platform \
  --project "$PROJECT_ID"

# Create secrets
echo "[5/6] Creating Secret Manager secrets..."
for SECRET in ANTHROPIC_API_KEY GROQ_API_KEY; do
  gcloud secrets create "$SECRET" --project "$PROJECT_ID" 2>/dev/null || \
    echo "Secret $SECRET already exists."
  echo "  Add value: echo -n 'YOUR_KEY' | gcloud secrets versions add $SECRET --data-file=- --project $PROJECT_ID"
done

echo ""
echo "[6/6] Setup complete!"
echo ""
echo "VM External IP:"
gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" --project "$PROJECT_ID" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
echo ""
echo "IMPORTANT: Set SSH_SOURCE_IP to restrict SSH access:"
echo "  gcloud compute firewall-rules update allow-ssh --source-ranges=YOUR_IP/32 --project $PROJECT_ID"
echo ""
echo "Next steps:"
echo "  1. SSH: gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT_ID"
echo "  2. Run setup-vm.sh on the VM"
echo "  3. Add API keys to Secret Manager"
