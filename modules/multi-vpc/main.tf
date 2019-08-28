variable "vpcs" {
  type       = map
}

variable "map_public_ip_on_launch" {
  description = "Should be false if you do not want to auto-assign public IP on launch"
  type        = bool
  default     = true
}

locals {
  
  private_subnets_metadata = flatten([
    for vpc_name, vpc_config in var.vpcs : [
      for subnet_metadata in vpc_config.private_subnets : [
        {
          key      = vpc_name,
          vpc_id   = aws_vpc.this[vpc_name].id
          name     = subnet_metadata.name,
          cidr     = subnet_metadata.cidr,
          az       = subnet_metadata.az
        }
      ]
    ]
  ])

  public_subnets_metadata = flatten([
    for vpc_name, vpc_config in var.vpcs : [
      for subnet_metadata in vpc_config.public_subnets : [
        {
          key      = vpc_name,
          vpc_id   = aws_vpc.this[vpc_name].id
          name     = subnet_metadata.name,
          cidr     = subnet_metadata.cidr,
          az       = subnet_metadata.az
        }
      ]
    ]
  ])

  gateways_subnets_match = flatten([
    for rt in aws_route_table.public : [
      for igw in aws_internet_gateway.this : [
        {
          rt_vpc_id  = rt.vpc_id
          rt_id      = rt.id
          igw_vpc_id  = igw.vpc_id
          igw_id      = igw.id
        }
      ]
      if rt.vpc_id == igw.vpc_id
    ]
  ])
}

resource "aws_vpc" "this" {
  for_each             = var.vpcs

  cidr_block           = each.value.cidr
  instance_tenancy     = "default"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  enable_classiclink   = "false"

  tags = each.value.tags
}

###################
# Internet Gateway
###################
resource "aws_internet_gateway" "this" {
  for_each             = var.vpcs

  vpc_id = aws_vpc.this[each.key].id
}

################
# Publiс routes
################
resource "aws_route_table" "public" {
  for_each = { for o in local.public_subnets_metadata : o.name => o }

  vpc_id = each.value.vpc_id
}

#resource "null_resource" "resource" {
#  for_each = aws_route_table.public
#
#  triggers = {
#    key = each.key,
#    id  = each.value.id
#    vpc_id = each.value.vpc_id
#    gateway_id = aws_internet_gateway.this[keys(aws_vpc.this)].id
#  }
#}

resource "aws_route" "public_internet_gateway" {
  for_each = { for o in local.gateways_subnets_match: o.rt_id => o }

  route_table_id         = each.value.rt_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = each.value.igw_id

  timeouts {
    create = "5m"
  }
}

#################
# Private subnet
#################
resource "aws_subnet" "private" {
  for_each = { for o in local.private_subnets_metadata : o.name => o }

  vpc_id                  = each.value.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
}

#################
# Private subnet
#################
resource "aws_subnet" "public" {
  for_each = { for o in local.public_subnets_metadata : o.name => o }

  vpc_id            = each.value.vpc_id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  map_public_ip_on_launch = var.map_public_ip_on_launch
}


### Outputs

output "vpc-names" {
  description = "The names of the VPC"
  value       = keys(aws_vpc.this)
}

output "vpc-ids" {
  description = "The IDs of the VPC"
  value       = values(aws_vpc.this)[*].id
}

output "rtables" {
  description = "The IDs of the VPC"
  value       = values(aws_route_table.public)[*]
}

output test {
  value = local.gateways_subnets_match
}
