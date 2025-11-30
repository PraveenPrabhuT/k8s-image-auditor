% k8s-image-auditor(1) Version 1.0 | Kubernetes Image Architecture Auditor

# NAME
k8s-image-auditor - audits container images for architecture compatibility

# SYNOPSIS
**k8s-image-auditor** [**-a** *arch*] [**-p** *profile*] [**-r** *region*] [**-o** *file*] [**-s**]

# DESCRIPTION
**k8s-image-auditor** scans all pods in the current Kubernetes context (including initContainers and ephemeralContainers). It extracts image names and inspects their remote manifests using **skopeo(1)**.

It determines if the image supports the target architecture (e.g., amd64, arm64) and detects if the image is a multi-arch manifest or a single-arch image.

# OPTIONS
**-a** *arch*
:   Target architecture to check. Defaults to **amd64**.

**-p** *profile*
:   AWS Profile to use for ECR authentication. Overrides **AWS_PROFILE** environment variable.

**-r** *region*
:   AWS Region for ECR. Defaults to **ap-south-1**.

**-o** *file*
:   Output CSV filename. Defaults to **image_audit_report_TIMESTAMP.csv**.

**-s**
:   Skip AWS Login. Useful for checking public images without credentials.

**-h**
:   Show help message.

# EXAMPLES
**Audit for Graviton (ARM64) migration:**
:   k8s-image-auditor -a arm64

**Audit private ECR images using a specific profile:**
:   k8s-image-auditor -p prod-admin -r us-east-1

# ENVIRONMENT
**AWS_PROFILE**
:   If set, the script uses this profile for AWS CLI authentication unless overridden by **-p**.

# SEE ALSO
**kubectl(1)**, **skopeo(1)**, **aws(1)**