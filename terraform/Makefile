.PHONY: help init plan apply destroy validate format clean kubeconfig

# Variables
AWS_PROFILE ?= morpheus-terraform-admin
CLUSTER_NAME ?= exystem-dev

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize Terraform
	@echo "Initializing Terraform..."
	AWS_PROFILE=$(AWS_PROFILE) terraform init

plan: ## Run Terraform plan
	@echo "Running Terraform plan..."
	AWS_PROFILE=$(AWS_PROFILE) terraform plan

apply: ## Apply Terraform configuration
	@echo "Applying Terraform configuration..."
	AWS_PROFILE=$(AWS_PROFILE) terraform apply

destroy: ## Destroy all resources (DANGEROUS!)
	@echo "WARNING: This will destroy all resources!"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
	AWS_PROFILE=$(AWS_PROFILE) terraform destroy

validate: ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	terraform validate

format: ## Format Terraform files
	@echo "Formatting Terraform files..."
	terraform fmt -recursive

clean: ## Clean Terraform cache and temporary files
	@echo "Cleaning Terraform cache..."
	rm -rf .terraform
	rm -f .terraform.lock.hcl
	rm -f terraform.tfstate.backup

kubeconfig: ## Configure kubectl for the EKS cluster
	@echo "Configuring kubectl..."
	AWS_PROFILE=$(AWS_PROFILE) aws eks update-kubeconfig \
		--region us-west-2 \
		--name $(CLUSTER_NAME) \
		--role-arn arn:aws:iam::143495498599:role/terraform-admin \
		--alias $(CLUSTER_NAME)
	@echo "kubectl configured! Test with: kubectl get nodes"

verify: ## Verify cluster is healthy
	@echo "Checking cluster health..."
	@kubectl get nodes
	@echo ""
	@kubectl get pods -A
	@echo ""
	@echo "Checking Karpenter..."
	@kubectl get pods -n karpenter
	@echo ""
	@echo "Checking Traefik..."
	@kubectl get pods -n traefik

output: ## Show Terraform outputs
	@AWS_PROFILE=$(AWS_PROFILE) terraform output

output-json: ## Show Terraform outputs in JSON format
	@AWS_PROFILE=$(AWS_PROFILE) terraform output -json

get-grafana-password: ## Get Grafana admin password
	@AWS_PROFILE=$(AWS_PROFILE) terraform output -raw grafana_admin_password 2>/dev/null || echo "Observability not enabled"

get-rds-password: ## Get RDS password from Secrets Manager
	@secret_arn=$$(AWS_PROFILE=$(AWS_PROFILE) terraform output -raw rds_password_secret_arn 2>/dev/null) && \
	AWS_PROFILE=$(AWS_PROFILE) aws secretsmanager get-secret-value \
		--secret-id $$secret_arn \
		--query SecretString \
		--output text | jq -r .password || echo "RDS not enabled"

upgrade: ## Upgrade Terraform providers
	@echo "Upgrading Terraform providers..."
	AWS_PROFILE=$(AWS_PROFILE) terraform init -upgrade
