sudo tee /tmp/fix-dashboard-api.sh > /dev/null << 'FIXSCRIPT'
#!/bin/bash

echo "Fixing Dashboard API and Services..."

# Install fcgiwrap
sudo apt-get update -qq
sudo apt-get install -y fcgiwrap

# Create API directory
sudo mkdir -p /opt/sentinel/api

# Create status API
sudo tee /opt/sentinel/api/status.sh > /dev/null << 'STATUSAPI'
#!/bin/bash
echo "Content-Type: application/json"
echo ""
SERVICE=$(echo "$REQUEST_URI" | sed 's/.*\/status\/\([^?]*\).*/\1/')
if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
    echo '{"service":"'$SERVICE'","active":true}'
else
    echo '{"service":"'$SERVICE'","active":false}'
fi
STATUSAPI

# Create clients API
sudo tee /opt/sentinel/api/clients.sh > /dev/null << 'CLIENTSAPI'
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
        if [ "$FIRST" = false ]; then echo ","; fi
        FIRST=false
        echo '{"ip":"'$CLIENT_IP'","user":"'$SSH_USER'","port":"'${SSH_PORT:-22}'"}'
    fi
done
echo ']}'
CLIENTSAPI

sudo chmod +x /opt/sentinel/api/*.sh

# Update Nginx
sudo tee /etc/nginx/sites-available/sentinel > /dev/null << 'NGINXCONF'
server {
    listen 80 default_server;
    server_name _;
    location / {
        root /opt/sentinel/dashboard;
        index index.html;
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
NGINXCONF

# Fix Wazuh
sudo mkdir -p /var/ossec/logs /var/ossec/queue /var/ossec/var
sudo chown -R wazuh:wazuh /var/ossec/logs /var/ossec/queue /var/ossec/var 2>/dev/null
sudo chmod -R 770 /var/ossec/logs /var/ossec/queue /var/ossec/var 2>/dev/null
sudo rm -f /var/ossec/var/*.lock 2>/dev/null

# Restart everything
sudo systemctl restart fcgiwrap
sudo systemctl restart nginx
sudo systemctl restart wazuh-manager

echo "Done! Refresh your dashboard"
FIXSCRIPT

chmod +x /tmp/fix-dashboard-api.sh
sudo /tmp/fix-dashboard-api.sh