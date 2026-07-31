output "namespace" {
  description = "Namespace the app runs in."
  value       = kubernetes_namespace.app.metadata[0].name
}

output "service_name" {
  description = "ClusterIP Service name."
  value       = kubernetes_service.app.metadata[0].name
}

output "deployment_name" {
  description = "Deployment name."
  value       = kubernetes_deployment.app.metadata[0].name
}

output "service_account_name" {
  description = "ServiceAccount the pod runs as — the identity half of the IRSA `sub`."
  value       = kubernetes_service_account.app.metadata[0].name
}

# Cross-check against app-factory's `app_role_trust.oidc_sub`: if these differ, the pod gets AccessDenied from STS.
output "irsa_subject" {
  description = "The OIDC `sub` this workload presents to STS: system:serviceaccount:<namespace>:<serviceaccount>."
  value       = "system:serviceaccount:${kubernetes_namespace.app.metadata[0].name}:${kubernetes_service_account.app.metadata[0].name}"
}
