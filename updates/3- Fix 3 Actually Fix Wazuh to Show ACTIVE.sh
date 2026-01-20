# Fix Wazuh permissions and configuration
sudo mkdir -p /var/ossec/logs /var/ossec/queue /var/ossec/var /var/ossec/etc/shared

# Create the Wazuh group if it doesn't exist
sudo groupadd ossec 2>/dev/null || true
sudo groupadd wazuh 2>/dev/null || true

# Fix ownership
sudo chown -R root:ossec /var/ossec 2>/dev/null
sudo chown -R wazuh:wazuh /var/ossec/logs /var/ossec/queue /var/ossec/var 2>/dev/null

# Fix permissions
sudo chmod -R 750 /var/ossec
sudo chmod -R 770 /var/ossec/logs /var/ossec/queue /var/ossec/var 2>/dev/null

# Remove locks
sudo rm -f /var/ossec/var/*.lock /var/ossec/queue/ossec/*.lock 2>/dev/null

# Start Wazuh
sudo systemctl restart wazuh-manager
sleep 5

# Check status
systemctl status wazuh-manager