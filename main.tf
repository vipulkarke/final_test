provider "aws" {

  region = "us-east-1"

}

resource "aws_vpc" "karke_main_vpc" {

  cidr_block = "10.0.0.0/16"

}

resource "aws_internet_gateway" "karke_main_igw" {

  vpc_id = aws_vpc.karke_main_vpc.id

}

resource "aws_subnet" "karke_private_subnet_1a" {

  vpc_id            = aws_vpc.karke_main_vpc.id

  cidr_block        = "10.0.1.0/24"

  availability_zone = "us-east-1a"

}

resource "aws_subnet" "karke_private_subnet_1b" {

  vpc_id            = aws_vpc.karke_main_vpc.id

  cidr_block        = "10.0.2.0/24"

  availability_zone = "us-east-1b"

}

resource "aws_subnet" "karke_public_subnet_1a" {

  vpc_id                  = aws_vpc.karke_main_vpc.id

  cidr_block              = "10.0.3.0/24"

  availability_zone       = "us-east-1a"

  map_public_ip_on_launch = true

}

resource "aws_eip" "karke_nat_eip" {

}

resource "aws_route_table" "karke_public_rt" {

  vpc_id = aws_vpc.karke_main_vpc.id

}

resource "aws_route" "karke_public_internet_route" {

  route_table_id         = aws_route_table.karke_public_rt.id

  destination_cidr_block = "0.0.0.0/0"

  gateway_id             = aws_internet_gateway.karke_main_igw.id

}

resource "aws_route_table_association" "karke_public_rta" {

  subnet_id      = aws_subnet.karke_public_subnet_1a.id

  route_table_id = aws_route_table.karke_public_rt.id

}

resource "aws_nat_gateway" "karke_nat_gateway" {

  allocation_id = aws_eip.karke_nat_eip.id

  subnet_id     = aws_subnet.karke_public_subnet_1a.id

}

resource "aws_route_table" "karke_private_rt" {

  vpc_id = aws_vpc.karke_main_vpc.id

}

resource "aws_route" "karke_private_internet_route" {

  route_table_id         = aws_route_table.karke_private_rt.id

  destination_cidr_block = "0.0.0.0/0"

  nat_gateway_id         = aws_nat_gateway.karke_nat_gateway.id

}

resource "aws_route_table_association" "karke_private_rta_1" {

  subnet_id      = aws_subnet.karke_private_subnet_1a.id

  route_table_id = aws_route_table.karke_private_rt.id

}

resource "aws_route_table_association" "karke_private_rta_2" {

  subnet_id      = aws_subnet.karke_private_subnet_1b.id

  route_table_id = aws_route_table.karke_private_rt.id

}

resource "aws_security_group" "karke_ecs_sg" {

  vpc_id = aws_vpc.karke_main_vpc.id

  ingress {

    from_port   = 80

    to_port     = 80

    protocol    = "tcp"

    cidr_blocks = ["0.0.0.0/0"]

  }

  egress {

    from_port   = 0

    to_port     = 0

    protocol    = "-1"

    cidr_blocks = ["0.0.0.0/0"]

  }

}

resource "aws_ecs_cluster" "karke_ecs_cluster" {

  name = "karke-flask-ecs-cluster"

}

resource "aws_ecr_repository" "karke_flask_ecr" {

  name                 = "flask-app-repo-karke"

  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {

    scan_on_push = true

  }

  tags = {

    Environment = "Production"

  }

}

resource "aws_ecs_task_definition" "karke_ecs_task" {

  family                   = "karke-flask-app-task"

  network_mode             = "awsvpc"

  requires_compatibilities = ["FARGATE"]

  cpu                      = "256"

  memory                   = "512"

  execution_role_arn       = aws_iam_role.karke_ecs_exec_role.arn

  task_role_arn            = aws_iam_role.karke_ecs_exec_role.arn

  container_definitions = <<DEFINITION

[{

  "name": "karke-flask-container",

  "image": "${aws_ecr_repository.karke_flask_ecr.repository_url}:latest",

  "essential": true,

  "portMappings": [{

    "containerPort": 80,

    "hostPort": 80

  }]

}]

DEFINITION

}

resource "aws_iam_role" "karke_ecs_exec_role" {

  name = "karke-ecs-execution-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {

        Action    = "sts:AssumeRole"

        Effect    = "Allow"

        Principal = {

          Service = "ecs-tasks.amazonaws.com"

        }

      }

    ]

  })

}

resource "aws_iam_role_policy_attachment" "karke_ecs_exec_role_policy" {

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"

  role       = aws_iam_role.karke_ecs_exec_role.name

}

resource "aws_ecs_service" "karke_ecs_service" {

  name            = "karke-ecs-service"

  cluster         = aws_ecs_cluster.karke_ecs_cluster.id

  task_definition = aws_ecs_task_definition.karke_ecs_task.arn

  desired_count   = 2

  launch_type     = "FARGATE"

  network_configuration {

    subnets         = [aws_subnet.karke_private_subnet_1a.id, aws_subnet.karke_private_subnet_1b.id]

    security_groups = [aws_security_group.karke_ecs_sg.id]

    assign_public_ip = false

  }

  load_balancer {

    target_group_arn = aws_lb_target_group.karke_target_group.arn

    container_name   = "karke-flask-container"

    container_port   = 80

  }

}

resource "aws_lb" "karke_alb" {

  name               = "karke-alb"

  internal           = false

  load_balancer_type = "application"

  security_groups    = [aws_security_group.karke_ecs_sg.id]

  subnets            = [aws_subnet.karke_private_subnet_1a.id, aws_subnet.karke_private_subnet_1b.id]

}

resource "aws_lb_listener" "karke_alb_listener" {

  load_balancer_arn = aws_lb.karke_alb.arn

  port              = 80

  protocol          = "HTTP"

  default_action {

    type             = "forward"

    target_group_arn = aws_lb_target_group.karke_target_group.arn

  }

}

resource "aws_lb_target_group" "karke_target_group" {

  name       = "karke-target-group"

  port       = 80

  protocol   = "HTTP"

  vpc_id     = aws_vpc.karke_main_vpc.id

  target_type = "ip"

}

resource "aws_appautoscaling_target" "karke_scaling_target" {

  max_capacity       = 5

  min_capacity       = 2

  resource_id        = "service/${aws_ecs_cluster.karke_ecs_cluster.name}/${aws_ecs_service.karke_ecs_service.name}"

  scalable_dimension = "ecs:service:DesiredCount"

  service_namespace  = "ecs"

}

resource "aws_appautoscaling_policy" "karke_scaling_policy" {

  name               = "karke-scaling-policy"

  policy_type        = "TargetTrackingScaling"

  resource_id        = aws_appautoscaling_target.karke_scaling_target.resource_id

  scalable_dimension = aws_appautoscaling_target.karke_scaling_target.scalable_dimension

  service_namespace  = aws_appautoscaling_target.karke_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {

    target_value       = 50.0

    predefined_metric_specification {

      predefined_metric_type = "ECSServiceAverageCPUUtilization"

    }

    scale_in_cooldown  = 300

    scale_out_cooldown = 300

  }

} 