resource "kubernetes_namespace" "prometheus" {
  metadata {
    name = "monitoring"
  }
}


# role for prometheus service account
# used for prometheus to discover kubernetes cluster
resource "kubernetes_cluster_role" "prometheus" {
  metadata {
    name = "prometheus-cluster-role"
  }


  rule {
    api_groups = [""]
    resources  = ["namespaces","services", "pods", "endpoints", "nodes", "nodes/metrics"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources = ["configmaps"]
    verbs = [ "get" ]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources = ["ingresses"]
    verbs = [ "get", "list", "watch" ]
  }

  rule {
    non_resource_urls = [ "/metrics" ]
    verbs = [ "get" ]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }
}

# this binds the prometheus service account to the prometheus cluster role
resource "kubernetes_cluster_role_binding" "prometheus_discoverer" {
  depends_on = [ 
    kubernetes_cluster_role.prometheus,
    kubernetes_service_account.prometheus,
    kubernetes_namespace.prometheus
   ]
  metadata {
    name = "prometheus-discoverer"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind     = "ClusterRole"
    name     = kubernetes_cluster_role.prometheus.metadata[0].name
  }

  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.prometheus.metadata[0].name
    namespace = kubernetes_namespace.prometheus.metadata[0].name
  }
}
# reads the prometheus.yaml file and store it in the config map
# config maps are used to store configuration files in kubernetes for pods to use
resource "kubernetes_config_map" "prometheus-config"{
  depends_on = [ 
    kubernetes_namespace.prometheus
   ]
    metadata {
        name = "prometheus-config"
        namespace = kubernetes_namespace.prometheus.metadata[0].name
    }

    # reads local config file
    data = {
        "prometheus.yml" = file("prometheus.yaml")
    }
}

resource "kubernetes_service_account" "prometheus" {
  depends_on = [ 
    kubernetes_namespace.prometheus
   ]
  metadata {
    name = "prometheus"
    namespace = kubernetes_namespace.prometheus.metadata[0].name
  }
}
