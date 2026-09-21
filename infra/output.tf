output "information" {
  value = [
    local.vpc_id,
    data.aws_security_groups.security_groups.ids
    # data.aws_security_group.external_alb_sg.id,
    # data.aws_security_group.ssh_sg.id
  ]
}
