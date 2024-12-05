provider "aws" {
  region = "us-east-1"
}

# VPC Configuration
data "aws_vpc" "selected" {
  id = "vpc-084570e9d3d7c0f8d"
}

# Subnet Configuration
data "aws_subnet" "subnet_a" {
  vpc_id            = data.aws_vpc.selected.id
  availability_zone = "us-east-1b"
  cidr_block        = "10.0.16.0/20"
}

data "aws_subnet" "subnet_b" {
  vpc_id            = data.aws_vpc.selected.id
  availability_zone = "us-east-1a"
  cidr_block        = "10.0.0.0/20"
}

# Security Group Configuration
resource "aws_security_group" "web_sg" {
  name_prefix = "web_sg"
  description = "Allow HTTP traffic"
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

# Fetch latest Ubuntu AMI
data "aws_ami" "latest_ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical's AWS account ID
}


variable "environment" {
  description = "The environment to deploy (blue or green)"
  type        = string
}

# Launch Configuration for Blue Environment
resource "aws_launch_configuration" "blue_config" {
  name              = "blue-launch-configuration-${replace(timestamp(), ":", "")}"
  image_id          = data.aws_ami.latest_ubuntu.id
  instance_type     = "t2.micro"
  security_groups   = [aws_security_group.web_sg.id]
  key_name          = "Fortress-Automation-check"
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt upgrade -y
              sudo apt install -y apache2
              echo "Hello from Apache Web Server - Blue Environment" | sudo tee /var/www/html/index.html
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

# Launch Configuration for Green Environment
resource "aws_launch_configuration" "green_config" {
  name              = "green-launch-configuration-${replace(timestamp(), ":", "")}"
  image_id          = data.aws_ami.latest_ubuntu.id
  instance_type     = "t2.micro"
  security_groups   = [aws_security_group.web_sg.id]
  key_name          = "Fortress-Automation-check"
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt upgrade -y
              sudo apt install -y apache2
              echo "Hello from Apache Web Server - Green Environment" | sudo tee /var/www/html/index.html
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "green_asg" {
  desired_capacity     = 1
  max_size             = 2
  min_size             = 1
  vpc_zone_identifier  = [data.aws_subnet.subnet_a.id, data.aws_subnet.subnet_b.id]
  launch_configuration = aws_launch_configuration.green_config.id
  health_check_type          = "EC2"
  health_check_grace_period = 300
  force_delete               = true

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${var.environment}-web-instance"
    propagate_at_launch = true
  }
}

# Elastic Load Balancer
resource "aws_lb" "web_lb" {
  name               = "web-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [data.aws_subnet.subnet_a.id, data.aws_subnet.subnet_b.id]
}

# Load Balancer Listener
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      status_code = 200
      content_type = "text/plain"
      message_body = "OK"
    }
  }
}

# Load Balancer Target Groups
resource "aws_lb_target_group" "blue_target_group" {
  name     = "blue-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.selected.id
}

resource "aws_lb_target_group" "green_target_group" {
  name     = "green-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.selected.id
}

# ALB Listener Rule
resource "aws_lb_listener_rule" "traffic_shift_rule" {
  listener_arn = aws_lb_listener.example.arn
  priority     = 100

  conditions {
    field  = "host-header"
    values = ["*"]
  }

  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = 80
      }
      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = 20
      }
    }
  }
}

# Auto Scaling Policy
resource "aws_autoscaling_policy" "scale_green_up" {
  name                   = "scale-green-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  estimated_instance_warmup = 180
  autoscaling_group_name  = aws_autoscaling_group.green_asg.name
}
