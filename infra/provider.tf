terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.0"
    }
  }
}
provider "aws" {
  region = "ap-southeast-2"

  default_tags {
    tags = { Class = "bipa17" }
  }
}
