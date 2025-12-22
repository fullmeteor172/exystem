terraform {
  backend "s3" {
    bucket         = "tf-state-meteor"
    key            = "meteor/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true

    # Assuming role for terraform operations
    role_arn = "arn:aws:iam::143495498599:role/terraform-admin"
  }
}
