variable "cidr" {
  type        = string
  description = ""
}

variable "region" {
  type        = string
  description = ""
}

variable "profile" {
  type        = string
  description = ""
}

variable "destination_cidr_block" {
  type        = string
  description = ""
}

variable "subnet_count" {
  type        = number
  description = ""
}

variable "owners" {
  type        = string
  description = ""
}

variable "db_password" {
  description = ""
  sensitive   = true
}

data "aws_availability_zones" "azs" {}

variable "hostedzoneid" {
  type        = string
  description = ""
}

variable "hostzonename" {
  type        = string
  description = ""
}