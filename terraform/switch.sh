#!/bin/bash
set -e

#
# Switch between clusters by changing the terraform backend.
# Your terraform.tfvars is NEVER modified by this script.
#
# Usage:
#   ./switch.sh myproject dev     # Switch to myproject-dev cluster
#   ./switch.sh myproject staging # Switch to myproject-staging cluster
#

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <project_name> <environment>"
    echo ""
    echo "Examples:"
    echo "  $0 exystem dev       # Switch to exystem-dev"
    echo "  $0 exystem staging   # Switch to exystem-staging"
    echo ""
    if [[ -f ".terraform/terraform.tfstate" ]]; then
        current=$(cat .terraform/terraform.tfstate 2>/dev/null | grep -o '"key": "[^"]*"' | cut -d'"' -f4 || echo "unknown")
        echo "Current: $current"
    fi
    exit 1
fi

PROJECT="$1"
ENV="$2"
STATE_KEY="${PROJECT}/${ENV}/terraform.tfstate"

echo "Switching to: ${PROJECT}-${ENV}"
echo "State: s3://tf-state-meteor/${STATE_KEY}"
echo ""

# Clear cache if switching
rm -rf .terraform .terraform.lock.hcl 2>/dev/null || true

# Init with new backend
terraform init -backend-config="key=${STATE_KEY}" -reconfigure

echo ""
echo "Done. Make sure your terraform.tfvars has:"
echo "  project_name = \"${PROJECT}\""
echo "  environment  = \"${ENV}\""
