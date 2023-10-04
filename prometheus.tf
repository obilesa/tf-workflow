resource "kubernetes_namespace" "prometheus" {
  metadata {
    name = "monitoring"
  }
}