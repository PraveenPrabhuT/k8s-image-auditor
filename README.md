# Kubernetes Image Architecture Auditor

A robust, automated utility to audit container images running in your Kubernetes cluster. It verifies if images support a specific architecture (e.g., `amd64`, `arm64`) by inspecting their remote manifests using `skopeo`.

This tool is optimized for **AWS ECR** environments but works with any standard registry.

## 🚀 Features

* **Comprehensive Scrape:** Fetches images from `containers`, `initContainers`, and `ephemeralContainers` across **all namespaces**.
* **Smart AWS Auth:** Automatically detects your `AWS_PROFILE` or handles manual overrides for seamless ECR inspection.
* **Deep Inspection:** Distinguishes between Multi-Architecture Manifests and Single-Architecture Images.
* **Timestamped Reporting:** Generates unique CSV reports for every run (e.g., `image_audit_report_20231027_103000.csv`).
* **Auto-Dependency Check:** Detects missing tools and provides the exact `brew install` command to fix them.
* **CI/CD Ready:** Includes a GitHub Actions workflow for weekly automated audits.

## 📋 Prerequisites

The script checks for these tools on startup. If missing, it will give you the install command.

* `bash` (v4+)
* `kubectl` (configured with cluster access)
* `skopeo` (for inspecting remote registries)
* `jq` (for JSON parsing)
* `aws-cli` (v2, required for ECR)
* `pandoc` (optional, only for building the man page)

**Quick Install (Homebrew):**
```bash
brew install kubernetes-cli skopeo jq awscli pandoc
```

## 🛠 Installation

### Method 1: The "Byte-Smith" Way (Makefile)
This installs the tool to your user-local path (`~/.local/bin`) and installs the manual page (`man k8s-image-auditor`). **No sudo required.**

```bash
make install
```

Ensure `~/.local/bin` is in your `$PATH`. You can then run:
```bash
k8s-image-auditor
man k8s-image-auditor
```

### Method 2: Manual (Quick & Dirty)
Simply make the script executable and run it directly:
```bash
chmod +x k8s-image-auditor.sh
./k8s-image-auditor.sh
```

## 📖 Usage

### 1. Standard Run (Default)
Checks all images for `amd64` compatibility. Uses your current `AWS_PROFILE` env var or default credentials for ECR login.
```bash
k8s-image-auditor
```

### 2. Check for Graviton (ARM64) Support
Ideal for migration planning.
```bash
k8s-image-auditor -a arm64
```

### 3. Using a Specific AWS Profile
Overrides the environment variable.
```bash
k8s-image-auditor -p my-production-profile
```

### 4. Skip AWS Login
Use this if you are only checking public images (Docker Hub, Quay, etc.) and don't need ECR access.
```bash
k8s-image-auditor -s
```

### Full Options
```text
Usage: k8s-image-auditor [OPTIONS]

Options:
  -a <arch>     Target architecture to check (default: amd64)
  -p <profile>  AWS Profile (defaults to $AWS_PROFILE or active config)
  -r <region>   AWS Region (default: ap-south-1)
  -o <file>     Output filename (default: image_audit_report_TIMESTAMP.csv)
  -s            Skip AWS Login
  -v            Show version info
  -h            Show help message
```

## 📊 Output Format

The script generates a CSV file with the following columns:

| Column | Description |
| :--- | :--- |
| **Image** | The full image tag (e.g., `nginx:latest`). |
| **Status** | `OK` (compatible), `MISSING_ARCH` (multi-arch but missing target), `MISMATCH` (wrong single arch), `ERROR` (not found/auth fail). |
| **Target_Arch_Found** | `TRUE` if the requested architecture exists, otherwise `FALSE`. |
| **Type** | `Multi-Arch` (manifest list) or `Single-Arch`. |
| **Details** | Lists available architectures (if multi-arch) or the actual architecture (if single). |

## 🤖 Automation (GitHub Actions)

This repository includes a workflow `.github/workflows/audit.yml` that runs every **Sunday at 00:00 UTC**.

To enable it, set the following Secrets in your GitHub Repo:
1.  `AWS_ROLE_ARN`: IAM Role ARN with ECR Read permissions.
2.  `KUBE_CONFIG_DATA`: Base64 encoded `~/.kube/config` file.

The audit report will be available as a downloadable Artifact in the GitHub Actions "Summary" tab.

## 🤝 Troubleshooting

* **"Failed to inspect (Auth/Network/Not Found)"**:
    * Ensure you have network access to the registry.
    * If using ECR, check that your AWS Profile has permission to `ecr:GetAuthorizationToken` and `ecr:BatchGetImage`.
    * Run with `-s` if you are sure you don't need AWS credentials.
* **"command not found: k8s-image-auditor"**:
    * If you used `make install`, ensure `export PATH=$HOME/.local/bin:$PATH` is in your shell profile (`.zshrc` or `.bashrc`).