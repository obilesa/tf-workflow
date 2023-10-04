
resource "kubernetes_namespace" "prometheus" {
  count = var.enable_monitoring ? 1 : 0
  metadata {
    name = var.monitoring_namespace
  }
}

# role for prometheus service account
# used for prometheus to discover kubernetes cluster
resource "kubernetes_cluster_role" "prometheus" {
  count = var.enable_monitoring ? 1 : 0
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
  count = var.enable_monitoring ? 1 : 0
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
    name     = kubernetes_cluster_role.prometheus[0].metadata[0].name
  }

  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.prometheus[0].metadata[0].name
    namespace = kubernetes_namespace.prometheus[0].metadata[0].name
  }
}
# reads the prometheus.yaml file and store it in the config map
# config maps are used to store configuration files in kubernetes for pods to use
resource "kubernetes_config_map" "prometheus-config"{
  count = var.enable_monitoring ? 1 : 0
  depends_on = [ 
    kubernetes_namespace.prometheus
   ]
    metadata {
        name = "prometheus-config"
        namespace = kubernetes_namespace.prometheus[0].metadata[0].name
    }

    # reads local config file
    data = {
        "prometheus.yml" = file("prometheus.yaml")
    }
}

resource "kubernetes_service_account" "prometheus" {
    count = var.enable_monitoring ? 1 : 0
  depends_on = [ 
    kubernetes_namespace.prometheus
   ]
  metadata {
    name = "prometheus"
    namespace = kubernetes_namespace.prometheus[0].metadata[0].name
  }
}


# deploys prometheus pod
resource "kubernetes_deployment" "prometheus" {
    count = var.enable_monitoring ? 1 : 0
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
    namespace = kubernetes_namespace.prometheus[0].metadata[0].name
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
        service_account_name = kubernetes_service_account.prometheus[0].metadata[0].name
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
            name = kubernetes_config_map.prometheus-config[0].metadata[0].name
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
    count = var.enable_monitoring ? 1 : 0
    metadata {
        name = "prometheus-lb"
        namespace = kubernetes_namespace.prometheus[0].metadata[0].name
    }
    
    spec {
        selector = {
        app = "prometheus"
        }
    
        port {
        port        = 9090
        target_port = 9090
        }
    
        type = "NodePort"
    }
}


resource "kubernetes_ingress_v1" "prometheus" {
    count = var.enable_monitoring ? 1 : 0
  metadata {
    name = "prometheus"
    labels = {
      app = "prometheus"
    }

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
              name = kubernetes_service.prometheus[0].metadata[0].name
              port {
                number = kubernetes_service.prometheus[0].spec[0].port[0].port
              }
            }
          }
        }
      }
    }
  }
}



# Create a Kubernetes DaemonSet for the node exporter
resource "kubernetes_daemonset" "node_exporter" {
    count = var.enable_monitoring && var.enable_node_monitoring ? 1 : 0
  metadata {
    name = "node-exporter"
    labels = {
      app = "node-exporter"
    }
    namespace = kubernetes_namespace.prometheus[0].metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        app = "node-exporter"
      }
    }

    template {
      metadata {
        labels = {
          app = "node-exporter"
          "prometheus.io/scrape" = "true"
        }
      }

      spec {
        container {
          name = "node-exporter"
          image = "prom/node-exporter:v1.2.2"
          args = [
            "--web.listen-address=:9100",
            "--path.procfs=/host/proc",
            "--path.sysfs=/host/sys",
            "--collector.filesystem.ignored-mount-points=^/(dev|proc|sys|run|var/lib/docker/.+)($|/)",
          ]
          port {
            container_port = 9100
          }
          volume_mount {
            name = "proc"
            mount_path = "/host/proc"
            read_only = true
          }
          volume_mount {
            name = "sys"
            mount_path = "/host/sys"
            read_only = true
          }
        }

        volume {
          name = "proc"
          host_path {
            path = "/proc"
          }
        }
        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }
      }
    }
  }
}



# Expose the node exporter metrics endpoint using a Kubernetes service
resource "kubernetes_service" "node_exporter" {
    count = var.enable_monitoring && var.enable_node_monitoring ? 1 : 0
  metadata {
    name = "node-exporter"
    namespace = kubernetes_namespace.prometheus[0].metadata[0].name
    annotations = {
      
    }
  }

  spec {
    selector = {
      app = "node-exporter"
    }

    port {
      name = "metrics"
      port = 9100
      target_port = 9100
    }
  }
}

