#!/bin/bash
# 변수 설정
REGION="ap-southeast-2"
ECR_REPOSITORY="nginx"
CONTAINER_NAME="nginx-app"
PORJECT_DIR=

# 권한 획득
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
# ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPOSITORY:latest"

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# 이미지(Docker) Pull
# docker pull $ECR_URI
docker compose pull

# 컨테이너 배포
# docker stop $CONTAINER_NAME 2>/dev/null || true
# docker rm $CONTAINER_NAME 2>/dev/null || true
# docker run -d --name $CONTAINER_NAME -p 80:80 --restart always $ECR_URI
docker compose up -d --build

# 사용하지 않는 이미지 정리(디스크 용량 확보 차원)
docker image prune -f