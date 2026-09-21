# ======================================================================
# IAM Roles (인스턴스에 부여할 역할)
# ======================================================================
resource "aws_iam_role" "asg_node_role" {
  name = "${local.tag_header}AmazonASGNodeEC2-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole" # 신뢰관계 허용(임시권한)
    }]
  })
}
resource "aws_iam_role_policy_attachment" "asg_node_policies" {
  for_each   = toset(local.ec2_policy_arns)
  role       = aws_iam_role.asg_node_role.name
  policy_arn = each.value
}

# ======================================================================
# Instance Profile
# ======================================================================
resource "aws_iam_instance_profile" "asg_node_profile" {
  name = "${local.tag_header}ASGNodeEC2Instance-profile"
  role = aws_iam_role.asg_node_role.name
}
resource "aws_iam_role" "codedeploy_role" {
  name = "${local.tag_header}AmazonCodeDeployService-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "codedeploy_policy" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# ======================================================================
# CodePipeline 서비스 IAM Role
# ======================================================================
resource "aws_iam_role" "codepipeline_role" {
  name = "${local.tag_header}AmazonCodePipelineService-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# CodePipeline 실행 권한 (S3, CodeBuild, CodeDeploy 액세스)
resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${local.tag_header}CodePipelineServicePolicy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObjectAcl",
          "s3:PutObject"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision"
        ]
        Resource = "*"
      }
    ]
  })
}

# ======================================================================
# Pipeline Artifacts 저장용 S3 Bucket
# ======================================================================
resource "random_id" "bucket_suffix" {
  byte_length = 4
}
resource "aws_s3_bucket" "pipeline_bucket" {
  bucket        = "${local.tag_header}pipeline-artifacts-${random_id.bucket_suffix.hex}"
  force_destroy = true
  tags = {
    Name = "${local.tag_header}pipeline-artifacts-${random_id.bucket_suffix.hex}"
  }
}
# 생성된 버킷의 버전관리 활성화 (CodePipeline에서 필수 요구사항)
resource "aws_s3_bucket_versioning" "pipeline_bucket_versioning" {
  bucket = aws_s3_bucket.pipeline_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
# 퍼블릭 액세스 전체 차단 (보안 규정 준수)
resource "aws_s3_bucket_public_access_block" "pipeline_bucket_public_access" {
  bucket                  = aws_s3_bucket.pipeline_bucket.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
# 서버 측 기본 암호화 설정
resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_bucket_encryption" {
  bucket = aws_s3_bucket.pipeline_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3
    }
  }
}

# ======================================================================
# Launch Template & UserData
# ======================================================================
resource "aws_launch_template" "asg_lt" {
  name_prefix            = "${local.tag_header}launch-template-"
  image_id               = local.ami_id
  instance_type          = "t3.micro"
  key_name               = local.key_name
  vpc_security_group_ids = local.security_group_ids
  # vpc_security_group_ids = [data.aws_security_group.external_alb_sg.id,data.aws_security_group.ssh_sg.id]

  # 기본 버전 지정 방법 --------------------------------------
  update_default_version = var.default_version == "latest" ? true : false
  default_version        = var.default_version != "latest" ? tostring(var.default_version) : null
  # ---------------------------------------------------------
  iam_instance_profile {
    name = aws_iam_instance_profile.asg_node_profile.name
  }

  # Docker 및 CodeDeploy Agent 자동 설치 스크립트 (base64 자동 인코딩)
  user_data = base64encode(<<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y ruby wget docker

              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user

              cd /tmp
              wget https://aws-codedeploy-ap-south-1.s3.ap-south-1.amazonaws.com/latest/install
              chmod +x ./install
              ./install auto

              systemctl start codedeploy-agent
              systemctl enable codedeploy-agent
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.tag_header}asg-node-instance"
    }
  }
}

# ======================================================================
# 3. Auto Scaling Group
# ======================================================================
resource "aws_autoscaling_group" "asg" {
  name                = "${local.tag_header}codedeploy-asg"
  min_size            = 1
  max_size            = 3
  desired_capacity    = 2
  vpc_zone_identifier = local.subnet_ids

  launch_template {
    id      = aws_launch_template.asg_lt.id
    version = "$Latest"
  }
}

# ======================================================================
# CodeDeploy Application & Deployment Group
# ======================================================================
# CodeDeploy Application 생성
resource "aws_codedeploy_app" "app" {
  name = "${local.tag_header}asg-codedeploy-app"
  # 배포 대상 정의: Server / Lambda / ECS
  compute_platform = "Server"
}

# CodeDeploy Deployment Group 생성 (ASG 연동)
resource "aws_codedeploy_deployment_group" "dg" {
  deployment_group_name = "${local.tag_header}asg-deployment-group"
  app_name              = aws_codedeploy_app.app.name
  service_role_arn      = aws_iam_role.codedeploy_role.arn

  # 배포 대상 정의
  autoscaling_groups = [aws_autoscaling_group.asg.name]

  # 배포 전략(구성) 지정
  # "CodeDeployDefault.AllAtOnce": 타겟 인스턴스 전체 동시에 한 번에 배포하는 방식
  #                                 ( 전체 중단 --> 동시 배포 --> 동시 재시작)
  # "OneAtATime": 한 대씩 순차 배포 ( 1대 배포 --> 검증 및 다음 배포 대상 선정 --> 순차 반복 )
  # "HalfAtATime": 대상 인스턴스의 50%를 먼저 배포 후 나머지 배포

  deployment_config_name = "CodeDeployDefault.AllAtOnce"
}

# =======================================================================
# 연결 리소스 생성 및 AWS CodePipeline 리소스 생성
# =======================================================================
# AWS - GitHub 간 CodeStar Connection 생성
resource "aws_codestarconnections_connection" "github" {
  name          = "${local.tag_header}github-connection"
  provider_type = "GitHub"
}

# AWS CodePipeline 생성
resource "aws_codepipeline" "codepipeline" {
  name     = "${local.tag_header}asg-cicd-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  # 소스코드 정보
  artifact_store {
    location = aws_s3_bucket.pipeline_bucket.bucket
    type     = "S3" # 아티팩트 저장소 유형 지정 (S3 사용)
  }

  # -----------------------------------------------------------------------
  # Stage 1: Source (GitHub / CodeStar Connection 기준)
  # -----------------------------------------------------------------------
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"                      # 액션 제공자(AWS에서 제공하는 서비스 활용)
      provider         = "CodeStarSourceConnection" # GitHub V2액션과 연동 표준인 "CodeStarSourceConnection" 사용
      version          = "1"
      output_artifacts = ["source_output"] # ZIP 소스 압축파일을 다음 스테이지로 전달할 전달용 아티팩트 이름선언

      # 연결객체의 ARN 및 GitHub Repository 정보 기재
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn # 본인 연결 ARN으로 수정
        FullRepositoryId = "yjunho/ex9-aws-codepipeline"                 # 본인 GitHub 레포지토리로 수정
        BranchName       = "main"
      }
    }
  }
  # -----------------------------------------------------------------------
  # Stage 2: Deploy (CodeDeploy ASG 배포)
  # -----------------------------------------------------------------------
  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy" # 배포에 사용할 AWS 서비스 지정 ("CodeDeploy")
      version         = "1"
      input_artifacts = ["source_output"] # stage1의 output_artifacts에 정의된 이름

      configuration = {
        ApplicationName     = aws_codedeploy_app.app.name # 배포 서비스 이름
        DeploymentGroupName = aws_codedeploy_deployment_group.dg.deployment_group_name
      }
    }
  }
}
