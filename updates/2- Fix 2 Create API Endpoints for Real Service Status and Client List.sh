# Create a simple PHP or Python API backend
# For simplicity, let's use a bash CGI script with Nginx

sudo mkdir -p /opt/sentinel/api

# Create service status API
sudo tee /opt/sentinel/api/status.sh > /dev/null << 'SCRIPT'
#!/bin/bash

echo "Content-Type: application/json"
echo ""

# Get service name from query string
SERVICE=$(echo "$QUERY_STRING" | sed 's/.*service=\([^&]*\).*/\1/')

if [ -z "$SERVICE" ]; then
    SERVICE=$(echo "$REQUEST_URI" | sed 's/.*\/status\/\([^?]*\).*/\1/')
fi

# Check if service is active
if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
    echo '{"service":"'$SERVICE'","active":true,"status":"running"}'
else
    echo '{"service":"'$SERVICE'","active":false,"status":"stopped"}'
fi
SCRIPT

sudo chmod +x /opt/sentinel/api/status.sh

# Create clients list API
sudo tee /opt/sentinel/api/clients.sh > /dev/null << 'SCRIPT'
#!/bin/bash

echo "Content-Type: application/json"
echo ""

CLIENTS_DIR="/opt/sentinel/config/clients"

if [ ! -d "$CLIENTS_DIR" ] || [ -z "$(ls -A $CLIENTS_DIR 2>/dev/null)" ]; then
    echo '{"clients":[]}'
    exit 0
fi

echo '{"clients":['

FIRST=true
for conf in "$CLIENTS_DIR"/*.conf; do
    if [ -f "$conf" ]; then
        source "$conf"
        
        if [ "$FIRST" = false ]; then
            echo ","
        fi
        FIRST=false
        
        echo '{"ip":"'$CLIENT_IP'","user":"'$SSH_USER'","port":"'${SSH_PORT:-22}'","auth":"'$AUTH_METHOD'"}'
    fi
done

echo ']}'
SCRIPT

sudo chmod +x /opt/sentinel/api/clients.sh

# Update Nginx configuration to handle API calls
sudo tee /etc/nginx/sites-available/sentinel > /dev/null << 'EOF'
server {
    listen 80 default_server;
    server_name _;
    
    location / {
        root /opt/sentinel/dashboard;
        index index.html;
        try_files $uri $uri/ /index.html;
    }
    
    location /api/status {
        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /opt/sentinel/api/status.sh;
    }
    
    location ~ ^/api/status/(.+)$ {
        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /opt/sentinel/api/status.sh;
        fastcgi_param REQUEST_URI $request_uri;
    }
    
    location /api/clients {
        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /opt/sentinel/api/clients.sh;
    }
}
EOF

# Install fcgiwrap for CGI support
sudo apt-get install -y fcgiwrap

# Restart services
sudo systemctl restart fcgiwrap
sudo systemctl restart nginx