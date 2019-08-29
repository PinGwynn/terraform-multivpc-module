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
          vpc_id   = aws_vpc.this[vpc_config.name].id
          vpc_name = vpc_config.name
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
          vpc_id   = aws_vpc.this[vpc_config.name].id
          vpc_name = vpc_config.name
          name     = subnet_metadata.name,
          cidr     = subnet_metadata.cidr,
          az       = subnet_metadata.az,
          nat_gw   = lookup(subnet_metadata, "nat_gw", false)
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
  for_each = { for o in  var.vpcs: o.name => o }

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
  for_each = { for o in  var.vpcs: o.name => o }

  vpc_id = aws_vpc.this[each.value.name].id
  tags = {
    Name = each.value.name
  }
}

################
# Publiс routes
################
resource "aws_route_table" "public" {
  for_each = { for o in local.public_subnets_metadata : o.name => o }

  vpc_id = each.value.vpc_id
  tags = {
    Name = each.value.name
    VPC = each.value.vpc_name
  }
}

#################
# Private routes
# There are as many routing tables as the number of NAT gateways
#################
resource "aws_route_table" "private" {
  for_each = { for o in local.private_subnets_metadata : o.name => o }

  vpc_id = each.value.vpc_id
  tags = {
    Name = each.value.name
    VPC = each.value.vpc_name
  }

  lifecycle {
    # When attaching VPN gateways it is common to define aws_vpn_gateway_route_propagation
    # resources that manipulate the attributes of the routing table (typically for the private subnets)
    ignore_changes = [propagating_vgws]
  }
}

#resource "null_resource" "resource" {
#  for_each = aws_route_table.public
#
#  triggers = {
#    key = each.key,
#    id  = each.value.id
#    vpc_id = each.value.vpc_id
#    #    gateway_id = aws_internet_gateway.this[keys(aws_vpc.this)].id
#  }
#}

resource "aws_route" "public_internet_gateway" {
  for_each = { for o in local.public_subnets_metadata : o.name => o }

  route_table_id         = aws_route_table.public[each.value.name].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[each.value.vpc_name].id

  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "public" {
  for_each = { for o in local.public_subnets_metadata : o.name => o }

  subnet_id      = aws_subnet.public[each.value.name].id
  route_table_id = aws_route_table.public[each.value.name].id
}

#################
# Private subnet
#################
resource "aws_subnet" "private" {
  for_each = { for o in local.private_subnets_metadata : o.name => o }

  vpc_id                  = each.value.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  tags = {
    Name = each.value.name
    VPC = each.value.vpc_name
  }
}

#################
# Public subnet
#################
resource "aws_subnet" "public" {
  for_each = { for o in local.public_subnets_metadata : o.name => o }

  vpc_id            = each.value.vpc_id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  map_public_ip_on_launch = var.map_public_ip_on_launch
  tags = {
    Name = each.value.name
    VPC = each.value.vpc_name
    NAT_GW = each.value.nat_gw
  }
}


resource "aws_eip" "nat" {
  for_each = { 
    for o in local.public_subnets_metadata: 
    o.name => o
    if "true" == o.nat_gw
  }
  vpc = true
  tags = {
    Name = format("NAT-EIP-%s", each.value.name)
  }
}

resource "aws_nat_gateway" "this" {
  for_each = { 
    for o in local.public_subnets_metadata: 
    o.name => o
    if "true" == o.nat_gw
  }
  allocation_id = aws_eip.nat[each.value.name].id
  subnet_id = aws_subnet.public[each.value.name].id
  
  #subnet_id = element(values(aws_subnet.public)[each.value.name.vpc_id][*].id,0)
  depends_on = [aws_internet_gateway.this]
  tags = {
    Name = each.value.name
  }
}

#resource "aws_route" "private_nat_gateway" {
#  for_each = { for o in local.private_subnets_metadata : o.name => o }
#
#  route_table_id         = aws_route_table.private[each.value.name].id
#  destination_cidr_block = "0.0.0.0/0"
#  nat_gateway_id         = aws_nat_gateway.this[each.value.name].id
#  
#  timeouts {
#    create = "5m"
#  }
#}
#
#resource "aws_route_table_association" "private" {
#  for_each = { for o in local.private_subnets_metadata : o.name => o }
#
#  subnet_id      = aws_subnet.private[each.value.name].id
#  route_table_id = aws_route_table.private[each.value.name].id
#}

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

#output test {
#  value = local.gateways_subnets_match
#}
