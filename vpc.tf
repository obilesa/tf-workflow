module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = local.config.variables.vpc_name.value
  azs  = ["us-east-1a", "us-east-1b"]
  cidr = "10.0.0.0/16"

  instance_tenancy = "default"

  private_subnets      = local.config.variables.vpc_private_subnets.value
  public_subnets       = local.config.variables.vpc_public_subnets.value

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support = true


 
  tags = {
    "kubernetes.io/cluster/eks-cluster" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/eks-cluster" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/eks-cluster" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
    "karpenter.sh/discovery" = "eks-cluster"
  }
}


