output "instance_public_ip" {
  value = aws_instance.web_instance[count.index].public_ip
}

output "load_balancer_dns" {
  value = aws_lb.web_lb.dns_name
}
