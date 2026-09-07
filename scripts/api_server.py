#!/usr/bin/env python3
"""
API Server for Real-Time Social Media Feed
Bridges the frontend (JavaScript) to the Bash backend
"""

import json
import subprocess
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import threading
import time

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKEND_DIR = os.path.join(PROJECT_ROOT, 'backend')
SCRIPTS_DIR = os.path.join(PROJECT_ROOT, 'scripts')

# Default configuration (from config.sh)
DEFAULT_PRODUCERS = 3
DEFAULT_WORKERS = 2

class APIHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        
        if path == '/api/status':
            self.handle_status()
        elif path == '/api/feed':
            self.handle_feed(query)
        elif path == '/api/processes':
            self.handle_processes()
        elif path == '/api/queue':
            self.handle_queue()
        elif path == '/api/stats':
            self.handle_stats()
        elif path == '/api/resources':
            self.handle_resources()
        elif path == '/api/logs':
            self.handle_logs(query)
        elif path == '/api/health':
            self.handle_health()
        else:
            self.send_error(404, 'Not Found')
    
    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8') if content_length > 0 else '{}'
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            data = {}
        
        if path == '/api/command':
            self.handle_command(data)
        else:
            self.send_error(404, 'Not Found')
    
    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))
    
    def run_bash(self, cli_cmd, args=None, env=None):
        """Run a bash CLI command and return parsed JSON output"""
        cli_script = os.path.join(BACKEND_DIR, 'backend_cli.sh')
        cmd = ['bash', cli_script, cli_cmd]
        if args:
            cmd.extend(args)
        
        # Merge environment
        full_env = os.environ.copy()
        full_env['PROJECT_ROOT'] = PROJECT_ROOT
        if env:
            full_env.update(env)
        
        try:
            result = subprocess.run(
                cmd,
                cwd=PROJECT_ROOT,
                capture_output=True,
                text=True,
                timeout=10,
                env=full_env
            )
            if result.returncode != 0:
                print(f"Bash CLI error: {result.stderr}", file=sys.stderr)
                return None
            
            # Try to parse JSON from stdout
            stdout = result.stdout.strip()
            if stdout:
                try:
                    return json.loads(stdout)
                except json.JSONDecodeError:
                    # If not JSON, return as string
                    return stdout
            return None
        except subprocess.TimeoutExpired:
            print(f"Bash CLI timeout: {cli_cmd}", file=sys.stderr)
            return None
        except Exception as e:
            print(f"Error running bash CLI: {e}", file=sys.stderr)
            return None
    
    def handle_status(self):
        """Get system status"""
        result = self.run_bash('sys:status')
        if result:
            self.send_json(result)
        else:
            # Fallback: construct status from PID files
            status = self.get_fallback_status()
            self.send_json(status)
    
    def get_fallback_status(self):
        pids_dir = os.path.join(PROJECT_ROOT, 'runtime/pids')
        manager_pid = ''
        manager_status = 'STOPPED'
        producers = 0
        running_producers = 0
        workers = 0
        running_workers = 0
        
        if os.path.exists(pids_dir):
            for f in os.listdir(pids_dir):
                if f.endswith('.pid'):
                    path = os.path.join(pids_dir, f)
                    try:
                        with open(path) as pf:
                            pid = int(pf.read().strip())
                        running = self.is_process_running(pid)
                        if f == 'manager.pid':
                            manager_pid = pid
                            manager_status = 'RUNNING' if running else 'STOPPED'
                        elif f.startswith('producer-'):
                            producers += 1
                            if running: running_producers += 1
                        elif f.startswith('worker-'):
                            workers += 1
                            if running: running_workers += 1
                    except:
                        pass
        
        return {
            'manager': {'pid': manager_pid, 'status': manager_status},
            'producers': {'total': producers, 'running': running_producers},
            'workers': {'total': workers, 'running': running_workers},
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S')
        }
    
    def is_process_running(self, pid):
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    
    def handle_feed(self, query):
        """Get feed data"""
        page = int(query.get('page', ['1'])[0])
        page_size = int(query.get('page_size', ['20'])[0])
        
        result = self.run_bash('feed:display', [str(page), str(page_size)])
        if result:
            self.send_json(result)
        else:
            self.send_json({'posts': [], 'stats': {}, 'page': page, 'page_size': page_size})
    
    def handle_processes(self):
        """Get process list"""
        result = self.run_bash('proc:list-all')
        if result and isinstance(result, list):
            # Convert to expected format
            processes = []
            for p in result:
                if isinstance(p, dict):
                    processes.append({
                        'name': p.get('name', ''),
                        'type': p.get('type', ''),
                        'pid': p.get('pid', 0),
                        'status': p.get('status', 'UNKNOWN'),
                        'events_processed': p.get('events_processed', 0),
                        'start_time': p.get('start_time', '')
                    })
            self.send_json(processes)
        else:
            self.send_json([])
    
    def handle_queue(self):
        """Get queue status"""
        result = self.run_bash('queue:stats')
        if result:
            # Also get events for display
            events_result = self.run_bash('queue:get-all', ['50'])
            if events_result and isinstance(events_result, list):
                result['events'] = events_result
            self.send_json(result)
        else:
            self.send_json({'size': 0, 'by_type': {}, 'by_priority': {}, 'events': []})
    
    def handle_stats(self):
        """Get statistics"""
        result = self.run_bash('stats:display')
        if result:
            self.send_json(result)
        else:
            self.send_json({})
    
    def handle_resources(self):
        """Get system resources"""
        result = self.run_bash('res:all')
        if result:
            self.send_json(result)
        else:
            self.send_json({})
    
    def handle_logs(self, query):
        """Get logs"""
        category = query.get('category', ['SYSTEM'])[0]
        lines = int(query.get('lines', ['100'])[0])
        
        log_file_map = {
            'SYSTEM': 'system.log',
            'EVENT': 'events.log',
            'EVENTS': 'events.log',
            'WORKER': 'workers.log',
            'WORKERS': 'workers.log',
            'PRODUCER': 'system.log',
            'QUEUE': 'system.log',
            'FEED': 'system.log',
            'SYNC': 'system.log',
            'PROCESS': 'system.log',
        }
        
        log_file = log_file_map.get(category, 'system.log')
        log_path = os.path.join(PROJECT_ROOT, 'logs', log_file)
        
        logs = []
        if os.path.exists(log_path):
            with open(log_path, 'r') as f:
                lines_list = f.readlines()[-lines:]
                for line in lines_list:
                    parsed = self.parse_log_line(line.strip())
                    if parsed:
                        logs.append(parsed)
        
        self.send_json(logs)
    
    def parse_log_line(self, line):
        """Parse a log line into structured data"""
        # Format: [TIMESTAMP] PID=xxx USER=xxx CATEGORY=xxx LEVEL=xxx [EVENT_ID=xxx] [EVENT_TYPE=xxx] [STATUS=xxx] MSG="xxx"
        import re
        
        # Extract timestamp
        ts_match = re.match(r'\[([^\]]+)\]', line)
        timestamp = ts_match.group(1) if ts_match else ''
        
        # Extract key-value pairs
        data = {'timestamp': timestamp}
        
        # PID
        pid_match = re.search(r'PID=(\S+)', line)
        if pid_match: data['PID'] = pid_match.group(1)
        
        # USER
        user_match = re.search(r'USER=(\S+)', line)
        if user_match: data['USER'] = user_match.group(1)
        
        # CATEGORY
        cat_match = re.search(r'CATEGORY=(\S+)', line)
        if cat_match: data['CATEGORY'] = cat_match.group(1)
        
        # LEVEL
        lvl_match = re.search(r'LEVEL=(\S+)', line)
        if lvl_match: data['LEVEL'] = lvl_match.group(1)
        
        # EVENT_ID
        eid_match = re.search(r'EVENT_ID=(\S+)', line)
        if eid_match: data['EVENT_ID'] = eid_match.group(1)
        
        # EVENT_TYPE
        etype_match = re.search(r'EVENT_TYPE=(\S+)', line)
        if etype_match: data['EVENT_TYPE'] = etype_match.group(1)
        
        # STATUS
        status_match = re.search(r'STATUS=(\S+)', line)
        if status_match: data['STATUS'] = status_match.group(1)
        
        # MSG
        msg_match = re.search(r'MSG="([^"]*)"', line)
        if msg_match: data['MSG'] = msg_match.group(1)
        
        return data
    
    def handle_health(self):
        """Health check"""
        result = self.run_bash('sys:health')
        if result:
            self.send_json(result)
        else:
            self.send_json({'status': 'UNKNOWN', 'issues': ['Health check failed']})
    
    def handle_command(self, data):
        """Execute a command"""
        cmd = data.get('command', '')
        args = data.get('args', '')
        
        if not cmd:
            self.send_json({'success': False, 'error': 'No command specified'}, 400)
            return
        
        # Map commands to CLI commands
        try:
            if cmd == 'start':
                # Start system in background
                def run_start():
                    self.run_bash('sys:start', [str(DEFAULT_PRODUCERS), str(DEFAULT_WORKERS)])
                
                thread = threading.Thread(target=run_start)
                thread.daemon = True
                thread.start()
                self.send_json({'success': True, 'message': 'System start initiated'})
                
            elif cmd == 'stop':
                def run_stop():
                    self.run_bash('sys:stop')
                
                thread = threading.Thread(target=run_stop)
                thread.daemon = True
                thread.start()
                self.send_json({'success': True, 'message': 'System stop initiated'})
                
            elif cmd == 'restart':
                def run_restart():
                    self.run_bash('sys:stop')
                    time.sleep(2)
                    self.run_bash('sys:start', [str(DEFAULT_PRODUCERS), str(DEFAULT_WORKERS)])
                
                thread = threading.Thread(target=run_restart)
                thread.daemon = True
                thread.start()
                self.send_json({'success': True, 'message': 'System restart initiated'})
                
            elif cmd == 'simulate':
                parts = args.split()
                if parts and parts[0] == 'burst':
                    self.run_bash('event:create', ['user_1', 'TestUser', 'POST', 'Burst post'])
                    self.send_json({'success': True})
                elif parts and parts[0] == 'start':
                    # Start simulator
                    def run_sim():
                        self.run_bash('proc:start-producer', ['simulator'])
                    thread = threading.Thread(target=run_sim)
                    thread.daemon = True
                    thread.start()
                    self.send_json({'success': True, 'message': 'Simulator start initiated'})
                elif parts and parts[0] == 'stop':
                    self.run_bash('proc:stop-producer', ['simulator'])
                    self.send_json({'success': True})
                else:
                    self.send_json({'success': False, 'error': 'Invalid simulate command'}, 400)
                    
            elif cmd == 'add':
                parts = args.split()
                if parts:
                    proc_type = parts[0]
                    if proc_type == 'producer':
                        self.run_bash('proc:start-producer')
                        self.send_json({'success': True})
                    elif proc_type == 'worker':
                        self.run_bash('proc:start-worker')
                        self.send_json({'success': True})
                    else:
                        self.send_json({'success': False, 'error': 'Invalid process type'}, 400)
                else:
                    self.send_json({'success': False, 'error': 'Missing process type'}, 400)
                    
            elif cmd == 'remove':
                parts = args.split()
                if parts:
                    proc_type = parts[0]
                    if proc_type == 'producer':
                        self.run_bash('proc:stop-producer')
                        self.send_json({'success': True})
                    elif proc_type == 'worker':
                        self.run_bash('proc:stop-worker')
                        self.send_json({'success': True})
                    else:
                        self.send_json({'success': False, 'error': 'Invalid process type'}, 400)
                else:
                    self.send_json({'success': False, 'error': 'Missing process type'}, 400)
                    
            elif cmd == 'event':
                parts = args.split(' ', 1)
                event_type = parts[0] if parts else 'POST'
                content = parts[1] if len(parts) > 1 else ''
                # Create event using user_1 as default
                result = self.run_bash('event:create', ['user_1', 'TestUser', event_type, content, '', '', '5'])
                if result:
                    self.send_json({'success': True, 'result': result})
                else:
                    self.send_json({'success': False, 'error': 'Failed to create event'}, 500)
                    
            elif cmd == 'clear':
                self.run_bash('log:clear')
                self.send_json({'success': True})
                
            else:
                self.send_json({'success': False, 'error': f'Unknown command: {cmd}'}, 400)
                
        except Exception as e:
            self.send_json({'success': False, 'error': str(e)}, 500)
    
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default log messages
        pass

def run_server(port=8080):
    server = HTTPServer(('', port), APIHandler)
    print(f"API Server starting on http://localhost:{port}")
    print(f"Project root: {PROJECT_ROOT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.shutdown()

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    run_server(port)