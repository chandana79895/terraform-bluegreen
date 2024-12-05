provider "aws" {
  region = "us-east-1"  # Adjust region if necessary
}

# VPC Configuration
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
  image_id      = data.aws_ami.latest_ubuntu.id  # Dynamically fetch AMI ID
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

  tags = {
    Name = "${var.environment}-web-instance"
  }
}

# Launch Configuration for EC2 instances with key pair (Green Environment)
resource "aws_launch_configuration" "green_config" {
  name = "green-launch-configuration-${replace(timestamp(), ":", "")}"
  image_id      = data.aws_ami.latest_ubuntu.id  # Dynamically fetch AMI ID
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

  tags = {
    Name = "${var.environment}-web-instance"
  }
}

# Auto Scaling Group for blue-green deployment
resource "aws_autoscaling_group" "asg" {
  desired_capacity     = 1
  max_size             = 2
  min_size             = 1
  vpc_zone_identifier  = [data.aws_subnet.subnet.id]

  # Switch between Blue and Green configurations based on deployment
  launch_configuration = aws_launch_configuration.blue_config.id  # Initially blue, can be switched to green

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
  subnets            = [data.aws_subnet.subnet.id]
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

# Create EC2 instances with dynamic IP assignment
resource "aws_instance" "web_instance" {
  count = 1
  ami           = data.aws_ami.latest_ubuntu.id  # Dynamically fetch AMI ID
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]
  subnet_id     = data.aws_subnet.subnet.id
  associate_public_ip_address = true
  key_name      = "Fortress-Automation-check"

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt upgrade -y
              sudo apt install -y apache2
              echo "Hello from Apache Web Server - Sample app for testing" | sudo tee /var/www/html/index.html
              sudo systemctl start apache2
              sudo systemctl enable apache2
              EOF

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "WebInstance"
  }
}

# Output Public IP of EC2 instances dynamically
output "instance_public_ip" {
  value = aws_instance.web_instance.*.public_ip
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

resource "aws_lb_listener_rule" "traffic_shift_rule" {
  listener_arn = aws_lb_listener.web_listener.arn
  priority     = 100  # Set a priority for the rule

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_target_group.arn
    weight           = 100  # Initially route all traffic to the blue target group
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green_target_group.arn
    weight           = 0  # Initially route no traffic to the green target group
  }

  condition {
    field  = "host-header"
    values = ["*"]  # This condition matches all hosts (adjust as needed)
  }
}

resource "aws_lb_listener_rule" "traffic_shift_green" {
  listener_arn = aws_lb_listener.web_listener.arn
  priority     = 200  # Set a lower priority for green

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_target_group.arn
    weight           = 0  # No traffic to the blue target group
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green_target_group.arn
    weight           = 100  # Route all traffic to the green target group when it's ready
  }

  condition {
    field  = "host-header"
    values = ["*"]  # This condition matches all hosts (adjust as needed)
  }
}


# Outputs
output "load_balancer_dns" {
  value = aws_lb.web_lb.dns_name
}
