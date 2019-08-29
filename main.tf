variable "AWS_REGION" {
  default = "eu-west-1"
}

variable "nat_gw" {
  default = false
}

variable "vpcs" {
  type = map
  default = {
    multi-vpc1 = {
       name               = "multi-vpc1-name"
       cidr               = "172.22.0.0/16",
       enable_nat_gateway = true
       single_nat_gateway = false
       one_nat_gw_per_az  = true
       
       private_subnets = [
         { 
           name = "Private-A-VPC1",
           cidr = "172.22.1.0/24"
           az   = "eu-west-1a"
         },
         {
           name = "Private-B-VPC1",
           cidr = "172.22.2.0/24",
           az   = "eu-west-1b"
         }
       ],
       public_subnets  = [
         { 
           name = "Public-A-VPC1",
           cidr = "172.22.10.0/24",
           az   = "eu-west-1a",
           nat_gw = true
         },
         {
           name = "Public-B-VPC1",
           cidr = "172.22.20.0/24",
           az   = "eu-west-1b"
         }
       ],
       tags            = {
         Name = "multi-prod",
         Environment = "production",
         Terraform = "True"
       }
    },
    multi-vpc2 = {
       name               = "multi-vpc2-name"
       cidr               = "172.12.0.0/16",
       enable_nat_gateway = true
       single_nat_gateway = true
       one_nat_gw_per_az  = false
       private_subnets = [
         { 
           name = "Private-A-VPC2",
           cidr = "172.12.101.0/24"
           az   = "eu-west-1a"
         },
         {
           name = "Private-B-VPC2",
           cidr = "172.12.102.0/24",
           az   = "eu-west-1b"
         }
       ],
       public_subnets  = [
         { 
           name = "Public-A-VPC2",
           cidr = "172.12.110.0/24",
           az   = "eu-west-1a"
         },
         {
           name = "Public-B-VPC2",
           cidr = "172.12.120.0/24",
           az   = "eu-west-1b",
           nat_gw = true
         }
       ],
       tags            = {
         Name = "multi-vpc2",
         Environment = "staging",
         Terraform = "True"
       }
    }
  }
}

# Declare the data source
data "aws_availability_zones" "available" {
  state = "available"
}

module "multi-vpc" {
  source  = "./modules/multi-vpc"

  vpcs = var.vpcs
}

output "vpc-names" {
  value = module.multi-vpc.vpc-names
}

output "vpc-ids" {
  value = module.multi-vpc.vpc-ids
}

output "rtables" {
  value = module.multi-vpc.rtables
}

#output test {
#  value = module.multi-vpc.test
#}
