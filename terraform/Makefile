.PHONY: help setup init plan apply destroy validate format clean kubeconfig verify output summary

# Variables - override these for different clusters
AWS_PROFILE ?= morpheus
AWS_REGION ?= us-west-2
PROJECT_NAME ?= exystem
ENVIRONMENT ?= dev
CLUSTER_NAME = $(PROJECT_NAME)-$(ENVIRONMENT)

help: ## Show this help message
	@echo 'EKS Provisioning Tool'
	@echo ''
	@echo 'Usage: make [target] [PROJECT_NAME=xxx] [ENVIRONMENT=yyy]'
	@echo ''
	@echo 'Examples:'
	@echo '  make setup PROJECT_NAME=myapp ENVIRONMENT=prod'
	@echo '  make apply'
	@echo '  make summary'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Initialize a new cluster (interactive or with PROJECT_NAME/ENVIRONMENT)
	@./setup.sh $(PROJECT_NAME) $(ENVIRONMENT)

init: ## Initialize Terraform (use 'make setup' for new clusters)
	AWS_PROFILE=$(AWS_PROFILE) terraform init

plan: ## Run Terraform plan
	@AWS_PROFILE=$(AWS_PROFILE) terraform plan

apply: ## Apply Terraform configuration
	@AWS_PROFILE=$(AWS_PROFILE) terraform apply

destroy: ## Destroy resources (use cleanup.sh for full cleanup)
	@echo "For full cleanup including orphaned resources, use:"
	@echo "  PROJECT_NAME=$(PROJECT_NAME) ENVIRONMENT=$(ENVIRONMENT) ./cleanup.sh"
	@echo ""
	@read -p "Continue with terraform destroy? (y/n): " confirm && \
	if [ "$$confirm" = "y" ]; then \
		AWS_PROFILE=$(AWS_PROFILE) terraform destroy; \
	fi

validate: ## Validate Terraform configuration
	@terraform validate

format: ## Format Terraform files
	@terraform fmt -recursive

clean: ## Clean Terraform cache (for switching clusters)
	rm -rf .terraform .terraform.lock.hcl terraform.tfstate.backup

kubeconfig: ## Configure kubectl for the cluster
	@echo "Configuring kubectl for $(CLUSTER_NAME)..."
	@eval $$(AWS_PROFILE=$(AWS_PROFILE) terraform output -raw configure_kubectl 2>/dev/null) && \
	echo "Done! Test with: kubectl get nodes" || \
	echo "Error: Cluster may not be deployed yet"

verify: ## Verify cluster health
	@echo "=== Cluster: $(CLUSTER_NAME) ==="
	@echo ""
	@echo "=== Nodes ==="
	@kubectl get nodes -o wide 2>/dev/null || echo "Cannot connect to cluster"
	@echo ""
	@echo "=== System Pods ==="
	@kubectl get pods -n kube-system --field-selector=status.phase!=Running 2>/dev/null | head -20 || true
	@echo ""
	@echo "=== Karpenter ==="
	@kubectl get nodepools,ec2nodeclasses 2>/dev/null || echo "Karpenter CRDs not found"
	@echo ""
	@echo "=== Pending Pods ==="
	@kubectl get pods -A --field-selector=status.phase=Pending 2>/dev/null | head -10 || true

output: ## Show Terraform outputs
	@AWS_PROFILE=$(AWS_PROFILE) terraform output

summary: ## Show resource summary (what will be created)
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  Resource Summary for: $(CLUSTER_NAME)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@AWS_PROFILE=$(AWS_PROFILE) terraform plan -out=.tfplan -input=false 2>/dev/null && \
	terraform show -json .tfplan 2>/dev/null | jq -r '
		.resource_changes // [] |
		group_by(.type) |
		map({
			type: .[0].type,
			add: [.[] | select(.change.actions | contains(["create"]))] | length,
			change: [.[] | select(.change.actions | contains(["update"]))] | length,
			destroy: [.[] | select(.change.actions | contains(["delete"]))] | length
		}) |
		sort_by(.type) |
		.[] |
		select(.add > 0 or .change > 0 or .destroy > 0) |
		"  \(.type): +\(.add) ~\(.change) -\(.destroy)"
	' && \
	rm -f .tfplan || \
	echo "  Run 'terraform init' first"
	@echo ""

grafana-password: ## Get Grafana admin password
	@AWS_PROFILE=$(AWS_PROFILE) terraform output -raw grafana_admin_password 2>/dev/null || echo "Observability not enabled"

rds-password: ## Get RDS password from Secrets Manager
	@secret_arn=$$(AWS_PROFILE=$(AWS_PROFILE) terraform output -raw rds_password_secret_arn 2>/dev/null) && \
	AWS_PROFILE=$(AWS_PROFILE) aws secretsmanager get-secret-value \
		--secret-id $$secret_arn \
		--region $(AWS_REGION) \
		--query SecretString \
		--output text | jq -r .password || echo "RDS not enabled"

upgrade: ## Upgrade Terraform providers
	AWS_PROFILE=$(AWS_PROFILE) terraform init -upgrade

list-clusters: ## List all provisioned clusters
	@echo "Provisioned clusters in s3://$(TF_STATE_BUCKET):"
	@echo ""
	@AWS_PROFILE=$(AWS_PROFILE) aws s3 ls s3://tf-state-meteor/ --region $(AWS_REGION) 2>/dev/null | \
		grep "PRE" | awk '{print "  " $$2}' | sed 's|/||g' || \
		echo "  No clusters found"
