# Save the script
sudo nano /tmp/sentinel-fix.sh
# Paste the entire script above, then save (Ctrl+X, Y, Enter)

# Make it executable
sudo chmod +x /tmp/sentinel-fix.sh

# Run 
sudo /tmp/sentinel-fix.sh

# ===================================================

# step :1 java fix for elastic

sudo apt update
sudo apt install -y openjdk-17-jre-headless
sudo update-alternatives --config java   # Select the Java 17 option if multiple
java -version   # Verify again
sudo systemctl restart elasticsearch
sleep 10
systemctl status elasticsearch -l


# Step 2: Force vm.max_map_count (most common silent killer)

sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-elasticsearch.conf
sudo sysctl -p /etc/sysctl.d/99-elasticsearch.conf
sudo systemctl restart elasticsearch
sleep 10
systemctl status elasticsearch -l


# Step 3: Lower heap to minimal (VM live mode has tight memory)

sudo tee /etc/elasticsearch/jvm.options.d/heap.options >/dev/null <<EOF
-Xms128m
-Xmx512m
EOF
sudo systemctl restart elasticsearch
sleep 15
systemctl status elasticsearch -l


# Step 4: Check for ANY log now (after restarts above)

sudo ls -la /var/log/elasticsearch/   # See if sentinel-cluster.log appeared
sudo tail -n 50 /var/log/elasticsearch/sentinel-cluster.log 2>/dev/null || echo "Still no log file"
sudo journalctl -u elasticsearch -n 80 --no-pager | grep -i -e error -e exception -e failed -e bootstrap

# Step 5: Nuclear reset if still dead (wipes old state — safe in live ISO)

sudo systemctl stop elasticsearch
sudo rm -rf /var/lib/elasticsearch/* /var/log/elasticsearch/*
sudo systemctl start elasticsearch
sleep 30
systemctl status elasticsearch -l
curl http://localhost:9200   # Should return JSON if alive


# ========================================= 

# For Wazuh (most likely permissions or lock file):

# Reset ownership (Wazuh uses root:wazuh on top level, wazuh:wazuh on runtime dirs)
sudo chown -R root:wazuh /var/ossec
sudo chown -R wazuh:wazuh /var/ossec/logs /var/ossec/queue /var/ossec/var /var/ossec/etc/shared /var/ossec/active-response
sudo chmod -R 750 /var/ossec
sudo chmod -R 770 /var/ossec/logs /var/ossec/queue /var/ossec/var /var/ossec/etc/shared

# Remove stale locks (common in live boots)
sudo rm -f /var/ossec/var/*.lock /var/ossec/queue/ossec/*.lock

# Start and check
sudo systemctl restart wazuh-manager
sleep 10
systemctl status wazuh-manager -l --no-pager



# After both — run:

systemctl status elasticsearch wazuh-manager suricata kibana grafana-server nginx -l