#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   TECHNO SERVERLESS OMS — JURI DEPLOY SCRIPT                    ║
# ║   Build layer + package Lambda + upload S3 + deploy 7 stacks    ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# CARA PAKAI:
#   1. Set AWS credentials di terminal (dari AWS Academy Learner Lab)
#   2. Jalankan: chmod +x deploy-juri.sh && ./deploy-juri.sh
#
# PREREQUISITES:
#   - AWS CLI v2
#   - Python 3.11+ & pip3
#   - zip / unzip
# ──────────────────────────────────────────────────────────────────

set -e

# ── KONFIGURASI (edit sesuai kebutuhan) ───────────────────────────
YOUR_NAME="${1:-juritest}"          # nama lowercase, tanpa spasi
BUCKET_SUFFIX="${2:-01}"            # ganti jika bucket sudah ada
NOTIFICATION_EMAIL="${3:-handi@seamolec.org}"
DB_PASSWORD="TechnoCloud2026!"
REGION="us-east-1"
# ──────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_BUCKET="techno-layer-${YOUR_NAME}-${BUCKET_SUFFIX}"
LAMBDA_BUCKET="techno-lambda-${YOUR_NAME}-${BUCKET_SUFFIX}"
TMP="/tmp/techno-juri-deploy"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()     { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }
step()    { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }

# ── VALIDASI AWS CREDENTIALS ──────────────────────────────────────
step "VALIDASI CREDENTIALS"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || err "AWS credentials tidak valid. Set dulu: export AWS_ACCESS_KEY_ID=... dst"
LAB_ROLE="arn:aws:iam::${ACCOUNT_ID}:role/LabRole"
success "Account: ${ACCOUNT_ID} | Role: LabRole"

echo ""
echo -e "${BOLD}Konfigurasi deploy:${NC}"
echo "  Nama       : ${YOUR_NAME}"
echo "  Suffix     : ${BUCKET_SUFFIX}"
echo "  Email      : ${NOTIFICATION_EMAIL}"
echo "  Region     : ${REGION}"
echo "  Account    : ${ACCOUNT_ID}"
echo ""
read -p "Lanjutkan? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && echo "Dibatalkan." && exit 0

rm -rf "$TMP" && mkdir -p "$TMP"

# ══════════════════════════════════════════════════════════════════
# STEP 1 — BUILD LAMBDA LAYER
# ══════════════════════════════════════════════════════════════════
step "STEP 1/8 — Build Lambda Layer"

LAYER_DIR="$TMP/layer/python"
mkdir -p "$LAYER_DIR"

info "Install dependencies ke $LAYER_DIR ..."
pip3 install \
  psycopg2-binary \
  requests \
  pandas \
  openpyxl \
  "aws-xray-sdk>=2.12.0" \
  --target "$LAYER_DIR" \
  --quiet \
  --no-cache-dir

# Strip test/cache files untuk kecilkan ukuran
find "$LAYER_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$LAYER_DIR" -type d -name "tests"       -exec rm -rf {} + 2>/dev/null || true
find "$LAYER_DIR" -name "*.pyc"               -delete 2>/dev/null || true

cd "$TMP/layer"
zip -r "$TMP/techno-layer-dependencies.zip" python/ -q
LAYER_SIZE=$(du -sh "$TMP/techno-layer-dependencies.zip" | cut -f1)
success "Layer built: ${LAYER_SIZE}"

# ══════════════════════════════════════════════════════════════════
# STEP 2 — PACKAGE LAMBDA FUNCTIONS (7 fungsi)
# ══════════════════════════════════════════════════════════════════
step "STEP 2/8 — Package Lambda Functions"

LAMBDA_SRC="$SCRIPT_DIR/lambda"
FUNCTIONS=(order_management process_payment update_inventory send_notification generate_report init_db health_check)

for fn in "${FUNCTIONS[@]}"; do
  SRC="$LAMBDA_SRC/$fn/lambda_function.py"
  [[ ! -f "$SRC" ]] && err "File tidak ditemukan: $SRC"
  cd "$LAMBDA_SRC/$fn"
  zip -q "$TMP/${fn}.zip" lambda_function.py
  success "Packaged: ${fn}.zip ($(du -sh $TMP/${fn}.zip | cut -f1))"
done

# ══════════════════════════════════════════════════════════════════
# STEP 3 — BUAT S3 BUCKETS & UPLOAD
# ══════════════════════════════════════════════════════════════════
step "STEP 3/8 — Buat S3 Buckets & Upload Artifacts"

create_bucket() {
  local BUCKET=$1
  if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
    warn "Bucket $BUCKET sudah ada, skip create"
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" --no-cli-pager
    aws s3api put-bucket-versioning --bucket "$BUCKET" \
      --versioning-configuration Status=Enabled --no-cli-pager
    success "Bucket dibuat: $BUCKET"
  fi
}

create_bucket "$LAYER_BUCKET"
create_bucket "$LAMBDA_BUCKET"

info "Upload layer..."
aws s3 cp "$TMP/techno-layer-dependencies.zip" \
  "s3://${LAYER_BUCKET}/layer/techno-layer-dependencies.zip" \
  --region "$REGION" --no-cli-pager
success "Layer uploaded"

info "Upload Lambda zips..."
for fn in "${FUNCTIONS[@]}"; do
  aws s3 cp "$TMP/${fn}.zip" \
    "s3://${LAMBDA_BUCKET}/${fn}/lambda_function.zip" \
    --region "$REGION" --no-cli-pager
  success "  $fn uploaded"
done

# ══════════════════════════════════════════════════════════════════
# FUNGSI DEPLOY STACK
# ══════════════════════════════════════════════════════════════════
deploy_stack() {
  local STACK_NAME=$1
  local TEMPLATE=$2
  shift 2
  local PARAMS=("$@")

  info "Deploy stack: ${STACK_NAME} ..."

  # Build parameter overrides string
  PARAM_STR=""
  for p in "${PARAMS[@]}"; do
    PARAM_STR="$PARAM_STR $p"
  done

  aws cloudformation deploy \
    --template-file "$SCRIPT_DIR/cloudformation/${TEMPLATE}" \
    --stack-name "$STACK_NAME" \
    --parameter-overrides $PARAM_STR \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --no-fail-on-empty-changeset \
    --no-cli-pager

  success "Stack ${STACK_NAME} selesai!"
}

get_output() {
  local STACK=$1
  local KEY=$2
  aws cloudformation describe-stacks \
    --stack-name "$STACK" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='${KEY}'].OutputValue" \
    --output text --no-cli-pager
}

# ══════════════════════════════════════════════════════════════════
# STEP 4 — STACK 01: NETWORKING
# ══════════════════════════════════════════════════════════════════
step "STEP 4/8 — Deploy Stack 01: Networking"
deploy_stack "techno-01-networking" "01-networking.yaml" \
  "YourName=${YOUR_NAME}"

PRIV_SUB1=$(get_output "techno-01-networking" "PrivateSubnet1Id")
PRIV_SUB2=$(get_output "techno-01-networking" "PrivateSubnet2Id")
LAMBDA_SG=$(get_output "techno-01-networking" "LambdaSGId")
RDS_SG=$(get_output "techno-01-networking" "RdsSGId")
info "PrivateSubnet1: $PRIV_SUB1"
info "PrivateSubnet2: $PRIV_SUB2"
info "LambdaSG: $LAMBDA_SG"

# ══════════════════════════════════════════════════════════════════
# STEP 5 — STACK 02: STORAGE
# ══════════════════════════════════════════════════════════════════
step "STEP 5/8 — Deploy Stack 02: Storage"
deploy_stack "techno-02-storage" "02-storage.yaml" \
  "YourName=${YOUR_NAME}" \
  "BucketSuffix=${BUCKET_SUFFIX}" \
  "DBPassword=${DB_PASSWORD}"

SECRET_ARN=$(get_output "techno-02-storage" "SecretArn")
ORDERS_BUCKET=$(get_output "techno-02-storage" "OrdersBucketName")
LOGS_BUCKET=$(get_output "techno-02-storage" "LogsBucketName")
info "SecretArn: $SECRET_ARN"
info "OrdersBucket: $ORDERS_BUCKET"
info "LogsBucket: $LOGS_BUCKET"

# ══════════════════════════════════════════════════════════════════
# STEP 5b — UPDATE 04-compute.yaml dengan S3 bucket yang benar
# ══════════════════════════════════════════════════════════════════
info "Inject S3 bucket name ke 04-compute.yaml ..."
# Update LayerS3Bucket default value di parameter description saja
# (kita pass via parameter override, tidak perlu edit file)

# ══════════════════════════════════════════════════════════════════
# STEP 6 — STACK 03: DATABASE (~15 menit)
# ══════════════════════════════════════════════════════════════════
step "STEP 6/8 — Deploy Stack 03: Database (estimasi 15 menit...)"
info "Menunggu RDS PostgreSQL 15 selesai provisioning..."
deploy_stack "techno-03-database" "03-database.yaml" \
  "DBPassword=${DB_PASSWORD}" \
  "PrivateSubnet1Id=${PRIV_SUB1}" \
  "PrivateSubnet2Id=${PRIV_SUB2}" \
  "RdsSGId=${RDS_SG}"

RDS_ENDPOINT=$(get_output "techno-03-database" "RdsEndpoint")
success "RDS Endpoint: $RDS_ENDPOINT"

# ── Update Secrets Manager dengan RDS endpoint via AWS CLI ────────
# (tidak pakai Custom Resource agar tidak hang)
info "Update Secrets Manager dengan RDS endpoint..."
aws secretsmanager update-secret \
  --secret-id "$SECRET_ARN" \
  --secret-string "{\"host\":\"${RDS_ENDPOINT}\",\"dbname\":\"ordersdb\",\"username\":\"dbadmin\",\"password\":\"${DB_PASSWORD}\"}" \
  --region "$REGION" \
  --no-cli-pager > /dev/null
success "Secrets Manager updated dengan host: $RDS_ENDPOINT"

# ══════════════════════════════════════════════════════════════════
# STEP 7 — STACK 04: COMPUTE
# ══════════════════════════════════════════════════════════════════
step "STEP 7/8 — Deploy Stack 04: Compute (Lambda + SNS + DynamoDB)"

deploy_stack "techno-04-compute" "04-compute.yaml" \
  "PrivateSubnet1Id=${PRIV_SUB1}" \
  "PrivateSubnet2Id=${PRIV_SUB2}" \
  "LambdaSGId=${LAMBDA_SG}" \
  "SecretArn=${SECRET_ARN}" \
  "S3OrdersBucket=${ORDERS_BUCKET}" \
  "S3LogsBucket=${LOGS_BUCKET}" \
  "NotificationEmail=${NOTIFICATION_EMAIL}" \
  "LayerS3Bucket=${LAYER_BUCKET}" \
  "LambdaS3Bucket=${LAMBDA_BUCKET}"

SNS_ARN=$(get_output  "techno-04-compute" "SnsTopicArn")
FN_ORDER=$(get_output "techno-04-compute" "FnOrderMgmtArn")
FN_PAY=$(get_output   "techno-04-compute" "FnPaymentArn")
FN_INV=$(get_output   "techno-04-compute" "FnInventoryArn")
FN_NOTIF=$(get_output "techno-04-compute" "FnNotifArn")
FN_REPORT=$(get_output "techno-04-compute" "FnReportArn")
FN_HEALTH=$(get_output "techno-04-compute" "FnHealthArn")

info "SNS: $SNS_ARN"
info "FnOrder: $FN_ORDER"

# Invoke init-db dengan sample data
info "Menjalankan init-db (buat tabel + sample data)..."
aws lambda invoke \
  --function-name techno-lambda-init-db \
  --payload '{"insert_sample_data": true, "drop_existing": false}' \
  --cli-binary-format raw-in-base64-out \
  "$TMP/init-db-response.json" \
  --region "$REGION" --no-cli-pager >/dev/null
success "Init DB: $(cat $TMP/init-db-response.json | python3 -c 'import sys,json; r=json.load(sys.stdin); print(r.get("body","done")[:80])' 2>/dev/null || echo 'done')"

# ══════════════════════════════════════════════════════════════════
# STEP 7b — STACK 05: ORCHESTRATION
# ══════════════════════════════════════════════════════════════════
step "STEP 7/8 — Deploy Stack 05: Orchestration (Step Functions + EventBridge)"
deploy_stack "techno-05-orchestration" "05-orchestration.yaml" \
  "FnOrderMgmtArn=${FN_ORDER}" \
  "FnPaymentArn=${FN_PAY}" \
  "FnInventoryArn=${FN_INV}" \
  "FnNotifArn=${FN_NOTIF}" \
  "FnReportArn=${FN_REPORT}"

SF_ARN=$(get_output "techno-05-orchestration" "StateMachineArn")
info "StateMachine: $SF_ARN"

# ══════════════════════════════════════════════════════════════════
# STEP 7c — STACK 06: API GATEWAY
# ══════════════════════════════════════════════════════════════════
# Set CloudWatch Logs role di account-level API Gateway (wajib ada meski tidak pakai logging)
info "Set CloudWatch role untuk API Gateway account settings..."
aws apigateway update-account \
  --patch-operations "op=replace,path=/cloudwatchRoleArn,value=arn:aws:iam::${ACCOUNT_ID}:role/LabRole" \
  --region "$REGION" --no-cli-pager > /dev/null 2>&1 \
  && success "API Gateway account settings updated" \
  || warn "update-account skip - lanjut deploy..."

deploy_stack "techno-06-apigateway" "06-apigateway.yaml" \
  "FnOrderMgmtArn=${FN_ORDER}" \
  "FnHealthArn=${FN_HEALTH}"

API_ENDPOINT=$(get_output "techno-06-apigateway" "ApiEndpoint")
API_KEY_ID=$(get_output   "techno-06-apigateway" "ApiKeyId")
API_ID=$(get_output       "techno-06-apigateway" "ApiId")

# Ambil nilai API key
API_KEY_VALUE=$(aws apigateway get-api-key \
  --api-key "$API_KEY_ID" \
  --include-value \
  --query value \
  --output text \
  --region "$REGION" --no-cli-pager)

info "API Endpoint: $API_ENDPOINT"
info "API Key: $API_KEY_VALUE"

# ══════════════════════════════════════════════════════════════════
# STEP 8 — STACK 07: CICD
# ══════════════════════════════════════════════════════════════════
step "STEP 8/8 — Deploy Stack 07: CI/CD & Observability"
deploy_stack "techno-07-cicd" "07-cicd.yaml" \
  "LogsBucketName=${LOGS_BUCKET}" \
  "SnsTopicArn=${SNS_ARN}" \
  "StateMachineArn=${SF_ARN}" \
  "ApiId=${API_ID}"

DASHBOARD=$(get_output "techno-07-cicd" "DashboardUrl")

# ══════════════════════════════════════════════════════════════════
# HASIL AKHIR
# ══════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         ✅  DEPLOY SELESAI — SEMUA 7 STACK AKTIF             ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}━━━ INFORMASI UNTUK TESTING ━━━${NC}"
printf "%-20s : %s\n" "API Endpoint"      "$API_ENDPOINT"
printf "%-20s : %s\n" "API Key"           "$API_KEY_VALUE"
printf "%-20s : %s\n" "SNS Topic ARN"     "$SNS_ARN"
printf "%-20s : %s\n" "Step Functions"    "$SF_ARN"
printf "%-20s : %s\n" "RDS Endpoint"      "$RDS_ENDPOINT"
printf "%-20s : %s\n" "Orders Bucket"     "$ORDERS_BUCKET"
printf "%-20s : %s\n" "Logs Bucket"       "$LOGS_BUCKET"
printf "%-20s : %s\n" "CloudWatch"        "$DASHBOARD"
echo ""

# Simpan output ke file
cat > "$SCRIPT_DIR/deploy-output.txt" << EOF
=== TECHNO SERVERLESS OMS - DEPLOY OUTPUT ===
Tanggal  : $(date)
Account  : ${ACCOUNT_ID}
Region   : ${REGION}

API Endpoint   : ${API_ENDPOINT}
API Key        : ${API_KEY_VALUE}
SNS Topic ARN  : ${SNS_ARN}
Step Functions : ${SF_ARN}
RDS Endpoint   : ${RDS_ENDPOINT}
Orders Bucket  : ${ORDERS_BUCKET}
Logs Bucket    : ${LOGS_BUCKET}
Dashboard      : ${DASHBOARD}

GitHub Actions Secrets:
  AWS_ACCESS_KEY_ID     = (dari Learner Lab)
  AWS_SECRET_ACCESS_KEY = (dari Learner Lab)
  AWS_SESSION_TOKEN     = (dari Learner Lab)
  SNS_TOPIC_ARN         = ${SNS_ARN}
  S3_DEPLOYMENT_BUCKET  = ${LOGS_BUCKET}
  AMPLIFY_APP_ID        = (isi setelah buat Amplify app)

Amplify Environment Variables:
  API_ENDPOINT = ${API_ENDPOINT}
  API_KEY      = ${API_KEY_VALUE}
  AWS_REGION   = ${REGION}
EOF

success "Output tersimpan di: $SCRIPT_DIR/deploy-output.txt"
echo ""
echo -e "${YELLOW}Langkah berikutnya:${NC}"
echo "  1. Cek email untuk konfirmasi SNS subscription"
echo "  2. Test API: curl -H 'x-api-key: ${API_KEY_VALUE}' ${API_ENDPOINT}/health"
echo "  3. Buat Amplify app → connect GitHub repo → set env vars (lihat deploy-output.txt)"
echo "  4. Set GitHub Actions secrets (lihat deploy-output.txt)"
echo ""
