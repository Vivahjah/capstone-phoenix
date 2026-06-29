terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote backend - we'll set this up soon
  backend "s3" {
    bucket         = "capstone-phoenix-tfstat-0775" # ← your bucket name
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "capstone-phoenix-tfstate-0775-lock" # ← your table name
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}