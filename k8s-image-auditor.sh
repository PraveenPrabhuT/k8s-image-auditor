#!/usr/bin/env bash
set -euo pipefail

VERSION="0.0.0-dev" #placeholder version to be replaced by goreleaser

# --- Configuration & Defaults ---
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TARGET_ARCH="amd64"
OUTPUT_FILE="image_audit_report_${TIMESTAMP}.csv"
TEMP_IMG_LIST="/tmp/k8s_images_unique.txt"

# Default to Env Var if present, otherwise empty (will rely on 'default' profile or instance role)
AWS_PROFILE_NAME="${AWS_PROFILE:-}" 
AWS_REGION="ap-south-1" 
DO_AWS_LOGIN=true 

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Signal Handling & Cleanup ---
function cleanup() {
    # Only run if the file actually exists
    if [[ -f "$TEMP_IMG_LIST" ]]; then
        # Check if debug mode is on (optional), otherwise remove
        rm -f "$TEMP_IMG_LIST"
    fi
    # Reset terminal colors just in case we crashed mid-color
    echo -ne "${NC}"
}

# Trap these signals:
# EXIT = Runs when script ends normally OR by error
# SIGINT = Runs when you press Ctrl+C
# SIGTERM = Runs when a kill command is sent
trap cleanup EXIT SIGINT SIGTERM

# --- Helper Functions ---

function usage() {
    echo -e "${CYAN}Kubernetes Image Architecture Auditor${NC}"
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -a <arch>     Target architecture to check (default: amd64)"
    echo "  -p <profile>  AWS Profile (defaults to \$AWS_PROFILE or active config)"
    echo "  -r <region>   AWS Region (default: ap-south-1)"
    echo "  -o <file>     Output filename (default: image_audit_report_TIMESTAMP.csv)"
    echo "  -s            Skip AWS Login (use if checking public/local images only)"
    echo "  -v            Show version info"
    echo "  -h --help     Show this help message"
}

function perform_aws_login() {
    echo -e "${CYAN}[*] Authenticating with AWS ECR...${NC}"
    
    # Export profile if set (either from Env or Flag)
    if [[ -n "$AWS_PROFILE_NAME" ]]; then
        export AWS_PROFILE="$AWS_PROFILE_NAME"
        echo "    Using AWS Profile: $AWS_PROFILE"
    else
        echo "    Using Default AWS Chain (Env/Instance Profile)"
    fi

    # verify aws connectivity
    if ! ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
        echo -e "${RED}[!] Error: Failed to get AWS Account ID. Check your credentials.${NC}"
        echo -e "${YELLOW}    Tip: Run 'aws configure' or set AWS_PROFILE.${NC}"
        exit 1
    fi

    echo "    Account ID: $ACCOUNT_ID"
    echo "    Region:     $AWS_REGION"

    REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

    if aws ecr get-login-password --region "$AWS_REGION" | skopeo login --username AWS --password-stdin "$REGISTRY" >/dev/null 2>&1; then
        echo -e "${GREEN}[✔] Successfully logged Skopeo into $REGISTRY${NC}"
    else
        echo -e "${RED}[!] Error: Skopeo login failed.${NC}"
        exit 1
    fi
}

function check_dependencies() {
    local missing_tools=()
    for tool in kubectl skopeo jq aws; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    # tr and sort are usually built-in, but good to be safe
    if ! command -v tr &> /dev/null; then missing_tools+=("coreutils"); fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}[!] Error: Missing required tools: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}    To install all dependencies via Homebrew, run:${NC}"
        
        # Map tool names to brew package names
        BREW_CMD="brew install"
        for t in "${missing_tools[@]}"; do
            case $t in
                kubectl) BREW_CMD="$BREW_CMD kubernetes-cli" ;;
                aws)     BREW_CMD="$BREW_CMD awscli" ;;
                *)       BREW_CMD="$BREW_CMD $t" ;;
            esac
        done
        
        echo -e "\n    ${CYAN}$BREW_CMD${NC}\n"
        exit 1
    fi
}

# --- Argument Parsing ---
for arg in "$@"; do
  case "$arg" in
    --help)
      usage
      exit 0
      ;;
  esac
done

while getopts ":a:p:r:o:shv" opt; do
  case ${opt} in
    a) TARGET_ARCH="$OPTARG" ;;
    p) AWS_PROFILE_NAME="$OPTARG" ;;
    r) AWS_REGION="$OPTARG" ;;
    o) OUTPUT_FILE="$OPTARG" ;;
    s) DO_AWS_LOGIN=false ;; # Flag to SKIP login
    v) echo "k8s-image-auditor version $VERSION"; exit 0 ;;
    h) usage; exit 0 ;;
    \?) echo -e "${RED}Invalid option: -$OPTARG${NC}" >&2; usage; exit 1 ;;
  esac
done

# --- Main Execution ---

# 1. Dependency Check
check_dependencies

# 2. AWS Login (Default: True)
if [[ "$DO_AWS_LOGIN" == "true" ]]; then
    perform_aws_login
fi

# 3. Fetch Images
echo -e "${CYAN}[*] Fetching unique images from current Kubernetes context...${NC}"
kubectl get pods -A -o jsonpath="{.items[*].spec['containers','initContainers','ephemeralContainers'][*].image}" \
    | tr ' ' '\n' \
    | sort -u \
    | grep -v "^$" > "$TEMP_IMG_LIST"

IMAGE_COUNT=$(wc -l < "$TEMP_IMG_LIST")
echo -e "${GREEN}[+] Found $IMAGE_COUNT unique images.${NC}"

# 4. Initialize CSV
echo "Image,Status,Target_Arch_($TARGET_ARCH),Type,Details" > "$OUTPUT_FILE"

# 5. Inspection Loop
echo -e "${CYAN}[*] Starting inspection for architecture: $TARGET_ARCH...${NC}"
while IFS= read -r IMAGE; do
    echo -ne "Processing: $IMAGE ... \r"

    if ! OUTPUT=$(skopeo inspect --raw "docker://$IMAGE" 2>/dev/null); then
        echo "$IMAGE,ERROR,Unknown,Unknown,Failed to inspect (Auth/Network/Not Found)" >> "$OUTPUT_FILE"
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

    echo "$IMAGE,$STATUS,$FOUND_TARGET,$TYPE,$DETAILS" >> "$OUTPUT_FILE"

done <"$TEMP_IMG_LIST"

echo -e "\n${GREEN}[✔] Audit complete! Report generated: $OUTPUT_FILE${NC}"