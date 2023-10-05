module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.vpc_name
  azs  = var.vpc_azs
  cidr = var.vpc_cidr

  instance_tenancy = "default"

  private_subnets      = var.vpc_private_subnets
  public_subnets       = var.vpc_public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support = true


 
  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

