# Main Terraform file
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
      "echo '=== 1. System Status Check ==='",
      "apt update",
      "DEBIAN_FRONTEND=noninteractive apt install -y net-tools curl wget lsof",
      
      "uname -a",
      "df -h",
      "free -h",
      "ps aux | grep -E 'apache|nginx|caddy'",
      "netstat -tulpn | grep -E ':80|:443'",
      
      # Docker status check
      "echo '=== 2. Docker Status ==='",
      "docker info",
      "docker ps -a",
      "docker network ls",
      
      # Network and DNS verification
      "echo '=== 3. Network and DNS Checks ==='",
      "echo 'Server IP address:'",
      "SERVER_IP=$(curl -s ifconfig.me)",
      "echo $SERVER_IP",
      
      "echo 'DNS Resolution for ${var.domain_name}:'",
      "host ${var.domain_name} || echo 'DNS not yet propagated'",
      
      "echo 'Detailed DNS Information:'",
      "dig +short ${var.domain_name}",
      
      "echo 'Checking DNS propagation:'",
      "DOMAIN_IP=$(dig +short ${var.domain_name} | head -n1)",
      "echo 'Domain resolves to: '$DOMAIN_IP",
      
      "echo 'Verifying DNS matches server:'",
      "if [ \"$SERVER_IP\" = \"$DOMAIN_IP\" ]; then",
      "    echo 'DNS is correctly configured!'",
      "else",
      "    echo 'WARNING: DNS does not match server IP'",
      "    echo 'Expected: '$SERVER_IP",
      "    echo 'Found: '$DOMAIN_IP",
      "fi",
      
      "echo 'Testing domain connectivity:'",
      "curl -sI -H 'Host: ${var.domain_name}' http://localhost:8080 | head -n1",
      
      # Port availability check
      "echo '=== 4. Port Checks ==='",
      "echo 'Checking port availability:'",
      "netstat -tulpn | grep -E ':80|:443|:8080' || echo 'No ports in use'",
      "echo 'Testing with ss command:'",
      "ss -tulpn | grep -E ':80|:443|:8080' || echo 'No ports in use'",
      "echo 'Testing with lsof:'",
      "lsof -i :80 || echo 'Port 80 free'",
      "lsof -i :443 || echo 'Port 443 free'",
      "lsof -i :8080 || echo 'Port 8080 free'",
      
      # Clean up existing services
      "echo '=== 5. Cleaning Up Services ==='",
      "echo 'Stopping web servers (if they exist)...'",
      "systemctl stop apache2 2>/dev/null || echo 'Apache not installed'",
      "systemctl stop nginx 2>/dev/null || echo 'Nginx not installed'",
      "systemctl stop caddy 2>/dev/null || echo 'Caddy not running'",
      
      "echo 'Cleaning up Docker resources...'",
      "docker rm -f mysql wordpress 2>/dev/null || echo 'No containers to remove'",
      "docker network rm wordpress_net 2>/dev/null || echo 'No network to remove'",
      
      # Docker setup
      "echo '=== 6. Setting Up Docker ==='",
      "docker network create wordpress_net",
      "docker pull mysql:5.7",
      "docker pull wordpress:latest",
      
      # Start MySQL with debug
      "echo '=== 7. Starting MySQL ==='",
      "docker run --name mysql --network wordpress_net --restart unless-stopped -e MYSQL_ROOT_PASSWORD=${var.wp_password}_root -e MYSQL_DATABASE=${var.wp_database} -e MYSQL_USER=${var.wp_user} -e MYSQL_PASSWORD=${var.wp_password} -v /var/lib/mysql:/var/lib/mysql -d mysql:5.7",
      "sleep 30",
      "docker logs mysql",
      
      # Start WordPress with debug
      "echo '=== 8. Starting WordPress ==='",
      # OLD "docker run --name wordpress --network wordpress_net --restart unless-stopped -e WORDPRESS_DB_HOST=mysql -e WORDPRESS_DB_USER=${var.wp_user} -e WORDPRESS_DB_PASSWORD=${var.wp_password} -e WORDPRESS_DB_NAME=${var.wp_database} -e WORDPRESS_CONFIG_EXTRA='define(\"WP_HOME\",\"https://${var.domain_name}\"); define(\"WP_SITEURL\",\"https://${var.domain_name}\");' -p 8080:80 -v /var/www/html:/var/www/html -d wordpress:latest",
      "docker run --name wordpress --network wordpress_net --restart unless-stopped -e WORDPRESS_DB_HOST=mysql -e WORDPRESS_DB_USER=${var.wp_user} -e WORDPRESS_DB_PASSWORD=${var.wp_password} -e WORDPRESS_DB_NAME=${var.wp_database} -e WORDPRESS_CONFIG_EXTRA='define(\"WP_HOME\",\"https://${var.domain_name}\"); define(\"WP_SITEURL\",\"https://${var.domain_name}\");' -p 8080:80 -v /var/www/html:/var/www/html -d wordpress:latest",
      "sleep 10",
      "docker logs wordpress",

      # DNS propagation check
      "echo '=== 9. DNS Propagation Check ==='",
      "echo 'Checking DNS propagation...'",
      "EXPECTED_IP=$(curl -s ifconfig.me)",
      "echo 'Server IP: '$EXPECTED_IP",
      
      "echo 'Waiting for DNS propagation (up to 1 minute)...'",
      "for i in {1..6}; do",
      "    DOMAIN_IP=$(dig +short ${var.domain_name} | head -n1)",
      "    echo 'Current DNS resolution: '$DOMAIN_IP",
      "    if [ \"$EXPECTED_IP\" = \"$DOMAIN_IP\" ]; then",
      "        echo 'DNS has propagated successfully!'",
      "        break",
      "    fi",
      "    echo 'Waiting for DNS propagation... attempt '$i' of 6'",
      "    sleep 10",
      "done",
      
      "if [ \"$EXPECTED_IP\" != \"$DOMAIN_IP\" ]; then",
      "    echo 'WARNING: DNS has not fully propagated after 1 minute'",
      "    echo 'Expected IP: '$EXPECTED_IP",
      "    echo 'Current IP: '$DOMAIN_IP",
      "    echo 'Continuing anyway...'",
      "fi",
      
      # Configure Caddy with advanced SSL options
      "echo '=== 10. Configuring Caddy ==='",
      <<-EOT
cat > /etc/caddy/Caddyfile << 'EOF'
{
    debug
    admin off
    log {
        output stderr
        format console
        level INFO
    }
    # Global SSL settings
    email ${var.email}  # For Let's Encrypt notifications
    default_sni ${var.domain_name}
}

# Handle both domain and IP access
(common) {
    reverse_proxy localhost:8080 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
    }
}

# Domain configuration with enhanced SSL
${var.domain_name} {
    import common
    
    # SSL/TLS Configuration
    tls {
        protocols tls1.2 tls1.3
        curves x25519
        ciphers TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
    }

    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
}

# IP fallback configuration - no automatic HTTPS
:80 {
    import common
}
EOF
EOT
      ,
      
      # Start Caddy with detailed error logging
      "echo '=== 11. Starting Caddy ==='",
      "systemctl stop caddy || true",
      "sleep 5",
      
      # Test Caddy configuration
      "echo 'Testing Caddy configuration...'",
      "caddy validate --config /etc/caddy/Caddyfile",
      
      # Try running Caddy directly to see errors
      "echo 'Testing Caddy directly...'",
      "caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &",
      "sleep 10",
      "pkill caddy",
      
      # Start Caddy service with full logging
      "echo 'Starting Caddy service...'",
      "systemctl restart caddy",
      "sleep 5",
      "systemctl status caddy --no-pager -l",
      "journalctl -xe --no-pager -u caddy",
      
      # Check if Caddy is actually running
      "echo 'Verifying Caddy status:'",
      "ps aux | grep caddy",
      "netstat -tulpn | grep -E ':80|:443'",
      
      # Final verification
      "echo '=== 12. Final Verification ==='",
      "echo 'Domain configuration:'",
      "dig +short ${var.domain_name}",
      
      "echo 'Certificate status:'",
      "curl -sI https://${var.domain_name} 2>&1 | grep -i \"SSL\\|TLS\\|certificate\" || echo 'Certificate not yet ready'",
      
      "echo 'HTTP accessibility:'",
      "curl -sI http://${var.domain_name} | grep -i 'HTTP/' || echo 'HTTP connection failed'",
      
      "echo '=== 13. Setup Complete! ==='",
    ]
  }
}

output "wordpress_url" {
  value = "https://${var.domain_name}"
  description = "The URL of the WordPress installation (HTTPS)"
}
