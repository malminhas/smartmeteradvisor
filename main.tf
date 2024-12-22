# Main Terraform file
# Execute the following command to run this file:
# $ terraform apply

provider "null" {
  # Null provider for executing remote commands
}

resource "null_resource" "wordpress_setup" {
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "root"
      private_key = file(var.private_key_path)
      host        = var.droplet_ip
    }

    inline = [
      # Update and install required packages
      "apt update",
      
      # Install Caddy via official debian repository
      "apt install -y debian-keyring debian-archive-keyring apt-transport-https",
      "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg",
      "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list",
      "apt update && apt install -y caddy docker.io",

      # Clean up any existing containers and networks
      "docker rm -f mysql wordpress || true",
      "docker network rm wordpress_net || true",

      # Create Docker network
      "docker network create wordpress_net",

      # Create directories for persistent storage
      "mkdir -p /var/lib/mysql /var/www/html",

      # Pull required Docker images
      "docker pull mysql:5.7",
      "docker pull wordpress:latest",

      # Start MySQL with proper restart policy and security
      "docker run --name mysql --network wordpress_net --restart unless-stopped -e MYSQL_ROOT_PASSWORD=${var.wp_password}_root -e MYSQL_DATABASE=${var.wp_database} -e MYSQL_USER=${var.wp_user} -e MYSQL_PASSWORD=${var.wp_password} -v /var/lib/mysql:/var/lib/mysql -d mysql:5.7",

      # Wait for MySQL to be ready
      "sleep 30",

      # Start WordPress with proper restart policy
      "docker run --name wordpress --network wordpress_net --restart unless-stopped -e WORDPRESS_DB_HOST=mysql -e WORDPRESS_DB_USER=${var.wp_user} -e WORDPRESS_DB_PASSWORD=${var.wp_password} -e WORDPRESS_DB_NAME=${var.wp_database} -p 8080:80 -v /var/www/html:/var/www/html -d wordpress:latest",

      # Configure Caddy
      <<-EOT
cat > /etc/caddy/Caddyfile << 'EOF'
${var.domain_name} {
    reverse_proxy localhost:8080
    encode gzip
    header {
        # Security headers
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' https: data:;"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
    
    # Handle large file uploads
    request_body {
        max_size 64MB
    }
    
    # Basic rate limiting
    rate_limit {
        requests 10 10s
    }
}
EOF
EOT
      ,

      # Restart Caddy to apply configuration
      "systemctl restart caddy",

      # Add basic firewall rules
      "ufw allow 80,443/tcp",
      "ufw allow OpenSSH",
      "ufw --force enable",

      # Set up log rotation
      <<-EOT
cat > /etc/logrotate.d/docker << 'EOF'
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    size=100M
    missingok
    delaycompress
    copytruncate
}
EOF
EOT
    ]
  }
}

output "wordpress_url" {
  value = "https://${var.domain_name}"
  description = "The URL of the WordPress installation (HTTPS)"
}