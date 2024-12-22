# Digital Ocean variables - these are the variables that are used in the main.tf file

variable "droplet_ip" {
  description = "The public IP address of the existing droplet"
}

variable "private_key_path" {
  description = "Path to the private SSH key for accessing the droplet"
}

variable "wp_database" {
  description = "Name of the WordPress database"
  default     = "wp_database"
}

variable "wp_user" {
  description = "WordPress database user"
  default     = "wp_user"
}

variable "wp_password" {
  description = "WordPress database password"
  default     = "secure_password"
}

variable "mysql_root_password" {
  description = "Root password for the MySQL database"
}

variable "domain_name" {
  description = "The domain name for the WordPress site"
}

variable "email" {
  description = "Email address for Let's Encrypt notifications"
}
