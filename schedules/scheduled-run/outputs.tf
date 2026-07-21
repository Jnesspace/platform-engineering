output "next_schedule" {
  description = "Unix timestamp of the next scheduled run."
  value       = spacelift_scheduled_run.nightly.next_schedule
}
