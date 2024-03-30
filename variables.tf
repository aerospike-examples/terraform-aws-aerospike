# Input variable definitions

# --- Aerospike cluster --------------------------------------------------------

variable "aerospike_cluster_size" {
  description = "Total number of Aerospike server nodes"
  type        = number
  default     = 2
}

variable "aerospike_instance_type" {
  description = "EC2 instance type to use for Aerospike nodes"
  type        = string
  default     = "t3.small"
}

variable "aerospike_instance_root_volume_size" {
  description = "Size of the root EBS block device in GB"
  type        = number
  default     = 10
}

variable "aerospike_service_ports" {
  description = "Aerospike service ports as defined in Aerospike configuration file"
  type        = list(number)
  default     = [3000]
}

variable "aerospike_fabric_port" {
  description = "Aerospike fabric port as defined in Aerospike configuration file"
  type        = number
  default     = 3001
}

variable "aerospike_heartbeat_port" {
  description = "Aerospike heartbeat port as defined in Aerospike configuration file"
  type        = number
  default     = 3002
}

variable "aerospike_client_cidrs" {
  description = "List of CIDR blocks for Aerospike clients outside of the VPC"
  type        = list(string)
  default     = []
}

variable "aerospike_xdr_sources" {
  description = "List of CIDR blocks and ports for XDR source (ingress) security group rules"
  type = list(object({
    cidr = list(string)
    port = number
  }))
  default = []
}

variable "aerospike_xdr_destinations" {
  description = "List of CIDR blocks and ports for XDR destination (egress) security group rules"
  type = list(object({
    cidr = list(string)
    port = number
  }))
  default = []
}

variable "aerospike_xdr_dest_cidrs" {
  description = "CIDR blocks for any Aerospike XDR destinations outside of the VPC"
  type        = list(string)
  default     = []
}


variable "aerospike_node_id_tag" {
  description = "Name of tag to add to Aerospike instances with a node ID"
  type        = string
  default     = "AerospikeNodeId"
}

variable "aerospike_rack_id_tag" {
  description = "Name of tag to add to Aerospike instances with a rack ID"
  type        = string
  default     = "AerospikeRackID"
}

variable "aerospike_zone_name_tag" {
  description = "Name of tag to add to Aerospike instances with AZ name"
  type        = string
  default     = "AerospikeAvailabilityZone"
}

variable "aerospike_default_ami" {
  description = "Default ami_id to use if the node_id is not found in aerospike_rolling_amis"
  type        = string
  default     = "ami-01056f54c380552e2" # Aerospike 7.0.0.0 on Amazon Linux 2
}

variable "aerospike_rolling_amis" {
  description = "Map of node_id => ami_id values for a rolling update"
  type        = map
  default     = {}
}

# --- VPC ----------------------------------------------------------------------

variable "region" {
    description = "AWS region"
    type        = string
    default     = "us-west-2"
}

variable "availability_zones" {
  description = "AWS availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "vpc_name" {
  description = "Name of AWS VPC"
  type        = string
  default     = "example-vpc"
}

variable "vpc_cidr" {
  description = "CIDR block for AWS VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "vpc_private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "vpc_data_subnets" {
  description = "Data subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.201.0/24", "10.0.202.0/24"]
}

# --- Instance Connect ---------------------------------------------------------

variable "ssh_port" {
  description = "SSH port to use to connect to instances via Instance Connect"
  type        = number
  default     = 22
}

variable "instance_connect_client_cidrs" {
  description = "A CIDR block allowed to connect to instances via Instance Connect"
  type        = list(string)
  default     = []
}

# --- Resource tagging ---------------------------------------------------------

variable "vpc_tags" {
  description = "Tags to apply to VPC resource"
  type        = map(string)
  default = {
    Name   = "Aerospike VPC"
  }
}

variable "igw_tags" {
  description = "Tags to apply to Internet Gateway resource"
  type        = map(string)
  default = {
    Name   = "Aerospike IGW"
  }
}

variable "public_subnet_tags" {
  description = "Tags to apply to public subnet resource"
  type        = map(string)
  default = {
    Name   = "Aerospike Public Subnet"
  }
}

variable "private_subnet_tags" {
  description = "Tags to apply to private subnet resource"
  type        = map(string)
  default = {
    Name   = "Aerospike Private Subnet"
  }
}

variable "data_subnet_tags" {
  description = "Tags to apply to data subnet resource"
  type        = map(string)
  default = {
    Name   = "Aerospike Data Subnet"
  }
}

variable "aerospike_instance_tags" {
  description = "Tags to apply to EC2 instances running Aerospike"
  type        = map(string)
  default = {
    Name   = "Aerospike Server"
  }
}

variable "instance_connect_endpoint_tags" {
  description = "Tags to apply to Instance Connect Endopint"
  type        = map(string)
  default = {
    Name   = "Aerospike Instance Connect Endpoint"
  }
}
