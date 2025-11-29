#!/usr/bin/env bash
set -euo pipefail

# --- Configuration & Defaults ---
TARGET_ARCH="amd64"
OUTPUT_FILE="image_audit_report.csv"
TEMP_IMG_LIST="/tmp/k8s_images_unique.txt"
AWS_PROFILE_NAME=""
AWS_REGION="ap-south-1" # Default region, can be overridden
DO_AWS_LOGIN=false

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Helper Functions ---

function usage() {
  echo -e "${CYAN}Kubernetes Image Architecture Auditor${NC}"
  echo "Usage: $(basename "$0") [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -a <arch>     Target architecture to check (default: amd64)"
  echo "  -p <profile>  AWS Profile to use for ECR authentication"
  echo "  -r <region>   AWS Region for ECR (default: ap-south-1)"
  echo "  -o <file>     Output CSV filename (default: image_audit_report.csv)"
  echo "  -h            Show this help message"
  echo ""
  echo "Examples:"
  echo "  ./$(basename "$0") -p my-aws-profile"
  echo "  ./$(basename "$0") -a arm64 -r us-east-1"
}

function perform_aws_login() {
  echo -e "${CYAN}[*] Authenticating with AWS ECR...${NC}"

  # Set profile if provided
  if [[ -n "$AWS_PROFILE_NAME" ]]; then
    export AWS_PROFILE="$AWS_PROFILE_NAME"
    echo "    Using AWS Profile: $AWS_PROFILE"
  fi

  # verify aws connectivity / get account ID
  if ! ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
    echo -e "${RED}[!] Error: Failed to get AWS Account ID. Check your credentials/profile.${NC}"
    exit 1
  fi

  echo "    Account ID: $ACCOUNT_ID"
  echo "    Region:     $AWS_REGION"

  # Construct Registry URL
  REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

  # Pipe token to Skopeo
  if aws ecr get-login-password --region "$AWS_REGION" | skopeo login --username AWS --password-stdin "$REGISTRY" >/dev/null 2>&1; then
    echo -e "${GREEN}[✔] Successfully logged Skopeo into $REGISTRY${NC}"
  else
    echo -e "${RED}[!] Error: Skopeo login failed.${NC}"
    exit 1
  fi
}

# --- Argument Parsing ---

while getopts ":a:p:r:o:h" opt; do
  case ${opt} in
  a) TARGET_ARCH="$OPTARG" ;;
  p)
    AWS_PROFILE_NAME="$OPTARG"
    DO_AWS_LOGIN=true
    ;;
  r) AWS_REGION="$OPTARG" ;;
  o) OUTPUT_FILE="$OPTARG" ;;
  h)
    usage
    exit 0
    ;;
  \?)
    echo -e "${RED}Invalid option: -$OPTARG${NC}" >&2
    usage
    exit 1
    ;;
  esac
done

# --- Main Execution ---

# 1. Dependency Check
for tool in kubectl skopeo jq tr sort aws; do
  if ! command -v "$tool" &>/dev/null; then
    echo -e "${RED}[!] Error: Required tool '$tool' is not installed.${NC}"
    exit 1
  fi
done

# 2. AWS Login (if requested via profile or implied context)
if [[ "$DO_AWS_LOGIN" == "true" ]]; then
  perform_aws_login
fi

# 3. Fetch Images
echo -e "${CYAN}[*] Fetching unique images from current Kubernetes context...${NC}"
kubectl get pods -A -o jsonpath="{.items[*].spec['containers','initContainers','ephemeralContainers'][*].image}" |
  tr ' ' '\n' |
  sort -u |
  grep -v "^$" >"$TEMP_IMG_LIST"

IMAGE_COUNT=$(wc -l <"$TEMP_IMG_LIST")
echo -e "${GREEN}[+] Found $IMAGE_COUNT unique images.${NC}"

# 4. Initialize CSV
echo "Image,Status,Target_Arch_($TARGET_ARCH),Type,Details" >"$OUTPUT_FILE"

# 5. Inspection Loop
echo -e "${CYAN}[*] Starting inspection for architecture: $TARGET_ARCH...${NC}"
while IFS= read -r IMAGE; do
  echo -ne "Processing: $IMAGE ... \r"

  if ! OUTPUT=$(skopeo inspect --raw "docker://$IMAGE" 2>/dev/null); then
    echo "$IMAGE,ERROR,Unknown,Unknown,Failed to inspect (Auth/Network/Not Found)" >>"$OUTPUT_FILE"
    echo -e "Processing: $IMAGE ... ${RED}FAILED${NC}"
    continue
  fi

  STATUS=""
  FOUND_TARGET="FALSE"
  TYPE=""
  DETAILS=""

  # Check for Manifest List (Multi-arch)
  if echo "$OUTPUT" | jq -e '.manifests' >/dev/null 2>&1; then
    TYPE="Multi-Arch"
    AVAIL_ARCHS=$(echo "$OUTPUT" | jq -r '[.manifests[].platform.architecture] | unique | join("|")')
    DETAILS="Available: $AVAIL_ARCHS"

    if echo "$OUTPUT" | jq -e --arg arch "$TARGET_ARCH" 'any(.manifests[]; .platform.architecture == $arch)' >/dev/null 2>&1; then
      STATUS="OK"
      FOUND_TARGET="TRUE"
      echo -e "Processing: $IMAGE ... ${GREEN}OK (Multi)${NC}"
    else
      STATUS="MISSING_ARCH"
      echo -e "Processing: $IMAGE ... ${YELLOW}MISSING ($TARGET_ARCH)${NC}"
    fi
  else
    # Single Image
    TYPE="Single-Arch"
    SINGLE_ARCH=$(skopeo inspect "docker://$IMAGE" 2>/dev/null | jq -r '.Architecture')
    DETAILS="Actual: $SINGLE_ARCH"

    if [[ "$SINGLE_ARCH" == "$TARGET_ARCH" ]]; then
      STATUS="OK"
      FOUND_TARGET="TRUE"
      echo -e "Processing: $IMAGE ... ${GREEN}OK (Single)${NC}"
    else
      STATUS="MISMATCH"
      echo -e "Processing: $IMAGE ... ${YELLOW}MISMATCH ($SINGLE_ARCH)${NC}"
    fi
  fi

  echo "$IMAGE,$STATUS,$FOUND_TARGET,$TYPE,$DETAILS" >>"$OUTPUT_FILE"

done <"$TEMP_IMG_LIST"

echo -e "\n${GREEN}[✔] Audit complete! Report generated: $OUTPUT_FILE${NC}"
