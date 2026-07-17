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
