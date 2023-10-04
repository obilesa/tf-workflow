module "karpenter" {
    source = "terraform-aws-modules/eks/aws//modules/karpenter"

    cluster_name = module.eks.cluster_name
    irsa_oidc_provider_arn = module.eks.oidc_provider_arn

    policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true
  /*
  v0.16.0 changed the default replicas from 1 to 2.

Karpenter won’t launch capacity to run itself (log related to the karpenter.sh/provisioner-name DoesNotExist requirement) so it can’t provision for the second Karpenter pod.

To solve this you can either reduce the replicas back from 2 to 1, or ensure there is enough capacity that isn’t being managed by Karpenter (these are instances with the name karpenter.sh/provisioner-name/<PROVIDER_NAME>) to run both pods.

To do so on AWS increase the minimum and desired parameters on the node group autoscaling group to launch at lease 2 instances
*/
  
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart = "karpenter"
  version = "v0.28.0"

   set {
    name  = "settings.aws.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "settings.aws.clusterEndpoint"
    value = module.eks.cluster_endpoint
  }

    set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter.irsa_arn
  }
 set {
    name  = "settings.aws.defaultInstanceProfile"
    value = module.karpenter.instance_profile_name
  }

    set {
    name  = "settings.aws.interruptionQueueName"
    value = module.karpenter.queue_name
  }

}

# Only can be used in us-east-1
data "aws_ecrpublic_authorization_token" "token" {
}

resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: default
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t2.small"]
      limits:
        resources:
          cpu: 1000
      providerRef:
        name: default
      ttlSecondsAfterEmpty: 30
      ttlSecondsUntilExpired: 2592000 
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}



resource "kubectl_manifest" "karpenter_node_template" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1alpha1
    kind: AWSNodeTemplate
    metadata:
      name: default
    spec:
      subnetSelector:
        karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelector:
        karpenter.sh/discovery: ${module.eks.cluster_name}
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}