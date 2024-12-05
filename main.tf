provider "aws" {
  region = "us-east-1"  # Adjust region if necessary
}

# VPC Configuration
data "aws_vpc" "selected" {
  id = "vpc-084570e9d3d7c0f8d"  # Use your existing VPC ID
}

# Subnet Configuration (Use an existing subnet from the selected VPC)
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

# Security Group for EC2 instance (Make sure this is in the correct VPC)
resource "aws_security_group" "web_sg" {
  name_prefix = "web_sg"
  description = "Allow HTTP traffic"
  vpc_id      = data.aws_vpc.selected.id  # Reference the correct VPC

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
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH from anywhere (0.0.0.0/0)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Fetch the latest AMI ID dynamically (Ubuntu in this example)
data "aws_ami" "latest_ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Ubuntu's official account ID
  filter {
    name   = "name"
    values = ["ubuntu*-x86_64-generic*"]  # Filter for Ubuntu AMIs
  }
}

variable "environment" {
  description = "The environment to deploy (blue or green)"
  type        = string
}

# Launch Configuration for EC2 instances with key pair (Blue Environment)
resource "aws_launch_configuration" "blue_config" {
  name = "blue-launch-configuration-${replace(timestamp(), ":", "")}"
  image_id      = data.aws_ami.latest_ubuntu.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]
  key_name      = "Fortress-Automation-check"

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

  tag {
    key                 = "Name"
    value               = "${var.environment}-web-instance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "green_config" {
  name = "green-launch-configuration-${replace(timestamp(), ":", "")}"
  image_id      = data.aws_ami.latest_ubuntu.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]
  key_name      = "Fortress-Automation-check"

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

  tag {
    key                 = "Name"
    value               = "${var.environment}-web-instance"
    propagate_at_launch = true
  }
}


# Auto Scaling Group for blue-green deployment
resource "aws_autoscaling_group" "green_asg" {
  desired_capacity     = 1
  max_size             = 2
  min_size             = 1
  vpc_zone_identifier  = [data.aws_subnet.subnet_a.id, data.aws_subnet.subnet_b.id]

  # Switch between Blue and Green configurations based on deployment
  launch_configuration = aws_launch_configuration.green_config.id  # Green config

  health_check_type          = "EC2"
  health_check_grace_period = 300
  force_delete               = true

  lifecycle {
    create_before_destroy = true
  }
}


# Elastic Load Balancer to distribute traffic between blue and green instances
resource "aws_lb" "web_lb" {
  name               = "web-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [data.aws_subnet.subnet_a.id, data.aws_subnet.subnet_b.id]  # Two subnets in different AZs
}

# Target Group for Blue Environment
resource "aws_lb_target_group" "blue_target_group" {
  name     = "blue-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.selected.id
}

# Target Group for Green Environment
resource "aws_lb_target_group" "green_target_group" {
  name     = "green-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.selected.id
}

# ALB Listener
resource "aws_lb_listener_rule" "traffic_shift_rule" {
  listener_arn = aws_lb_listener.web_listener.arn
  priority     = 100  # Set a priority for the rule

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_target_group.arn
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green_target_group.arn
  }

  condition {
    field  = "path-pattern"
    values = ["/green/*"]
  }
}


# Step Scaling Policy to scale Green ASG once Blue is healthy
resource "aws_autoscaling_policy" "scale_green_up" {
  name                   = "scale-green-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name  = aws_autoscaling_group.green_asg.name
}