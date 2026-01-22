#!/bin/bash
# ServerStore HD Sentinel - Custom ISO Builder
# Build script for creating a bootable disk monitoring system

set -e

PROJECT_NAME="serverstore-hd-sentinel"
VERSION="1.0.0"
BUILD_DIR="$(pwd)/build"
ISO_DIR="${BUILD_DIR}/iso"
OVERLAY_DIR="${BUILD_DIR}/overlay"
OUTPUT_ISO="${BUILD_DIR}/${PROJECT_NAME}-${VERSION}.iso"

echo "=== ServerStore HD Sentinel ISO Builder ==="
echo "Building version: ${VERSION}"

# Check dependencies
command -v xorriso >/dev/null 2>&1 || { echo "Error: xorriso not found. Install with: apt install xorriso"; exit 1; }
command -v mksquashfs >/dev/null 2>&1 || { echo "Error: squashfs-tools not found. Install with: apt install squashfs-tools"; exit 1; }

# Create build directories
mkdir -p "${BUILD_DIR}" "${ISO_DIR}" "${OVERLAY_DIR}"

echo "[1/6] Downloading SystemRescue base..."
SYSRESCUE_VERSION="11.01"
SYSRESCUE_ISO="systemrescue-${SYSRESCUE_VERSION}-amd64.iso"
SYSRESCUE_URL="https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/${SYSRESCUE_VERSION}/${SYSRESCUE_ISO}/download"

if [ ! -f "${BUILD_DIR}/${SYSRESCUE_ISO}" ]; then
    wget -O "${BUILD_DIR}/${SYSRESCUE_ISO}" "${SYSRESCUE_URL}" || {
        echo "Error: Failed to download SystemRescue. Please download manually from:"
        echo "https://www.system-rescue.org/Download/"
        exit 1
    }
fi

echo "[2/6] Extracting SystemRescue ISO..."
mkdir -p "${BUILD_DIR}/sysrescue_mount"
sudo mount -o loop "${BUILD_DIR}/${SYSRESCUE_ISO}" "${BUILD_DIR}/sysrescue_mount"
cp -a "${BUILD_DIR}/sysrescue_mount/"* "${ISO_DIR}/"
sudo umount "${BUILD_DIR}/sysrescue_mount"
rmdir "${BUILD_DIR}/sysrescue_mount"

echo "[3/6] Creating custom overlay filesystem..."

# Create directory structure
mkdir -p "${OVERLAY_DIR}/root"/{opt/serverstore,etc/systemd/system,usr/local/bin}

# Create the monitoring dashboard application
cat > "${OVERLAY_DIR}/root/opt/serverstore/dashboard.py" << 'DASHBOARD_EOF'
#!/usr/bin/env python3
"""
ServerStore HD Sentinel - Disk Monitoring Dashboard
Collects and displays disk health information via web interface
"""

import json
import subprocess
import re
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime
import threading

class DiskMonitor:
    def __init__(self):
        self.data = {}
        
    def get_smart_data(self):
        """Collect SMART data from all disks"""
        disks = []
        try:
            # Find all block devices
            result = subprocess.run(['lsblk', '-d', '-n', '-o', 'NAME,SIZE,TYPE'], 
                                  capture_output=True, text=True)
            for line in result.stdout.strip().split('\n'):
                parts = line.split()
                if len(parts) >= 3 and parts[2] == 'disk':
                    disks.append(parts[0])
        except Exception as e:
            print(f"Error finding disks: {e}")
        
        smart_data = {}
        for disk in disks:
            try:
                # Get SMART info
                smart_result = subprocess.run(['smartctl', '-a', f'/dev/{disk}'], 
                                            capture_output=True, text=True)
                smart_data[disk] = self.parse_smart_output(smart_result.stdout)
                
                # Get additional info
                smart_data[disk]['device'] = disk
                smart_data[disk]['timestamp'] = datetime.now().isoformat()
                
            except Exception as e:
                smart_data[disk] = {'error': str(e)}
        
        return smart_data
    
    def parse_smart_output(self, output):
        """Parse smartctl output"""
        data = {
            'model': 'Unknown',
            'serial': 'Unknown',
            'capacity': 'Unknown',
            'health': 'UNKNOWN',
            'temperature': 'N/A',
            'power_on_hours': 'N/A',
            'attributes': []
        }
        
        # Extract model
        model_match = re.search(r'Device Model:\s+(.+)', output)
        if model_match:
            data['model'] = model_match.group(1).strip()
        
        # Extract serial
        serial_match = re.search(r'Serial Number:\s+(.+)', output)
        if serial_match:
            data['serial'] = serial_match.group(1).strip()
        
        # Extract capacity
        capacity_match = re.search(r'User Capacity:\s+(.+)', output)
        if capacity_match:
            data['capacity'] = capacity_match.group(1).strip()
        
        # Extract health status
        health_match = re.search(r'SMART overall-health self-assessment test result:\s+(.+)', output)
        if health_match:
            data['health'] = health_match.group(1).strip()
        
        # Extract temperature
        temp_match = re.search(r'Temperature.*?:\s+(\d+)', output)
        if temp_match:
            data['temperature'] = temp_match.group(1) + '°C'
        
        # Extract power on hours
        poh_match = re.search(r'Power_On_Hours.*?(\d+)', output)
        if poh_match:
            hours = int(poh_match.group(1))
            data['power_on_hours'] = f"{hours} hrs ({hours/24:.0f} days)"
        
        # Parse SMART attributes table
        in_attributes = False
        for line in output.split('\n'):
            if 'ID# ATTRIBUTE_NAME' in line:
                in_attributes = True
                continue
            if in_attributes and line.strip():
                parts = line.split()
                if len(parts) >= 10 and parts[0].isdigit():
                    data['attributes'].append({
                        'id': parts[0],
                        'name': parts[1],
                        'value': parts[3],
                        'worst': parts[4],
                        'thresh': parts[5],
                        'raw_value': ' '.join(parts[9:])
                    })
        
        return data
    
    def get_raid_status(self):
        """Collect RAID status information"""
        raid_info = {}
        
        # Check for mdadm RAID
        try:
            mdstat = subprocess.run(['cat', '/proc/mdstat'], 
                                  capture_output=True, text=True)
            raid_info['mdadm'] = mdstat.stdout
        except:
            raid_info['mdadm'] = 'Not available'
        
        # Check for hardware RAID (basic detection)
        hw_raid = []
        for cmd in [['megacli', '-LDInfo', '-Lall', '-aALL'],
                   ['storcli', '/call', 'show']]:
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    hw_raid.append({
                        'controller': cmd[0],
                        'output': result.stdout
                    })
            except:
                pass
        
        raid_info['hardware'] = hw_raid if hw_raid else 'No hardware RAID detected'
        
        return raid_info
    
    def get_system_info(self):
        """Get system information"""
        info = {}
        
        try:
            # Hostname
            hostname = subprocess.run(['hostname'], capture_output=True, text=True)
            info['hostname'] = hostname.stdout.strip()
            
            # Uptime
            uptime = subprocess.run(['uptime', '-p'], capture_output=True, text=True)
            info['uptime'] = uptime.stdout.strip()
            
            # Memory
            meminfo = subprocess.run(['free', '-h'], capture_output=True, text=True)
            info['memory'] = meminfo.stdout
            
        except Exception as e:
            info['error'] = str(e)
        
        return info
    
    def collect_all_data(self):
        """Collect all monitoring data"""
        return {
            'timestamp': datetime.now().isoformat(),
            'system': self.get_system_info(),
            'disks': self.get_smart_data(),
            'raid': self.get_raid_status()
        }

class DashboardHandler(BaseHTTPRequestHandler):
    monitor = DiskMonitor()
    
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(self.get_html().encode())
        elif self.path == '/api/data':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            data = self.monitor.collect_all_data()
            self.wfile.write(json.dumps(data, indent=2).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def get_html(self):
        return '''<!DOCTYPE html>
<html>
<head>
    <title>ServerStore HD Sentinel</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #0f0f1e;
            color: #e0e0e0;
            padding: 20px;
        }
        .header {
            background: linear-gradient(135deg, #1e3a8a 0%, #3b82f6 100%);
            padding: 30px;
            border-radius: 12px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
        }
        .header h1 {
            color: white;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .header p {
            color: #bfdbfe;
            font-size: 1.1em;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: #1a1a2e;
            padding: 20px;
            border-radius: 8px;
            border: 1px solid #2d2d44;
        }
        .stat-card h3 {
            color: #60a5fa;
            font-size: 0.9em;
            text-transform: uppercase;
            margin-bottom: 10px;
        }
        .stat-card .value {
            font-size: 2em;
            font-weight: bold;
            color: #fff;
        }
        .disk-card {
            background: #1a1a2e;
            border: 2px solid #2d2d44;
            border-radius: 12px;
            padding: 25px;
            margin-bottom: 20px;
            transition: all 0.3s;
        }
        .disk-card:hover {
            border-color: #3b82f6;
            transform: translateY(-2px);
            box-shadow: 0 8px 16px rgba(59, 130, 246, 0.2);
        }
        .disk-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }
        .disk-name {
            font-size: 1.5em;
            font-weight: bold;
            color: #fff;
        }
        .health-badge {
            padding: 8px 16px;
            border-radius: 20px;
            font-weight: bold;
            font-size: 0.9em;
        }
        .health-passed { background: #10b981; color: white; }
        .health-failed { background: #ef4444; color: white; }
        .health-unknown { background: #6b7280; color: white; }
        .disk-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        .info-item {
            padding: 10px;
            background: #0f0f1e;
            border-radius: 6px;
        }
        .info-label {
            color: #9ca3af;
            font-size: 0.85em;
            margin-bottom: 5px;
        }
        .info-value {
            color: #fff;
            font-size: 1.1em;
            font-weight: 500;
        }
        .attributes-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        .attributes-table th {
            background: #0f0f1e;
            padding: 12px;
            text-align: left;
            color: #60a5fa;
            font-size: 0.9em;
            border-bottom: 2px solid #3b82f6;
        }
        .attributes-table td {
            padding: 10px 12px;
            border-bottom: 1px solid #2d2d44;
        }
        .attributes-table tr:hover {
            background: #0f0f1e;
        }
        .loading {
            text-align: center;
            padding: 60px;
            font-size: 1.2em;
            color: #60a5fa;
        }
        .timestamp {
            text-align: center;
            color: #9ca3af;
            margin-top: 20px;
            font-size: 0.9em;
        }
        .raid-section {
            background: #1a1a2e;
            border: 2px solid #2d2d44;
            border-radius: 12px;
            padding: 25px;
            margin-bottom: 20px;
        }
        .raid-section h2 {
            color: #60a5fa;
            margin-bottom: 15px;
        }
        .raid-section pre {
            background: #0f0f1e;
            padding: 15px;
            border-radius: 6px;
            overflow-x: auto;
            color: #e0e0e0;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>⚡ ServerStore HD Sentinel</h1>
        <p>Professional Disk Health Monitoring System</p>
    </div>
    
    <div id="dashboard">
        <div class="loading">🔄 Loading disk information...</div>
    </div>
    
    <script>
        function fetchData() {
            fetch('/api/data')
                .then(response => response.json())
                .then(data => renderDashboard(data))
                .catch(error => {
                    document.getElementById('dashboard').innerHTML = 
                        '<div class="loading">❌ Error loading data: ' + error + '</div>';
                });
        }
        
        function renderDashboard(data) {
            const diskCount = Object.keys(data.disks).length;
            const healthyDisks = Object.values(data.disks).filter(d => d.health === 'PASSED').length;
            
            let html = '<div class="stats-grid">';
            html += '<div class="stat-card"><h3>Total Disks</h3><div class="value">' + diskCount + '</div></div>';
            html += '<div class="stat-card"><h3>Healthy Disks</h3><div class="value">' + healthyDisks + '</div></div>';
            html += '<div class="stat-card"><h3>System</h3><div class="value" style="font-size:1.2em">' + 
                    (data.system.hostname || 'Unknown') + '</div></div>';
            html += '<div class="stat-card"><h3>Uptime</h3><div class="value" style="font-size:1em">' + 
                    (data.system.uptime || 'Unknown') + '</div></div>';
            html += '</div>';
            
            // Render RAID status if available
            if (data.raid && data.raid.mdadm && data.raid.mdadm !== 'Not available') {
                html += '<div class="raid-section">';
                html += '<h2>📊 RAID Status (mdadm)</h2>';
                html += '<pre>' + escapeHtml(data.raid.mdadm) + '</pre>';
                html += '</div>';
            }
            
            // Render disks
            for (const [device, disk] of Object.entries(data.disks)) {
                if (disk.error) {
                    html += '<div class="disk-card">';
                    html += '<div class="disk-name">/dev/' + device + '</div>';
                    html += '<p style="color: #ef4444;">Error: ' + disk.error + '</p>';
                    html += '</div>';
                    continue;
                }
                
                const healthClass = disk.health === 'PASSED' ? 'health-passed' : 
                                  disk.health === 'FAILED' ? 'health-failed' : 'health-unknown';
                
                html += '<div class="disk-card">';
                html += '<div class="disk-header">';
                html += '<div class="disk-name">🔷 /dev/' + device + '</div>';
                html += '<div class="health-badge ' + healthClass + '">' + disk.health + '</div>';
                html += '</div>';
                
                html += '<div class="disk-info">';
                html += '<div class="info-item"><div class="info-label">Model</div><div class="info-value">' + 
                        disk.model + '</div></div>';
                html += '<div class="info-item"><div class="info-label">Serial Number</div><div class="info-value">' + 
                        disk.serial + '</div></div>';
                html += '<div class="info-item"><div class="info-label">Capacity</div><div class="info-value">' + 
                        disk.capacity + '</div></div>';
                html += '<div class="info-item"><div class="info-label">Temperature</div><div class="info-value">' + 
                        disk.temperature + '</div></div>';
                html += '<div class="info-item"><div class="info-label">Power On Time</div><div class="info-value">' + 
                        disk.power_on_hours + '</div></div>';
                html += '</div>';
                
                if (disk.attributes && disk.attributes.length > 0) {
                    html += '<details><summary style="cursor:pointer; color:#60a5fa; margin-top:15px;">📋 SMART Attributes (' + 
                            disk.attributes.length + ')</summary>';
                    html += '<table class="attributes-table">';
                    html += '<tr><th>ID</th><th>Attribute</th><th>Value</th><th>Worst</th><th>Thresh</th><th>Raw Value</th></tr>';
                    for (const attr of disk.attributes) {
                        html += '<tr>';
                        html += '<td>' + attr.id + '</td>';
                        html += '<td>' + attr.name + '</td>';
                        html += '<td>' + attr.value + '</td>';
                        html += '<td>' + attr.worst + '</td>';
                        html += '<td>' + attr.thresh + '</td>';
                        html += '<td>' + attr.raw_value + '</td>';
                        html += '</tr>';
                    }
                    html += '</table></details>';
                }
                
                html += '</div>';
            }
            
            html += '<div class="timestamp">Last updated: ' + new Date(data.timestamp).toLocaleString() + '</div>';
            
            document.getElementById('dashboard').innerHTML = html;
        }
        
        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        
        // Initial load and auto-refresh every 30 seconds
        fetchData();
        setInterval(fetchData, 30000);
    </script>
</body>
</html>'''
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass

def run_server(port=8080):
    server = HTTPServer(('0.0.0.0', port), DashboardHandler)
    print(f"ServerStore HD Sentinel Dashboard running on port {port}")
    print(f"Access from: http://<server-ip>:{port}")
    server.serve_forever()

if __name__ == '__main__':
    run_server()
DASHBOARD_EOF

chmod +x "${OVERLAY_DIR}/root/opt/serverstore/dashboard.py"

# Create systemd service for auto-start
cat > "${OVERLAY_DIR}/root/etc/systemd/system/serverstore-dashboard.service" << 'SERVICE_EOF'
[Unit]
Description=ServerStore HD Sentinel Dashboard
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/serverstore/dashboard.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Create startup script
cat > "${OVERLAY_DIR}/root/usr/local/bin/serverstore-init.sh" << 'INIT_EOF'
#!/bin/bash
# ServerStore HD Sentinel Initialization Script

echo "Initializing ServerStore HD Sentinel..."

# Enable and start the dashboard service
systemctl enable serverstore-dashboard.service
systemctl start serverstore-dashboard.service

# Display network information
echo ""
echo "======================================"
echo "ServerStore HD Sentinel is ready!"
echo "======================================"
echo ""
ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print "Dashboard URL: http://" $2}' | sed 's/\/.*/:8080/'
echo ""
echo "Default port: 8080"
echo ""
INIT_EOF

chmod +x "${OVERLAY_DIR}/root/usr/local/bin/serverstore-init.sh"

# Create autorun configuration
cat > "${OVERLAY_DIR}/root/etc/systemd/system/serverstore-init.service" << 'AUTORUN_EOF'
[Unit]
Description=ServerStore HD Sentinel Initialization
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/serverstore-init.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
AUTORUN_EOF

# Create custom boot parameters
mkdir -p "${ISO_DIR}/boot/grub"
cat > "${ISO_DIR}/boot/grub/grub.cfg" << 'GRUB_EOF'
set timeout=5
set default=0

menuentry "ServerStore HD Sentinel (Auto-boot)" {
    linux /boot/vmlinuz root=/dev/ram0 rootfstype=ramfs init=/bin/bash
    initrd /boot/initrd.img
}

menuentry "ServerStore HD Sentinel (Safe Mode)" {
    linux /boot/vmlinuz root=/dev/ram0 rootfstype=ramfs init=/bin/bash single
    initrd /boot/initrd.img
}
GRUB_EOF

echo "[4/6] Extracting and modifying SystemRescue airootfs..."
# SystemRescue uses airootfs - we need to extract, modify, and repack it
AIROOTFS="${ISO_DIR}/sysresccd/x86_64/airootfs.sfs"

if [ -f "${AIROOTFS}" ]; then
    echo "Found airootfs, extracting..."
    mkdir -p "${BUILD_DIR}/airootfs_extract"
    sudo unsquashfs -f -d "${BUILD_DIR}/airootfs_extract" "${AIROOTFS}"
    
    echo "Injecting ServerStore files..."
    sudo cp -r "${OVERLAY_DIR}/root/"* "${BUILD_DIR}/airootfs_extract/"
    
    # Enable our services
    sudo chroot "${BUILD_DIR}/airootfs_extract" systemctl enable serverstore-dashboard.service || true
    sudo chroot "${BUILD_DIR}/airootfs_extract" systemctl enable serverstore-init.service || true
    
    # Create the autostart service (before cleanup!)
    echo "Creating autostart service..."
    sudo mkdir -p "${BUILD_DIR}/airootfs_extract/etc/systemd/system"
    sudo cat > "${BUILD_DIR}/airootfs_extract/etc/systemd/system/serverstore-autostart.service" << 'SYSTEMD_SERVICE'
[Unit]
Description=ServerStore HD Sentinel Auto-start
After=network.target

[Service]
Type=oneshot
ExecStart=/run/archiso/bootmnt/autorun/serverstore-init.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE
    
    # Enable the autostart service
    sudo mkdir -p "${BUILD_DIR}/airootfs_extract/etc/systemd/system/multi-user.target.wants"
    sudo ln -sf ../serverstore-autostart.service "${BUILD_DIR}/airootfs_extract/etc/systemd/system/multi-user.target.wants/serverstore-autostart.service"
    
    echo "Repacking modified airootfs..."
    sudo rm -f "${AIROOTFS}"
    sudo mksquashfs "${BUILD_DIR}/airootfs_extract" "${AIROOTFS}" -comp xz -b 1M
    
    echo "Cleaning up..."
    sudo rm -rf "${BUILD_DIR}/airootfs_extract"
else
    echo "Warning: airootfs not found at expected location"
    echo "Creating overlay package instead..."
    cd "${OVERLAY_DIR}"
    mksquashfs root "${BUILD_DIR}/serverstore-overlay.sqfs" -comp xz -b 1M
    cd "${BUILD_DIR}"
    mkdir -p "${ISO_DIR}/serverstore"
    cp "${BUILD_DIR}/serverstore-overlay.sqfs" "${ISO_DIR}/serverstore/"
fi

echo "[5/6] Configuring boot parameters..."

# Find and modify boot configuration
BOOT_CFG=$(find "${ISO_DIR}" -name "syslinux.cfg" -o -name "isolinux.cfg" 2>/dev/null | head -1)

if [ -n "$BOOT_CFG" ]; then
    echo "Found boot config: ${BOOT_CFG}"
    cp "${BOOT_CFG}" "${BOOT_CFG}.bak"
    
    # CRITICAL: Keep the original label that SystemRescue expects
    # Change it in the boot config AND the ISO volume label must match
    
    # Set shorter timeout (3 seconds)
    sed -i 's/^timeout .*/timeout 30/' "${BOOT_CFG}"
    sed -i 's/^TIMEOUT .*/TIMEOUT 30/' "${BOOT_CFG}"
    
    # Make first option auto-selected (it should boot and run our script)
    sed -i 's/^default .*/default 0/' "${BOOT_CFG}"
    sed -i 's/^DEFAULT .*/DEFAULT 0/' "${BOOT_CFG}"
    
    echo "Boot configuration updated (3 second timeout, auto-select first option)"
    
    # Show what the first boot option will be
    echo "First boot option:"
    grep -A 3 "^LABEL" "${BOOT_CFG}" | head -4
else
    echo "Warning: Boot configuration not found, using defaults"
fi

# IMPORTANT: Also modify the autorun script location
# SystemRescue looks for autorun scripts in specific locations
mkdir -p "${ISO_DIR}/autorun"
cat > "${ISO_DIR}/autorun/serverstore-init.sh" << 'AUTORUN_SCRIPT'
#!/bin/bash
# ServerStore Auto-initialization Script
# This runs automatically when SystemRescue boots

echo "========================================="
echo "ServerStore HD Sentinel - Initializing..."
echo "========================================="

# Wait for system to be ready
sleep 5

# Install required packages
echo "Installing dependencies..."
pacman -Sy --noconfirm python smartmontools dmidecode 2>/dev/null || {
    echo "Using pre-installed packages..."
}

# Create ServerStore directory
mkdir -p /opt/serverstore

# Copy dashboard from ISO
if [ -f /run/archiso/bootmnt/serverstore/dashboard.py ]; then
    cp /run/archiso/bootmnt/serverstore/dashboard.py /opt/serverstore/
    chmod +x /opt/serverstore/dashboard.py
fi

# Start the dashboard
nohup /usr/bin/python3 /opt/serverstore/dashboard.py > /var/log/serverstore.log 2>&1 &

# Wait for it to start
sleep 3

# Display access information
clear
echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                                                       ║"
echo "║     🚀 ServerStore HD Sentinel is READY! 🚀          ║"
echo "║                                                       ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Access the dashboard from your browser:"
echo ""
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | while read ip; do
    echo "  🌐 http://$ip:8080"
done
echo ""
echo "Dashboard is running in the background."
echo "Login credentials: root (no password)"
echo ""

AUTORUN_SCRIPT

chmod +x "${ISO_DIR}/autorun/serverstore-init.sh"

# Also copy the dashboard to a location accessible after boot
mkdir -p "${ISO_DIR}/serverstore"
cp "${OVERLAY_DIR}/root/opt/serverstore/dashboard.py" "${ISO_DIR}/serverstore/dashboard.py"

echo "Autorun scripts and dashboard copied to ISO"

echo "[6/6] Building final ISO..."

# Find actual boot files in SystemRescue structure
echo "Detecting boot structure..."
find "${ISO_DIR}" -name "isolinux.bin" -o -name "isohdpfx.bin" -o -name "efiboot.img" 2>/dev/null | head -5

# SystemRescue 11.x uses isolinux directory, not syslinux
BOOT_DIR="${ISO_DIR}/isolinux"
if [ ! -d "${BOOT_DIR}" ]; then
    BOOT_DIR="${ISO_DIR}/syslinux"
fi

if [ ! -d "${BOOT_DIR}" ]; then
    echo "ERROR: Cannot find boot directory (isolinux or syslinux)"
    ls -la "${ISO_DIR}/" | head -20
    exit 1
fi

echo "Using boot directory: ${BOOT_DIR}"
BOOT_DIR_NAME=$(basename "${BOOT_DIR}")

# Find boot files
ISOLINUX_BIN="${BOOT_DIR}/isolinux.bin"
ISOHDPFX="${BOOT_DIR}/isohdpfx.bin"
EFI_IMG=$(find "${ISO_DIR}" -name "efiboot.img" 2>/dev/null | head -1)

# Verify boot files exist
if [ ! -f "${ISOLINUX_BIN}" ]; then
    echo "ERROR: isolinux.bin not found at ${ISOLINUX_BIN}"
    ls -la "${BOOT_DIR}/"
    exit 1
fi

echo "Boot files:"
echo "  ISOLINUX: ${ISOLINUX_BIN}"
echo "  MBR: ${ISOHDPFX}"
echo "  EFI: ${EFI_IMG}"

# Build the ISO
xorriso -as mkisofs \
    -o "${OUTPUT_ISO}" \
    -isohybrid-mbr "${ISOHDPFX}" \
    -c ${BOOT_DIR_NAME}/boot.cat \
    -b ${BOOT_DIR_NAME}/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -isohybrid-gpt-basdat \
    -eltorito-alt-boot \
    -e EFI/archiso/efiboot.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -V "RESCUE1101" \
    -r \
    "${ISO_DIR}" 2>&1 | grep -v "^xorriso : UPDATE"

# Check if ISO was created
if [ ! -f "${OUTPUT_ISO}" ]; then
    echo "ERROR: ISO creation failed!"
    exit 1
fi

echo ""
echo "========================================="
echo "✅ Build complete!"
echo "========================================="
echo "ISO created: ${OUTPUT_ISO}"
echo "Size: $(du -h ${OUTPUT_ISO} | cut -f1)"
echo ""
echo "To write to USB:"
echo "  sudo dd if=${OUTPUT_ISO} of=/dev/sdX bs=4M status=progress"
echo ""
echo "Next steps:"
echo "  1. Test the ISO in a VM or physical server"
echo "  2. Access dashboard at http://<server-ip>:8080"
echo "  3. Verify disk monitoring functionality"
echo "========================================="
