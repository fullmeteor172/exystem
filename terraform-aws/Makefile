.PHONY: help init plan apply destroy output kubeconfig clean fmt validate

# Default AWS profile
AWS_PROFILE ?= default

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform
	AWS_PROFILE=$(AWS_PROFILE) terraform init

plan: ## Run terraform plan
	AWS_PROFILE=$(AWS_PROFILE) terraform plan

apply: ## Run terraform apply
	AWS_PROFILE=$(AWS_PROFILE) terraform apply

destroy: ## Run terraform destroy
	AWS_PROFILE=$(AWS_PROFILE) terraform destroy

output: ## Show all outputs
	AWS_PROFILE=$(AWS_PROFILE) terraform output

kubeconfig: ## Configure kubectl for the cluster
	@eval $$(AWS_PROFILE=$(AWS_PROFILE) terraform output -raw configure_kubectl)

clean: ## Clean Terraform cache
	rm -rf .terraform .terraform.lock.hcl

fmt: ## Format Terraform files
	terraform fmt -recursive

validate: ## Validate Terraform configuration
	terraform validate
