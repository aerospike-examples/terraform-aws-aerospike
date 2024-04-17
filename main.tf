# Terraform configuration for Aerospike Database on AWS

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  per_instance_tags = [
    for i in range(var.aerospike_cluster_size) :
    merge(
      {
        # Convert i to hex per https://docs.aerospike.com/reference/configuration#node-id and prepend with az identifier:
        (var.aerospike_node_id_tag) : join("", [substr(element(var.availability_zones, i), -1, 1), format("%x", floor(i / length(aws_subnet.data_subnet)) + 1)]),
        # rack-id is a numeric value per subnet starting at 1
        (var.aerospike_rack_id_tag) : element(range(1, length(var.vpc_data_subnets) + 1), i),
        (var.aerospike_zone_name_tag) : element(var.availability_zones, i),
      },
      var.aerospike_instance_tags
    )
  ]
}

# --- Route53 DNS -------------------------------------------------------------

resource "aws_route53_zone" "aerospike_private_dns" {
  name = var.aerospike_private_dns_tld

  vpc {
    vpc_id = aws_vpc.aerospike_vpc.id
  }
}

resource "aws_route53_record" "seed_dns" {
  # first IP per availability zone
  zone_id = aws_route53_zone.aerospike_private_dns.zone_id
  name    = "seed.${var.aerospike_private_dns_tld}"
  type    = "A"
  ttl     = var.aerospike_private_dns_ttl
  records = slice([for instance in values(aws_instance.aerospike_instance): instance.private_ip], 0, length(var.availability_zones))
}

resource "aws_route53_record" "node_dns" {
  for_each = toset(slice([for node_id in keys(aws_instance.aerospike_instance): node_id], 0, length(var.availability_zones)))
  zone_id = aws_route53_zone.aerospike_private_dns.zone_id
  name    = "${each.value}.${var.aerospike_private_dns_tld}"
  type    = "A"
  ttl     = var.aerospike_private_dns_ttl
  records = [aws_instance.aerospike_instance[each.value].private_ip]
}


# --- Aerospike AMI -----------------------------------------------------------

data "aws_ami" "aerospike_ami" {
  # per-instance AMIs to allow for manual rolling updates
  for_each = {for index, tag in local.per_instance_tags: tag[var.aerospike_node_id_tag] => tag}

  filter {
      name = "image-id"
      values = [lookup(var.aerospike_rolling_amis, each.key, var.aerospike_default_ami)]
    }
}

# --- Aerospike EC2 instances -------------------------------------------------

resource "aws_instance" "aerospike_instance" {
  for_each = {for index, tag in local.per_instance_tags: tag[var.aerospike_node_id_tag] => tag}

  instance_type               = var.aerospike_instance_type
  ami                         = data.aws_ami.aerospike_ami[each.key].id

  vpc_security_group_ids = [
    aws_security_group.instance_connect_instance.id,
    aws_security_group.aerospike_external.id,
    aws_security_group.aerospike_internal.id,
    aws_security_group.vpc_internal.id
  ]
  
  subnet_id              = aws_subnet.data_subnet[each.value[var.aerospike_zone_name_tag]].id
  user_data              = data.cloudinit_config.user_data[each.key].rendered
  source_dest_check      = false
  #iam_instance_profile  = var.iam_instance_profile_name

  metadata_options {
    instance_metadata_tags = "enabled"
  }

  dynamic "root_block_device" {
    for_each = (var.aerospike_instance_root_volume_size != null) ? [1] : []
    content {
      volume_size = var.aerospike_instance_root_volume_size
    }
  }

  tags = merge(var.aerospike_instance_tags, each.value)
}

# --- Cloud Init --------------------------------------------------------------

data "cloudinit_config" "user_data" {
  for_each = {for index, tag in local.per_instance_tags: tag[var.aerospike_node_id_tag] => tag}

  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    filename     = "hostname.yml"
    content      = templatefile(
      "${path.module}/cloudinit-configs/hostname.tpl",
      {
        fqdn = "${each.key}.${var.aerospike_private_dns_tld}"
      }
    )
  }
}


# --- VPC ---------------------------------------------------------------------

resource "aws_vpc" "aerospike_vpc" {
    cidr_block           = var.vpc_cidr
    enable_dns_hostnames = true

    tags = var.vpc_tags
}

# --- Public subnets -----------------------------------------------------------

resource "aws_subnet" "public_subnet" {
  for_each = {for i, az in var.availability_zones: az => i}

  vpc_id                  = aws_vpc.aerospike_vpc.id
  cidr_block              = var.vpc_public_subnets[each.value]
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = var.public_subnet_tags
}

resource "aws_ec2_instance_connect_endpoint" "public_instance_connect" {
  # Only need one EICE per VPC
  preserve_client_ip = length(var.instance_connect_client_cidrs) > 0 ? true : false
  subnet_id          = aws_subnet.public_subnet[var.availability_zones[0]].id
  security_group_ids = [aws_security_group.instance_connect_endpoint.id]
  tags               = var.instance_connect_endpoint_tags
}

resource "aws_route_table" "public_rtb" {
  vpc_id = aws_vpc.aerospike_vpc.id
  tags   = var.public_subnet_tags
}

resource "aws_route_table_association" "public_rtb_assoc" {
  for_each = {for i, az in var.availability_zones: az => i}

  subnet_id      = aws_subnet.public_subnet[each.key].id
  route_table_id = aws_route_table.public_rtb.id
}

# --- Private subnets ----------------------------------------------------------

resource "aws_subnet" "private_subnet" {
  for_each = {for i, az in var.availability_zones: az => i}

  vpc_id                  = aws_vpc.aerospike_vpc.id
  cidr_block              = var.vpc_private_subnets[each.value]
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = var.private_subnet_tags
}

resource "aws_route_table" "private_rtb" {
  vpc_id = aws_vpc.aerospike_vpc.id
  tags   = var.private_subnet_tags
}

resource "aws_route_table_association" "private_rtb_assoc" {
  for_each = {for i, az in var.availability_zones: az => i}

  subnet_id      = aws_subnet.private_subnet[each.key].id
  route_table_id = aws_route_table.private_rtb.id
}

# --- Data subnets ----------------------------------------------------------

resource "aws_subnet" "data_subnet" {
  for_each = {for i, az in var.availability_zones: az => i}

  vpc_id                  = aws_vpc.aerospike_vpc.id
  cidr_block              = var.vpc_data_subnets[each.value]
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = var.data_subnet_tags
}

resource "aws_route_table" "data_rtb" {
  vpc_id = aws_vpc.aerospike_vpc.id
  tags   = var.data_subnet_tags
}

resource "aws_route_table_association" "data_rtb_assoc" {
  for_each = {for i, az in var.availability_zones: az => i}

  subnet_id      = aws_subnet.data_subnet[each.key].id
  route_table_id = aws_route_table.data_rtb.id
}

# --- Security Groups ----------------------------------------------------------

resource "random_id" "sg_name" {
  byte_length = 2
}

resource "aws_security_group" "instance_connect_endpoint" {
  name        = "aerospike_instance_connect_endpoint_${random_id.sg_name.hex}"
  description = "Rules for Instance Connect endpoint"
  vpc_id      = aws_vpc.aerospike_vpc.id

  tags = {
    Name: "Aerospike VPC Instance Connect"
  }

  # https://github.com/terraform-providers/terraform-provider-aws/issues/265
  lifecycle { create_before_destroy = true }
}

resource "aws_security_group_rule" "allow_instance_connect_endpoint" {
  security_group_id = aws_security_group.instance_connect_endpoint.id
  type              = "egress"
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group" "instance_connect_instance" {
  name        = "aerospike_instance_connect_instance_${random_id.sg_name.hex}"
  description = "Rules for Instance Connect instances"
  vpc_id      = aws_vpc.aerospike_vpc.id

  tags = {
    Name: "Aerospike VPC Instance Connect"
  }

  # https://github.com/terraform-providers/terraform-provider-aws/issues/265
  lifecycle { create_before_destroy = true }
}

resource "aws_security_group_rule" "allow_instance_connect_clients" {
  security_group_id        = aws_security_group.instance_connect_instance.id
  type                     = "ingress"
  from_port                = var.ssh_port
  to_port                  = var.ssh_port
  protocol                 = "tcp"
  source_security_group_id = length(var.instance_connect_client_cidrs) == 0 ? aws_security_group.instance_connect_endpoint.id : null
  cidr_blocks              = length(var.instance_connect_client_cidrs) > 0 ? var.instance_connect_client_cidrs : null
}

resource "aws_security_group" "vpc_internal" {
  name        = "aerospike_server_private_${random_id.sg_name.hex}"
  description = "Rules for connections from within the VPC"
  vpc_id      = aws_vpc.aerospike_vpc.id

  tags = {
    Name: "Aerospike DB VPC Internal"
  }

  # https://github.com/terraform-providers/terraform-provider-aws/issues/265
  lifecycle { create_before_destroy = true }
}

resource "aws_security_group_rule" "allow_private_subnet_clients" {
  # allow Aerospike client connections from private subnet to data subnet
  for_each = {for port in var.aerospike_service_ports: tostring(port) => port}

  security_group_id = aws_security_group.vpc_internal.id
  type              = "ingress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  cidr_blocks       = var.vpc_private_subnets
}

resource "aws_security_group" "aerospike_internal" {
  name        = "aerospike_server_cluster_internal_${random_id.sg_name.hex}"
  description = "Rules for Aerospike nodes communicating with each other"
  vpc_id      = aws_vpc.aerospike_vpc.id

  tags = {
    Name: "Aerospike DB Intra-Cluster"
  }

  # https://github.com/terraform-providers/terraform-provider-aws/issues/265
  lifecycle { create_before_destroy = true }
}

resource "aws_security_group_rule" "allow_outbound_internal" {
  # used when running aerospike-tools locally on instance
  for_each = {for port in var.aerospike_service_ports: tostring(port) => port}

  security_group_id = aws_security_group.aerospike_internal.id
  type              = "egress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  cidr_blocks       = var.vpc_data_subnets
}

resource "aws_security_group_rule" "allow_inbound_internal" {
  # used when running aerospike-tools locally on instance
  for_each = {for port in var.aerospike_service_ports: tostring(port) => port}

  security_group_id = aws_security_group.aerospike_internal.id
  type              = "ingress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  cidr_blocks       = var.vpc_data_subnets
}

resource "aws_security_group_rule" "allow_inbound_fabric" {
  security_group_id = aws_security_group.aerospike_internal.id
  type              = "ingress"
  from_port         = var.aerospike_fabric_port
  to_port           = var.aerospike_fabric_port
  protocol          = "tcp"
  cidr_blocks       = var.vpc_data_subnets
}

resource "aws_security_group_rule" "allow_outbound_fabric" {
  security_group_id = aws_security_group.aerospike_internal.id
  type              = "egress"
  from_port         = var.aerospike_fabric_port
  to_port           = var.aerospike_fabric_port
  protocol          = "tcp"
  cidr_blocks       = var.vpc_data_subnets
}

resource "aws_security_group_rule" "allow_inbound_heartbeat" {
  security_group_id = aws_security_group.aerospike_internal.id
  type              = "ingress"
  from_port         = var.aerospike_heartbeat_port
  to_port           = var.aerospike_heartbeat_port
  protocol          = "tcp"
  cidr_blocks       = var.vpc_data_subnets
}

resource "aws_security_group_rule" "allow_outbound_heartbeat" {
  security_group_id = aws_security_group.aerospike_internal.id
  type              = "egress"
  from_port         = var.aerospike_heartbeat_port
  to_port           = var.aerospike_heartbeat_port
  protocol          = "tcp"
  cidr_blocks       = var.vpc_data_subnets
}

resource "aws_security_group" "aerospike_external" {
  name        = "aerospike_server_external_clients_${random_id.sg_name.hex}"
  description = "Rules for clients connecting from outside of the VPC"
  vpc_id      = aws_vpc.aerospike_vpc.id

  tags = {
    Name: "Aerospike DB External Clients"
  }

  # https://github.com/terraform-providers/terraform-provider-aws/issues/265
  lifecycle { create_before_destroy = true }
}

resource "aws_security_group_rule" "allow_inbound_clients" {
  for_each = {
    for port in var.aerospike_service_ports: tostring(port) => port
    if length(var.aerospike_client_cidrs) > 0
  }

  security_group_id = aws_security_group.aerospike_external.id
  type              = "ingress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  cidr_blocks       = var.aerospike_client_cidrs
}

resource "aws_security_group_rule" "allow_inbound_xdr" {
  count = length(var.aerospike_xdr_sources)

  security_group_id = aws_security_group.aerospike_external.id
  type              = "ingress"
  from_port         = coalesce(var.aerospike_xdr_sources[count.index].port, 3000)
  to_port           = coalesce(var.aerospike_xdr_sources[count.index].port, 3000)
  protocol          = "tcp"
  cidr_blocks       = var.aerospike_xdr_sources[count.index].cidr
}

resource "aws_security_group_rule" "allow_outbound_xdr" {
  count = length(var.aerospike_xdr_destinations)

  security_group_id = aws_security_group.aerospike_external.id
  type              = "egress"
  from_port         = coalesce(var.aerospike_xdr_destinations[count.index].port, 3000)
  to_port           = coalesce(var.aerospike_xdr_destinations[count.index].port, 3000)
  protocol          = "tcp"
  cidr_blocks       = var.aerospike_xdr_destinations[count.index].cidr
}
