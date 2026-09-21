data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = ["${local.tag_header}vpc"]
  }
}

data "aws_subnets" "target_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }
  filter {
    name   = "tag:Type"
    values = ["private"]
  }
}

# Amazon Linux 2023 최신 AMI 조회
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

data "aws_security_groups" "security_groups" {
  filter {
    name = "tag:Name"
    values = [
      "${local.tag_header}external-alb-sg",
      "${local.tag_header}ssh-sg"
    ]
  }
}

# data "aws_security_group" "external_alb_sg" {
#   filter {
#     name   = "tag:Name"
#     values = ["${local.tag_header}external-alb-sg"]
#   }
# }
# data "aws_security_group" "ssh_sg" {
#   filter {
#     name   = "tag:Name"
#     values = ["${local.tag_header}ssh-sg"]
#   }
# }
