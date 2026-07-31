# Runs the app image with what app-factory vended: role via IRSA, resources via env — no static creds. The pod is hardened to the `restricted` Pod Security Standard, and the AWS web-identity token is projected EXPLICITLY so the Kubernetes API token can be left unmounted without breaking IRSA.

locals {
  namespace = var.namespace != "" ? var.namespace : var.app_name
  labels    = { app = var.app_name }

  # Where the EKS pod-identity webhook mounts the projected token; matching it keeps the AWS SDK's default discovery working.
  irsa_token_volume = "aws-iam-token"
  irsa_token_mount  = "/var/run/secrets/eks.amazonaws.com/serviceaccount"

  # Vended resources by reference; the app fetches the secret VALUE from Secrets Manager at runtime via the role.
  env = merge(
    {
      BUCKET_NAME = var.bucket
      SECRET_ARN  = var.secret_arn
      AWS_REGION  = var.region
      # Regional STS: lower latency, and it keeps the credential exchange inside the region.
      AWS_STS_REGIONAL_ENDPOINTS = "regional"
    },
    # Only set alongside our own projected volume — the webhook skips a container that already declares these, so setting them without the volume would leave no token at all.
    var.project_irsa_token ? {
      AWS_ROLE_ARN                = var.app_role_arn
      AWS_WEB_IDENTITY_TOKEN_FILE = "${local.irsa_token_mount}/token"
    } : {},
  )
}

# Pod Security admission enforces at the namespace, so the hardened pod spec below cannot be quietly bypassed by anything else deployed here.
resource "kubernetes_namespace" "app" {
  metadata {
    name = local.namespace
    labels = merge(local.labels, {
      "pod-security.kubernetes.io/enforce" = var.pod_security_standard
      "pod-security.kubernetes.io/audit"   = var.pod_security_standard
      "pod-security.kubernetes.io/warn"    = var.pod_security_standard
    })
  }
}

# The IRSA annotation is how the pod assumes the vended app role. No token is auto-mounted from here; the Deployment projects the AWS-audience token itself.
resource "kubernetes_service_account" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.labels
    annotations = {
      "eks.amazonaws.com/role-arn" = var.app_role_arn
    }
  }

  automount_service_account_token = !var.project_irsa_token
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas               = var.replicas
    revision_history_limit = 3

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        service_account_name = kubernetes_service_account.app.metadata[0].name

        # False when we project the AWS token ourselves: the pod then holds NO Kubernetes API credential, only the sts.amazonaws.com-audience token. True only in webhook mode, where the webhook's patch needs the automount machinery.
        automount_service_account_token = !var.project_irsa_token

        # Legacy Service env vars leak the addresses of every Service in the namespace.
        enable_service_links = false

        security_context {
          run_as_non_root = true
          run_as_user     = var.run_as_user
          run_as_group    = var.run_as_group
          fs_group        = var.fs_group

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = var.app_name
          image = var.image

          port {
            container_port = var.container_port
          }

          dynamic "env" {
            for_each = local.env
            content {
              name  = env.key
              value = env.value
            }
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = var.run_as_user
            run_as_group               = var.run_as_group
            privileged                 = false
            allow_privilege_escalation = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }

            seccomp_profile {
              type = "RuntimeDefault"
            }
          }

          # An empty probe path falls back to a TCP check so there is always a real health signal.
          liveness_probe {
            dynamic "http_get" {
              for_each = var.liveness_path != "" ? [1] : []
              content {
                path = var.liveness_path
                port = var.container_port
              }
            }
            dynamic "tcp_socket" {
              for_each = var.liveness_path == "" ? [1] : []
              content {
                port = var.container_port
              }
            }
            initial_delay_seconds = var.liveness_initial_delay_seconds
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          readiness_probe {
            dynamic "http_get" {
              for_each = var.readiness_path != "" ? [1] : []
              content {
                path = var.readiness_path
                port = var.container_port
              }
            }
            dynamic "tcp_socket" {
              for_each = var.readiness_path == "" ? [1] : []
              content {
                port = var.container_port
              }
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          # Scratch space, because the root filesystem is read-only.
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          dynamic "volume_mount" {
            for_each = var.project_irsa_token ? [1] : []
            content {
              name       = local.irsa_token_volume
              mount_path = local.irsa_token_mount
              read_only  = true
            }
          }
        }

        volume {
          name = "tmp"
          empty_dir {
            size_limit = var.tmp_volume_size
          }
        }

        # The IRSA credential itself: a short-lived token minted for the sts.amazonaws.com audience only, so it is useless against the Kubernetes API.
        dynamic "volume" {
          for_each = var.project_irsa_token ? [1] : []
          content {
            name = local.irsa_token_volume
            projected {
              default_mode = "0440"
              sources {
                service_account_token {
                  audience           = "sts.amazonaws.com"
                  expiration_seconds = var.irsa_token_expiration_seconds
                  path               = "token"
                }
              }
            }
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
    labels    = local.labels
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

# Deny both directions for everything in the namespace; the policy below re-opens only what the app provably needs.
resource "kubernetes_network_policy" "default_deny" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy" "app" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "${var.app_name}-allow"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = local.labels
    }
    policy_types = ["Ingress", "Egress"]

    ingress {
      # Same namespace by default; anything cross-namespace has to be named explicitly.
      from {
        pod_selector {}
      }
      dynamic "from" {
        for_each = var.ingress_namespace_labels
        content {
          namespace_selector {
            match_labels = from.value
          }
        }
      }
      ports {
        port     = var.container_port
        protocol = "TCP"
      }
    }

    # Without DNS nothing resolves — including the STS endpoint the IRSA exchange needs.
    egress {
      to {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = var.dns_namespace }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }

    # AWS APIs over TLS. IMDS is carved out so a compromised pod cannot borrow the node's instance role and step around the vended, scoped one.
    egress {
      to {
        ip_block {
          cidr   = var.egress_cidr
          except = length(var.egress_except_cidrs) > 0 ? var.egress_except_cidrs : null
        }
      }
      dynamic "ports" {
        for_each = var.egress_ports
        content {
          port     = ports.value
          protocol = "TCP"
        }
      }
    }
  }
}
