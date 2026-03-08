#!/usr/bin/env bash
# =============================================================================
# uninstall.sh — H&M Fashion Clone — Full Teardown Script
# Order: Helm → Namespaces → EBS wait → ECR purge → Terraform destroy
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/uninstall.log"
> "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

# ── Colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m';  YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
step()    { local n="$1"; shift; echo -e "\n${CYAN}${BOLD}── STEP ${n}: $* ──${RESET}\n"; }

# ── Flags ──────────────────────────────────────────────────────────────────────
SKIP_K8S=false
SKIP_ECR=false
SKIP_TERRAFORM=false
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --skip-k8s)       SKIP_K8S=true       ;;
    --skip-ecr)       SKIP_ECR=true       ;;
    --skip-terraform) SKIP_TERRAFORM=true ;;
    --force)          FORCE=true          ;;
    --help)
      echo "Usage: $0 [--skip-k8s] [--skip-ecr] [--skip-terraform] [--force]"
      exit 0
      ;;
  esac
done

# ── Config ──────────────────────────────────────────────────────────────────────
AWS_REGION="ap-south-1"
CLUSTER_NAME="three-tier-cluster"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
SSH_KEY_PATH="${SSH_KEY_PATH:-${SCRIPT_DIR}/hm-eks-key.pem}"

# ── Safety Prompt ──────────────────────────────────────────────────────────────
if [[ "${FORCE}" == "false" ]]; then
  echo ""
  echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${RED}${BOLD}║                    ⚠  DESTRUCTIVE OPERATION  ⚠                  ║${RESET}"
  echo -e "${RED}${BOLD}╠══════════════════════════════════════════════════════════════════╣${RESET}"
  echo -e "${RED}${BOLD}║  The following resources will be PERMANENTLY DELETED:            ║${RESET}"
  echo -e "${RED}${BOLD}║                                                                  ║${RESET}"
  echo -e "${RED}${BOLD}║  • EKS Cluster: ${CLUSTER_NAME}                         ║${RESET}"
  echo -e "${RED}${BOLD}║  • All K8s workloads (hm-shop, argocd, monitoring)               ║${RESET}"
  echo -e "${RED}${BOLD}║  • All EBS volumes (PostgreSQL data will be LOST)                ║${RESET}"
  echo -e "${RED}${BOLD}║  • AWS Load Balancers (ALB + Grafana NLB)                        ║${RESET}"
  echo -e "${RED}${BOLD}║  • ECR images (hm-frontend, hm-backend)                         ║${RESET}"
  echo -e "${RED}${BOLD}║  • Jenkins EC2 instance                                          ║${RESET}"
  echo -e "${RED}${BOLD}║  • VPC, subnets, NAT Gateways, EIPs                              ║${RESET}"
  echo -e "${RED}${BOLD}║  • All IAM roles and policies created by Terraform               ║${RESET}"
  echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  read -rp "Type the word 'destroy' to confirm: " confirm
  if [[ "${confirm}" != "destroy" ]]; then
    info "Aborted — you typed '${confirm}' (expected 'destroy')"
    exit 0
  fi
  echo ""
fi

# ─────────────────────────────────────────────────────────────────────────────
step 1 "Connect to EKS cluster"
# ─────────────────────────────────────────────────────────────────────────────
if aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name   "${CLUSTER_NAME}" 2>/dev/null; then
  success "Connected to EKS cluster"
else
  warn "Could not connect to EKS cluster — skipping K8s cleanup steps"
  SKIP_K8S=true
fi

# ─────────────────────────────────────────────────────────────────────────────
step 2 "Uninstall Helm releases"
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_K8S}" == "false" ]]; then
  for release_ns in "grafana:monitoring" "prometheus:monitoring" "cluster-autoscaler:kube-system" "aws-load-balancer-controller:kube-system"; do
    release="${release_ns%%:*}"
    ns="${release_ns##*:}"
    info "Uninstalling helm release: ${release} in namespace ${ns}..."
    helm uninstall "${release}" --namespace "${ns}" 2>/dev/null && success "${release} removed" || warn "${release} not found (already removed)"
  done
else
  warn "Skipping Helm uninstall (SKIP_K8S=true)"
fi

# ─────────────────────────────────────────────────────────────────────────────
step 3 "Delete Kubernetes namespaces"
# Deleting namespaces releases ALBs and triggers EBS PVC deletion
# This MUST happen before Terraform destroy
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_K8S}" == "false" ]]; then
  info "Deleting hm-shop, argocd, monitoring namespaces..."
  kubectl delete namespace hm-shop argocd monitoring \
    --ignore-not-found=true \
    --timeout=120s || warn "Namespace deletion timed out — continuing"
  success "Namespaces deleted (ALBs + EBS PVCs released)"
else
  warn "Skipping namespace deletion (SKIP_K8S=true)"
fi

# ─────────────────────────────────────────────────────────────────────────────
step 4 "Wait for EBS volumes to detach"
# EBS volumes must be detached before Terraform can delete the VPC
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_K8S}" == "false" ]]; then
  info "Waiting for EBS volumes tagged to cluster to detach..."
  local_count=0
  local_retries=24
  until [[ "$(aws ec2 describe-volumes \
    --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
              "Name=status,Values=in-use" \
    --query "length(Volumes)" \
    --region "${AWS_REGION}" \
    --output text 2>/dev/null)" == "0" ]]; do
    local_count=$((local_count + 1))
    if [[ ${local_count} -ge ${local_retries} ]]; then
      warn "EBS volumes still attached after $((local_retries * 10))s — continuing anyway"
      break
    fi
    info "Waiting for EBS detach... attempt ${local_count}/${local_retries}"
    sleep 10
  done
  success "All EBS volumes detached"
fi

# ─────────────────────────────────────────────────────────────────────────────
step 5 "Delete PersistentVolumes"
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_K8S}" == "false" ]]; then
  info "Deleting PersistentVolumes with storageClassName=hm-ebs-gp2..."
  kubectl get pv -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.storageClassName=="hm-ebs-gp2") | .metadata.name' | \
    xargs -r kubectl delete pv || true
  success "PersistentVolumes cleaned up"
fi

# ─────────────────────────────────────────────────────────────────────────────
step 6 "Purge ECR images"
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_ECR}" == "false" ]]; then
  for repo in "hm-frontend" "hm-backend"; do
    info "Purging ECR repository: ${repo}..."
    local image_ids
    image_ids=$(aws ecr list-images \
      --repository-name "${repo}" \
      --region "${AWS_REGION}" \
      --query 'imageIds[*]' \
      --output json 2>/dev/null || echo "[]")

    if [[ "${image_ids}" != "[]" && "${image_ids}" != "null" && -n "${image_ids}" ]]; then
      aws ecr batch-delete-image \
        --repository-name "${repo}" \
        --image-ids "${image_ids}" \
        --region "${AWS_REGION}" \
        --output json > /dev/null
      success "ECR ${repo} images deleted"
    else
      info "ECR ${repo} already empty"
    fi
  done
else
  warn "Skipping ECR purge (--skip-ecr)"
fi

# ─────────────────────────────────────────────────────────────────────────────
step 7 "Stop SonarQube container on Jenkins EC2"
# ─────────────────────────────────────────────────────────────────────────────
JENKINS_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=jenkins-server" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --region "${AWS_REGION}" \
  --output text 2>/dev/null || echo "")

if [[ -n "${JENKINS_IP}" && "${JENKINS_IP}" != "None" && -f "${SSH_KEY_PATH}" ]]; then
  info "Stopping SonarQube container on Jenkins EC2 (${JENKINS_IP})..."
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
      -i "${SSH_KEY_PATH}" "ubuntu@${JENKINS_IP}" \
      'docker stop sonarqube 2>/dev/null; docker rm sonarqube 2>/dev/null; echo done' \
      2>/dev/null && success "SonarQube stopped" || warn "Could not SSH to Jenkins EC2 — it will be destroyed with EC2"
else
  info "Jenkins EC2 not reachable — SonarQube will be removed with EC2 termination"
fi

# ─────────────────────────────────────────────────────────────────────────────
step 8 "Terraform destroy"
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_TERRAFORM}" == "false" ]]; then
  if [[ ! -f "${TERRAFORM_DIR}/terraform.tfstate" ]] && [[ ! -d "${TERRAFORM_DIR}/.terraform" ]]; then
    warn "No Terraform state found — infrastructure may already be destroyed"
  else
    cd "${TERRAFORM_DIR}"
    info "Initialising Terraform..."
    terraform init -input=false

    if [[ "${FORCE}" == "false" ]]; then
      info "Creating destroy plan..."
      terraform plan -destroy -out=destroy.tfplan -input=false
      read -rp "Review plan above. Proceed with destroy? [y/N]: " proceed
      [[ "${proceed,,}" == "y" ]] || { info "Destroy aborted by user."; exit 0; }
      terraform apply destroy.tfplan
    else
      terraform destroy -auto-approve
    fi

    success "Terraform destroy complete"
    cd "${SCRIPT_DIR}"
  fi
else
  warn "Skipping Terraform destroy (--skip-terraform)"
fi

# ─────────────────────────────────────────────────────────────────────────────
step 9 "Local cleanup"
# ─────────────────────────────────────────────────────────────────────────────
info "Removing local kubeconfig context..."
kubectl config delete-context \
  "arn:aws:eks:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'unknown'):cluster/${CLUSTER_NAME}" \
  2>/dev/null || true

info "Removing temporary files..."
rm -f "${TERRAFORM_DIR}/tfplan" "${TERRAFORM_DIR}/destroy.tfplan" "${SCRIPT_DIR}/stack-urls.txt" 2>/dev/null || true
success "Local cleanup complete"

# ─────────────────────────────────────────────────────────────────────────────
step 10 "Verify teardown"
# ─────────────────────────────────────────────────────────────────────────────
echo ""
local_issues=0

info "Checking EKS clusters..."
if aws eks list-clusters --region "${AWS_REGION}" --output text 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  warn "⚠  EKS cluster ${CLUSTER_NAME} still exists — may still be deleting"
  local_issues=$((local_issues + 1))
else
  success "EKS cluster ${CLUSTER_NAME} — gone ✓"
fi

info "Checking Jenkins EC2 instances..."
jenkins_count=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=jenkins-server" "Name=instance-state-name,Values=running,stopping,stopped" \
  --query "length(Reservations)" \
  --region "${AWS_REGION}" \
  --output text 2>/dev/null || echo "0")
if [[ "${jenkins_count}" != "0" ]]; then
  warn "⚠  Jenkins EC2 instance still exists — may still be terminating"
  local_issues=$((local_issues + 1))
else
  success "Jenkins EC2 — gone ✓"
fi

info "Checking for orphaned EBS volumes..."
orphan_vols=$(aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
  --query "Volumes[*].VolumeId" \
  --region "${AWS_REGION}" \
  --output text 2>/dev/null || echo "")
if [[ -n "${orphan_vols}" ]]; then
  warn "⚠  Orphaned EBS volumes found: ${orphan_vols}"
  warn "   Delete manually: aws ec2 delete-volume --volume-id <id> --region ${AWS_REGION}"
  local_issues=$((local_issues + 1))
else
  success "No orphaned EBS volumes ✓"
fi

info "Checking for orphaned ALBs..."
orphan_albs=$(aws elbv2 describe-load-balancers \
  --region "${AWS_REGION}" \
  --query "LoadBalancers[?contains(LoadBalancerName, 'hm')].LoadBalancerArn" \
  --output text 2>/dev/null || echo "")
if [[ -n "${orphan_albs}" ]]; then
  warn "⚠  Orphaned ALBs found: ${orphan_albs}"
  warn "   Delete manually: aws elbv2 delete-load-balancer --load-balancer-arn <arn> --region ${AWS_REGION}"
  local_issues=$((local_issues + 1))
else
  success "No orphaned ALBs ✓"
fi

echo ""
if [[ ${local_issues} -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${GREEN}${BOLD}║      ✅  TEARDOWN COMPLETE — All resources removed   ║${RESET}"
  echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
else
  echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${YELLOW}${BOLD}║  ⚠  TEARDOWN COMPLETE WITH ${local_issues} WARNING(S)           ║${RESET}"
  echo -e "${YELLOW}${BOLD}║  Check warnings above for orphaned resources         ║${RESET}"
  echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
fi
echo ""
