variable "name" {
  description = "Logical name; used for the instance Name tag and derived resource names."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}

variable "instance_type" {
  description = "EC2 instance type. Small tier by default."
  type        = string
  default     = "t3.micro"
}
