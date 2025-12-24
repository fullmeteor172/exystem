# Just wrappers - you can use terraform commands directly
# AWS_PROFILE=morpheus is set by default

AWS_PROFILE ?= morpheus

plan:
	AWS_PROFILE=$(AWS_PROFILE) terraform plan

apply:
	AWS_PROFILE=$(AWS_PROFILE) terraform apply

destroy:
	AWS_PROFILE=$(AWS_PROFILE) terraform destroy

kubeconfig:
	@eval $$(AWS_PROFILE=$(AWS_PROFILE) terraform output -raw configure_kubectl)
	@echo "Done. Run: kubectl get nodes"

output:
	AWS_PROFILE=$(AWS_PROFILE) terraform output
