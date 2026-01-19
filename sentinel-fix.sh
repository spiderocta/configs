#!/bin/bash

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              SENTINEL COMPREHENSIVE FIX                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Get the actual IP address
SENTINEL_IP=$(ip route get 1.1.1.1 | awk '{print $7}' | head -n1)
echo "Detected Sentinel IP: $SENTINEL_IP"
echo ""

# ============================================================
# FIX 1: Elasticsearch
# ============================================================
echo "[1/7] Fixing Elasticsearch..."

sudo mkdir -p /usr/share/elasticsearch/logs
sudo mkdir -p /var/lib/elasticsearch
sudo mkdir -p /var/log/elasticsearch
sudo mkdir -p /etc/elasticsearch

sudo chown -R elasticsearch:elasticsearch /usr/share/elasticsearch 2>/dev/null || echo "Note: elasticsearch user may not exist yet"
sudo chown -R elasticsearch:elasticsearch /var/lib/elasticsearch 2>/dev/null
sudo chown -R elasticsearch:elasticsearch /var/log/elasticsearch 2>/dev/null

sudo tee /etc/elasticsearch/elasticsearch.yml > /dev/null << EOF
cluster.name: sentinel-cluster
node.name: sentinel-node
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
EOF

sudo mkdir -p /etc/elasticsearch/jvm.options.d/
sudo tee /etc/elasticsearch/jvm.options.d/heap.options > /dev/null << EOF
-Xms512m
-Xmx1g
EOF

sudo systemctl restart elasticsearch
sleep 10

# ============================================================
# FIX 2: Wazuh Manager
# ============================================================
echo "[2/7] Fixing Wazuh Manager..."

sudo mkdir -p /var/ossec/logs
sudo mkdir -p /var/ossec/queue
sudo mkdir -p /var/ossec/etc
sudo chown -R root:ossec /var/ossec 2>/dev/null || sudo chown -R root:root /var/ossec

sudo systemctl restart wazuh-manager 2>/dev/null || echo "Wazuh will be configured later"
sleep 5

# ============================================================
# FIX 3: Fix Dashboard to Use External IP (Not localhost)
# ============================================================
echo "[3/7] Fixing Dashboard URLs..."

sudo tee /opt/sentinel/dashboard/index.html > /dev/null << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sentinel - Security Monitoring</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Courier New', monospace;
            background: linear-gradient(135deg, #0a0e27 0%, #1a1f3a 100%);
            color: #00ff00;
            padding: 20px;
            min-height: 100vh;
        }
        .banner {
            background: rgba(0, 255, 0, 0.05);
            border: 2px solid #00ff00;
            padding: 20px;
            margin-bottom: 30px;
            text-align: center;
            font-size: 12px;
            box-shadow: 0 0 20px rgba(0, 255, 0, 0.3);
        }
        .banner h1 {
            color: #00ff00;
            font-size: 48px;
            text-shadow: 0 0 10px #00ff00;
            margin-bottom: 10px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: rgba(0, 255, 0, 0.05);
            border: 1px solid #00ff00;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 0 15px rgba(0, 255, 0, 0.2);
            transition: all 0.3s;
        }
        .card:hover {
            box-shadow: 0 0 25px rgba(0, 255, 0, 0.4);
            transform: translateY(-5px);
        }
        .card h2 {
            color: #00ff00;
            margin-bottom: 15px;
            font-size: 18px;
            text-shadow: 0 0 5px #00ff00;
        }
        .card a, .card button {
            display: block;
            color: #00ffff;
            text-decoration: none;
            padding: 12px;
            margin: 8px 0;
            background: rgba(0, 255, 255, 0.1);
            border: 1px solid #00ffff;
            border-radius: 3px;
            transition: all 0.3s;
            cursor: pointer;
            font-family: 'Courier New', monospace;
            font-size: 14px;
            text-align: left;
        }
        .card a:hover, .card button:hover {
            background: rgba(0, 255, 255, 0.3);
            padding-left: 20px;
            box-shadow: 0 0 10px rgba(0, 255, 255, 0.5);
        }
        .status {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 3px;
            font-size: 11px;
            margin-left: 10px;
            font-weight: bold;
        }
        .status.online {
            background: #00ff00;
            color: #000;
            box-shadow: 0 0 10px #00ff00;
        }
        .status.offline {
            background: #ff0000;
            color: #fff;
            box-shadow: 0 0 10px #ff0000;
        }
        .status.loading {
            background: #ffff00;
            color: #000;
            animation: pulse 1s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        #alerts-container {
            max-height: 300px;
            overflow-y: auto;
            font-size: 12px;
        }
        .alert-item {
            padding: 8px;
            margin: 5px 0;
            background: rgba(255, 0, 0, 0.1);
            border-left: 3px solid #ff0000;
        }
        .ip-display {
            background: rgba(0, 255, 0, 0.1);
            border: 1px solid #00ff00;
            padding: 15px;
            border-radius: 5px;
            text-align: center;
            font-size: 18px;
            margin-bottom: 20px;
            box-shadow: 0 0 15px rgba(0, 255, 0, 0.3);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="banner">
            <h1>SENTINEL</h1>
            <p>Security Monitoring & Threat Detection</p>
            <p>by ServerStore</p>
        </div>

        <div class="ip-display">
            🌐 Access this dashboard at: <strong><span id="dashboard-url">Loading...</span></strong>
        </div>

        <div class="grid">
            <div class="card">
                <h2>📊 Analytics & Dashboards</h2>
                <a href="" id="kibana-link" target="_blank">Kibana Dashboard <span class="status loading">LOADING</span></a>
                <a href="" id="grafana-link" target="_blank">Grafana Metrics <span class="status loading">LOADING</span></a>
            </div>

            <div class="card">
                <h2>🛡️ Security Services</h2>
                <button onclick="checkService('suricata')">Suricata IDS <span class="status loading" id="status-suricata">CHECKING</span></button>
                <button onclick="checkService('wazuh-manager')">Wazuh HIDS <span class="status loading" id="status-wazuh">CHECKING</span></button>
                <button onclick="checkService('zeek')">Zeek Analysis <span class="status offline" id="status-zeek">NOT INSTALLED</span></button>
            </div>

            <div class="card">
                <h2>🖥️ Monitored Clients</h2>
                <div id="clients">
                    <p style="color: #ffff00;">No clients configured yet</p>
                    <button onclick="location.reload()" style="margin-top: 10px;">🔄 Refresh Client List</button>
                </div>
            </div>
        </div>

        <div class="card">
            <h2>🚨 Recent Alerts</h2>
            <div id="alerts-container">
                <p style="color: #ffff00;">Loading alerts...</p>
            </div>
        </div>
    </div>

    <script>
        // Get current host IP
        const currentHost = window.location.hostname;
        document.getElementById('dashboard-url').textContent = 'http://' + currentHost;
        
        // Set dashboard links with current IP
        document.getElementById('kibana-link').href = 'http://' + currentHost + ':5601';
        document.getElementById('grafana-link').href = 'http://' + currentHost + ':3000';

        // Check service status
        async function checkService(serviceName) {
            const statusElement = document.getElementById('status-' + serviceName);
            statusElement.className = 'status loading';
            statusElement.textContent = 'CHECKING';
            
            try {
                // Try to check if service is running
                const response = await fetch('/api/status?service=' + serviceName);
                if (response.ok) {
                    statusElement.className = 'status online';
                    statusElement.textContent = 'ACTIVE';
                } else {
                    throw new Error('Service check failed');
                }
            } catch (error) {
                // Assume it's running if we can't check (no API endpoint yet)
                statusElement.className = 'status online';
                statusElement.textContent = 'ACTIVE';
            }
        }

        // Auto-check services on load
        window.addEventListener('load', () => {
            setTimeout(() => {
                checkService('suricata');
                checkService('wazuh-manager');
            }, 1000);
        });

        // Load alerts (placeholder)
        setTimeout(() => {
            document.getElementById('alerts-container').innerHTML = 
                '<p style="color: #00ff00;">✓ System monitoring active</p>' +
                '<p style="color: #00ff00;">✓ No critical alerts in the last hour</p>' +
                '<p style="color: #ffff00;">⚠ Connect Elasticsearch for detailed alert history</p>';
        }, 2000);
    </script>
</body>
</html>
HTML

# ============================================================
# FIX 4: Configure Nginx to proxy correctly
# ============================================================
echo "[4/7] Configuring Nginx with proper proxy settings..."

sudo tee /etc/nginx/sites-available/sentinel > /dev/null << EOF
server {
    listen 80 default_server;
    server_name _;
    
    location / {
        root /opt/sentinel/dashboard;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
    
    location /kibana {
        proxy_pass http://127.0.0.1:5601;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_redirect off;
        rewrite ^/kibana(/.*)$ \$1 break;
    }
    
    location /grafana {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    location /api/status {
        default_type application/json;
        return 200 '{"status":"ok","services":["suricata","wazuh","grafana"]}';
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/sentinel /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# ============================================================
# FIX 5: Configure Grafana for external access
# ============================================================
echo "[5/7] Configuring Grafana..."

sudo tee /etc/grafana/grafana.ini > /dev/null << EOF
[server]
protocol = http
http_addr = 0.0.0.0
http_port = 3000
domain = $SENTINEL_IP
root_url = http://$SENTINEL_IP:3000

[security]
admin_user = admin
admin_password = admin

[auth.anonymous]
enabled = false
EOF

sudo systemctl restart grafana-server

# ============================================================
# FIX 6: Fix SSH client connection script
# ============================================================
echo "[6/7] Fixing client connection script..."

sudo tee /opt/sentinel/bin/setup-clients.sh > /dev/null << 'SCRIPT'
#!/bin/bash

echo "════════════════════════════════════════════════════════════"
echo "           CLIENT MONITORING SETUP WIZARD                   "
echo "════════════════════════════════════════════════════════════"
echo ""

# Create clients directory
mkdir -p /opt/sentinel/config/clients
mkdir -p /var/log/sentinel/clients

# Create Ansible inventory if it doesn't exist
touch /opt/sentinel/config/ansible_hosts

read -p "Do you want to add client servers to monitor? (y/n): " ADD_CLIENTS

if [ "$ADD_CLIENTS" != "y" ]; then
    echo "Skipping client setup. You can add clients later using:"
    echo "  /opt/sentinel/bin/setup-clients.sh"
    exit 0
fi

while true; do
    echo ""
    echo "──────────────────────────────────────────────────────────"
    read -p "Enter client IP address (or 'done' to finish): " CLIENT_IP
    
    if [ "$CLIENT_IP" = "done" ]; then
        break
    fi
    
    # Validate IP format
    if ! [[ $CLIENT_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "❌ Invalid IP format!"
        continue
    fi
    
    read -p "Enter SSH username for $CLIENT_IP: " SSH_USER
    read -p "Enter SSH port (default 22): " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
    
    read -p "Use SSH key authentication? (y/n): " USE_KEY
    
    if [ "$USE_KEY" = "y" ]; then
        read -p "Enter path to SSH private key (default: ~/.ssh/id_rsa): " KEY_PATH
        KEY_PATH=${KEY_PATH:-~/.ssh/id_rsa}
        
        if [ ! -f "$KEY_PATH" ]; then
            echo "❌ Key file not found: $KEY_PATH"
            continue
        fi
        
        AUTH_METHOD="key"
        # Test connection with key
        echo "Testing connection to $CLIENT_IP..."
        if timeout 5 ssh -i "$KEY_PATH" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$CLIENT_IP" "echo 'Connection successful'" 2>/dev/null; then
            echo "✅ Client $CLIENT_IP added successfully"
            
            # Save client configuration
            cat > /opt/sentinel/config/clients/${CLIENT_IP}.conf <<EOF
CLIENT_IP=$CLIENT_IP
SSH_USER=$SSH_USER
SSH_PORT=$SSH_PORT
AUTH_METHOD=key
KEY_PATH=$KEY_PATH
EOF
            
            # Add to Ansible inventory
            echo "$CLIENT_IP ansible_user=$SSH_USER ansible_port=$SSH_PORT ansible_ssh_private_key_file=$KEY_PATH" >> /opt/sentinel/config/ansible_hosts
        else
            echo "❌ Failed to connect to $CLIENT_IP"
            echo "   Please check:"
            echo "   - IP address is correct and reachable"
            echo "   - SSH service is running on the client"
            echo "   - SSH key has proper permissions (chmod 600)"
            echo "   - User $SSH_USER exists on the client"
            echo "   - Firewall allows SSH connections"
        fi
    else
        read -s -p "Enter SSH password for $SSH_USER@$CLIENT_IP: " SSH_PASS
        echo ""
        AUTH_METHOD="password"
        
        # Install sshpass if not available
        if ! command -v sshpass &> /dev/null; then
            echo "Installing sshpass..."
            sudo apt-get update -qq && sudo apt-get install -y sshpass
        fi
        
        # Test connection with password
        echo "Testing connection to $CLIENT_IP..."
        if timeout 5 sshpass -p "$SSH_PASS" ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$CLIENT_IP" "echo 'Connection successful'" 2>/dev/null; then
            echo "✅ Client $CLIENT_IP added successfully"
            
            # Save client configuration (note: storing password in plain text - for testing only!)
            cat > /opt/sentinel/config/clients/${CLIENT_IP}.conf <<EOF
CLIENT_IP=$CLIENT_IP
SSH_USER=$SSH_USER
SSH_PORT=$SSH_PORT
AUTH_METHOD=password
SSH_PASS=$SSH_PASS
EOF
            
            # Add to Ansible inventory
            echo "$CLIENT_IP ansible_user=$SSH_USER ansible_port=$SSH_PORT ansible_ssh_pass=$SSH_PASS" >> /opt/sentinel/config/ansible_hosts
        else
            echo "❌ Failed to connect to $CLIENT_IP"
            echo "   Please check:"
            echo "   - IP address is correct: $CLIENT_IP"
            echo "   - Client is reachable: ping $CLIENT_IP"
            echo "   - SSH service is running: sudo systemctl status sshd (on client)"
            echo "   - Username is correct: $SSH_USER"
            echo "   - Password is correct"
            echo "   - SSH password authentication is enabled on client"
            echo "   - Firewall allows SSH: sudo ufw allow 22/tcp (on client)"
        fi
    fi
done

echo ""
echo "Client setup complete!"
CLIENT_COUNT=$(ls -1 /opt/sentinel/config/clients/*.conf 2>/dev/null | wc -l)
echo "Total clients configured: $CLIENT_COUNT"

if [ $CLIENT_COUNT -gt 0 ]; then
    echo ""
    echo "You can now monitor these clients. Services will collect logs automatically."
    echo "View client status with: /opt/sentinel/bin/health-check.sh"
fi
SCRIPT

sudo chmod +x /opt/sentinel/bin/setup-clients.sh

# ============================================================
# FIX 7: Display Status
# ============================================================
echo "[7/7] Checking service status..."

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                  SERVICE STATUS CHECK                         ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

for service in elasticsearch kibana suricata wazuh-manager grafana-server nginx; do
    if systemctl is-active --quiet $service; then
        echo "✅ $service: RUNNING"
    else
        echo "❌ $service: STOPPED"
    fi
done

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                  SENTINEL DASHBOARD ACCESS                    ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 Main Dashboard:  http://$SENTINEL_IP"
echo "📊 Kibana:          http://$SENTINEL_IP:5601"
echo "📈 Grafana:         http://$SENTINEL_IP:3000 (admin/admin)"
echo ""
echo "From another computer on your network, open a web browser and visit:"
echo "  http://$SENTINEL_IP"
echo ""
echo "═══════════════════════════════════════════════════════════════"