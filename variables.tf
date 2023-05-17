variable "app" {
  type        = string
  description = "contains the application name"
  default     = "ecs"
}

variable "url" {
  type        = string
  description = "points to the route53 dns name that will forward to elb"
  default     = "flask.visham.org"
}

variable "container_cpu" {
  type        = number
  description = "cpu consumed by each ecs container"
}

variable "desired_count" {
  type        = number
  description = "number of desired ECS containers"
}

variable "container_memory" {
  type        = number
  description = "memory consumed by each ecs container"
}

variable "region" {
  type        = string
  description = "AWS region to deploy the application to"
}

variable "port" {
  type        = number
  description = "port that the flask app servers content at"
}

variable "tag" {
  type        = string
  description = "contains the name of the tag"
}