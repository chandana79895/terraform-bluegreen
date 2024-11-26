provider "aws" {
  region = "us-east-1"  # Adjust region if necessary
}

# VPC Configuration
data "aws_vpc" "selected" {
  id = "vpc-084570e9d3d7c0f8d"  # Use your existing VPC ID
}

# Subnet Configuration (Two subnets in different AZs)
data "aws_subnet" "subnet_a" {
  vpc_id             = data.aws_vpc.selected.id
  availability_zone  = "us-east-1"
  cidr_block         = "10.0.16.0/20"  # Adjust with your VPC's available CIDR
}

data "aws_subnet" "subnet_b" {
  vpc_id             = data.aws_vpc.selected.id
  availability_zone  = "us-east-1a"
  cidr_block         = "10.0.0.0/20"  # Adjust with your VPC's available CIDR
}

# Security Group for EC2 instances
resource "aws_security_group" "web_sg" {
  name_prefix = "web_sg"
  description = "Allow HTTP and SSH traffic"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTP from anywhere
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH from anywhere
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Elastic Load Balancer (ALB)
resource "aws_lb" "web_lb" {
  name               = "web-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [data.aws_subnet.subnet_a.id, data.aws_subnet.subnet_b.id]  # Two subnets in different AZs
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

# Target Groups
resource "aws_lb_target_group" "blue_target_group" {
  name        = "blue-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.selected.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "green_target_group" {
  name        = "green-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.selected.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# Launch Configuration
resource "aws_launch_configuration" "web_config" {
  name          = "web-launch-config-${replace(timestamp(), ":", "")}"
  image_id      = "ami-0866a3c8686eaeeba"  # Replace with your AMI
  instance_type = "t2.micro"
  key_name      = "Fortress-Automation-check"  # Replace with your key pair name
  security_groups = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt upgrade -y
              sudo apt install -y apache2
              echo "Hello from Apache Web Server - Blue-Green Deployment" | sudo tee /var/www/html/index.html
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

# Blue ASG (Start with 1 instance running in Blue)
resource "aws_autoscaling_group" "blue_asg" {
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  vpc_zone_identifier  = [data.aws_subnet.subnet_a.id, data.aws_subnet.subnet_b.id]
  launch_configuration = aws_launch_configuration.web_config.id

  target_group_arns = [aws_lb_target_group.blue_target_group.arn]

  health_check_type          = "ELB"
  health_check_grace_period = 300
}

# Green ASG (Initially set to 0 instances)
resource "aws_autoscaling_group" "green_asg" {
  desired_capacity     = 0
  max_size             = 1
  min_size             = 0
  vpc_zone_identifier  = [data.aws_subnet.subnet_a.id, data.aws_subnet.subnet_b.id]
  launch_configuration = aws_launch_configuration.web_config.id

  target_group_arns = [aws_lb_target_group.green_target_group.arn]

  health_check_type          = "ELB"
  health_check_grace_period = 300
}

# Step Scaling Policy to scale Green ASG once Blue is healthy
resource "aws_autoscaling_policy" "scale_green_up" {
  name                   = "scale-green-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name  = aws_autoscaling_group.green_asg.name
}

# Traffic shift: gradually forward traffic to Green once it’s healthy
resource "aws_lb_listener_rule" "traffic_shift_rule" {
  listener_arn = aws_lb_listener.web_listener.arn

  condition {
    field  = "path-pattern"
    values = ["/"]  # Match all paths (or adjust as necessary)
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green_target_group.arn
  }

  priority = 1
}

# Outputs
output "load_balancer_dns" {
  value = aws_lb.web_lb.dns_name
}
