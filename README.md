# smartmeteradvisor
Smart Meter Advisor [smartmeteradvisor.uk](https://smartmeteradvisor.uk) website and Wordpress setup using terraform.

## Context
This repo contains terraform HCL files that will spin up a Dockerised Wordpress stack onto a blank and very basic Digital Ocean Ubuntu-based Droplet that has been pre-created.  The Droplet version details are as follows:  
```
smartmeteradvisor.uk / 1 GB Memory / 25 GB Disk / LON1 - Ubuntu 24.10 x64
```
You will need to set up DNS records for your Droplet accordingly.  In this case the nameservers were switched over at the Domain Registrar to Digital Ocean's ones which took a while to propagate through.

## Terraform recipe
There are two primary terraform recipes.  They both do broadly the same thing which is to set up Wordpress with `MySQL` and `nginx` as well as `Caddy` for setting up SSL and Let's Encrypt certificate creation:
* [`main.tf.original`](main.tf.original): Initial version with basic outline and no logging.
* [`main.tf`](main.tf): Advanced version with enhanced logging and support around DNS propagation checks.
Note that Terraform does not take `.tf` files as arguments directly but instead reads all `.tf` files in the working directory so the original receip has been renamed as `main.tf.original`](main.tf.original) to ensure you don't hit that condition.  If you want to run the original recipe you must rename or move [`main.tf`](main.tf).

Here's the command line for executing the other one after doing that:
```
$ terraform destroy -auto-approve && terraform apply -auto-approve
```
A separate private `terraform.tfvars` file contains all the secrets used by both the primary .tf files.  Here's an outline of what it contains per the descriptions in [`variables.tf`](variables.tf):
```
droplet_ip          = "<IP address of Droplet>"
private_key_path    = "<path to private SSH key for accessing Droplet>"
wp_database         = "<name of Wordpress MySQL database>"
wp_user             = "<username for accessing database>"
wp_password         = "<password for accessing database>"
mysql_root_password = "<root password for MySQL>"  # Use a different secure password
domain_name         = "<domain name>"
email               = "<email for domain owner>"
```

## Next Steps
Add Cloudflare to the primary terraform recipe.
