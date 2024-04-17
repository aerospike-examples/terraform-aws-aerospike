# Terraform outputs for Aerospike Database on AWS

output "vpc_id" {
  description = "VPC ID"
  value = aws_vpc.aerospike_vpc.id
}

output "dns_records" {
  description = ""
  value       = merge(
    {"seed": aws_route53_record.seed_dns.name},
    {for node_id, record in aws_route53_record.node_dns : node_id => record.name}
  )
}

output "amis" {
  description = "Map of AMIs: {node_id: {id: ami_id description: ami_description}, ...}"
  value       = {
    for node_id, instance in aws_instance.aerospike_instance : node_id => 
    {id: data.aws_ami.aerospike_ami[node_id].id, description: data.aws_ami.aerospike_ami[node_id].description}
  }
}

output "instance_ids" {
  description = "Map of instance IDs: {node_id: instance_id, ...}"
  value       = {for node_id, instance in aws_instance.aerospike_instance : node_id => instance.id}
}

output "private_ips" {
  description = "Map of private IPs: {node_id: private_ip, ...}"
  value       = {for node_id, instance in aws_instance.aerospike_instance : node_id => instance.private_ip}
}

output "cli_ssh_commands" {
  description = "Commands to SSH into instances via Instance connect"
  value       = {
    for node_id, instance in aws_instance.aerospike_instance : node_id => 
    "aws ec2-instance-connect ssh --connection-type eice --instance-id ${instance.id}"
  }
}

output "subnets" {
  description = "Subnets"
  value       = {
    "public": {for az, subnet in aws_subnet.public_subnet : az => subnet.id}, 
    "private": {for az, subnet in aws_subnet.private_subnet : az => subnet.id},
    "data": {for az, subnet in aws_subnet.data_subnet : az => subnet.id}}
}
