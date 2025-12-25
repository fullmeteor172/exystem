################################################################################
# Terraform Backend Configuration
#
# For multi-cluster support, the S3 key is dynamically set during init.
# Use the switch.sh script or specify backend config manually:
#
#   terraform init -backend-config="key=myproject/staging/terraform.tfstate"
################################################################################

terraform {
  backend "s3" {
    bucket         = "tf-state-meteor"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true

    # Key is set dynamically via -backend-config during init
    # Default key for backward compatibility:
    key = "exystem/dev/terraform.tfstate"
  }
}
