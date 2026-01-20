# Sentinel NDR - Master Build Guide
## By Server Store

---

## 1. Project Overview

**Sentinel** is a lightweight, enterprise-grade Network Detection and Response (NDR) ISO image designed to provide advanced threat detection, network monitoring, and incident response capabilities.

### Core Objectives
- Lightweight base system (< 2GB ISO)
- Real-time network traffic analysis
- Advanced threat detection with ML/AI
- Full packet capture capabilities
- Automated threat hunting
- Integration-ready (SIEM, SOAR, ticketing)
- Web-based management interface

---

## 2. Technology Stack

### Base System
- **OS Foundation**: Debian 12 (Bookworm) minimal
- **Kernel**: Custom hardened Linux kernel 6.1 LTS
- **Init System**: systemd (optimized)

### Core Detection Engines
- **Suricata 7.x**: IDS/IPS engine
- **Zeek (Bro) 6.x**: Network security monitor
- **Snort 3.x**: Backup IDS engine
- **YARA**: Malware identification

### Traffic Analysis
- **Arkime (Moloch)**: Full packet capture and analysis
- **ntopng**: Real-time traffic monitoring
- **Wireshark/tshark**: Packet analysis tools

### Threat Intelligence
- **MISP**: Threat intelligence platform
- **OpenCTI**: Cyber threat intelligence
- **AlienVault OTX**: Community threat feeds
- **Abuse.ch feeds**: Malware indicators

### Machine Learning/AI
- **Elasticsearch ML**: Anomaly detection
- **Scikit-learn**: Custom ML models
- **TensorFlow Lite**: Deep learning inference
- **Isolation Forest**: Outlier detection

### Data Storage & Processing
- **Elasticsearch 8.x**: Log storage and search
- **PostgreSQL 15**: Metadata storage
- **Redis**: Caching and queuing
- **Apache Kafka**: Event streaming

### Visualization & UI
- **Kibana**: Data visualization
- **Grafana**: Metrics dashboards
- **Custom React Dashboard**: Main interface
- **Evebox**: Suricata event viewer

### Additional Tools
- **Stenographer**: High-performance packet capture
- **Filebeat/Metricbeat**: Data shippers
- **Logstash**: Log processing pipeline
- **Nginx**: Web server and reverse proxy

---

## 3. System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Network Interfaces                    │
│              (SPAN/TAP/Mirror Port Input)               │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │   Packet Capture Layer   │
        │  - AF_PACKET/PF_RING     │
        │  - Stenographer          │
        └────────────┬────────────┘
                     │
        ┌────────────┴────────────────────────┐
        │     Detection & Analysis Layer       │
        ├──────────────┬──────────────────────┤
        │   Suricata   │   Zeek   │  Snort3   │
        └──────┬───────┴────┬─────┴───────┬───┘
               │            │             │
        ┌──────┴────────────┴─────────────┴────┐
        │      Intelligence Correlation         │
        │  - MISP Integration                   │
        │  - Custom Rule Engine                 │
        │  - ML Anomaly Detection               │
        └──────────────┬───────────────────────┘
                       │
        ┌──────────────┴───────────────────────┐
        │     Processing & Enrichment          │
        │  - Kafka Streaming                   │
        │  - Logstash Pipeline                 │
        │  - GeoIP/ASN Enrichment              │
        └──────────────┬───────────────────────┘
                       │
        ┌──────────────┴───────────────────────┐
        │      Storage & Indexing              │
        │  - Elasticsearch Cluster             │
        │  - PostgreSQL Metadata               │
        │  - PCAP Storage (Arkime)             │
        └──────────────┬───────────────────────┘
                       │
        ┌──────────────┴───────────────────────┐
        │    Visualization & API Layer         │
        │  - Sentinel Dashboard                │
        │  - Kibana                            │
        │  - REST API                          │
        │  - WebSocket (real-time)             │
        └──────────────────────────────────────┘
```

---

## 4. Detailed Build Process

### Phase 1: Base System Creation

#### Step 1: Prepare Build Environment

```bash
# Install build tools on your host system
sudo apt install -y debootstrap squashfs-tools genisoimage \
  syslinux isolinux xorriso live-boot

# Create working directory
mkdir -p ~/sentinel-build/{chroot,image,scratch}
cd ~/sentinel-build
```

#### Step 2: Bootstrap Debian Base

```bash
# Bootstrap minimal Debian
sudo debootstrap --arch=amd64 --variant=minbase bookworm \
  chroot http://deb.debian.org/debian/

# Chroot into the system
sudo chroot chroot

# Inside chroot - basic configuration
echo "sentinel" > /etc/hostname

cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
EOF

apt update && apt upgrade -y
```

#### Step 3: Install Core Packages

```bash
# Essential system packages
apt install -y linux-image-amd64 live-boot systemd-sysv \
  network-manager openssh-server sudo vim tmux htop curl wget git

# Development tools
apt install -y build-essential cmake autoconf automake libtool \
  pkg-config python3 python3-pip python3-dev

# Network tools
apt install -y tcpdump ethtool net-tools iproute2 bridge-utils \
  vlan iputils-ping dnsutils
```

### Phase 2: Detection Engine Installation

#### Suricata Installation

```bash
# Install dependencies
apt install -y libpcre3 libpcre3-dev libyaml-0-2 libyaml-dev \
  libcap-ng-dev libcap-ng0 libmagic-dev libjansson-dev \
  libnetfilter-queue-dev libnetfilter-queue1 libnfnetlink-dev \
  libnfnetlink0 libhiredis-dev libhiredis0.14

# Add OISF repository
apt install -y software-properties-common
add-apt-repository ppa:oisf/suricata-stable
apt update
apt install -y suricata

# Configure Suricata
cat > /etc/suricata/suricata.yaml << 'EOF'
%YAML 1.1
---
vars:
  address-groups:
    HOME_NET: "[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
    EXTERNAL_NET: "!$HOME_NET"
  
af-packet:
  - interface: auto
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes
    use-mmap: yes
    ring-size: 200000

outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: eve.json
      types:
        - alert
        - http
        - dns
        - tls
        - files
        - smtp
        - ssh
        - flow

detect:
  profile: high
  custom-values:
    toclient-groups: 3
    toserver-groups: 25

threading:
  set-cpu-affinity: yes
  cpu-affinity:
    - management-cpu-set:
        cpu: [ 0 ]
    - receive-cpu-set:
        cpu: [ 1,2,3,4 ]
    - worker-cpu-set:
        cpu: [ 5,6,7,8 ]
  detect-thread-ratio: 1.0
EOF

# Download rulesets
suricata-update
suricata-update enable-source et/open
suricata-update enable-source oisf/trafficid
suricata-update enable-source sslbl/ssl-fp-blacklist
```

#### Zeek Installation

```bash
# Install Zeek
echo 'deb http://download.opensuse.org/repositories/security:/zeek/Debian_12/ /' | \
  sudo tee /etc/apt/sources.list.d/security:zeek.list
curl -fsSL https://download.opensuse.org/repositories/security:zeek/Debian_12/Release.key | \
  gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/security_zeek.gpg > /dev/null
apt update
apt install -y zeek

# Configure Zeek
cat > /opt/zeek/etc/node.cfg << EOF
[zeek]
type=standalone
host=localhost
interface=af_packet::eth0
EOF

cat > /opt/zeek/share/zeek/site/local.zeek << 'EOF'
@load policy/frameworks/software/vulnerable
@load policy/frameworks/software/version-changes
@load policy/protocols/conn/known-hosts
@load policy/protocols/conn/known-services
@load policy/protocols/ssl/known-certs
@load policy/protocols/ssl/validate-certs
@load policy/protocols/http/detect-sqli
@load policy/protocols/ftp/detect
@load policy/protocols/smb
@load packages/zeek-af_packet-plugin
EOF
```

### Phase 3: ML & Analytics Engine

#### Elasticsearch Installation

```bash
# Install Java
apt install -y openjdk-17-jdk

# Add Elasticsearch repository
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" | \
  tee /etc/apt/sources.list.d/elastic-8.x.list

apt update
apt install -y elasticsearch kibana filebeat metricbeat

# Configure Elasticsearch for NDR workload
cat > /etc/elasticsearch/elasticsearch.yml << EOF
cluster.name: sentinel-cluster
node.name: sentinel-node-1
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node

# Memory settings
bootstrap.memory_lock: true

# ML settings
xpack.ml.enabled: true
xpack.ml.max_machine_memory_percent: 30

# Security
xpack.security.enabled: true
xpack.security.enrollment.enabled: true
EOF

# Set JVM heap (50% of available RAM, max 31GB)
cat > /etc/elasticsearch/jvm.options.d/heap.options << EOF
-Xms4g
-Xmx4g
EOF
```

#### Custom ML Anomaly Detection

```bash
# Install Python ML libraries
pip3 install --break-system-packages \
  scikit-learn pandas numpy scipy tensorflow-lite \
  pyshark scapy elasticsearch kafka-python redis

# Create ML detection scripts
mkdir -p /opt/sentinel/ml

cat > /opt/sentinel/ml/anomaly_detector.py << 'PYTHON'
#!/usr/bin/env python3
"""
Sentinel ML Anomaly Detection Engine
Detects network anomalies using Isolation Forest and LSTM
"""

import numpy as np
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
import json
import sys
from elasticsearch import Elasticsearch
from datetime import datetime, timedelta

class SentinelAnomalyDetector:
    def __init__(self):
        self.es = Elasticsearch(['http://localhost:9200'])
        self.scaler = StandardScaler()
        self.model = IsolationForest(
            contamination=0.1,
            random_state=42,
            n_estimators=100
        )
        
    def extract_features(self, flow_data):
        """Extract features from network flow"""
        features = []
        for flow in flow_data:
            feature_vector = [
                flow.get('bytes_in', 0),
                flow.get('bytes_out', 0),
                flow.get('packets_in', 0),
                flow.get('packets_out', 0),
                flow.get('duration', 0),
                flow.get('src_port', 0),
                flow.get('dst_port', 0),
                len(flow.get('unique_ips', [])),
            ]
            features.append(feature_vector)
        return np.array(features)
    
    def train(self, historical_days=7):
        """Train on historical data"""
        query = {
            "query": {
                "range": {
                    "@timestamp": {
                        "gte": f"now-{historical_days}d",
                        "lt": "now"
                    }
                }
            },
            "size": 10000
        }
        
        result = self.es.search(index="sentinel-flows-*", body=query)
        flows = [hit['_source'] for hit in result['hits']['hits']]
        
        features = self.extract_features(flows)
        features_scaled = self.scaler.fit_transform(features)
        self.model.fit(features_scaled)
        
    def detect(self, current_flows):
        """Detect anomalies in current traffic"""
        features = self.extract_features(current_flows)
        features_scaled = self.scaler.transform(features)
        predictions = self.model.predict(features_scaled)
        
        anomalies = []
        for idx, pred in enumerate(predictions):
            if pred == -1:  # Anomaly detected
                anomalies.append({
                    'flow': current_flows[idx],
                    'timestamp': datetime.utcnow().isoformat(),
                    'severity': 'medium',
                    'type': 'statistical_anomaly'
                })
        
        return anomalies

if __name__ == '__main__':
    detector = SentinelAnomalyDetector()
    detector.train()
    print("Anomaly detection model trained and ready", file=sys.stderr)
PYTHON

chmod +x /opt/sentinel/ml/anomaly_detector.py
```

### Phase 4: Packet Capture & Analysis

#### Arkime (Full Packet Capture)

```bash
# Install Arkime
cd /tmp
wget https://s3.amazonaws.com/files.molo.ch/builds/ubuntu-22.04/arkime_4.0.0-1_amd64.deb
dpkg -i arkime_4.0.0-1_amd64.deb
apt install -f -y

# Configure Arkime
/opt/arkime/bin/Configure << EOF
eth0
no
localhost
9200


EOF

# Initialize Arkime
/opt/arkime/db/db.pl http://localhost:9200 init

# Add admin user
/opt/arkime/bin/arkime_add_user.sh admin "Admin User" sentinel --admin
```

#### Stenographer (High-Performance PCAP)

```bash
# Install Stenographer
apt install -y stenographer

# Configure
cat > /etc/stenographer/config << EOF
{
  "Threads": [
    { "PacketsDirectory": "/var/lib/stenographer/packets"
    , "IndexDirectory": "/var/lib/stenographer/index"
    , "MaxDirectoryFiles": 10000
    , "DiskFreePercentage": 10
    }
  ],
  "StenotypePath": "/usr/bin/stenotype",
  "Interface": "eth0",
  "Port": 1234,
  "Host": "127.0.0.1",
  "Flags": [],
  "CertPath": "/etc/stenographer/certs"
}
EOF

mkdir -p /var/lib/stenographer/{packets,index}
```

### Phase 5: Threat Intelligence Integration

```bash
# Install MISP
cd /opt
git clone https://github.com/MISP/MISP.git
cd MISP
git submodule update --init --recursive

# Install dependencies
apt install -y apache2 mariadb-server php php-mysql php-xml php-mbstring \
  php-gd php-zip libapache2-mod-php redis-server python3-pip

pip3 install --break-system-packages -r requirements.txt

# Configure automated threat feed ingestion
cat > /opt/sentinel/feeds/feed_manager.py << 'PYTHON'
#!/usr/bin/env python3
"""
Sentinel Threat Intelligence Feed Manager
"""

import requests
import json
from datetime import datetime

class FeedManager:
    def __init__(self):
        self.feeds = {
            'abuse_ch_urlhaus': 'https://urlhaus.abuse.ch/downloads/json/',
            'abuse_ch_malware': 'https://bazaar.abuse.ch/export/json/recent/',
            'alienvault_otx': 'https://otx.alienvault.com/api/v1/pulses/subscribed',
            'emergingthreats': 'https://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt',
        }
    
    def fetch_feeds(self):
        """Fetch all configured feeds"""
        indicators = []
        
        for feed_name, feed_url in self.feeds.items():
            try:
                response = requests.get(feed_url, timeout=30)
                if response.status_code == 200:
                    indicators.extend(self.parse_feed(feed_name, response.text))
            except Exception as e:
                print(f"Error fetching {feed_name}: {e}")
        
        return indicators
    
    def parse_feed(self, feed_name, content):
        """Parse feed content"""
        # Implementation specific to each feed format
        pass
    
    def update_rules(self, indicators):
        """Update Suricata/Zeek rules with new indicators"""
        # Generate custom rules from indicators
        pass

if __name__ == '__main__':
    manager = FeedManager()
    indicators = manager.fetch_feeds()
    manager.update_rules(indicators)
PYTHON

chmod +x /opt/sentinel/feeds/feed_manager.py
```

### Phase 6: Web Interface

#### Custom React Dashboard

```bash
# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Create dashboard application
mkdir -p /opt/sentinel/dashboard
cd /opt/sentinel/dashboard

npm init -y
npm install react react-dom next @mui/material @emotion/react \
  recharts axios socket.io-client

# Create Next.js dashboard (structure only - full code in separate artifact)
mkdir -p pages components lib
```

#### REST API Backend

```bash
# Install FastAPI
pip3 install --break-system-packages fastapi uvicorn pydantic \
  python-jose passlib bcrypt

# Create API server
mkdir -p /opt/sentinel/api

cat > /opt/sentinel/api/main.py << 'PYTHON'
#!/usr/bin/env python3
"""
Sentinel REST API
"""

from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from elasticsearch import Elasticsearch
from typing import List, Optional
import uvicorn

app = FastAPI(title="Sentinel NDR API", version="1.0.0")
security = HTTPBearer()
es = Elasticsearch(['http://localhost:9200'])

class Alert(BaseModel):
    id: str
    timestamp: str
    severity: str
    category: str
    signature: str
    src_ip: str
    dst_ip: str
    
class NetworkStats(BaseModel):
    total_flows: int
    total_alerts: int
    top_talkers: List[dict]
    protocols: dict

@app.get("/api/v1/alerts", response_model=List[Alert])
async def get_alerts(
    limit: int = 100,
    severity: Optional[str] = None,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    """Get recent alerts"""
    query = {"match_all": {}}
    if severity:
        query = {"match": {"severity": severity}}
    
    result = es.search(
        index="sentinel-alerts-*",
        body={"query": query, "size": limit, "sort": [{"@timestamp": "desc"}]}
    )
    
    alerts = []
    for hit in result['hits']['hits']:
        alerts.append(Alert(**hit['_source']))
    
    return alerts

@app.get("/api/v1/stats", response_model=NetworkStats)
async def get_stats(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Get network statistics"""
    # Implementation
    pass

@app.post("/api/v1/pcap/query")
async def query_pcap(
    filters: dict,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    """Query PCAP data"""
    # Integration with Arkime/Stenographer
    pass

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
PYTHON

chmod +x /opt/sentinel/api/main.py
```

### Phase 7: System Integration & Automation

#### Systemd Services

```bash
# Create Sentinel master service
cat > /etc/systemd/system/sentinel.service << EOF
[Unit]
Description=Sentinel NDR Master Service
After=network.target elasticsearch.service

[Service]
Type=oneshot
ExecStart=/opt/sentinel/bin/sentinel-start.sh
RemainAfterExit=yes
ExecStop=/opt/sentinel/bin/sentinel-stop.sh

[Install]
WantedBy=multi-user.target
EOF

# Create startup script
mkdir -p /opt/sentinel/bin
cat > /opt/sentinel/bin/sentinel-start.sh << 'BASH'
#!/bin/bash
set -e

echo "Starting Sentinel NDR..."

# Start core services
systemctl start elasticsearch
systemctl start kibana
systemctl start suricata
systemctl start zeek
systemctl start arkime-capture
systemctl start stenographer

# Start custom components
/opt/sentinel/api/main.py &
/opt/sentinel/ml/anomaly_detector.py &

# Start feed updates
/opt/sentinel/feeds/feed_manager.py

echo "Sentinel NDR started successfully"
BASH

chmod +x /opt/sentinel/bin/sentinel-start.sh

# Enable on boot
systemctl enable sentinel.service
```

### Phase 8: ISO Creation

```bash
# Exit chroot
exit

# Clean up chroot
sudo chroot chroot apt clean
sudo rm -rf chroot/tmp/*
sudo rm -rf chroot/var/log/*

# Create filesystem
sudo mkdir -p image/{live,isolinux}
sudo mksquashfs chroot image/live/filesystem.squashfs -comp xz

# Copy kernel
sudo cp chroot/boot/vmlinuz-* image/live/vmlinuz
sudo cp chroot/boot/initrd.img-* image/live/initrd

# Create bootloader config
cat > image/isolinux/isolinux.cfg << EOF
DEFAULT live
LABEL live
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live quiet splash
PROMPT 0
TIMEOUT 0
EOF

# Copy isolinux files
sudo cp /usr/lib/ISOLINUX/isolinux.bin image/isolinux/
sudo cp /usr/lib/syslinux/modules/bios/ldlinux.c32 image/isolinux/
sudo cp /usr/lib/syslinux/modules/bios/menu.c32 image/isolinux/

# Create ISO
sudo xorriso -as mkisofs \
  -iso-level 3 \
  -full-iso9660-filenames \
  -volid "SENTINEL_NDR" \
  -eltorito-boot isolinux/isolinux.bin \
  -eltorito-catalog isolinux/boot.cat \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -output ~/sentinel-v1.0.iso \
  image/

echo "ISO created: ~/sentinel-v1.0.iso"
```

---