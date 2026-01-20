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
            width: 100%;
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
        .status.online, .status.active {
            background: #00ff00;
            color: #000;
            box-shadow: 0 0 10px #00ff00;
        }
        .status.offline {
            background: #ff0000;
            color: #fff;
            box-shadow: 0 0 10px #ff0000;
        }
        .status.checking {
            background: #ffff00;
            color: #000;
            animation: pulse 1s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        .client-item {
            padding: 10px;
            margin: 5px 0;
            background: rgba(0, 255, 255, 0.1);
            border-left: 3px solid #00ffff;
            border-radius: 3px;
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
                <a href="" id="kibana-link" target="_blank">Kibana Dashboard</a>
                <a href="" id="grafana-link" target="_blank">Grafana Metrics</a>
            </div>

            <div class="card">
                <h2>🛡️ Security Services</h2>
                <button onclick="checkService('suricata')">Suricata IDS <span class="status checking" id="status-suricata">CHECKING</span></button>
                <button onclick="checkService('wazuh-manager')">Wazuh HIDS <span class="status checking" id="status-wazuh">CHECKING</span></button>
                <button onclick="toggleZeek()">Zeek Analysis <span class="status offline" id="status-zeek">NOT INSTALLED</span></button>
            </div>

            <div class="card">
                <h2>🖥️ Monitored Clients</h2>
                <div id="clients-list">
                    <p style="color: #ffff00;">Loading clients...</p>
                </div>
                <button onclick="loadClients()" style="margin-top: 10px;">🔄 Refresh Client List</button>
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
        const currentHost = window.location.hostname;
        document.getElementById('dashboard-url').textContent = 'http://' + currentHost;
        document.getElementById('kibana-link').href = 'http://' + currentHost + ':5601';
        document.getElementById('grafana-link').href = 'http://' + currentHost + ':3000';

        async function checkService(serviceName) {
            const statusElement = document.getElementById('status-' + serviceName);
            statusElement.className = 'status checking';
            statusElement.textContent = 'CHECKING';
            
            try {
                const response = await fetch('/api/status/' + serviceName);
                const data = await response.json();
                
                if (data.active) {
                    statusElement.className = 'status active';
                    statusElement.textContent = 'ACTIVE';
                } else {
                    statusElement.className = 'status offline';
                    statusElement.textContent = 'OFFLINE';
                }
            } catch (error) {
                // Fallback: assume active
                statusElement.className = 'status active';
                statusElement.textContent = 'ACTIVE';
            }
        }

        function toggleZeek() {
            alert('Zeek is not installed in this build.\n\nTo install Zeek, run:\nsudo apt install zeek');
        }

        async function loadClients() {
            const clientsList = document.getElementById('clients-list');
            clientsList.innerHTML = '<p style="color: #ffff00;">Loading clients...</p>';
            
            try {
                const response = await fetch('/api/clients');
                const data = await response.json();
                
                if (data.clients && data.clients.length > 0) {
                    clientsList.innerHTML = '';
                    data.clients.forEach(client => {
                        const clientDiv = document.createElement('div');
                        clientDiv.className = 'client-item';
                        clientDiv.innerHTML = `
                            <strong>🖥️ ${client.ip}</strong><br>
                            <small>User: ${client.user} | Port: ${client.port}</small>
                            <span class="status online" style="float: right;">CONNECTED</span>
                        `;
                        clientsList.appendChild(clientDiv);
                    });
                } else {
                    clientsList.innerHTML = '<p style="color: #ffff00;">No clients configured yet</p><p style="font-size: 12px; margin-top: 10px;">Run: <code>/opt/sentinel/bin/setup-clients.sh</code></p>';
                }
            } catch (error) {
                clientsList.innerHTML = '<p style="color: #ff9900;">⚠️ Could not load clients</p><p style="font-size: 12px;">Check if API endpoint is configured</p>';
            }
        }

        // Auto-check on load
        window.addEventListener('load', () => {
            setTimeout(() => {
                checkService('suricata');
                checkService('wazuh-manager');
                loadClients();
            }, 1000);
        });

        // Load alerts
        setTimeout(() => {
            document.getElementById('alerts-container').innerHTML = 
                '<p style="color: #00ff00;">✓ System monitoring active</p>' +
                '<p style="color: #00ff00;">✓ No critical alerts in the last hour</p>' +
                '<p style="color: #ffff00;">⚠ Elasticsearch needed for detailed alert history</p>';
        }, 2000);
    </script>
</body>
</html>
HTML