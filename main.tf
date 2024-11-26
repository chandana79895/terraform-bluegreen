provider "aws" {
  region = "us-east-1"
}

# VPC Configuration
data "aws_vpc" "selected" {
  id = "vpc-084570e9d3d7c0f8d" # Replace with your VPC ID
}

data "aws_subnet" "subnet_a" {
  vpc_id             = data.aws_vpc.selected.id
  availability_zone  = "us-east-1a"
  cidr_block         = "10.0.0.0/20"  # Adjust with your VPC's available CIDR
}

data "aws_subnet" "subnet_b" {
  vpc_id             = data.aws_vpc.selected.id
  availability_zone  = "us-east-1b"
  cidr_block         = "10.0.16.0/20"  # Adjust with your VPC's available CIDR
}

# Security Group
resource "aws_security_group" "web_sg" {
  name        = "web-sg-name1"
  description = "Allow HTTP and SSH traffic"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

# Application Load Balancer (ALB)
resource "aws_lb" "web_lb" {
  name               = "web-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [
    data.aws_subnet.subnet_a.id,
    data.aws_subnet.subnet_b.id
  ]  # Include both subnets in different AZs
}

# Target Groups
resource "aws_lb_target_group" "blue_target_group" {
  name     = "blue-target-group-1"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.selected.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "green_target_group" {
  name     = "green-target-group-2"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.selected.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# ALB Listener
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_target_group.arn
  }
}

# Launch Configurations
resource "aws_launch_configuration" "blue_launch_config" {
  name          = "blue-launch-config-${replace(timestamp(), ":", "-")}"
  image_id      = "ami-0866a3c8686eaeeba" # Replace with your AMI
  instance_type = "t2.micro"
  key_name      = "Fortress-Automation-check" # Replace with your key pair
  security_groups = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y apache2
              echo "Hello from Blue Deployment" | sudo tee /var/www/html/index.html
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_configuration" "green_launch_config" {
  name          = "green-launch-config-${replace(timestamp(), ":", "-")}"
  image_id      = "ami-0866a3c8686eaeeba" # Replace with your AMI
  instance_type = "t2.micro"
  key_name      = "Fortress-Automation-check" # Replace with your key pair
  security_groups = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y apache2
              echo "Hello from Green Deployment" | sudo tee /var/www/html/index.html
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Groups
resource "aws_autoscaling_group" "blue_asg" {
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  vpc_zone_identifier  = [
    data.aws_subnet.subnet_a.id,
    data.aws_subnet.subnet_b.id
  ]
  launch_configuration = aws_launch_configuration.blue_launch_config.id

  target_group_arns = [aws_lb_target_group.blue_target_group.arn]

  health_check_type          = "ELB"
  health_check_grace_period = 300
}

resource "aws_autoscaling_group" "green_asg" {
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  vpc_zone_identifier  = [
    data.aws_subnet.subnet_a.id,
    data.aws_subnet.subnet_b.id
  ]
  launch_configuration = aws_launch_configuration.green_launch_config.id

  target_group_arns = [aws_lb_target_group.green_target_group.arn]

  health_check_type          = "ELB"
  health_check_grace_period = 300
}

# ALB Listener Rules for Blue-Green Switching
resource "aws_lb_listener_rule" "switch_to_green" {
  listener_arn = aws_lb_listener.web_listener.arn
  priority     = 100

  condition {
    host_header {
      values = ["green.example.com"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green_target_group.arn
  }
}

resource "aws_lb_listener_rule" "switch_to_blue" {
  listener_arn = aws_lb_listener.web_listener.arn
  priority     = 200

  condition {
    host_header {
      values = ["blue.example.com"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_target_group.arn
  }
}

# Outputs
output "load_balancer_dns" {
  value = aws_lb.web_lb.dns_name
}