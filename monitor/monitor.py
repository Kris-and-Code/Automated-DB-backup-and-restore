#!/usr/bin/env python3
"""
InfluxDB Monitor Service
Monitors InfluxDB health and backup services
"""

import os
import time
import json
import requests
import configparser
from flask import Flask, jsonify
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

class InfluxDBMonitor:
    def __init__(self, config_file='/etc/monitor.conf'):
        self.config = configparser.ConfigParser()
        self.config.read(config_file)
        
        self.influxdb_url = self.config.get('influxdb', 'url')
        self.token = self.config.get('influxdb', 'token')
        self.org = self.config.get('influxdb', 'org')
        self.bucket = self.config.get('influxdb', 'bucket')
        
        self.check_interval = int(self.config.get('monitoring', 'check_interval'))
        self.alert_threshold = float(self.config.get('monitoring', 'alert_threshold'))
        
    def check_influxdb_health(self):
        """Check InfluxDB service health"""
        try:
            response = requests.get(f"{self.influxdb_url}/health", timeout=10)
            if response.status_code == 200:
                return {"status": "healthy", "response_time": response.elapsed.total_seconds()}
            else:
                return {"status": "unhealthy", "status_code": response.status_code}
        except Exception as e:
            return {"status": "error", "error": str(e)}
    
    def check_backup_service(self):
        """Check backup service health"""
        try:
            # Check if backup service is running
            result = os.system("pgrep -f backup > /dev/null")
            if result == 0:
                return {"status": "running"}
            else:
                return {"status": "stopped"}
        except Exception as e:
            return {"status": "error", "error": str(e)}
    
    def check_storage_usage(self):
        """Check storage usage"""
        try:
            # Check disk usage for backup directories
            backup_dir = "/backups"
            if os.path.exists(backup_dir):
                stat = os.statvfs(backup_dir)
                free_space = stat.f_frsize * stat.f_bavail
                total_space = stat.f_frsize * stat.f_blocks
                used_percentage = ((total_space - free_space) / total_space) * 100
                
                return {
                    "status": "ok",
                    "free_space_gb": round(free_space / (1024**3), 2),
                    "used_percentage": round(used_percentage, 2)
                }
            else:
                return {"status": "error", "error": "Backup directory not found"}
        except Exception as e:
            return {"status": "error", "error": str(e)}
    
    def get_system_metrics(self):
        """Get system metrics"""
        try:
            import psutil
            
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            return {
                "cpu_percent": cpu_percent,
                "memory_percent": memory.percent,
                "disk_percent": disk.percent
            }
        except ImportError:
            return {"status": "psutil not available"}
        except Exception as e:
            return {"status": "error", "error": str(e)}
    
    def run_health_check(self):
        """Run complete health check"""
        health_data = {
            "timestamp": time.time(),
            "influxdb": self.check_influxdb_health(),
            "backup_service": self.check_backup_service(),
            "storage": self.check_storage_usage(),
            "system": self.get_system_metrics()
        }
        
        # Log health status
        logger.info(f"Health check completed: {json.dumps(health_data, indent=2)}")
        
        return health_data

# Global monitor instance
monitor = InfluxDBMonitor()

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "service": "influxdb-monitor"})

@app.route('/metrics')
def metrics():
    """Get current metrics"""
    return jsonify(monitor.run_health_check())

@app.route('/status')
def status():
    """Get service status"""
    return jsonify({
        "service": "influxdb-monitor",
        "version": "1.0.0",
        "uptime": time.time(),
        "config": {
            "influxdb_url": monitor.influxdb_url,
            "org": monitor.org,
            "bucket": monitor.bucket,
            "check_interval": monitor.check_interval
        }
    })

def main():
    """Main monitoring loop"""
    logger.info("Starting InfluxDB Monitor Service")
    
    # Start Flask app in a separate thread
    import threading
    flask_thread = threading.Thread(target=lambda: app.run(host='0.0.0.0', port=3000, debug=False))
    flask_thread.daemon = True
    flask_thread.start()
    
    logger.info("Monitor service started on port 3000")
    
    # Main monitoring loop
    while True:
        try:
            health_data = monitor.run_health_check()
            
            # Check for critical issues
            if health_data['influxdb']['status'] != 'healthy':
                logger.error(f"InfluxDB health check failed: {health_data['influxdb']}")
            
            if health_data['backup_service']['status'] != 'running':
                logger.warning(f"Backup service not running: {health_data['backup_service']}")
            
            # Wait for next check
            time.sleep(monitor.check_interval)
            
        except KeyboardInterrupt:
            logger.info("Shutting down monitor service")
            break
        except Exception as e:
            logger.error(f"Error in monitoring loop: {e}")
            time.sleep(10)

if __name__ == "__main__":
    main()
