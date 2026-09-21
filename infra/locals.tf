locals {
  key_name = var.key_name

  tag_header = (var.owner != "" && var.env_type != "") ? "${var.owner}-${var.env_type}-" : (
    (var.owner != "") ? "${var.owner}-" : ""
  )

  vpc_id             = data.aws_vpc.vpc.id
  ami_id             = data.aws_ami.al2023.id
  security_group_ids = data.aws_security_groups.security_groups.ids
  subnet_ids         = data.aws_subnets.target_subnets.ids

  ec2_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}
