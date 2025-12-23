#!/usr/bin/env python3
"""
Parental Control Web Server
Central management interface for remote administration.

Features:
- REST API for all PS scripts
- Web dashboard
- Remote PC management via PSRemoting
- Real-time status monitoring

Usage:
    pip install flask flask-cors
    python web-server.py
    
Then open: http://localhost:5000
"""

import os
import sys
import json
import subprocess
import threading
from pathlib import Path
from datetime import datetime
from functools import wraps

try:
    from flask import Flask, render_template_string, jsonify, request, redirect, url_for, session
    from flask_cors import CORS
except ImportError:
    print("Installing Flask...")
    subprocess.run([sys.executable, "-m", "pip", "install", "flask", "flask-cors"], check=True)
    from flask import Flask, render_template_string, jsonify, request, redirect, url_for, session
    from flask_cors import CORS

# Paths
BASE_DIR = Path(__file__).parent.parent
SCRIPTS_DIR = BASE_DIR / "scripts"
CONFIG_DIR = BASE_DIR / "config"

app = Flask(__name__)
app.secret_key = os.urandom(24)
CORS(app)

# Configuration
ADMIN_USER = "admin"
ADMIN_PASS = "parental123"  # Change this!

# Remote PCs configuration
REMOTE_PCS = []  # Will be loaded from config

def load_remote_pcs():
    global REMOTE_PCS
    config_file = CONFIG_DIR / "remote-pcs.json"
    if config_file.exists():
        try:
            REMOTE_PCS = json.loads(config_file.read_text())
        except:
            REMOTE_PCS = []

def save_remote_pcs():
    config_file = CONFIG_DIR / "remote-pcs.json"
    config_file.write_text(json.dumps(REMOTE_PCS, indent=2))

load_remote_pcs()

# Auth decorator
def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated

# Run PowerShell locally
def run_ps_local(script, args=""):
    script_path = SCRIPTS_DIR / script
    if not script_path.exists():
        return {"error": f"Script not found: {script}"}
    
    cmd = f'powershell -ExecutionPolicy Bypass -File "{script_path}" {args}'
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        
        # Try to parse as JSON
        try:
            return json.loads(output)
        except:
            return {"output": output, "exitCode": result.returncode}
    except subprocess.TimeoutExpired:
        return {"error": "Timeout"}
    except Exception as e:
        return {"error": str(e)}

# Run PowerShell on remote PC
def run_ps_remote(pc_name, script, args=""):
    pc = next((p for p in REMOTE_PCS if p["name"] == pc_name), None)
    if not pc:
        return {"error": f"PC not found: {pc_name}"}
    
    script_path = SCRIPTS_DIR / script
    remote_script = f"C:\\ParentalControl\\scripts\\{script}"
    
    ps_cmd = f'''
    $cred = New-Object PSCredential("{pc['user']}", (ConvertTo-SecureString "{pc['password']}" -AsPlainText -Force))
    Invoke-Command -ComputerName "{pc['ip']}" -Credential $cred -ScriptBlock {{
        Set-Location "C:\\ParentalControl"
        & "{remote_script}" {args}
    }}
    '''
    
    try:
        result = subprocess.run(
            ["powershell", "-Command", ps_cmd],
            capture_output=True, text=True, timeout=30
        )
        output = result.stdout + result.stderr
        try:
            return json.loads(output)
        except:
            return {"output": output, "exitCode": result.returncode}
    except Exception as e:
        return {"error": str(e)}

# HTML Template
DASHBOARD_HTML = '''
<!DOCTYPE html>
<html lang="cs">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Parental Control</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #eee;
            min-height: 100vh;
        }
        .header {
            background: rgba(0,0,0,0.3);
            padding: 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .header h1 { color: #00d4ff; font-size: 24px; }
        .header a { color: #888; text-decoration: none; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .card {
            background: rgba(255,255,255,0.05);
            border-radius: 12px;
            padding: 20px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .card h2 { color: #00d4ff; margin-bottom: 15px; font-size: 18px; }
        .card h3 { color: #fff; margin: 10px 0; font-size: 14px; }
        .status { padding: 5px 12px; border-radius: 20px; font-size: 12px; display: inline-block; }
        .status.ok { background: #00ff8830; color: #00ff88; }
        .status.warn { background: #ffaa0030; color: #ffaa00; }
        .status.error { background: #ff444430; color: #ff4444; }
        .btn {
            background: #00d4ff;
            color: #000;
            border: none;
            padding: 10px 20px;
            border-radius: 8px;
            cursor: pointer;
            font-weight: bold;
            margin: 5px;
            transition: all 0.2s;
        }
        .btn:hover { background: #00a8cc; transform: translateY(-2px); }
        .btn.danger { background: #ff4444; }
        .btn.secondary { background: #444; color: #fff; }
        input, select {
            background: rgba(255,255,255,0.1);
            border: 1px solid rgba(255,255,255,0.2);
            padding: 10px;
            border-radius: 8px;
            color: #fff;
            width: 100%;
            margin: 5px 0;
        }
        .pc-list { margin: 10px 0; }
        .pc-item {
            background: rgba(0,0,0,0.2);
            padding: 15px;
            border-radius: 8px;
            margin: 10px 0;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .pc-item .name { font-weight: bold; }
        .pc-item .ip { color: #888; font-size: 12px; }
        .app-list { margin: 10px 0; }
        .app-item {
            display: flex;
            justify-content: space-between;
            padding: 8px;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .modal {
            display: none;
            position: fixed;
            top: 0; left: 0;
            width: 100%; height: 100%;
            background: rgba(0,0,0,0.8);
            z-index: 1000;
            justify-content: center;
            align-items: center;
        }
        .modal.active { display: flex; }
        .modal-content {
            background: #1a1a2e;
            padding: 30px;
            border-radius: 12px;
            max-width: 500px;
            width: 90%;
        }
        .output-box {
            background: #000;
            padding: 15px;
            border-radius: 8px;
            font-family: monospace;
            white-space: pre-wrap;
            max-height: 300px;
            overflow-y: auto;
            font-size: 12px;
        }
        .tabs { display: flex; gap: 10px; margin-bottom: 20px; }
        .tab {
            padding: 10px 20px;
            background: rgba(255,255,255,0.1);
            border-radius: 8px;
            cursor: pointer;
        }
        .tab.active { background: #00d4ff; color: #000; }
        .form-group { margin: 15px 0; }
        .form-group label { display: block; margin-bottom: 5px; color: #888; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Parental Control</h1>
        <div>
            <span>{{ session.get('user', 'Admin') }}</span>
            <a href="/logout">Odhlasit</a>
        </div>
    </div>
    
    <div class="container">
        <div class="tabs">
            <div class="tab active" onclick="showTab('dashboard')">Dashboard</div>
            <div class="tab" onclick="showTab('pcs')">Pocitace</div>
            <div class="tab" onclick="showTab('time')">Casove limity</div>
            <div class="tab" onclick="showTab('apps')">Aplikace</div>
            <div class="tab" onclick="showTab('dns')">DNS</div>
        </div>
        
        <!-- Dashboard -->
        <div id="tab-dashboard" class="tab-content">
            <div class="grid">
                <div class="card">
                    <h2>Lokalni PC</h2>
                    <div id="local-status">Nacitani...</div>
                </div>
                
                <div class="card">
                    <h2>Vzdalene PC</h2>
                    <div id="remote-pcs"></div>
                    <button class="btn secondary" onclick="showAddPc()">Pridat PC</button>
                </div>
                
                <div class="card">
                    <h2>Rychle akce</h2>
                    <button class="btn" onclick="runLocal('time-control.ps1', '-ShowStatus')">Stav casu</button>
                    <button class="btn" onclick="runLocal('app-limits.ps1', '-Status')">Stav aplikaci</button>
                    <button class="btn" onclick="runLocal('adguard-manager.ps1', '-Status')">Stav DNS</button>
                </div>
            </div>
        </div>
        
        <!-- PCs -->
        <div id="tab-pcs" class="tab-content" style="display:none">
            <div class="card">
                <h2>Spravovane pocitace</h2>
                <div id="pc-list"></div>
                <button class="btn" onclick="showAddPc()">Pridat pocitac</button>
            </div>
        </div>
        
        <!-- Time -->
        <div id="tab-time" class="tab-content" style="display:none">
            <div class="card">
                <h2>Casove limity</h2>
                <div id="time-config"></div>
                <button class="btn" onclick="loadTimeConfig()">Nacist</button>
                <button class="btn" onclick="saveTimeConfig()">Ulozit</button>
            </div>
        </div>
        
        <!-- Apps -->
        <div id="tab-apps" class="tab-content" style="display:none">
            <div class="card">
                <h2>Limity aplikaci</h2>
                <button class="btn" onclick="detectApps()">Detekovat aplikace</button>
                <div id="detected-apps"></div>
            </div>
        </div>
        
        <!-- DNS -->
        <div id="tab-dns" class="tab-content" style="display:none">
            <div class="card">
                <h2>AdGuard Home</h2>
                <div id="dns-status"></div>
                <button class="btn" onclick="runLocal('adguard-manager.ps1', '-Status')">Stav</button>
                <button class="btn" onclick="openAdguard()">Otevrit AdGuard</button>
            </div>
        </div>
    </div>
    
    <!-- Modal -->
    <div id="modal" class="modal">
        <div class="modal-content">
            <h2 id="modal-title">Output</h2>
            <div id="modal-body"></div>
            <button class="btn secondary" onclick="closeModal()">Zavrit</button>
        </div>
    </div>
    
    <!-- Add PC Modal -->
    <div id="add-pc-modal" class="modal">
        <div class="modal-content">
            <h2>Pridat pocitac</h2>
            <div class="form-group">
                <label>Nazev</label>
                <input type="text" id="pc-name" placeholder="Detske PC">
            </div>
            <div class="form-group">
                <label>IP adresa</label>
                <input type="text" id="pc-ip" placeholder="192.168.0.100">
            </div>
            <div class="form-group">
                <label>Uzivatel</label>
                <input type="text" id="pc-user" placeholder="rdpuser">
            </div>
            <div class="form-group">
                <label>Heslo</label>
                <input type="password" id="pc-pass">
            </div>
            <button class="btn" onclick="addPc()">Pridat</button>
            <button class="btn secondary" onclick="closeAddPc()">Zrusit</button>
        </div>
    </div>
    
    <script>
        // Tab switching
        function showTab(name) {
            document.querySelectorAll('.tab-content').forEach(t => t.style.display = 'none');
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.getElementById('tab-' + name).style.display = 'block';
            event.target.classList.add('active');
        }
        
        // Modal
        function showModal(title, content) {
            document.getElementById('modal-title').textContent = title;
            document.getElementById('modal-body').innerHTML = content;
            document.getElementById('modal').classList.add('active');
        }
        
        function closeModal() {
            document.getElementById('modal').classList.remove('active');
        }
        
        // Run local script
        async function runLocal(script, args) {
            showModal('Spoustim...', '<div class="output-box">Cekejte...</div>');
            try {
                const res = await fetch(`/api/local/${script}?args=${encodeURIComponent(args)}`);
                const data = await res.json();
                const output = data.output || JSON.stringify(data, null, 2);
                showModal('Vysledek', `<div class="output-box">${escapeHtml(output)}</div>`);
            } catch (e) {
                showModal('Chyba', `<div class="output-box">${e}</div>`);
            }
        }
        
        // Run remote script
        async function runRemote(pcName, script, args) {
            showModal('Spoustim na ' + pcName, '<div class="output-box">Cekejte...</div>');
            try {
                const res = await fetch(`/api/remote/${pcName}/${script}?args=${encodeURIComponent(args)}`);
                const data = await res.json();
                const output = data.output || JSON.stringify(data, null, 2);
                showModal('Vysledek', `<div class="output-box">${escapeHtml(output)}</div>`);
            } catch (e) {
                showModal('Chyba', `<div class="output-box">${e}</div>`);
            }
        }
        
        // Load status
        async function loadStatus() {
            try {
                // Local status
                const local = await fetch('/api/local/time-control.ps1?args=-StatusJson');
                const localData = await local.json();
                document.getElementById('local-status').innerHTML = formatStatus(localData);
                
                // Remote PCs
                const pcs = await fetch('/api/pcs');
                const pcsData = await pcs.json();
                document.getElementById('remote-pcs').innerHTML = pcsData.map(pc => `
                    <div class="pc-item">
                        <div>
                            <div class="name">${pc.name}</div>
                            <div class="ip">${pc.ip}</div>
                        </div>
                        <button class="btn secondary" onclick="runRemote('${pc.name}', 'time-control.ps1', '-StatusJson')">Stav</button>
                    </div>
                `).join('');
                
                document.getElementById('pc-list').innerHTML = pcsData.map(pc => `
                    <div class="pc-item">
                        <div>
                            <div class="name">${pc.name}</div>
                            <div class="ip">${pc.ip} (${pc.user})</div>
                        </div>
                        <div>
                            <button class="btn secondary" onclick="runRemote('${pc.name}', 'time-control.ps1', '-ShowStatus')">Cas</button>
                            <button class="btn secondary" onclick="runRemote('${pc.name}', 'app-limits.ps1', '-Status')">Appky</button>
                            <button class="btn danger" onclick="removePc('${pc.name}')">Odebrat</button>
                        </div>
                    </div>
                `).join('');
            } catch (e) {
                console.error(e);
            }
        }
        
        function formatStatus(data) {
            if (data.error) return `<span class="status error">${data.error}</span>`;
            if (data.dailyLimit) {
                return `
                    <div>PC: ${data.computer || 'Local'}</div>
                    <div>Limit: ${data.dailyLimit.limitHours}h</div>
                    <div>Pouzito: ${data.dailyLimit.usedMinutes}m</div>
                    <div>Zbyva: <span class="status ${data.dailyLimit.remainingMinutes > 30 ? 'ok' : 'warn'}">${data.dailyLimit.remainingMinutes}m</span></div>
                `;
            }
            return `<div class="output-box">${JSON.stringify(data, null, 2)}</div>`;
        }
        
        // Detect apps
        async function detectApps() {
            document.getElementById('detected-apps').innerHTML = '<div>Detekuji...</div>';
            try {
                const res = await fetch('/api/local/app-limits.ps1?args=-DetectJson');
                const data = await res.json();
                if (data.apps) {
                    document.getElementById('detected-apps').innerHTML = `
                        <div class="app-list">
                            ${data.apps.map(app => `
                                <div class="app-item">
                                    <span>${app.name} (${app.category})</span>
                                    <span class="status ${app.running ? 'ok' : ''}">${app.running ? 'RUNNING' : ''}</span>
                                </div>
                            `).join('')}
                        </div>
                    `;
                }
            } catch (e) {
                document.getElementById('detected-apps').innerHTML = `<div class="status error">${e}</div>`;
            }
        }
        
        // Add PC
        function showAddPc() {
            document.getElementById('add-pc-modal').classList.add('active');
        }
        
        function closeAddPc() {
            document.getElementById('add-pc-modal').classList.remove('active');
        }
        
        async function addPc() {
            const pc = {
                name: document.getElementById('pc-name').value,
                ip: document.getElementById('pc-ip').value,
                user: document.getElementById('pc-user').value,
                password: document.getElementById('pc-pass').value
            };
            
            await fetch('/api/pcs', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(pc)
            });
            
            closeAddPc();
            loadStatus();
        }
        
        async function removePc(name) {
            if (confirm('Odebrat ' + name + '?')) {
                await fetch('/api/pcs/' + name, {method: 'DELETE'});
                loadStatus();
            }
        }
        
        function openAdguard() {
            window.open('http://127.0.0.1', '_blank');
        }
        
        function escapeHtml(text) {
            return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        }
        
        // Initial load
        loadStatus();
        setInterval(loadStatus, 30000);
    </script>
</body>
</html>
'''

LOGIN_HTML = '''
<!DOCTYPE html>
<html>
<head>
    <title>Login - Parental Control</title>
    <style>
        body {
            font-family: 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #1a1a2e, #16213e);
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            color: #fff;
        }
        .login-box {
            background: rgba(255,255,255,0.05);
            padding: 40px;
            border-radius: 12px;
            border: 1px solid rgba(255,255,255,0.1);
            width: 300px;
        }
        h1 { color: #00d4ff; margin-bottom: 30px; text-align: center; }
        input {
            width: 100%;
            padding: 12px;
            margin: 10px 0;
            border: 1px solid rgba(255,255,255,0.2);
            border-radius: 8px;
            background: rgba(255,255,255,0.1);
            color: #fff;
        }
        button {
            width: 100%;
            padding: 12px;
            background: #00d4ff;
            border: none;
            border-radius: 8px;
            color: #000;
            font-weight: bold;
            cursor: pointer;
            margin-top: 20px;
        }
        .error { color: #ff4444; text-align: center; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="login-box">
        <h1>Parental Control</h1>
        {% if error %}<div class="error">{{ error }}</div>{% endif %}
        <form method="POST">
            <input type="text" name="username" placeholder="Uzivatel" required>
            <input type="password" name="password" placeholder="Heslo" required>
            <button type="submit">Prihlasit</button>
        </form>
    </div>
</body>
</html>
'''

# Routes
@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        if request.form['username'] == ADMIN_USER and request.form['password'] == ADMIN_PASS:
            session['logged_in'] = True
            session['user'] = request.form['username']
            return redirect('/')
        error = 'Spatne prihlaseni'
    return render_template_string(LOGIN_HTML, error=error)

@app.route('/logout')
def logout():
    session.clear()
    return redirect('/login')

@app.route('/')
@login_required
def dashboard():
    return render_template_string(DASHBOARD_HTML, session=session)

# API Routes
@app.route('/api/local/<script>')
@login_required
def api_local(script):
    args = request.args.get('args', '')
    return jsonify(run_ps_local(script, args))

@app.route('/api/remote/<pc_name>/<script>')
@login_required
def api_remote(pc_name, script):
    args = request.args.get('args', '')
    return jsonify(run_ps_remote(pc_name, script, args))

@app.route('/api/pcs', methods=['GET', 'POST'])
@login_required
def api_pcs():
    if request.method == 'POST':
        pc = request.json
        REMOTE_PCS.append(pc)
        save_remote_pcs()
        return jsonify({"ok": True})
    return jsonify(REMOTE_PCS)

@app.route('/api/pcs/<name>', methods=['DELETE'])
@login_required
def api_pcs_delete(name):
    global REMOTE_PCS
    REMOTE_PCS = [p for p in REMOTE_PCS if p['name'] != name]
    save_remote_pcs()
    return jsonify({"ok": True})

@app.route('/api/config/<name>', methods=['GET', 'PUT'])
@login_required
def api_config(name):
    config_file = CONFIG_DIR / name
    if request.method == 'PUT':
        config_file.write_text(json.dumps(request.json, indent=2))
        return jsonify({"ok": True})
    if config_file.exists():
        return jsonify(json.loads(config_file.read_text()))
    return jsonify({})

if __name__ == '__main__':
    print("\n" + "="*50)
    print("  Parental Control Web Server")
    print("="*50)
    print(f"\n  URL: http://localhost:5000")
    print(f"  User: {ADMIN_USER}")
    print(f"  Pass: {ADMIN_PASS}")
    print("\n  Zmenit heslo v souboru web-server.py")
    print("="*50 + "\n")
    
    app.run(host='0.0.0.0', port=5000, debug=True)

