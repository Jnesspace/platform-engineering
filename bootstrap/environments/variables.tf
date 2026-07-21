# dev auto-deploys for fast iteration; stage/prod are gated (manual confirm) — the promotion gate.
# All three default to the same demo integration; in production each env points at ITS OWN account's integration.
variable "environments" {
  type = map(object({
    branch             = string
    autodeploy         = bool
    aws_integration_id = string
  }))
  default = {
    dev   = { branch = "dev", autodeploy = true, aws_integration_id = "01JV4YKENC7KXV3MNBYPSH88AX" }
    stage = { branch = "stage", autodeploy = false, aws_integration_id = "01JV4YKENC7KXV3MNBYPSH88AX" }
    prod  = { branch = "main", autodeploy = false, aws_integration_id = "01JV4YKENC7KXV3MNBYPSH88AX" }
  }
  description = "The environment list; adding an env here is the whole 'add an environment' procedure."
}
