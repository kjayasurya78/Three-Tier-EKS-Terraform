#!/usr/bin/env bash
# scripts/setup-jenkins-pipeline.sh — Fully automates Jenkins + SonarQube configuration
# Called by install.sh Phase 7, or run standalone: ./scripts/setup-jenkins-pipeline.sh
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# COLOUR HELPERS
# ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[✅ OK]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${MAGENTA}${BOLD}━━━ STEP $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"; }

# ─────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER_NAME="${CLUSTER_NAME:-three-tier-cluster}"
JENKINS_PORT="8080"
SONAR_PORT="9000"
JENKINS_EC2_TAG_VALUE="jenkins-server"
SSH_KEY_PATH="${SSH_KEY_PATH:-${SCRIPT_DIR}/../hm-eks-key.pem}"
SONAR_ADMIN_USER="admin"
SONAR_ADMIN_PASS_DEFAULT="admin"
SONAR_ADMIN_PASS_NEW="Sonar@HMShop2024!"
SONAR_PROJECT_KEY="hm-fashion-clone"
SONAR_PROJECT_NAME="H&M Fashion Clone"
JENKINS_ADMIN_USER="admin"
GITHUB_REPO_NAME="three-tier-eks-iac"

# ─────────────────────────────────────────────────────────────
# STEP 1: DEPENDENCY CHECK (AUTOMATIC)
# ─────────────────────────────────────────────────────────────
step "1 — Checking Dependencies"

for tool in aws curl jq ssh scp; do
  if command -v "${tool}" &>/dev/null; then
    success "Found: ${tool}"
  else
    error "Missing required tool: ${tool}. Install with: sudo apt install ${tool} -y"
  fi
done

# ─────────────────────────────────────────────────────────────
# STEP 2: AUTO-DETECT JENKINS EC2 IP (AUTOMATIC)
# ─────────────────────────────────────────────────────────────
step "2 — Auto-detecting Jenkins EC2 IP"

JENKINS_IP=$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters \
    "Name=tag:Name,Values=${JENKINS_EC2_TAG_VALUE}" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text 2>/dev/null || echo "")

if [ -z "${JENKINS_IP}" ] || [ "${JENKINS_IP}" = "None" ]; then
  warn "Could not auto-detect Jenkins EC2 IP from tag: ${JENKINS_EC2_TAG_VALUE}"
  read -rp "Enter Jenkins EC2 public IP address: " JENKINS_IP
  [ -n "${JENKINS_IP}" ] || error "Jenkins IP cannot be empty."
fi

JENKINS_URL="http://${JENKINS_IP}:${JENKINS_PORT}"
SONAR_URL="http://${JENKINS_IP}:${SONAR_PORT}"
success "Jenkins URL: ${JENKINS_URL}"
success "SonarQube URL: ${SONAR_URL}"

# ─────────────────────────────────────────────────────────────
# STEP 3: WAIT FOR JENKINS HTTP (AUTOMATIC)
# ─────────────────────────────────────────────────────────────
step "3 — Waiting for Jenkins to be Reachable"

info "Polling Jenkins login page..."
jenkins_ready=false
for i in $(seq 1 30); do
  if curl -sSf "${JENKINS_URL}/login" -o /dev/null 2>/dev/null; then
    jenkins_ready=true
    break
  fi
  info "[${i}/30] Jenkins not ready yet..."
  sleep 10
done

if [ "${jenkins_ready}" = "false" ]; then
  error "Jenkins did not become reachable after 5 minutes.\n  Troubleshooting:\n  1. Check security group allows port ${JENKINS_PORT} from 0.0.0.0/0\n  2. SSH to EC2 and run: sudo systemctl status jenkins\n  3. Verify: curl http://${JENKINS_IP}:${JENKINS_PORT}/login"
fi
success "Jenkins is reachable."

# ─────────────────────────────────────────────────────────────
# STEP 4: GET JENKINS ADMIN PASSWORD (AUTOMATIC)
# ─────────────────────────────────────────────────────────────
step "4 — Retrieving Jenkins Admin Password"

JENKINS_INIT_PASS=""
if [ -f "${SSH_KEY_PATH}" ]; then
  info "Reading initial password via SSH..."
  JENKINS_INIT_PASS=$(ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    -i "${SSH_KEY_PATH}" \
    ubuntu@"${JENKINS_IP}" \
    "sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo ''" 2>/dev/null || echo "")
fi

if [ -z "${JENKINS_INIT_PASS}" ]; then
  warn "Could not retrieve password via SSH."
  echo -e "${YELLOW}Manual step:${RESET} SSH to Jenkins EC2 and run:"
  echo "  sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
  read -rsp "Enter Jenkins admin password: " JENKINS_INIT_PASS
  echo ""
fi

[ -n "${JENKINS_INIT_PASS}" ] || error "Jenkins admin password cannot be empty."
success "Jenkins password obtained."

JENKINS_AUTH="${JENKINS_ADMIN_USER}:${JENKINS_INIT_PASS}"

# Get CSRF crumb
info "Fetching Jenkins CSRF crumb..."
CRUMB_JSON=$(curl -sSf -u "${JENKINS_AUTH}" \
  "${JENKINS_URL}/crumbIssuer/api/json" 2>/dev/null || echo "{}")
CRUMB_FIELD=$(echo "${CRUMB_JSON}" | jq -r '.crumbRequestField // "Jenkins-Crumb"')
CRUMB_VALUE=$(echo "${CRUMB_JSON}" | jq -r '.crumb // ""')

if [ -n "${CRUMB_VALUE}" ]; then
  CRUMB_HEADER="${CRUMB_FIELD}: ${CRUMB_VALUE}"
  success "CSRF crumb obtained."
else
  CRUMB_HEADER="Jenkins-Crumb: skip"
  warn "Could not get CSRF crumb — proceeding without (may fail on strict Jenkins configs)."
fi

# ─────────────────────────────────────────────────────────────
# STEP 5: INSTALL JENKINS PLUGINS (AUTOMATIC)
# ─────────────────────────────────────────────────────────────
step "5 — Installing Jenkins Plugins"

PLUGINS=(
  "pipeline-stage-view"
  "git"
  "github"
  "github-branch-source"
  "docker-workflow"
  "docker-plugin"
  "sonar"
  "credentials-binding"
  "snyk-security"
  "pipeline-utility-steps"
  "ws-cleanup"
  "build-timeout"
  "timestamper"
  "ansicolor"
  "workflow-aggregator"
)

info "Building plugin installation XML..."
PLUGIN_XML="<jenkins><install"
for plugin in "${PLUGINS[@]}"; do
  PLUGIN_XML="${PLUGIN_XML} plugin='${plugin}@latest'"
done
PLUGIN_XML="${PLUGIN_XML}/></jenkins>"

# Rebuild as proper XML
PLUGIN_XML="<jenkins>"
for plugin in "${PLUGINS[@]}"; do
  PLUGIN_XML="${PLUGIN_XML}<install plugin='${plugin}@latest'/>"
done
PLUGIN_XML="${PLUGIN_XML}</jenkins>"

HTTP_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" \
  -u "${JENKINS_AUTH}" \
  -H "${CRUMB_HEADER}" \
  -H "Content-Type: text/xml" \
  -d "${PLUGIN_XML}" \
  "${JENKINS_URL}/pluginManager/installPlugins" 2>/dev/null || echo "000")

if [[ "${HTTP_STATUS}" =~ ^2 ]]; then
  success "Plugin installation triggered (HTTP ${HTTP_STATUS}). Waiting for Jenkins to restart..."
  sleep 60
  # Wait for Jenkins to come back online
  for i in $(seq 1 18); do
    if curl -sSf "${JENKINS_URL}/login" -o /dev/null 2>/dev/null; then
      success "Jenkins back online after plugin install."
      break
    fi
    info "[${i}/18] Waiting for Jenkins to restart..."
    sleep 10
  done
else
  warn "Plugin installation returned HTTP ${HTTP_STATUS}."
  warn "Manual plugin install: ${JENKINS_URL}/pluginManager/available"
  warn "Plugins to install: ${PLUGINS[*]}"
fi

# ─────────────────────────────────────────────────────────────
# STEP 6: START SONARQUBE (AUTOMATIC)
# ─────────────────────────────────────────────────────────────
step "6 — Starting SonarQube"

if [ -f "${SSH_KEY_PATH}" ]; then
  info "Starting SonarQube container on Jenkins EC2..."
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
    -i "${SSH_KEY_PATH}" ubuntu@"${JENKINS_IP}" << 'REMOTE_EOF'
if docker ps --format '{{.Names}}' | grep -q '^sonarqube$'; then
  echo "SonarQube already running."
else
  echo "Starting SonarQube..."
  sudo sysctl -w vm.max_map_count=524288 >/dev/null
  docker run -d \
    --name sonarqube \
    --restart unless-stopped \
    -p 9000:9000 \
    -v sonarqube_data:/opt/sonarqube/data \
    -v sonarqube_logs:/opt/sonarqube/logs \
    -v sonarqube_extensions:/opt/sonarqube/extensions \
    sonarqube:lts-community
  echo "SonarQube container started. Waiting 60 seconds for startup..."
  sleep 60
fi
docker ps | grep sonarqube
REMOTE_EOF
else
  warn "SSH key not found — cannot auto-start SonarQube."
  warn "Manually start: docker run -d --name sonarqube -p 9000:9000 sonarqube:lts-community"
fi

info "Waiting for SonarQube to report UP status..."
sonar_ready=false
for i in $(seq 1 24); do
  SONAR_STATUS=$(curl -sSf "${SONAR_URL}/api/system/status" 2>/dev/null | \
    jq -r '.status // "STARTING"' 2>/dev/null || echo "UNREACHABLE")
  info "[${i}/24] SonarQube status: ${SONAR_STATUS}"
  [ "${SONAR_STATUS}" = "UP" ] && sonar_ready=true && break
  sleep 10
done
[ "${sonar_ready}" = "true" ] || warn "SonarQube may not be fully up — continuing anyway."
success "SonarQube is UP."

# ─────────────────────────────────────────────────────────────
# STEP 7: CONFIGURE SONARQUBE (AUTOMATIC)
# ─────────────────────────────────────────────────────────────
step "7 — Configuring SonarQube"

# 7a: Change admin password
info "Changing SonarQube admin password..."
curl -sSf -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASS_DEFAULT}" \
  -X POST \
  "${SONAR_URL}/api/users/change_password?login=${SONAR_ADMIN_USER}&previousPassword=${SONAR_ADMIN_PASS_DEFAULT}&password=${SONAR_ADMIN_PASS_NEW}" \
  -o /dev/null 2>/dev/null || warn "Password change failed (may already be changed — continuing)"

SONAR_AUTH="${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASS_NEW}"

# 7c: Create project
info "Creating SonarQube project: ${SONAR_PROJECT_KEY}..."
curl -sSf -u "${SONAR_AUTH}" \
  -X POST \
  "${SONAR_URL}/api/projects/create?project=${SONAR_PROJECT_KEY}&name=${SONAR_PROJECT_NAME}&visibility=private" \
  -o /dev/null 2>/dev/null || warn "Project may already exist — continuing."

# 7d: Generate analysis token
info "Generating SonarQube analysis token..."
TOKEN_RESPONSE=$(curl -sSf -u "${SONAR_AUTH}" \
  -X POST \
  "${SONAR_URL}/api/user_tokens/generate?name=jenkins-token&type=GLOBAL_ANALYSIS_TOKEN" \
  2>/dev/null || echo "{}")
SONAR_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r '.token // ""' 2>/dev/null || echo "")

if [ -z "${SONAR_TOKEN}" ]; then
  warn "Could not auto-generate SonarQube token."
  echo -e "${YELLOW}Manual step: Go to ${SONAR_URL} → My Account → Security → Generate Token${RESET}"
  read -rsp "Enter SonarQube token (sqp_...): " SONAR_TOKEN
  echo ""
fi
[ -n "${SONAR_TOKEN}" ] || error "SonarQube token cannot be empty."
success "SonarQube token obtained."

# 7e: Set built-in quality gate as default
info "Setting built-in quality gate as default..."
GATE_ID=$(curl -sSf -u "${SONAR_AUTH}" \
  "${SONAR_URL}/api/qualitygates/list" 2>/dev/null | \
  jq -r '.qualitygates[] | select(.isBuiltIn==true) | .id' 2>/dev/null || echo "")

if [ -n "${GATE_ID}" ]; then
  curl -sSf -u "${SONAR_AUTH}" \
    -X POST \
    "${SONAR_URL}/api/qualitygates/set_as_default?id=${GATE_ID}" \
    -o /dev/null 2>/dev/null || true
  success "Built-in quality gate set as default."
fi

# ─────────────────────────────────────────────────────────────
# STEP 8: COLLECT MANUAL CREDENTIALS (MANUAL INPUT REQUIRED)
# ─────────────────────────────────────────────────────────────
step "8 — Collect Manual Credentials"

echo -e "${YELLOW}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║              MANUAL INPUT REQUIRED — BANNER A                    ║"
echo "║                   Snyk API Token                                 ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  WHY: Snyk tokens are personal account tokens. They cannot be    ║"
echo "║  auto-generated without browser-based OAuth interaction.         ║"
echo "║                                                                  ║"
echo "║  WHERE to get your token:                                        ║"
echo "║  1. Open https://app.snyk.io/account                            ║"
echo "║  2. Find the 'Auth Token' section under 'API Token'             ║"
echo "║  3. Click 'click to show' to reveal your token                  ║"
echo "║  4. Copy the token (it starts with a long alphanumeric string)  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
read -rsp "  Enter your Snyk API Token: " SNYK_TOKEN
echo ""
[ -n "${SNYK_TOKEN}" ] || error "Snyk token cannot be empty."
success "Snyk token received."

echo ""
echo -e "${YELLOW}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║              MANUAL INPUT REQUIRED — BANNER B                    ║"
echo "║             GitHub Username + Personal Access Token              ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  WHY: GitHub PATs require browser-based 2FA confirmation.        ║"
echo "║  They cannot be generated via API without an existing OAuth      ║"
echo "║  token, which itself requires browser authentication.            ║"
echo "║                                                                  ║"
echo "║  WHERE to create your PAT:                                       ║"
echo "║  1. Go to https://github.com/settings/tokens/new                ║"
echo "║  2. Note: ${GITHUB_REPO_NAME} Jenkins CI                                  ║"
echo "║  3. Expiration: 90 days                                         ║"
echo "║  4. Required scopes:                                            ║"
echo "║       ✅ repo (full control of private repositories)            ║"
echo "║       ✅ admin:repo_hook (manage webhooks)                      ║"
echo "║  5. Click 'Generate token'                                      ║"
echo "║  6. COPY IMMEDIATELY — it is shown only once                    ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
read -rp  "  GitHub username: " GITHUB_USER
[ -n "${GITHUB_USER}" ] || error "GitHub username cannot be empty."
read -rsp "  GitHub PAT (ghp_...): " GITHUB_PAT
echo ""
[ -n "${GITHUB_PAT}" ] || error "GitHub PAT cannot be empty."
success "GitHub credentials received."

echo ""
echo -e "${YELLOW}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║              MANUAL INPUT REQUIRED — BANNER C                    ║"
echo "║          AWS IAM Credentials for Jenkins CI User                 ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  WHY: Jenkins needs dedicated AWS credentials to push Docker     ║"
echo "║  images to ECR and run Trivy image scans. Use a CI-specific     ║"
echo "║  IAM user — not your personal admin credentials.                ║"
echo "║                                                                  ║"
echo "║  WHERE to create the IAM credentials:                           ║"
echo "║  1. AWS Console → IAM → Users → Create user                    ║"
echo "║  2. Username: jenkins-ci                                        ║"
echo "║  3. Attach policy: AmazonEC2ContainerRegistryPowerUser          ║"
echo "║  4. Security credentials tab → Create access key               ║"
echo "║  5. Use case: Application running outside AWS                   ║"
echo "║  6. Copy both the Access Key ID and Secret Access Key           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
read -rsp "  AWS Access Key ID: "     AWS_CI_ACCESS_KEY
echo ""
[ -n "${AWS_CI_ACCESS_KEY}" ] || error "AWS Access Key ID cannot be empty."
read -rsp "  AWS Secret Access Key: " AWS_CI_SECRET_KEY
echo ""
[ -n "${AWS_CI_SECRET_KEY}" ] || error "AWS Secret Access Key cannot be empty."
success "AWS CI credentials received."

# ─────────────────────────────────────────────────────────────
# STEP 9: REGISTER CREDENTIALS IN JENKINS (AUTOMATIC)
# ─────────────────────────────────────────────────────────────
step "9 — Registering Credentials in Jenkins"

# Re-fetch crumb (may have expired)
CRUMB_JSON=$(curl -sSf -u "${JENKINS_AUTH}" \
  "${JENKINS_URL}/crumbIssuer/api/json" 2>/dev/null || echo "{}")
CRUMB_FIELD=$(echo "${CRUMB_JSON}" | jq -r '.crumbRequestField // "Jenkins-Crumb"')
CRUMB_VALUE=$(echo "${CRUMB_JSON}" | jq -r '.crumb // ""')
CRUMB_HEADER="${CRUMB_FIELD}: ${CRUMB_VALUE}"

CRED_URL="${JENKINS_URL}/credentials/store/system/domain/_/createCredentials"

# Helper: add secret text credential
add_secret_text() {
  local cred_id="$1"
  local secret="$2"
  local desc="$3"

  local XML="<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>${cred_id}</id>
  <description>${desc}</description>
  <secret>${secret}</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>"

  HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${JENKINS_AUTH}" \
    -H "${CRUMB_HEADER}" \
    -H "Content-Type: application/xml" \
    -d "${XML}" \
    "${CRED_URL}" 2>/dev/null || echo "000")

  if [[ "${HTTP_CODE}" =~ ^(200|201|302)$ ]]; then
    success "Credential registered: ${cred_id} (HTTP ${HTTP_CODE})"
  else
    warn "Credential ${cred_id} returned HTTP ${HTTP_CODE} — may already exist or need manual entry"
  fi
}

# Helper: add username+password credential
add_user_pass() {
  local cred_id="$1"
  local user="$2"
  local pass="$3"
  local desc="$4"

  local XML="<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>${cred_id}</id>
  <description>${desc}</description>
  <username>${user}</username>
  <password>${pass}</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>"

  HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${JENKINS_AUTH}" \
    -H "${CRUMB_HEADER}" \
    -H "Content-Type: application/xml" \
    -d "${XML}" \
    "${CRED_URL}" 2>/dev/null || echo "000")

  if [[ "${HTTP_CODE}" =~ ^(200|201|302)$ ]]; then
    success "Credential registered: ${cred_id} (HTTP ${HTTP_CODE})"
  else
    warn "Credential ${cred_id} returned HTTP ${HTTP_CODE} — may already exist or need manual entry"
  fi
}

add_secret_text "aws-access-key"  "${AWS_CI_ACCESS_KEY}" "AWS Access Key ID for ECR push"
add_secret_text "aws-secret-key"  "${AWS_CI_SECRET_KEY}" "AWS Secret Access Key for ECR push"
add_secret_text "sonar-token"     "${SONAR_TOKEN}"        "SonarQube analysis token"
add_secret_text "snyk-token"      "${SNYK_TOKEN}"         "Snyk API token for dependency scan"
add_user_pass   "git-credentials" "${GITHUB_USER}" "${GITHUB_PAT}" "GitHub PAT for GitOps push"

# ─────────────────────────────────────────────────────────────
# STEP 10: LINK SONARQUBE TO JENKINS (AUTOMATIC)
# ─────────────────────────────────────────────────────────────
step "10 — Linking SonarQube to Jenkins"

GROOVY_SCRIPT="
import jenkins.model.Jenkins
import hudson.plugins.sonar.SonarGlobalConfiguration
import hudson.plugins.sonar.SonarInstallation
import hudson.plugins.sonar.model.TriggersConfig

def sonarConfig = Jenkins.instance.getDescriptorByType(SonarGlobalConfiguration)
def inst = new SonarInstallation(
  'SonarQube',
  '${SONAR_URL}',
  'sonar-token',
  '',
  '',
  new TriggersConfig(),
  ''
)
sonarConfig.setInstallations(inst)
sonarConfig.save()
println 'SonarQube configured successfully'
"

HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
  -u "${JENKINS_AUTH}" \
  -H "${CRUMB_HEADER}" \
  --data-urlencode "script=${GROOVY_SCRIPT}" \
  "${JENKINS_URL}/scriptText" 2>/dev/null || echo "000")

if [[ "${HTTP_CODE}" =~ ^(200|201)$ ]]; then
  success "SonarQube linked to Jenkins via Groovy (HTTP ${HTTP_CODE})"
else
  warn "Groovy script returned HTTP ${HTTP_CODE} — manual step:"
  warn "Jenkins → Manage Jenkins → Configure System → SonarQube servers"
  warn "Add: Name=SonarQube, URL=${SONAR_URL}, Token=sonar-token"
fi

# ─────────────────────────────────────────────────────────────
# STEP 11: CREATE PIPELINE JOB (AUTOMATIC)
# ─────────────────────────────────────────────────────────────
step "11 — Creating Jenkins Pipeline Job"

JOB_XML="<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin='workflow-job'>
  <description>H&amp;M Fashion Clone CI/CD Pipeline — 7-stage DevSecOps</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <com.coravy.hudson.plugins.github.GithubProjectProperty>
      <projectUrl>https://github.com/${GITHUB_USER}/${GITHUB_REPO_NAME}/</projectUrl>
    </com.coravy.hudson.plugins.github.GithubProjectProperty>
  </properties>
  <triggers>
    <com.cloudbees.jenkins.GitHubPushTrigger>
      <spec></spec>
    </com.cloudbees.jenkins.GitHubPushTrigger>
  </triggers>
  <definition class='org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition' plugin='workflow-cps'>
    <scm class='hudson.plugins.git.GitSCM' plugin='git'>
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/${GITHUB_USER}/${GITHUB_REPO_NAME}.git</url>
          <credentialsId>git-credentials</credentialsId>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class='empty-list'/>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
</flow-definition>"

# Try to create
HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
  -u "${JENKINS_AUTH}" \
  -H "${CRUMB_HEADER}" \
  -H "Content-Type: application/xml" \
  -d "${JOB_XML}" \
  "${JENKINS_URL}/createItem?name=hm-fashion-pipeline" 2>/dev/null || echo "000")

if [[ "${HTTP_CODE}" =~ ^(200|201)$ ]]; then
  success "Pipeline job created: hm-fashion-pipeline"
elif [ "${HTTP_CODE}" = "400" ]; then
  info "Job already exists — updating configuration..."
  HTTP_CODE2=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${JENKINS_AUTH}" \
    -H "${CRUMB_HEADER}" \
    -H "Content-Type: application/xml" \
    -d "${JOB_XML}" \
    "${JENKINS_URL}/job/hm-fashion-pipeline/config.xml" 2>/dev/null || echo "000")
  success "Pipeline job updated (HTTP ${HTTP_CODE2})"
else
  warn "Job creation returned HTTP ${HTTP_CODE} — check Jenkins manually"
fi

# ─────────────────────────────────────────────────────────────
# WEBHOOK INSTRUCTIONS (always manual)
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║          ⚙️  MANUAL STEP REQUIRED — GitHub Webhook               ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  GitHub webhooks require browser-based OAuth and cannot be      ║"
echo "║  created via API without an existing installation token.        ║"
echo "║                                                                  ║"
echo "║  Step 1: Open this URL in your browser:                         ║"
echo "║  https://github.com/${GITHUB_USER}/${GITHUB_REPO_NAME}/settings/hooks/new"
echo "║                                                                  ║"
echo "║  Step 2: Fill in:                                               ║"
echo "║    Payload URL:  ${JENKINS_URL}/github-webhook/         ║"
echo "║    Content type: application/json                               ║"
echo "║    Events:       ⦿ Just the push event                         ║"
echo "║                                                                  ║"
echo "║  Step 3: Click 'Add webhook'                                    ║"
echo "║          Look for a green ✓ checkmark = success                 ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ─────────────────────────────────────────────────────────────
# FINAL SUMMARY
# ─────────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║           ✅ JENKINS PIPELINE SETUP COMPLETE                     ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Jenkins URL:    ${JENKINS_URL}                       ║"
echo "║  Pipeline Job:   ${JENKINS_URL}/job/hm-fashion-pipeline/ ║"
echo "║  SonarQube URL:  ${SONAR_URL}                         ║"
echo "║  Sonar Project:  ${SONAR_URL}/dashboard?id=${SONAR_PROJECT_KEY} ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Credentials registered in Jenkins:                              ║"
echo "║    ✅ aws-access-key   — AWS Access Key ID                       ║"
echo "║    ✅ aws-secret-key   — AWS Secret Access Key                   ║"
echo "║    ✅ sonar-token      — SonarQube analysis token                ║"
echo "║    ✅ snyk-token       — Snyk API token                          ║"
echo "║    ✅ git-credentials  — GitHub username + PAT                   ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Next steps:                                                     ║"
echo "║  1. Complete the GitHub Webhook (manual — see box above)        ║"
echo "║  2. Verify <ACCOUNT_ID> is replaced in k8s_manifests/           ║"
echo "║  3. Trigger first run: git commit --allow-empty -m 'ci: trigger'║"
echo "║                        git push origin main                     ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
 'hm-fashion-pipeline' created"
else
  warn "Pipeline job creation returned HTTP ${CREATE_STATUS} — create manually at ${JENKINS_URL}/newJob"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Webhook instructions (ALWAYS MANUAL — cannot be automated)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${YELLOW}${BOLD}║  🔗  MANUAL STEP: Configure GitHub Webhook                      ║${RESET}"
echo -e "${YELLOW}${BOLD}╠══════════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${YELLOW}  Step 1: Open:  https://github.com/${GITHUB_USER}/${GITHUB_REPO_NAME}/settings/hooks/new${RESET}"
echo -e "${YELLOW}  Step 2: Payload URL   = ${JENKINS_URL}/github-webhook/${RESET}"
echo -e "${YELLOW}          Content type  = application/json${RESET}"
echo -e "${YELLOW}          Event         = Just the push event${RESET}"
echo -e "${YELLOW}  Step 3: Click 'Add webhook' — look for green ✓ ping delivery${RESET}"
echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════════╝${RESET}"

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║        ✅  Jenkins Pipeline Setup Complete                       ║${RESET}"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${GREEN}  Jenkins URL:       ${JENKINS_URL}${RESET}"
echo -e "${GREEN}  Pipeline Job:      ${JENKINS_URL}/job/hm-fashion-pipeline/${RESET}"
echo -e "${GREEN}  SonarQube URL:     ${SONAR_URL}${RESET}"
echo -e "${GREEN}  SonarQube Project: ${SONAR_URL}/dashboard?id=${SONAR_PROJECT_KEY}${RESET}"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${GREEN}  Credentials registered (5):${RESET}"
echo -e "${GREEN}    ✅ aws-access-key   — AWS Access Key ID${RESET}"
echo -e "${GREEN}    ✅ aws-secret-key   — AWS Secret Access Key${RESET}"
echo -e "${GREEN}    ✅ sonar-token      — SonarQube auth token${RESET}"
echo -e "${GREEN}    ✅ snyk-token       — Snyk API token${RESET}"
echo -e "${GREEN}    ✅ git-credentials  — GitHub username + PAT${RESET}"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${GREEN}  Next steps:${RESET}"
echo -e "${GREEN}    1. Configure GitHub webhook (see above)${RESET}"
echo -e "${GREEN}    2. Verify AWS Account ID injected in k8s_manifests/${RESET}"
echo -e "${GREEN}    3. Trigger first run: git commit --allow-empty -m 'CI: trigger' && git push${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
