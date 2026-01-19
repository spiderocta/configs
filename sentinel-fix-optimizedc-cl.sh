# ============================================================
# PRE-INSTALL JAVA 17
# ============================================================
echo "Installing Java 17 in the ISO..."
apt update
apt install -y openjdk-17-jre-headless
update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
java -version

# ============================================================
# SET vm.max_map_count PERMANENTLY
# ============================================================
echo "vm.max_map_count=262144" > /etc/sysctl.d/99-elasticsearch.conf

# ============================================================
# PRE-CONFIGURE ELASTICSEARCH FOR 4GB RAM
# ============================================================
mkdir -p /etc/elasticsearch/jvm.options.d
cat > /etc/elasticsearch/jvm.options.d/heap.options <<EOF
-Xms256m
-Xmx512m
EOF

cat > /etc/elasticsearch/elasticsearch.yml <<EOF
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
indices.memory.index_buffer_size: 10%
indices.queries.cache.size: 5%
indices.fielddata.cache.size: 10%
EOF

# ============================================================
# CONFIGURE KIBANA FOR LOW MEMORY
# ============================================================
cat > /etc/kibana/node.options <<EOF
--max-old-space-size=512
EOF

# ============================================================
# CONFIGURE LOGSTASH FOR LOW MEMORY
# ============================================================
mkdir -p /etc/logstash/jvm.options.d
cat > /etc/logstash/jvm.options.d/heap.options <<EOF
-Xms128m
-Xmx256m
EOF

# ============================================================
# CREATE COMPREHENSIVE BOOT SCRIPT
# ============================================================
cat > /opt/sentinel/bin/first-boot-setup.sh << 'BOOTSCRIPT'
#!/bin/bash

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              SENTINEL FIRST BOOT SETUP                        ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

# Apply sysctl settings
sysctl -w vm.max_map_count=262144

# Create required directories
mkdir -p /usr/share/elasticsearch/logs
mkdir -p /var/lib/elasticsearch
mkdir -p /var/log/elasticsearch
mkdir -p /var/ossec/logs /var/ossec/queue /var/ossec/var

# Fix permissions
chown -R elasticsearch:elasticsearch /usr/share/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch 2>/dev/null
chown -R root:ossec /var/ossec 2>/dev/null || chown -R root:root /var/ossec
chown -R wazuh:wazuh /var/ossec/logs /var/ossec/queue /var/ossec/var 2>/dev/null
chmod -R 750 /var/ossec
chmod -R 770 /var/ossec/logs /var/ossec/queue /var/ossec/var 2>/dev/null

# Remove lock files
rm -f /var/ossec/var/*.lock /var/ossec/queue/ossec/*.lock 2>/dev/null
rm -rf /var/lib/elasticsearch/* 2>/dev/null

# Start services with delays
echo "Starting Elasticsearch..."
systemctl start elasticsearch
sleep 25

echo "Starting other services..."
systemctl start wazuh-manager
systemctl start suricata
systemctl start kibana
systemctl start grafana-server
systemctl start nginx
sleep 10

# Show status
SENTINEL_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -n1)

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                  SENTINEL IS READY!                           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Access from another computer at:"
echo "  🌐 http://$SENTINEL_IP"
echo "  📊 Kibana:  http://$SENTINEL_IP:5601"
echo "  📈 Grafana: http://$SENTINEL_IP:3000 (admin/admin)"
echo ""

touch /var/sentinel-configured
BOOTSCRIPT

chmod +x /opt/sentinel/bin/first-boot-setup.sh

# ============================================================
# UPDATE USER PROFILE
# ============================================================
cat > /home/sentinel/.profile <<'PROFILE'
# Run first boot setup on login
if [ ! -f /var/sentinel-configured ]; then
    sudo /opt/sentinel/bin/first-boot-setup.sh
fi

# Show banner
cat << "BANNER"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║  ███████╗███████╗███╗   ██╗████████╗██╗███╗   ██╗███████╗██╗ ║
║  ██╔════╝██╔════╝████╗  ██║╚══██╔══╝██║████╗  ██║██╔════╝██║ ║
║  ███████╗█████╗  ██╔██╗ ██║   ██║   ██║██╔██╗ ██║█████╗  ██║ ║
║  ╚════██║██╔══╝  ██║╚██╗██║   ██║   ██║██║╚██╗██║██╔══╝  ██║ ║
║  ███████║███████╗██║ ╚████║   ██║   ██║██║ ╚████║███████╗███║ ║
║  ╚══════╝╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚═╝╚═╝  ╚═══╝╚══════╝╚══╝ ║
║                                                               ║
║            Security Monitoring & Threat Detection            ║
║                      by ServerStore                          ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

BANNER

exec bash
PROFILE

# Clean up
apt-get clean
apt-get autoclean
rm -rf /var/cache/apt/archives/*
rm -rf /tmp/*
rm -rf /var/tmp/*

# Exit chroot
exit