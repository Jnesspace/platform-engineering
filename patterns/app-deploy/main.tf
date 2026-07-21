# Runs the app image with what app-factory vended: role via IRSA, resources via env — no static creds.

locals {
  namespace = var.namespace != "" ? var.namespace : var.app_name
  labels    = { app = var.app_name }
}

resource "kubernetes_namespace" "app" {
  metadata {
    name   = local.namespace
    labels = local.labels
  }
}

# The IRSA annotation is how the pod assumes the vended app role.
resource "kubernetes_service_account" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = var.app_role_arn
    }
  }
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        service_account_name = kubernetes_service_account.app.metadata[0].name

        container {
          name  = var.app_name
          image = var.image

          port {
            container_port = var.container_port
          }

          # Vended resources by reference; the app fetches the secret VALUE from Secrets Manager at runtime via the role.
          env {
            name  = "BUCKET_NAME"
            value = var.bucket
          }
          env {
            name  = "SECRET_ARN"
            value = var.secret_arn
          }
          env {
            name  = "AWS_REGION"
            value = var.region
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    type     = "ClusterIP"
    selector = local.labels

    port {
      port        = var.container_port
      target_port = var.container_port
    }
  }
}
