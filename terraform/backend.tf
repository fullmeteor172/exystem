terraform {
  backend "s3" {
    bucket         = "tf-state-meteor"
    key            = "meteor/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true

    # Role assumption is handled by AWS profile configuration
    # Ensure AWS_PROFILE is set to 'morpheus' which assumes terraform-admin role
  }
}
