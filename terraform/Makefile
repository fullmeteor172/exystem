.PHONY: help init plan apply destroy validate format clean kubeconfig verify output

# Variables
AWS_PROFILE ?= morpheus
AWS_REGION ?= us-west-2
CLUSTER_NAME ?= exystem-dev

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize Terraform
	AWS_PROFILE=$(AWS_PROFILE) terraform init

plan: ## Run Terraform plan
	AWS_PROFILE=$(AWS_PROFILE) terraform plan

apply: ## Apply Terraform configuration
	AWS_PROFILE=$(AWS_PROFILE) terraform apply

destroy: ## Destroy all resources (use cleanup.sh for full cleanup)
	@echo "For full cleanup including orphaned resources, use: ./cleanup.sh"
	AWS_PROFILE=$(AWS_PROFILE) terraform destroy

validate: ## Validate Terraform configuration
	terraform validate

format: ## Format Terraform files
	terraform fmt -recursive

clean: ## Clean Terraform cache
	rm -rf .terraform .terraform.lock.hcl terraform.tfstate.backup

kubeconfig: ## Configure kubectl (run after apply)
	@echo "Configuring kubectl..."
	@eval $$(AWS_PROFILE=$(AWS_PROFILE) terraform output -raw configure_kubectl)
	@echo "Done! Test with: kubectl get nodes"

verify: ## Verify cluster health
	@echo "=== Nodes ==="
	@kubectl get nodes
	@echo ""
	@echo "=== Pods (all namespaces) ==="
	@kubectl get pods -A
	@echo ""
	@echo "=== Karpenter ==="
	@kubectl get nodepools,ec2nodeclasses -A 2>/dev/null || echo "Karpenter CRDs not found"

output: ## Show Terraform outputs
	@AWS_PROFILE=$(AWS_PROFILE) terraform output

grafana-password: ## Get Grafana admin password
	@AWS_PROFILE=$(AWS_PROFILE) terraform output -raw grafana_admin_password 2>/dev/null || echo "Observability not enabled or password not set"

rds-password: ## Get RDS password from Secrets Manager
	@secret_arn=$$(AWS_PROFILE=$(AWS_PROFILE) terraform output -raw rds_password_secret_arn 2>/dev/null) && \
	AWS_PROFILE=$(AWS_PROFILE) aws secretsmanager get-secret-value \
		--secret-id $$secret_arn \
		--region $(AWS_REGION) \
		--query SecretString \
		--output text | jq -r .password || echo "RDS not enabled"

upgrade: ## Upgrade Terraform providers
	AWS_PROFILE=$(AWS_PROFILE) terraform init -upgrade
