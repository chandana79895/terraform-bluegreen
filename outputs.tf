# Output Public IP of EC2 instance
output "instance_public_ip" {
  value = aws_instance.web_instance.public_ip
}

# Output Load Balancer DNS Name (for ALB or NLB)
output "load_balancer_dns" {
  value = aws_lb.my_lb.dns_name  # Replace with your ALB or NLB resource
}