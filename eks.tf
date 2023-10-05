module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "19.16.0"
  cluster_name    = var.cluster_name
  cluster_version = "1.27"
  

  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  eks_managed_node_groups = {
    default_node_group = {
      # Define the node group for the worker nodes
      # Set the desired, minimum and maximum count of nodes
      min_size = var.node_group_minimum_instances
      desired_size = var.node_group_desired_instances
      max_size = var.node_group_maximum_instances

      # Set the instance types for the worker nodes
      instance_types = var.node_group_instance_types

      # Set the security groups for the worker nodes

      capacity_type = var.node_group_capacity_type

    }
    
  }

  enable_irsa = true




  aws_auth_roles =  [
    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
    {
      rolearn  = module.karpenter[0].role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    }
  ] 
  
  tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}

