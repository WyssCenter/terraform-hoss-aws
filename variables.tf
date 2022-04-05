
variable "vpc_id" {
  description = "ID of the VPC to use when deploying instances"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet in the VPC to use when deploying a server instance"
  type        = string
}

variable "buckets" {
  description = "The buckets used to back the Hoss server storage"
  type = map(object({
    name       = string
    versioning = bool
  }))
}

variable "server_domain_name" {
  description = "The FQDN for the server"
  type        = string
}

variable "server_ami_id" {
  description = "AMI ID to use when creating the instance"
  type        = string
}

variable "server_instance_type" {
  description = "Instance type to use when deploying the server"
  default     = "t3.large"
  type        = string
}

variable "server_iam_instance_profile" {
  description = "(Optional) IAM instance profile to set. Note, the server does not use this profile directly yet, but loads creds from files. This is primarily used for instance management."
  default     = ""
  type        = string
}

variable "server_private_ip" {
  description = "(Optional) Private IP to assign to the server."
  default     = ""
  type        = string
}

variable "server_volume_size_gb" {
  description = "Size of server root volume in GBs"
  default     = "48"
  type        = string
}

variable "server_key_name" {
  description = "Name of the key file to use when creating the instance"
  type        = string
}

variable "ssh_cidr_block" {
  description = "CIDR block from which SSH access will be allowed"
  type        = string
}

variable "region" {
  description = "Region to use when deploying non-global resources"
  default     = "us-east-1"
  type        = string
}


variable "tags" {
  description = "Additional tags to add to created resources."
  type        = map(string)
  default     = {}
}

variable "tags_instance" {
  description = "Additional tags to add to created instance."
  type        = map(string)
  default     = {}
}


variable "security_group_ids" {
  description = "Additional security groups to add to created instance."
  type        = list(string)
  default     = []
}