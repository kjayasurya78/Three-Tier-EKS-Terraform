# H&M Fashion Clone — DevSecOps on AWS EKS

![AWS](https://img.shields.io/badge/AWS-EKS-orange) ![Jenkins](https://img.shields.io/badge/CI-Jenkins-blue) ![ArgoCD](https://img.shields.io/badge/CD-ArgoCD-green) ![Terraform](https://img.shields.io/badge/IaC-Terraform-purple) ![Prometheus](https://img.shields.io/badge/Monitoring-Prometheus-red)

A production-grade, three-tier fashion e-commerce application deployed on AWS EKS with a full DevSecOps pipeline — security scanning, GitOps delivery, autoscaling, and observability — all in the Mumbai (ap-south-1) region.

---

## ⚠️ Cost Warning

| Duration | Mumbai (ap-south-1) Est. |
|----------|--------------------------|
| 1 hour   | ~$0.48                   |
| 1 day    | ~$11.52                  |
| 1 month  | ~$346                    |

> **Always run `./uninstall.sh` when you are finished.** NAT Gateways and EKS nodes accrue charges even when idle.

---

## 📐 Architecture Diagram

```
Developer pushes code → GitHub (main branch)
        │
        │  Webhook triggers
        ▼
┌──────────────────────────────────────────────────────────┐
│  JENKINS EC2 (t3.medium) — CI/CD Pipeline                │
│                                                          │
│  Stage 1: Code Quality Analysis  (SonarQube)             │
│      ↓                                                   │
│  Stage 2: Dependency Check       (Snyk)                  │
│      ↓                                                   │
│  Stage 3: File System Scan       (Trivy fs)              │
│      ↓                                                   │
│  Stage 4: Build Docker Images    (frontend + backend)    │
│      ↓                                                   │
│  Stage 5: Push to ECR Private    (both images)           │
│      ↓                                                   │
│  Stage 6: ECR Image Scan         (Trivy image)           │
│      ↓                                                   │
│  Stage 7: Update Deployment YAML → git commit → push     │
└──────────────────────────────────────────────────────────┘
        │
        │  ArgoCD polls GitHub every 3 min, detects new commit
        ▼
┌──────────────────────────────────────────────────────────┐
│  EKS CLUSTER (ap-south-1) — three-tier-cluster           │
│                                                          │
│  Namespace: hm-shop                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │ Frontend    │  │ Backend     │  │ Database    │      │
│  │ 2 pods      │  │ 2 pods      │  │ 1 pod       │      │
│  │ React/Nginx │  │ Node.js     │  │ Postgres 15 │      │
│  │ port 80     │  │ port 5000   │  │ port 5432   │      │
│  │ HPA: 2–5   │  │ HPA: 2–5   │  │ HPA: 1–2   │      │
│  └─────────────┘  └─────────────┘  └──────┬──────┘      │
│                                           │             │
│  IngressClass (alb) ← AWS ALB             │ PVC → EBS   │
│  ALB → /api  → backend-service            │ K8s Secret  │
│      → /     → frontend-service           │ IRSA Auth   │
│                                           │             │
│  Namespace: argocd      → ArgoCD Server               │
│  Namespace: monitoring  → Prometheus + Grafana LB     │
│  kube-system            → AWS LB Controller           │
│                         → Cluster Autoscaler          │
└──────────────────────────────────────────────────────────┘
        │
        ▼
User accesses app via raw ALB DNS URL
(e.g. k8s-hmshop-xxxx.ap-south-1.elb.amazonaws.com)
```

---

## 🛠 Tech Stack

| Layer             | Technology                        | Purpose                                  |
|-------------------|-----------------------------------|------------------------------------------|
| Frontend          | React 18 + Nginx 1.25             | SPA served via Nginx reverse proxy       |
| Backend           | Node.js 18 + Express              | REST API with JWT auth                   |
| Database          | PostgreSQL 15                     | Relational store, EBS-backed PVC         |
| Storage           | AWS EBS gp2 (dynamic)             | Persistent volume for Postgres data      |
| Container Build   | Docker (multi-stage)              | Non-root images, minimal attack surface  |
| CI                | Jenkins on EC2                    | 7-stage security-hardened pipeline       |
| CD / GitOps       | ArgoCD (in-cluster)               | Polls GitHub, auto-syncs manifests       |
| IaC               | Terraform >= 1.5                  | VPC, EKS, ECR, IAM, EC2                  |
| Container Registry| AWS ECR Private                   | Private image storage with scan-on-push  |
| ECR Auth          | IRSA                              | IAM Role bound to K8s ServiceAccount     |
| Code Quality      | SonarQube LTS Community           | Static analysis + Quality Gate           |
| Dependency Scan   | Snyk                              | CVE scanning for npm packages            |
| Image Scan        | Trivy                             | FS + container image vulnerability scans |
| Monitoring        | Prometheus + Grafana              | Metrics collection + dashboards          |
| Ingress           | AWS ALB Controller + IngressClass | Internet-facing ALB, path-based routing  |
| HPA               | autoscaling/v2                    | CPU + memory-based autoscaling           |
| Cluster Scaling   | Cluster Autoscaler                | Node-level scale-out                     |

---

## ✅ Prerequisites

### Local Machine Requirements

#### 1. AWS CLI v2

The AWS CLI allows you to interact with AWS services from your terminal.

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip
sudo ./aws/install
aws --version
# Expected: aws-cli/2.x.x Python/3.x.x Linux/...
```

Configure your credentials:

```bash
aws configure
# AWS Access Key ID [None]:     AKIAIOSFODNN7EXAMPLE
# AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
# Default region name [None]:   ap-south-1
# Default output format [None]: json
```

✅ **Verify:** `aws sts get-caller-identity` returns your Account ID and ARN.

---

#### 2. Terraform >= 1.5

Terraform provisions all AWS infrastructure declaratively.

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update && sudo apt-get install terraform
terraform --version
# Expected: Terraform v1.5.x or higher
```

✅ **Verify:** `terraform --version` shows 1.5+.

---

#### 3. kubectl

The Kubernetes command-line tool for interacting with your EKS cluster.

```bash
KUBECTL_VER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
# Expected: Client Version: v1.29.x
```

✅ **Verify:** `kubectl version --client` shows a version number.

---

#### 4. Helm v3

Helm is the package manager for Kubernetes — used to install ALB Controller, Autoscaler, Prometheus, and Grafana.

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
# Expected: version.BuildInfo{Version:"v3.x.x", ...}
```

✅ **Verify:** `helm version` shows v3.x.

---

#### 5. Docker

Docker builds your frontend and backend container images.

```bash
sudo apt-get install -y docker.io
sudo systemctl enable docker && sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker
docker --version
# Expected: Docker version 24.x.x, build ...
```

✅ **Verify:** `docker run hello-world` completes without permission errors.

---

#### 6. Supporting tools (jq, git, curl)

```bash
sudo apt-get install -y jq git curl
jq --version    # jq-1.6
git --version   # git version 2.x.x
curl --version  # curl 7.x.x
```

---

#### 7. EC2 Key Pair for Jenkins SSH

The install script and setup-jenkins-pipeline.sh SSH into the Jenkins EC2. The key must be named `hm-eks-key` and placed in the repo root.

```bash
# Create the key pair in ap-south-1
aws ec2 create-key-pair \
  --key-name hm-eks-key \
  --region ap-south-1 \
  --query KeyMaterial \
  --output text > hm-eks-key.pem

chmod 400 hm-eks-key.pem

# Move to repo root
mv hm-eks-key.pem /path/to/three-tier-eks-iac/
```

✅ **Verify:** `ls -la hm-eks-key.pem` shows `-r--------` permissions.

---

#### 8. GitHub Repository

```bash
git clone https://github.com/<YOUR_USERNAME>/three-tier-eks-iac.git
cd three-tier-eks-iac
```

Or if creating fresh:

```bash
git init
git remote add origin https://github.com/<YOUR_USERNAME>/three-tier-eks-iac.git
git add . && git commit -m "Initial commit"
git push -u origin main
```

---

### AWS IAM Requirements

Your IAM user/role needs the following policies attached:

| Policy | Why It's Needed |
|--------|----------------|
| `AmazonEKSFullAccess` | Create and manage EKS clusters |
| `AmazonEC2FullAccess` | Provision EC2, VPC, subnets, security groups |
| `AmazonVPCFullAccess` | Create VPC, subnets, route tables, NAT GWs |
| `AmazonECR_FullAccess` | Create ECR repos, lifecycle policies |
| `IAMFullAccess` | Create IRSA roles, OIDC providers, policies |
| Inline ECR pull policy | Allow nodes to pull from ECR (added by irsa.tf) |

---

## 🚀 Option A — Automated Deployment (One Command)

```bash
chmod +x install.sh uninstall.sh scripts/setup-jenkins-pipeline.sh
./install.sh
```

The script runs 9 phases automatically:

| Phase | Description |
|-------|-------------|
| 1 — Preflight | Tool checks, AWS identity, SSH key, git remote |
| 2 — Terraform | Provisions EKS, ECR, VPC, IAM, Jenkins EC2 |
| 3 — EKS Bootstrap | kubeconfig, EBS CSI addon, Metrics Server, StorageClass |
| 4 — Controllers | AWS ALB Controller, Cluster Autoscaler, IngressClass |
| 5 — Jenkins | SSH bootstrap of Java, Jenkins, Docker, Trivy, Snyk, SonarScanner |
| 6 — ArgoCD | Install ArgoCD, deploy hm-shop Application |
| 7 — Monitoring | Prometheus stack + Grafana with LoadBalancer |
| 8 — Pipeline | Runs setup-jenkins-pipeline.sh (prompts for tokens) |
| 9 — Verify | Polls for ALB DNS, writes stack-urls.txt |

**Manual inputs you will be prompted for:**
- Snyk API token (from https://app.snyk.io/account)
- GitHub username + Personal Access Token
- AWS IAM credentials for Jenkins CI user

**Available flags:**
```bash
./install.sh --skip-terraform   # Reuse existing infra
./install.sh --skip-jenkins     # Skip Jenkins EC2 setup
./install.sh --skip-monitoring  # Skip Prometheus/Grafana
./install.sh --dry-run          # Print plan without creating anything
```

All URLs and credentials are written to `stack-urls.txt` on completion.

---

## 🔧 Option B — Manual Step-by-Step Deployment

---

### Step 1 — Clone the Repository

> [AUTO] Handled by: you run this before any script.

```bash
git clone https://github.com/<YOUR_USERNAME>/three-tier-eks-iac.git
cd three-tier-eks-iac
```

Expected output:
```
Cloning into 'three-tier-eks-iac'...
remote: Enumerating objects: 87, done.
Receiving objects: 100% (87/87), done.
```

✅ **Success indicator:** `ls` shows Jenkinsfile, install.sh, terraform/, k8s_manifests/, app/

---

### Step 2 — Provision Infrastructure (Terraform)

> [AUTO] Handled by install.sh Phase 2

```bash
cd terraform

terraform init -input=false
terraform plan -out=tfplan -input=false
terraform apply tfplan
```

Expected output (last lines of apply):
```
Apply complete! Resources: 34 added, 0 changed, 0 destroyed.

Outputs:

cluster_endpoint           = "https://XXXXXXXXXXXXXXXX.gr7.ap-south-1.eks.amazonaws.com"
ecr_frontend_url           = "123456789012.dkr.ecr.ap-south-1.amazonaws.com/hm-frontend"
ecr_backend_url            = "123456789012.dkr.ecr.ap-south-1.amazonaws.com/hm-backend"
ecr_pull_role_arn_frontend = "arn:aws:iam::123456789012:role/hm-shop-frontend-ecr-role"
ecr_pull_role_arn_backend  = "arn:aws:iam::123456789012:role/hm-shop-backend-ecr-role"
alb_controller_role_arn    = "arn:aws:iam::123456789012:role/hm-shop-alb-controller-role"
jenkins_public_ip          = "13.233.x.x"
aws_account_id             = "123456789012"
```

Export outputs as shell variables:

```bash
export AWS_ACCOUNT_ID=$(terraform output -raw aws_account_id)
export ECR_FRONTEND=$(terraform output -raw ecr_frontend_url)
export ECR_BACKEND=$(terraform output -raw ecr_backend_url)
export JENKINS_IP=$(terraform output -raw jenkins_public_ip)
cd ..
```

✅ **Success indicator:** `aws eks list-clusters --region ap-south-1` shows `three-tier-cluster`.

---

### Step 3 — Configure kubectl

> [AUTO] Handled by install.sh Phase 3

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name three-tier-cluster

kubectl get nodes
```

Expected output:
```
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-0-10-xx.ap-south-1.compute.internal  Ready    <none>   2m    v1.29.x
ip-10-0-11-xx.ap-south-1.compute.internal  Ready    <none>   2m    v1.29.x
```

✅ **Success indicator:** Both nodes show `STATUS=Ready`.

---

### Step 4 — Install AWS EBS CSI Driver

> [AUTO] Handled by install.sh Phase 3

**Why this is critical:** Without the EBS CSI driver, the PostgreSQL PersistentVolumeClaim will stay in `Pending` state forever. The pod will never start.

```bash
aws eks create-addon \
  --cluster-name three-tier-cluster \
  --addon-name aws-ebs-csi-driver \
  --region ap-south-1

# Poll until ACTIVE
watch aws eks describe-addon \
  --cluster-name three-tier-cluster \
  --addon-name aws-ebs-csi-driver \
  --region ap-south-1 \
  --query "addon.status" \
  --output text
```

Expected output (after 2–3 minutes):
```
ACTIVE
```

Verify the driver pods are running:

```bash
kubectl get pods -n kube-system | grep ebs
```

Expected:
```
ebs-csi-controller-xxxxxxxxx-xxxxx   6/6   Running   0   2m
ebs-csi-node-xxxxx                   3/3   Running   0   2m
ebs-csi-node-xxxxx                   3/3   Running   0   2m
```

✅ **Success indicator:** `ACTIVE` status and controller pod in `Running` state.

---

### Step 5 — Apply StorageClass and IngressClass

> [AUTO] Handled by install.sh Phase 3 & 4

```bash
kubectl apply -f k8s_manifests/storageclass.yaml
kubectl apply -f k8s_manifests/ingressclass.yaml

kubectl get storageclass
kubectl get ingressclass
```

Expected output:
```
NAME           PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
hm-ebs-gp2    ebs.csi.aws.com         Retain          WaitForFirstConsumer   true

NAME   CONTROLLER                  PARAMETERS   AGE
alb    ingress.k8s.aws/alb         <none>        5s
```

✅ **Success indicator:** `hm-ebs-gp2` StorageClass and `alb` IngressClass appear.

---

### Step 6 — Install AWS Load Balancer Controller

> [AUTO] Handled by install.sh Phase 4

```bash
# Get VPC ID
VPC_ID=$(aws eks describe-cluster \
  --name three-tier-cluster \
  --region ap-south-1 \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=three-tier-cluster \
  --set region=ap-south-1 \
  --set vpcId=${VPC_ID} \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/hm-shop-alb-controller-role" \
  --wait

kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system | grep aws-load-balancer
```

Expected:
```
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
aws-load-balancer-controller   2/2     2            2           60s
```

✅ **Success indicator:** Deployment shows `2/2 READY`.

---

### Step 7 — Install Cluster Autoscaler

> [AUTO] Handled by install.sh Phase 4

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=three-tier-cluster \
  --set awsRegion=ap-south-1 \
  --set rbac.serviceAccount.create=true \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set "rbac.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/hm-shop-cluster-autoscaler-role" \
  --wait

kubectl get deployment -n kube-system cluster-autoscaler
```

✅ **Success indicator:** `cluster-autoscaler` deployment shows `1/1 READY`.

---

### Step 8 — Install Metrics Server (Required for HPA)

> [AUTO] Handled by install.sh Phase 3

**Why:** HorizontalPodAutoscaler cannot read CPU/memory metrics without Metrics Server. HPAs will show `<unknown>` targets without it.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Wait ~60s then verify
kubectl top nodes
```

Expected output:
```
NAME                                        CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
ip-10-0-10-xx.ap-south-1.compute.internal  120m         6%     820Mi           27%
ip-10-0-11-xx.ap-south-1.compute.internal  115m         5%     790Mi           26%
```

✅ **Success indicator:** `kubectl top nodes` shows CPU% and MEMORY% values (not errors).

---

### Step 9 — Inject AWS Account ID into Manifests

> [AUTO] Handled by install.sh Phase 2

The K8s manifests contain `<ACCOUNT_ID>` placeholders for ECR image URLs and IRSA role ARNs. Replace them with your real account ID:

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export GITHUB_USER=<YOUR_USERNAME>

# Replace in all K8s manifests
find k8s_manifests/ -name "*.yaml" -exec \
  sed -i "s|<ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" {} \;

# Replace GitHub username in ArgoCD application
sed -i "s|<YOUR_USERNAME>|${GITHUB_USER}|g" argocd/application.yaml

# Replace in Jenkinsfile
sed -i "s|<ACCOUNT_ID>|${AWS_ACCOUNT_ID}|g" Jenkinsfile
sed -i "s|<YOUR_USERNAME>|${GITHUB_USER}|g" Jenkinsfile

# Commit and push so ArgoCD can read the updated manifests
git add k8s_manifests/ argocd/ Jenkinsfile
git commit -m "CI: Inject AWS Account ID ${AWS_ACCOUNT_ID} into manifests"
git push origin main
```

✅ **Success indicator:** `grep '<ACCOUNT_ID>' k8s_manifests/**/*.yaml` returns no output.

---

### Step 10 — Install ArgoCD

> [AUTO] Handled by install.sh Phase 6

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD server to be ready
kubectl wait deployment/argocd-server \
  --namespace argocd \
  --for=condition=Available \
  --timeout=180s

# Get initial admin password
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD password: ${ARGOCD_PASS}"

# Deploy the hm-shop Application
kubectl apply -f argocd/application.yaml
```

Access the ArgoCD UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443
# Open https://localhost:8443 — username: admin, password: (above)
```

**What ArgoCD does automatically after this:** It polls the `k8s_manifests/` path in your GitHub repo every 3 minutes. When Jenkins pushes an updated image tag (Stage 7), ArgoCD detects the commit and applies the new manifests to the cluster — completing the GitOps loop.

✅ **Success indicator:** ArgoCD UI shows `hm-shop` application with status `Synced` and `Healthy`.

---

### Step 11 — Verify Application Pods

> [AUTO] Handled by install.sh Phase 9 (polling)

```bash
kubectl get pods -n hm-shop --watch
```

Expected output (all Running):
```
NAME                        READY   STATUS    RESTARTS   AGE
backend-xxxxxxxxx-xxxxx     1/1     Running   0          3m
backend-xxxxxxxxx-yyyyy     1/1     Running   0          3m
frontend-xxxxxxxxx-xxxxx    1/1     Running   0          3m
frontend-xxxxxxxxx-yyyyy    1/1     Running   0          3m
postgres-xxxxxxxxx-xxxxx    1/1     Running   0          5m
```

Check HPAs:

```bash
kubectl get hpa -n hm-shop
```

Expected:
```
NAME           REFERENCE             TARGETS          MINPODS   MAXPODS   REPLICAS
backend-hpa    Deployment/backend    15%/70%, 20%/80%  2         5         2
frontend-hpa   Deployment/frontend   10%/70%, 15%/80%  2         5         2
postgres-hpa   Deployment/postgres   8%/80%, 12%/85%   1         2         1
```

Check ingress (wait up to 5 minutes for ALB):

```bash
kubectl get ingress -n hm-shop
```

Expected:
```
NAME              CLASS   HOSTS   ADDRESS                                          PORTS   AGE
hm-shop-ingress   alb     *       k8s-hmshop-xxxx.ap-south-1.elb.amazonaws.com   80      5m
```

✅ **Success indicator:** All pods `Running`, HPAs show real percentages (not `<unknown>`), ingress `ADDRESS` field is populated.

---

### Step 12 — Set Up Jenkins EC2

> [AUTO] Handled by install.sh Phase 5

#### 12a — Get Jenkins EC2 IP

```bash
JENKINS_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=jenkins-server" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --region ap-south-1 \
  --output text)
echo "Jenkins IP: ${JENKINS_IP}"
```

#### 12b — Required Security Group Ports

| Port  | Protocol | Source    | Purpose                  |
|-------|----------|-----------|--------------------------|
| 22    | TCP      | 0.0.0.0/0 | SSH access               |
| 8080  | TCP      | 0.0.0.0/0 | Jenkins web UI           |
| 9000  | TCP      | 0.0.0.0/0 | SonarQube web UI         |
| 50000 | TCP      | 0.0.0.0/0 | Jenkins agent JNLP port  |

These are created automatically by Terraform in `vpc.tf`.

#### 12c — Manual Bootstrap (if not using install.sh)

SSH into the Jenkins EC2 and install each tool:

```bash
ssh -i hm-eks-key.pem ubuntu@${JENKINS_IP}
```

**Java 17:**
```bash
sudo apt-get update && sudo apt-get install -y openjdk-17-jdk
java -version
# openjdk version "17.0.x"
```

**Jenkins:**
```bash
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update && sudo apt-get install -y jenkins
sudo systemctl enable jenkins && sudo systemctl start jenkins
sudo systemctl status jenkins
# Active: active (running)
```

**Docker:**
```bash
sudo apt-get install -y docker.io
sudo usermod -aG docker jenkins
sudo usermod -aG docker ubuntu
sudo systemctl restart jenkins
docker --version
# Docker version 24.x.x
```

**AWS CLI v2:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install
aws --version
# aws-cli/2.x.x
```

**kubectl:**
```bash
KUBECTL_VER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

**Node.js 18 + Snyk:**
```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g snyk
snyk --version
```

**SonarScanner 5.0.1.3006:**
```bash
SONAR_VERSION="5.0.1.3006"
curl -fsSLO "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_VERSION}-linux.zip"
sudo unzip -q "sonar-scanner-cli-${SONAR_VERSION}-linux.zip" -d /opt/
sudo ln -sf "/opt/sonar-scanner-${SONAR_VERSION}-linux/bin/sonar-scanner" /usr/local/bin/sonar-scanner
sonar-scanner --version
```

**Trivy:**
```bash
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
  https://aquasecurity.github.io/trivy-repo/deb generic main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install -y trivy
trivy --version
```

**vm.max_map_count (required for SonarQube):**
```bash
sudo sysctl -w vm.max_map_count=524288
echo 'vm.max_map_count=524288' | sudo tee -a /etc/sysctl.conf
```

#### 12d — Get Jenkins Initial Password

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
# Output: a32-character hex string e.g. 3d4f2bf07a6c4e8...
```

#### 12e — Jenkins Browser Setup

1. Open `http://<JENKINS_IP>:8080` in your browser
2. Paste the initial admin password from 12d
3. Click **Install suggested plugins** and wait ~3 minutes
4. Create admin user: fill in username, password, full name, email
5. Click **Save and Finish** → **Start using Jenkins**

✅ **Success indicator:** Jenkins dashboard loads showing "Welcome to Jenkins!"

---

### Step 13 — Set Up SonarQube

> [AUTO] Handled by scripts/setup-jenkins-pipeline.sh Step 6 & 7

**Start SonarQube on the Jenkins EC2:**

```bash
ssh -i hm-eks-key.pem ubuntu@${JENKINS_IP}

docker run -d \
  --name sonarqube \
  --restart unless-stopped \
  -p 9000:9000 \
  -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
  -v sonarqube_data:/opt/sonarqube/data \
  sonarqube:lts-community
```

Wait ~60 seconds, then open `http://<JENKINS_IP>:9000`.

**First login:**
1. Username: `admin`, Password: `admin`
2. You'll be prompted to change the password → set it to `Sonar@HMShop2024!`
3. Click **Create a local project** → Project key: `hm-fashion-clone`, Display name: `H&M Fashion Clone`
4. Click **Set up project for clean code**

**Generate a token:**
1. Click your avatar (top right) → **My Account** → **Security**
2. Under **Generate Tokens**: Name = `jenkins-token`, Type = `User Token`
3. Click **Generate** — **copy the token immediately** (shown only once)

**Add token to Jenkins:**
1. Jenkins → **Manage Jenkins** → **Configure System**
2. Scroll to **SonarQube servers** section → **Add SonarQube**
3. Name: `SonarQube`, Server URL: `http://<JENKINS_IP>:9000`
4. Server authentication token → **Add** → **Jenkins** → Kind: **Secret text** → paste token
5. Click **Save**

✅ **Success indicator:** Jenkins can reach SonarQube — test via a pipeline run.

---

### Step 14 — Configure Jenkins Credentials

> [AUTO] Handled by scripts/setup-jenkins-pipeline.sh Step 9

Navigate to: **Jenkins → Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

| ID | Kind | Value | Security Note |
|----|------|-------|---------------|
| `aws-access-key` | Secret text | AWS Access Key ID for `jenkins-ci` IAM user | Never use personal admin keys |
| `aws-secret-key` | Secret text | AWS Secret Access Key for `jenkins-ci` | Rotate every 90 days |
| `sonar-token` | Secret text | SonarQube user token from Step 13 | Regenerate if compromised |
| `snyk-token` | Secret text | Snyk API token from app.snyk.io/account | Bound to your Snyk account |
| `git-credentials` | Username/Password | GitHub username + PAT | PAT needs `repo` + `admin:repo_hook` scopes |

✅ **Success indicator:** All 5 credentials appear in the global credentials list.

---

### Step 15 — Install Jenkins Plugins

> [AUTO] Handled by scripts/setup-jenkins-pipeline.sh Step 5

Navigate to: **Jenkins → Manage Jenkins → Plugins → Available plugins**

Search for and install each:

- [ ] `pipeline-stage-view`
- [ ] `git`
- [ ] `github`
- [ ] `github-branch-source`
- [ ] `docker-workflow`
- [ ] `docker-plugin`
- [ ] `sonar`
- [ ] `credentials-binding`
- [ ] `snyk-security-scanner`
- [ ] `pipeline-utility-steps`
- [ ] `ws-cleanup`
- [ ] `build-timeout`
- [ ] `timestamper`
- [ ] `ansicolor`
- [ ] `workflow-aggregator`

Click **Install** and wait for Jenkins to restart.

✅ **Success indicator:** Jenkins restarts and all 15 plugins show as **Installed**.

---

### Step 16 — Create Jenkins Pipeline Job

> [AUTO] Handled by scripts/setup-jenkins-pipeline.sh Step 11

1. Jenkins dashboard → **New Item**
2. Enter name: `hm-fashion-pipeline`
3. Select **Pipeline** → click **OK**
4. Under **Build Triggers**: check **GitHub hook trigger for GITScm polling**
5. Under **Pipeline**:
   - Definition: `Pipeline script from SCM`
   - SCM: `Git`
   - Repository URL: `https://github.com/<YOUR_USERNAME>/three-tier-eks-iac.git`
   - Credentials: select `git-credentials`
   - Branch: `*/main`
   - Script Path: `Jenkinsfile`
6. Click **Save**

✅ **Success indicator:** Pipeline job appears in Jenkins dashboard.

---

### Step 17 — Configure GitHub Webhook

> **Always manual — this step cannot be automated** (GitHub requires browser 2FA confirmation)

1. Go to: `https://github.com/<YOUR_USERNAME>/three-tier-eks-iac/settings/hooks/new`
2. Fill in:
   - **Payload URL:** `http://<JENKINS_IP>:8080/github-webhook/`
   - **Content type:** `application/json`
   - **Which events:** select **Just the push event**
3. Click **Add webhook**
4. GitHub will send a ping — look for a green ✓ checkmark on the webhook page

✅ **Success indicator:** Green checkmark on GitHub webhook page, and Jenkins shows a build was triggered.

---

### Step 18 — Trigger First Pipeline Run

> [AUTO] The webhook handles subsequent runs. This triggers the very first.

```bash
git commit --allow-empty -m "CI: trigger first pipeline run"
git push origin main
```

Watch the pipeline in Jenkins at `http://<JENKINS_IP>:8080/job/hm-fashion-pipeline/`:

| Stage | What to watch for |
|-------|-------------------|
| Stage 1 (SonarQube) | Quality Gate result — must be PASSED |
| Stage 2 (Snyk) | `✓ Tested X dependencies` |
| Stage 3 (Trivy FS) | Results table, pipeline continues regardless |
| Stage 4 (Build) | `Successfully built <image-id>` for both images |
| Stage 5 (ECR Push) | `The push refers to repository [...]` |
| Stage 6 (Trivy Image) | Scan results archived as artifacts |
| Stage 7 (GitOps) | `CI: Update image tags to build-1 [skip ci]` commit appears in GitHub |

After Stage 7, ArgoCD detects the new commit within 3 minutes and deploys the updated images automatically.

✅ **Success indicator:** All 7 stages green, ArgoCD application status shows `Synced`.

---

### Step 19 — Install Monitoring Stack

> [AUTO] Handled by install.sh Phase 7

```bash
kubectl create namespace monitoring

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana              https://grafana.github.io/helm-charts
helm repo update

# Install Prometheus stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring/prometheus-values.yaml \
  --wait

# Install Grafana with LoadBalancer
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --values monitoring/grafana-values.yaml \
  --wait

# Get Grafana external URL
kubectl get svc -n monitoring grafana
```

Expected:
```
NAME      TYPE           CLUSTER-IP     EXTERNAL-IP                                    PORT(S)
grafana   LoadBalancer   172.20.x.x     abc123.elb.ap-south-1.amazonaws.com           80:30xxx/TCP
```

Open `http://<EXTERNAL-IP>` → login with `admin` / `HMGrafana2024!`

Pre-imported dashboards (under **H&M Shop** folder):
- Kubernetes Cluster (6417)
- Kubernetes Pods (6336)
- Node Exporter Full (1860)
- Nginx Ingress (9614)

✅ **Success indicator:** Grafana loads, all 4 dashboards show live data.

---

### Step 20 — Access the Application

```bash
# Get the ALB URL
ALB_URL=$(kubectl get ingress hm-shop-ingress -n hm-shop \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test the API health endpoint
curl http://${ALB_URL}/api/health
```

Expected JSON response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "service": "hm-backend",
  "database": {
    "status": "connected",
    "latency_ms": 2
  },
  "uptime_seconds": 120
}
```

Open the application in your browser:

```bash
echo "Application URL: http://${ALB_URL}"
```

✅ **Success indicator:** Browser loads the H&M Fashion clone homepage with product listings.

---

## 🔄 Day-2 Operations

### View Logs

```bash
# Backend logs (follow)
kubectl logs -f deployment/backend -n hm-shop

# Frontend logs
kubectl logs -f deployment/frontend -n hm-shop

# PostgreSQL logs
kubectl logs -f deployment/postgres -n hm-shop

# All pods in namespace
kubectl logs -f -l app=backend -n hm-shop --all-containers=true
```

### Manual Scaling + Watch HPA

```bash
# Scale backend manually
kubectl scale deployment backend --replicas=4 -n hm-shop

# Watch HPA react
kubectl get hpa -n hm-shop --watch
```

### View Security Scan Results

Trivy and Snyk results are archived as Jenkins build artifacts. Access them at:
`http://<JENKINS_IP>:8080/job/hm-fashion-pipeline/<BUILD_NUMBER>/artifact/`

### Trigger Pipeline Manually

```bash
git commit --allow-empty -m "CI: manual trigger"
git push origin main
```

### ArgoCD Sync Check + Force Sync

```bash
# Check sync status
kubectl get application hm-shop -n argocd

# Force sync immediately (don't wait 3 minutes)
kubectl patch application hm-shop -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"syncStrategy":{"hook":{"force":true}}}}}'
```

### Rolling Restart

```bash
kubectl rollout restart deployment/frontend -n hm-shop
kubectl rollout restart deployment/backend  -n hm-shop
kubectl rollout status  deployment/backend  -n hm-shop
```

### Connect to PostgreSQL CLI

```bash
# Get the postgres pod name
POSTGRES_POD=$(kubectl get pod -n hm-shop -l app=postgres -o jsonpath='{.items[0].metadata.name}')

# Open psql
kubectl exec -it ${POSTGRES_POD} -n hm-shop -- \
  psql -U hmuser -d hmshop

# Once inside psql:
\dt                          -- list tables
SELECT COUNT(*) FROM products;
SELECT * FROM orders LIMIT 5;
\q                           -- quit
```

---

## 💥 Option C — Jenkins Pipeline Only (Existing Cluster)

If you already have a running EKS cluster and just need to set up the Jenkins pipeline:

```bash
chmod +x scripts/setup-jenkins-pipeline.sh
./scripts/setup-jenkins-pipeline.sh
```

**Automated by the script:**
- Detects Jenkins EC2 IP via AWS tag
- Waits for Jenkins HTTP readiness
- Reads initial admin password via SSH
- Installs 15 Jenkins plugins
- Starts SonarQube container
- Configures SonarQube project + token
- Registers all 5 credentials in Jenkins
- Links SonarQube to Jenkins
- Creates the pipeline job

**Prompts for manual input (3 items):**
- Snyk API token (requires browser login to app.snyk.io)
- GitHub username + Personal Access Token
- AWS IAM credentials for jenkins-ci user

---

## 🗑️ Teardown

### Option A — Automated (Recommended)

```bash
./uninstall.sh
```

You'll be prompted to type `destroy` to confirm. The script then:
1. Uninstalls all Helm releases (Grafana, Prometheus, ALB Controller, Autoscaler)
2. Deletes Kubernetes namespaces (releases ALBs + PVCs)
3. Waits for EBS volumes to detach
4. Purges ECR images
5. Stops SonarQube container
6. Runs `terraform destroy`
7. Cleans up local kubeconfig context

### Option B — Manual (Order Matters!)

```bash
# 1. Uninstall Helm releases FIRST (releases cloud resources)
helm uninstall grafana              -n monitoring
helm uninstall prometheus           -n monitoring
helm uninstall cluster-autoscaler   -n kube-system
helm uninstall aws-load-balancer-controller -n kube-system

# 2. Delete namespaces (triggers ALB + EBS cleanup)
kubectl delete namespace hm-shop argocd monitoring --timeout=120s

# 3. Wait for EBS volumes to detach before Terraform runs
# (otherwise TF destroy fails because VPC has attached resources)
sleep 60

# 4. Terraform destroy
cd terraform
terraform destroy -auto-approve
```

> **Why order matters:** Terraform cannot delete the VPC while ALBs or EBS volumes are still attached to it. Helm + namespace deletion must happen first to release those resources cleanly.

---

## 🔐 Environment Variables Reference

| Variable | Where Set | Value | Notes |
|----------|-----------|-------|-------|
| `AWS_REGION` | install.sh config | `ap-south-1` | All resources in Mumbai |
| `CLUSTER_NAME` | install.sh config | `three-tier-cluster` | EKS cluster name |
| `AWS_ACCOUNT_ID` | install.sh auto-detect | Your 12-digit ID | Used for ECR URL construction |
| `SSH_KEY_PATH` | env override or default | `./hm-eks-key.pem` | Set: `SSH_KEY_PATH=/path/key.pem ./install.sh` |
| `REGISTRY` | Jenkinsfile env | `<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com` | Injected by install.sh |
| `GIT_REPO` | Jenkinsfile env | Your GitHub repo URL | Injected by install.sh |
| `SONAR_ADMIN_PASS_NEW` | setup-jenkins-pipeline.sh | `Sonar@HMShop2024!` | Change before production use |
| `DB_PASSWORD` | K8s Secret `backend-secret` | `hmpassword` (base64) | Rotate for real deployments |
| `JWT_SECRET` | K8s Secret `backend-secret` | base64-encoded string | Change before production use |

---

## 🐛 Troubleshooting

### 1. PostgreSQL pod stuck in `Pending`

**Symptom:**
```
NAME                  READY   STATUS    RESTARTS
postgres-xxx-xxx      0/1     Pending   0
```

**Diagnosis:**
```bash
kubectl describe pod -n hm-shop -l app=postgres | grep -A 5 Events
# Look for: "no volume plugin matched" or "waiting for first consumer"
```

**Fix:**
```bash
# Verify EBS CSI Driver is ACTIVE
aws eks describe-addon \
  --cluster-name three-tier-cluster \
  --addon-name aws-ebs-csi-driver \
  --region ap-south-1 \
  --query "addon.status" --output text

# If not ACTIVE, check node role has AmazonEBSCSIDriverPolicy attached
aws iam list-attached-role-policies \
  --role-name three-tier-cluster-node-role \
  --query "AttachedPolicies[].PolicyName"
```

---

### 2. ALB not provisioning (Ingress ADDRESS stays empty)

**Symptom:** `kubectl get ingress -n hm-shop` shows no ADDRESS after 5+ minutes.

**Diagnosis:**
```bash
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller \
  --tail=50
```

**Fix:**
```bash
# Check VPC subnets have correct tags
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query "Subnets[*].{ID:SubnetId,Tags:Tags}"
# Public subnets need: kubernetes.io/role/elb = 1
# Private subnets need: kubernetes.io/role/internal-elb = 1

# Verify ALB Controller IRSA role
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml | grep role-arn
```

---

### 3. ArgoCD out of sync

**Symptom:** ArgoCD UI shows `OutOfSync` or `Unknown` health.

**Diagnosis:**
```bash
kubectl describe application hm-shop -n argocd | grep -A 10 "Conditions"
```

**Fix:**
```bash
# Check repoURL in application.yaml matches your GitHub repo exactly
cat argocd/application.yaml | grep repoURL

# Check ArgoCD can reach GitHub
kubectl exec -it deployment/argocd-server -n argocd -- \
  argocd-util repo ls

# Force a sync
kubectl patch application hm-shop -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

---

### 4. Jenkins Stage 5 fails (ECR auth error)

**Symptom:** `no basic auth credentials` or `denied: Your authorization token has expired`

**Diagnosis:**
```bash
# Check Jenkins aws-access-key credential is set
# Jenkins → Manage Jenkins → Credentials → look for aws-access-key
```

**Fix:**
```bash
# Verify the jenkins-ci IAM user has ECR permissions
aws iam list-attached-user-policies --user-name jenkins-ci
# Should include: AmazonEC2ContainerRegistryPowerUser

# Test ECR login manually on Jenkins EC2
ssh -i hm-eks-key.pem ubuntu@${JENKINS_IP}
aws ecr get-login-password --region ap-south-1 \
  | docker login --username AWS --password-stdin \
    ${AWS_ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com
# Expected: Login Succeeded
```

---

### 5. HPA shows `<unknown>` targets

**Symptom:**
```
NAME          TARGETS           MINPODS   MAXPODS
backend-hpa   <unknown>/70%     2         5
```

**Diagnosis:**
```bash
kubectl top pods -n hm-shop
# If this fails: Metrics Server is not running
```

**Fix:**
```bash
# Check Metrics Server pods
kubectl get pods -n kube-system | grep metrics-server

# Reinstall if missing
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Wait 60 seconds then check HPA again
kubectl get hpa -n hm-shop
```

---

### 6. SonarQube Quality Gate fails

**Symptom:** Stage 1 fails with `QUALITY GATE STATUS: FAILED`

**Diagnosis:**
```bash
# Open SonarQube dashboard
# http://<JENKINS_IP>:9000/dashboard?id=hm-fashion-clone
# Look at the Issues tab for specific violations
```

**Fix:**
- Review code issues reported in the SonarQube dashboard
- Common issues: code smells, high cognitive complexity, missing test coverage
- To temporarily allow the pipeline to proceed: in SonarQube → Quality Gates → Conditions → raise the threshold or switch to a more lenient gate

---

### 7. GitHub Webhook returns 404

**Symptom:** GitHub webhook delivery shows red ✗ with 404 response.

**Diagnosis:**
Check if Jenkins is reachable from GitHub (needs public IP, not localhost):
```bash
curl -I http://<JENKINS_IP>:8080/github-webhook/
# Expected: HTTP/1.1 200
```

**Fix:**
```bash
# Verify port 8080 is open in Jenkins security group
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=hm-shop-jenkins-sg" \
  --region ap-south-1 \
  --query "SecurityGroups[0].IpPermissions"

# Verify Jenkins GitHub plugin is installed
# Jenkins → Manage Jenkins → Plugins → Installed → search "github"

# Verify webhook URL format (must end with /github-webhook/)
# Correct:   http://13.233.x.x:8080/github-webhook/
# Incorrect: http://13.233.x.x:8080/github-webhook  (no trailing slash)
```

---

## 📁 Repository Structure

```
three-tier-eks-iac/
├── .gitignore
├── README.md                              ← This file
├── Jenkinsfile                            ← 7-stage CI/CD pipeline
├── install.sh                             ← One-command full bootstrap
├── uninstall.sh                           ← One-command full teardown
├── scripts/
│   └── setup-jenkins-pipeline.sh         ← Jenkins + SonarQube automation
├── app/
│   ├── frontend/                          ← React 18 H&M clone
│   │   ├── Dockerfile                     ← Multi-stage, non-root Nginx
│   │   ├── nginx.conf                     ← Reverse proxy to /api
│   │   ├── package.json
│   │   └── src/                           ← Components, contexts, services
│   └── backend/                           ← Node.js/Express REST API
│       ├── Dockerfile                     ← Non-root Node container
│       ├── index.js                       ← Express server entry point
│       ├── db/init.sql                    ← Schema + seed products
│       ├── routes/                        ← auth, products, orders, health
│       ├── middleware/authMiddleware.js   ← JWT verification
│       └── metrics/prometheus.js         ← prom-client metrics
├── terraform/
│   ├── providers.tf                       ← AWS + Kubernetes providers
│   ├── variables.tf                       ← All configurable variables
│   ├── vpc.tf                             ← VPC, subnets, NAT GWs, Jenkins EC2
│   ├── eks.tf                             ← EKS cluster + node group + OIDC
│   ├── ecr.tf                             ← ECR repos + lifecycle policies
│   ├── irsa.tf                            ← IRSA roles for ECR, ALB, Autoscaler
│   ├── outputs.tf                         ← All output values
│   └── alb-controller-policy.json        ← IAM policy for ALB controller
├── k8s_manifests/
│   ├── namespace.yaml
│   ├── storageclass.yaml                  ← hm-ebs-gp2 (WaitForFirstConsumer)
│   ├── ingressclass.yaml                  ← alb IngressClass
│   ├── ingress.yaml                       ← ALB with /api and / routing
│   ├── postgres/                          ← secret, configmap, pvc, deployment, svc, hpa
│   ├── backend/                           ← serviceaccount (IRSA), secret, deployment, svc, hpa
│   └── frontend/                          ← serviceaccount (IRSA), deployment, svc, hpa
├── argocd/
│   └── application.yaml                   ← GitOps app pointing at k8s_manifests/
└── monitoring/
    ├── prometheus-values.yaml             ← kube-prometheus-stack + backend scrape config
    └── grafana-values.yaml                ← Grafana with 4 pre-imported dashboards
```

---

*Generated for AWS region ap-south-1 (Mumbai). Do not use ap-southeast-1 — all ECR URLs, IRSA ARNs, and region flags in this repository are ap-south-1.*
