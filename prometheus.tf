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


# deploys prometheus pod
resource "kubernetes_deployment" "prometheus" {
  depends_on = [ 
    kubernetes_namespace.prometheus,
    kubernetes_service_account.prometheus,
    kubernetes_config_map.prometheus-config,
    kubernetes_cluster_role.prometheus
   ]

  metadata {
    name = "prometheus"
    labels = {
      app = "prometheus"
    }
    namespace = kubernetes_namespace.prometheus.metadata[0].name
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "prometheus"
      }
    }
    template {
      metadata {
        labels = {
          app = "prometheus"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.prometheus.metadata[0].name
        automount_service_account_token = true
        container {
          name = "prometheus"
          image = "prom/prometheus:v2.45.0"
          args = []

          port {
            container_port = 9090
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus"
          }

          volume_mount {
            name       = "prometheus-storage"
            mount_path = "/prometheus"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.prometheus-config.metadata[0].name
          }
        }

        volume {
          name = "prometheus-storage"
          empty_dir {}
        }
      }
    }
  }
}


resource "kubernetes_service" "prometheus" {
    metadata {
        name = "prometheus-lb"
        namespace = "monitoring"
    }
    
    spec {
        selector = {
        app = kubernetes_deployment.prometheus.spec[0].template[0].metadata[0].labels.app
        }
    
        port {
        port        = 9090
        target_port = 9090
        }
    
        type = "NodePort"
    }
}


resource "kubernetes_ingress_v1" "prometheus" {
  metadata {
    name = "prometheus-ingress"
    labels = {
      app = "prometheus-ingress"
    }
    namespace = "monitoring"

    annotations = {
      "alb.ingress.kubernetes.io/scheme" = "internet-facing"
      "alb.ingress.kubernetes.io/group.name" = "outbound"
      "alb.ingress.kubernetes.io/group.order" = "1"
      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 9090}]"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path = "/*"
          backend {
            service {
              name = "prometheus-lb"
              port {
                number = 9090
              }
            }
          }
        }
      }
    }
  }
}


