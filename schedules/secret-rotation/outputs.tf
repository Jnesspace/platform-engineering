output "schedule_id" {
  description = "ID of the created schedule."
  value       = spacelift_scheduled_run.rotation.schedule_id
}

output "next_schedule" {
  description = "Unix timestamp of the next scheduled run."
  value       = spacelift_scheduled_run.rotation.next_schedule
}
