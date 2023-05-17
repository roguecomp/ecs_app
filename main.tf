provider "aws" {
  region = var.region
}

terraform {
  cloud {
    organization = "vishnukap_learning"

    workspaces {
      name = "ECS_workflow"
    }
  }
}

locals {
  app_name = "${var.tag}-${var.app}"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.3"

  name = "${local.app_name}-vpc"
  cidr = "10.0.0.0/19"

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.3.0/24", "10.0.4.0/24", "10.0.5.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  private_subnet_tags = {
    Name = "${var.tag}-private"
  }

  public_subnet_tags = {
    Name = "${var.tag}-public"
  }

  tags = {
    Environment = var.tag
  }

}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Name"
    values = ["${var.tag}-public"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Name"
    values = ["${var.tag}-private"]
  }
}

resource "aws_security_group" "lb-sg" {
  name        = "${local.app_name}-lb-sg"
  description = "Allow flask traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "TLS from VPC"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = var.port
    to_port          = var.port
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Environment = var.tag
  }
}

resource "aws_security_group" "sg" {
  name        = "${local.app_name}-sg"
  description = "Allow flask traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "TLS from VPC"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = var.port
    to_port          = var.port
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "To allow ECR repository image download"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Environment = var.tag
  }
}

resource "aws_lb" "public" {
  name_prefix        = var.tag
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb-sg.id]
  subnets            = data.aws_subnets.public.ids
  tags = {
    Environment = var.tag
  }

  depends_on = [
    data.aws_subnets.public,
    data.aws_subnets.private
  ]
}

resource "aws_lb_listener" "public_listener" {
  load_balancer_arn = aws_lb.public.arn
  port              = var.port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group_public.arn
  }

  tags = {
    Environment = var.tag
  }
}

resource "aws_lb_target_group" "target_group_public" {
  name_prefix = var.tag
  port        = var.port
  protocol    = "HTTP"
  target_type = "ip"

  vpc_id = module.vpc.vpc_id

  tags = {
    Environment = var.tag
  }
}

data "aws_caller_identity" "current" {}

resource "random_string" "rand4" {
  length  = 4
  special = false
  upper   = false
}

resource "aws_cloudwatch_log_group" "logs" {
  name = "${local.app_name}-cloudwatch-log-group"

  tags = {
    Environment = var.tag
  }
}

resource "aws_iam_role" "ECSTaskExecutionRole" {
  name_prefix = local.app_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Environment = var.tag
  }
}

resource "aws_iam_policy" "ECSTaskPolicy" {

  name        = "ECSTaskPolicy"
  path        = "/"
  description = "Permissions used by ECS tasks"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "ecr:GetAuthorizationToken",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutRetentionPolicy",
          "logs:CreateLogGroup"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ECSRolePolicyAttachment" {
  role       = aws_iam_role.ECSTaskExecutionRole.name
  policy_arn = aws_iam_policy.ECSTaskPolicy.arn
}

resource "aws_ecs_cluster" "ecs_fargate" {
  name = "${local.app_name}-${random_string.rand4.result}"
}

resource "aws_ecs_cluster_capacity_providers" "app" {
  cluster_name = aws_ecs_cluster.ecs_fargate.name

  capacity_providers = ["FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
  }
}

data "aws_ecr_repository" "app" {
  name = local.app_name
}

resource "aws_ecs_task_definition" "ecs_task" {
  family                   = "${local.app_name}_server"
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ECSTaskExecutionRole.arn


  container_definitions = jsonencode(
    [
      {
        "cpu" : var.container_cpu,
        "image" : data.aws_ecr_repository.app.repository_url,
        "memory" : var.container_memory,
        "name" : local.app_name
        "portMappings" : [
          {
            "containerPort" : var.port,
            "hostPort" : var.port
          }
        ]
        "environment" : [
          {
            "name" : "FLASK_APP",
            "value" : "main"
          },
          {
            "name" : "FLASK_ENV",
            "value" : "development"
          }
        ]
        "logConfiguration" : {
          "logDriver" : "awslogs",
          "options" : {
            "awslogs-group" : aws_cloudwatch_log_group.logs.name,
            "awslogs-region" : var.region,
            "awslogs-stream-prefix" : "ecs"
          }
        }
      }
  ])
}

resource "aws_ecs_service" "ecs_service" {
  depends_on                         = [aws_lb.public]
  name                               = "${local.app_name}-${random_string.rand4.result}"
  cluster                            = aws_ecs_cluster.ecs_fargate.id
  launch_type                        = "FARGATE"
  deployment_maximum_percent         = "200"
  deployment_minimum_healthy_percent = "75"
  desired_count                      = var.desired_count

  force_new_deployment = true

  network_configuration {
    subnets         = data.aws_subnets.private.ids
    security_groups = [aws_security_group.sg.id]
  }
  # Track the latest ACTIVE revision
  task_definition = "${aws_ecs_task_definition.ecs_task.family}:${max(aws_ecs_task_definition.ecs_task.revision, aws_ecs_task_definition.ecs_task.revision)}"

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group_public.arn
    container_name   = local.app_name
    container_port   = var.port
  }
}

# resource "aws_route53_zone" "dns" {
#   name = "visham.org"
# }

resource "aws_route53_record" "www" {
  zone_id = "Z02024842F73WIP3EA0PB"
  name    = var.url
  type    = "A"

  alias {
    name                   = aws_lb.public.dns_name
    zone_id                = aws_lb.public.zone_id
    evaluate_target_health = true
  }
}