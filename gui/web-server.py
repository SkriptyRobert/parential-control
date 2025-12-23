#!/usr/bin/env python3
"""
Parental Control Web Server v2
Intuitive remote management for parents.
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
    subprocess.run([sys.executable, "-m", "pip", "install", "flask", "flask-cors"], check=True)
    from flask import Flask, render_template_string, jsonify, request, redirect, url_for, session
    from flask_cors import CORS

# Auto-detect paths
def find_project_path():
    # Try common locations
    paths = [
        Path(__file__).parent.parent,  # gui/../
        Path("C:/ParentalControl"),
        Path("C:/Users") / os.environ.get("USERNAME", "") / "Documents/parential-control",
        Path("C:/Users") / os.environ.get("USERNAME", "") / "Documents/Parental-Control",
    ]
    for p in paths:
        if (p / "scripts").exists():
            return p
    return Path(__file__).parent.parent

BASE_DIR = find_project_path()
SCRIPTS_DIR = BASE_DIR / "scripts"
CONFIG_DIR = BASE_DIR / "config"

app = Flask(__name__)
app.secret_key = os.urandom(24)
CORS(app)

# Settings
SETTINGS_FILE = CONFIG_DIR / "web-settings.json"

def load_settings():
    defaults = {
        "admin_user": "admin",
        "admin_pass": "parental123",
        "project_path": str(BASE_DIR),
        "remote_pcs": []
    }
    if SETTINGS_FILE.exists():
        try:
            saved = json.loads(SETTINGS_FILE.read_text())
            defaults.update(saved)
        except: pass
    # Also load remote-pcs.json
    rpc_file = CONFIG_DIR / "remote-pcs.json"
    if rpc_file.exists():
        try:
            defaults["remote_pcs"] = json.loads(rpc_file.read_text())
        except: pass
    return defaults

def save_settings(settings):
    SETTINGS_FILE.parent.mkdir(parents=True, exist_ok=True)
    # Save remote PCs separately
    rpc_file = CONFIG_DIR / "remote-pcs.json"
    rpc_file.write_text(json.dumps(settings.get("remote_pcs", []), indent=2))
    # Save other settings
    save_data = {k: v for k, v in settings.items() if k != "remote_pcs"}
    SETTINGS_FILE.write_text(json.dumps(save_data, indent=2))

SETTINGS = load_settings()

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated

# PowerShell execution
def run_ps_local(script, args=""):
    global SETTINGS
    scripts_path = Path(SETTINGS.get("project_path", BASE_DIR)) / "scripts"
    script_path = scripts_path / script
    
    if not script_path.exists():
        return {"error": f"Skript nenalezen: {script_path}", "path": str(script_path)}
    
    cmd = f'powershell -ExecutionPolicy Bypass -File "{script_path}" {args}'
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        try:
            return json.loads(output)
        except:
            return {"output": output, "exitCode": result.returncode}
    except subprocess.TimeoutExpired:
        return {"error": "Timeout"}
    except Exception as e:
        return {"error": str(e)}

def run_ps_remote(pc_name, script, args=""):
    global SETTINGS
    pc = next((p for p in SETTINGS.get("remote_pcs", []) if p["name"] == pc_name), None)
    if not pc:
        return {"error": f"PC nenalezeno: {pc_name}"}
    
    remote_path = pc.get("path", "C:\\ParentalControl")
    
    ps_cmd = f'''
$ErrorActionPreference = "SilentlyContinue"
$cred = New-Object PSCredential("{pc['user']}", (ConvertTo-SecureString "{pc['password']}" -AsPlainText -Force))
try {{
    $result = Invoke-Command -ComputerName "{pc['ip']}" -Credential $cred -ScriptBlock {{
        Set-Location "{remote_path}"
        & ".\\scripts\\{script}" {args}
    }} -ErrorAction Stop
    $result
}} catch {{
    Write-Output ("ERROR: " + $_.Exception.Message)
}}
'''
    try:
        result = subprocess.run(
            ["powershell", "-Command", ps_cmd],
            capture_output=True, text=True, timeout=30
        )
        output = result.stdout.strip()
        if output.startswith("ERROR:"):
            return {"error": output[7:], "connected": False}
        try:
            return json.loads(output)
        except:
            return {"output": output, "connected": True}
    except Exception as e:
        return {"error": str(e), "connected": False}

def test_connection(pc):
    """Test if PC is reachable"""
    ps_cmd = f'''
$cred = New-Object PSCredential("{pc['user']}", (ConvertTo-SecureString "{pc['password']}" -AsPlainText -Force))
try {{
    $result = Invoke-Command -ComputerName "{pc['ip']}" -Credential $cred -ScriptBlock {{
        @{{
            computer = $env:COMPUTERNAME
            user = $env:USERNAME
            time = (Get-Date).ToString("HH:mm:ss")
            path = if (Test-Path "C:\\ParentalControl") {{ "C:\\ParentalControl" }} 
                   elseif (Test-Path "$env:USERPROFILE\\Documents\\parential-control") {{ "$env:USERPROFILE\\Documents\\parential-control" }}
                   else {{ "NOT_FOUND" }}
        }} | ConvertTo-Json
    }} -ErrorAction Stop
    $result
}} catch {{
    @{{ error = $_.Exception.Message }} | ConvertTo-Json
}}
'''
    try:
        result = subprocess.run(["powershell", "-Command", ps_cmd], capture_output=True, text=True, timeout=15)
        data = json.loads(result.stdout.strip())
        if "error" in data:
            return {"connected": False, "error": data["error"]}
        return {"connected": True, **data}
    except Exception as e:
        return {"connected": False, "error": str(e)}

# HTML Template - Simplified & Intuitive
HTML = '''
<!DOCTYPE html>
<html lang="cs">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Parental Control</title>
    <style>
        :root {
            --bg: #0f0f1a;
            --card: #1a1a2e;
            --accent: #00d4ff;
            --success: #00ff88;
            --warning: #ffaa00;
            --danger: #ff4444;
            --text: #ffffff;
            --muted: #888888;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', system-ui, sans-serif;
            background: var(--bg);
            color: var(--text);
            min-height: 100vh;
        }
        
        /* Header */
        .header {
            background: var(--card);
            padding: 15px 30px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .logo { font-size: 22px; font-weight: bold; color: var(--accent); }
        .user-info { display: flex; align-items: center; gap: 15px; }
        .user-info a { color: var(--muted); text-decoration: none; }
        
        /* Navigation */
        .nav {
            background: var(--card);
            display: flex;
            gap: 5px;
            padding: 10px 30px;
            border-bottom: 1px solid rgba(255,255,255,0.1);
            flex-wrap: wrap;
        }
        .nav-btn {
            padding: 12px 24px;
            background: transparent;
            border: none;
            color: var(--text);
            cursor: pointer;
            border-radius: 8px;
            font-size: 14px;
            transition: all 0.2s;
        }
        .nav-btn:hover { background: rgba(255,255,255,0.1); }
        .nav-btn.active { background: var(--accent); color: #000; font-weight: bold; }
        
        /* Main */
        .main { padding: 30px; max-width: 1400px; margin: 0 auto; }
        .page { display: none; }
        .page.active { display: block; }
        
        /* Cards */
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(350px, 1fr)); gap: 20px; }
        .card {
            background: var(--card);
            border-radius: 16px;
            padding: 25px;
            border: 1px solid rgba(255,255,255,0.05);
        }
        .card-title {
            font-size: 18px;
            font-weight: bold;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .card-title .icon { font-size: 24px; }
        
        /* Status indicators */
        .status {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 6px 14px;
            border-radius: 20px;
            font-size: 13px;
            font-weight: 500;
        }
        .status.online { background: rgba(0,255,136,0.15); color: var(--success); }
        .status.offline { background: rgba(255,68,68,0.15); color: var(--danger); }
        .status.warning { background: rgba(255,170,0,0.15); color: var(--warning); }
        .status-dot {
            width: 8px; height: 8px;
            border-radius: 50%;
            background: currentColor;
        }
        
        /* PC List */
        .pc-card {
            background: rgba(0,0,0,0.2);
            border-radius: 12px;
            padding: 20px;
            margin: 15px 0;
        }
        .pc-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }
        .pc-name { font-size: 18px; font-weight: bold; }
        .pc-ip { color: var(--muted); font-size: 13px; }
        .pc-stats {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 15px;
            margin: 15px 0;
        }
        .stat-box {
            background: rgba(255,255,255,0.05);
            padding: 15px;
            border-radius: 10px;
            text-align: center;
        }
        .stat-value { font-size: 24px; font-weight: bold; color: var(--accent); }
        .stat-label { font-size: 12px; color: var(--muted); margin-top: 5px; }
        .pc-actions { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 15px; }
        
        /* Buttons */
        .btn {
            padding: 10px 20px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            transition: all 0.2s;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }
        .btn-primary { background: var(--accent); color: #000; }
        .btn-primary:hover { background: #00a8cc; transform: translateY(-2px); }
        .btn-secondary { background: rgba(255,255,255,0.1); color: var(--text); }
        .btn-secondary:hover { background: rgba(255,255,255,0.2); }
        .btn-success { background: var(--success); color: #000; }
        .btn-danger { background: var(--danger); color: #fff; }
        .btn-sm { padding: 8px 14px; font-size: 13px; }
        
        /* Forms */
        .form-group { margin: 15px 0; }
        .form-group label { display: block; margin-bottom: 8px; color: var(--muted); font-size: 14px; }
        input, select {
            width: 100%;
            padding: 12px 16px;
            background: rgba(255,255,255,0.05);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 10px;
            color: var(--text);
            font-size: 14px;
        }
        input:focus, select:focus {
            outline: none;
            border-color: var(--accent);
        }
        
        /* Modal */
        .modal {
            display: none;
            position: fixed;
            top: 0; left: 0;
            width: 100%; height: 100%;
            background: rgba(0,0,0,0.8);
            z-index: 1000;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .modal.active { display: flex; }
        .modal-content {
            background: var(--card);
            border-radius: 16px;
            padding: 30px;
            max-width: 500px;
            width: 100%;
            max-height: 80vh;
            overflow-y: auto;
        }
        .modal-title { font-size: 20px; margin-bottom: 20px; }
        
        /* Output */
        .output {
            background: #000;
            padding: 15px;
            border-radius: 10px;
            font-family: 'Consolas', monospace;
            font-size: 13px;
            white-space: pre-wrap;
            max-height: 300px;
            overflow-y: auto;
            color: #0f0;
        }
        
        /* Time config */
        .time-row {
            display: grid;
            grid-template-columns: 120px 1fr 1fr;
            gap: 15px;
            align-items: center;
            padding: 12px;
            background: rgba(255,255,255,0.03);
            border-radius: 8px;
            margin: 8px 0;
        }
        .time-row .day { font-weight: 500; }
        
        /* App item */
        .app-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 15px;
            background: rgba(255,255,255,0.03);
            border-radius: 10px;
            margin: 10px 0;
        }
        .app-info { display: flex; align-items: center; gap: 12px; }
        .app-icon { font-size: 24px; }
        .app-name { font-weight: 500; }
        .app-category { font-size: 12px; color: var(--muted); }
        
        /* Toggle */
        .toggle {
            width: 50px; height: 26px;
            background: rgba(255,255,255,0.2);
            border-radius: 13px;
            position: relative;
            cursor: pointer;
        }
        .toggle.active { background: var(--success); }
        .toggle::after {
            content: '';
            position: absolute;
            width: 22px; height: 22px;
            background: white;
            border-radius: 50%;
            top: 2px; left: 2px;
            transition: 0.2s;
        }
        .toggle.active::after { left: 26px; }
        
        /* Settings path */
        .path-box {
            display: flex;
            gap: 10px;
            align-items: center;
        }
        .path-box input { flex: 1; }
        
        /* Responsive */
        @media (max-width: 768px) {
            .nav { padding: 10px 15px; }
            .nav-btn { padding: 10px 16px; font-size: 13px; }
            .main { padding: 15px; }
            .grid { grid-template-columns: 1fr; }
            .pc-stats { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="logo">Parental Control</div>
        <div class="user-info">
            <span>{{ session.get('user', 'Admin') }}</span>
            <a href="/logout">Odhlasit</a>
        </div>
    </div>
    
    <div class="nav">
        <button class="nav-btn active" onclick="showPage('home')">Prehled</button>
        <button class="nav-btn" onclick="showPage('pcs')">Pocitace</button>
        <button class="nav-btn" onclick="showPage('time')">Casove limity</button>
        <button class="nav-btn" onclick="showPage('apps')">Aplikace</button>
        <button class="nav-btn" onclick="showPage('settings')">Nastaveni</button>
    </div>
    
    <div class="main">
        <!-- HOME -->
        <div id="page-home" class="page active">
            <div class="grid">
                <div class="card">
                    <div class="card-title"><span class="icon">🖥️</span> Spravovane pocitace</div>
                    <div id="home-pcs"></div>
                    <button class="btn btn-primary" onclick="showPage('pcs')">Spravovat pocitace</button>
                </div>
                
                <div class="card">
                    <div class="card-title"><span class="icon">⏱️</span> Rychle akce</div>
                    <p style="color: var(--muted); margin-bottom: 15px;">Proved akci na vybranem pocitaci</p>
                    <select id="quick-pc" style="margin-bottom: 15px;"></select>
                    <div style="display: flex; flex-wrap: wrap; gap: 10px;">
                        <button class="btn btn-secondary" onclick="quickAction('time-control.ps1', '-ShowStatus')">Zobrazit cas</button>
                        <button class="btn btn-secondary" onclick="quickAction('app-limits.ps1', '-Status')">Zobrazit appky</button>
                        <button class="btn btn-secondary" onclick="quickAction('adguard-manager.ps1', '-Status')">DNS stav</button>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- PCS -->
        <div id="page-pcs" class="page">
            <div class="card">
                <div class="card-title"><span class="icon">💻</span> Pocitace deti</div>
                <p style="color: var(--muted); margin-bottom: 20px;">Pridejte pocitace, ktere chcete spravovat. Kazdy pocitac musi mit nainstalovan Parental Control.</p>
                
                <div id="pc-list"></div>
                
                <button class="btn btn-primary" onclick="showModal('add-pc')">+ Pridat pocitac</button>
            </div>
        </div>
        
        <!-- TIME -->
        <div id="page-time" class="page">
            <div class="card">
                <div class="card-title"><span class="icon">⏰</span> Casove limity</div>
                <p style="color: var(--muted); margin-bottom: 20px;">Nastavte denni limit a rozvrh pouzivani PC.</p>
                
                <div class="form-group">
                    <label>Vyberte pocitac</label>
                    <select id="time-pc" onchange="loadTimeConfig()"></select>
                </div>
                
                <div id="time-config" style="margin-top: 20px;"></div>
            </div>
        </div>
        
        <!-- APPS -->
        <div id="page-apps" class="page">
            <div class="card">
                <div class="card-title"><span class="icon">📱</span> Limity aplikaci</div>
                <p style="color: var(--muted); margin-bottom: 20px;">Nastavte casove limity pro konkretni aplikace (hry, socialni site...).</p>
                
                <div class="form-group">
                    <label>Vyberte pocitac</label>
                    <select id="apps-pc" onchange="loadAppsStatus()"></select>
                </div>
                
                <button class="btn btn-secondary" onclick="detectApps()" style="margin: 15px 0;">Detekovat aplikace</button>
                
                <div id="apps-list"></div>
            </div>
        </div>
        
        <!-- SETTINGS -->
        <div id="page-settings" class="page">
            <div class="grid">
                <div class="card">
                    <div class="card-title"><span class="icon">📁</span> Cesta k projektu</div>
                    <p style="color: var(--muted); margin-bottom: 15px;">Cesta k slozce Parental Control na tomto PC.</p>
                    <div class="path-box">
                        <input type="text" id="project-path" value="{{ settings.project_path }}">
                        <button class="btn btn-secondary" onclick="detectPath()">Detekovat</button>
                        <button class="btn btn-primary" onclick="savePath()">Ulozit</button>
                    </div>
                </div>
                
                <div class="card">
                    <div class="card-title"><span class="icon">🔐</span> Prihlaseni</div>
                    <div class="form-group">
                        <label>Uzivatel</label>
                        <input type="text" id="admin-user" value="{{ settings.admin_user }}">
                    </div>
                    <div class="form-group">
                        <label>Heslo</label>
                        <input type="password" id="admin-pass" value="{{ settings.admin_pass }}">
                    </div>
                    <button class="btn btn-primary" onclick="saveCredentials()">Ulozit</button>
                </div>
            </div>
        </div>
    </div>
    
    <!-- MODALS -->
    <div id="modal-add-pc" class="modal">
        <div class="modal-content">
            <div class="modal-title">Pridat pocitac</div>
            <div class="form-group">
                <label>Nazev (napr. "Nikolka PC")</label>
                <input type="text" id="new-pc-name" placeholder="Detsky pocitac">
            </div>
            <div class="form-group">
                <label>IP adresa</label>
                <input type="text" id="new-pc-ip" placeholder="192.168.0.100">
            </div>
            <div class="form-group">
                <label>Uzivatel (pro vzdalene pripojeni)</label>
                <input type="text" id="new-pc-user" placeholder="rdpuser">
            </div>
            <div class="form-group">
                <label>Heslo</label>
                <input type="password" id="new-pc-pass">
            </div>
            <div class="form-group">
                <label>Cesta k Parental Control (na vzdalenem PC)</label>
                <input type="text" id="new-pc-path" value="C:\\ParentalControl" placeholder="C:\\ParentalControl">
            </div>
            <div style="display: flex; gap: 10px; margin-top: 20px;">
                <button class="btn btn-primary" onclick="addPc()">Pridat</button>
                <button class="btn btn-secondary" onclick="closeModal('add-pc')">Zrusit</button>
            </div>
        </div>
    </div>
    
    <div id="modal-output" class="modal">
        <div class="modal-content">
            <div class="modal-title" id="output-title">Vysledek</div>
            <div class="output" id="output-content"></div>
            <button class="btn btn-secondary" onclick="closeModal('output')" style="margin-top: 15px;">Zavrit</button>
        </div>
    </div>
    
    <script>
        let pcs = {{ pcs | tojson }};
        let settings = {{ settings | tojson }};
        
        // Navigation
        function showPage(name) {
            document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
            document.getElementById('page-' + name).classList.add('active');
            event.target.classList.add('active');
            
            if (name === 'home') loadHomePcs();
            if (name === 'pcs') loadPcList();
            if (name === 'time') { updatePcSelects(); loadTimeConfig(); }
            if (name === 'apps') { updatePcSelects(); loadAppsStatus(); }
        }
        
        // Modal
        function showModal(name) {
            document.getElementById('modal-' + name).classList.add('active');
        }
        function closeModal(name) {
            document.getElementById('modal-' + name).classList.remove('active');
        }
        function showOutput(title, content) {
            document.getElementById('output-title').textContent = title;
            document.getElementById('output-content').textContent = typeof content === 'object' ? JSON.stringify(content, null, 2) : content;
            showModal('output');
        }
        
        // Update PC selects
        function updatePcSelects() {
            const options = '<option value="local">Tento pocitac</option>' + 
                pcs.map(p => `<option value="${p.name}">${p.name}</option>`).join('');
            ['quick-pc', 'time-pc', 'apps-pc'].forEach(id => {
                const el = document.getElementById(id);
                if (el) el.innerHTML = options;
            });
        }
        
        // Load home PCs
        async function loadHomePcs() {
            updatePcSelects();
            const container = document.getElementById('home-pcs');
            
            if (pcs.length === 0) {
                container.innerHTML = '<p style="color: var(--muted);">Zadne pocitace. Pridejte je v sekci Pocitace.</p>';
                return;
            }
            
            container.innerHTML = pcs.map(pc => `
                <div class="pc-card">
                    <div class="pc-header">
                        <div>
                            <div class="pc-name">${pc.name}</div>
                            <div class="pc-ip">${pc.ip}</div>
                        </div>
                        <span class="status" id="status-${pc.name}">
                            <span class="status-dot"></span> Testuji...
                        </span>
                    </div>
                </div>
            `).join('');
            
            // Test connections
            for (const pc of pcs) {
                testPcConnection(pc.name);
            }
        }
        
        async function testPcConnection(name) {
            const el = document.getElementById('status-' + name);
            try {
                const res = await fetch('/api/test/' + name);
                const data = await res.json();
                if (data.connected) {
                    el.className = 'status online';
                    el.innerHTML = '<span class="status-dot"></span> Online';
                } else {
                    el.className = 'status offline';
                    el.innerHTML = '<span class="status-dot"></span> Offline';
                }
            } catch {
                el.className = 'status offline';
                el.innerHTML = '<span class="status-dot"></span> Chyba';
            }
        }
        
        // Load PC list
        async function loadPcList() {
            const container = document.getElementById('pc-list');
            
            if (pcs.length === 0) {
                container.innerHTML = '<p style="color: var(--muted); padding: 20px;">Zatim zadne pocitace. Kliknete na "Pridat pocitac".</p>';
                return;
            }
            
            container.innerHTML = pcs.map(pc => `
                <div class="pc-card">
                    <div class="pc-header">
                        <div>
                            <div class="pc-name">${pc.name}</div>
                            <div class="pc-ip">${pc.ip} - ${pc.user}</div>
                        </div>
                        <span class="status" id="list-status-${pc.name}">
                            <span class="status-dot"></span> ...
                        </span>
                    </div>
                    <div class="pc-actions">
                        <button class="btn btn-sm btn-secondary" onclick="testAndShow('${pc.name}')">Test spojeni</button>
                        <button class="btn btn-sm btn-secondary" onclick="runRemote('${pc.name}', 'time-control.ps1', '-ShowStatus')">Cas</button>
                        <button class="btn btn-sm btn-secondary" onclick="runRemote('${pc.name}', 'app-limits.ps1', '-Status')">Appky</button>
                        <button class="btn btn-sm btn-danger" onclick="removePc('${pc.name}')">Odebrat</button>
                    </div>
                </div>
            `).join('');
            
            // Test all
            for (const pc of pcs) {
                testPcStatus('list-status-' + pc.name, pc.name);
            }
        }
        
        async function testPcStatus(elId, name) {
            const el = document.getElementById(elId);
            try {
                const res = await fetch('/api/test/' + name);
                const data = await res.json();
                if (data.connected) {
                    el.className = 'status online';
                    el.innerHTML = '<span class="status-dot"></span> Pripojeno';
                } else {
                    el.className = 'status offline';
                    el.innerHTML = '<span class="status-dot"></span> Nedostupne';
                }
            } catch {
                el.className = 'status offline';
                el.innerHTML = '<span class="status-dot"></span> Chyba';
            }
        }
        
        async function testAndShow(name) {
            showOutput('Test spojeni: ' + name, 'Testuji...');
            const res = await fetch('/api/test/' + name);
            const data = await res.json();
            showOutput('Test spojeni: ' + name, data);
        }
        
        // Add PC
        async function addPc() {
            const pc = {
                name: document.getElementById('new-pc-name').value,
                ip: document.getElementById('new-pc-ip').value,
                user: document.getElementById('new-pc-user').value,
                password: document.getElementById('new-pc-pass').value,
                path: document.getElementById('new-pc-path').value || 'C:\\\\ParentalControl'
            };
            
            if (!pc.name || !pc.ip || !pc.user || !pc.password) {
                alert('Vyplnte vsechna pole');
                return;
            }
            
            await fetch('/api/pcs', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(pc)
            });
            
            pcs.push(pc);
            closeModal('add-pc');
            loadPcList();
            updatePcSelects();
        }
        
        async function removePc(name) {
            if (!confirm('Odebrat pocitac ' + name + '?')) return;
            await fetch('/api/pcs/' + name, {method: 'DELETE'});
            pcs = pcs.filter(p => p.name !== name);
            loadPcList();
            updatePcSelects();
        }
        
        // Run scripts
        async function quickAction(script, args) {
            const pc = document.getElementById('quick-pc').value;
            if (pc === 'local') {
                runLocal(script, args);
            } else {
                runRemote(pc, script, args);
            }
        }
        
        async function runLocal(script, args) {
            showOutput('Spoustim ' + script, 'Cekejte...');
            try {
                const res = await fetch(`/api/local/${script}?args=${encodeURIComponent(args)}`);
                const data = await res.json();
                showOutput('Vysledek', data.output || data);
            } catch (e) {
                showOutput('Chyba', e.toString());
            }
        }
        
        async function runRemote(pc, script, args) {
            showOutput('Spoustim na ' + pc, 'Pripojuji se...');
            try {
                const res = await fetch(`/api/remote/${pc}/${script}?args=${encodeURIComponent(args)}`);
                const data = await res.json();
                showOutput('Vysledek: ' + pc, data.output || data.error || data);
            } catch (e) {
                showOutput('Chyba', e.toString());
            }
        }
        
        // Time config
        async function loadTimeConfig() {
            const pc = document.getElementById('time-pc').value;
            const container = document.getElementById('time-config');
            container.innerHTML = '<p>Nacitam...</p>';
            
            try {
                let data;
                if (pc === 'local') {
                    const res = await fetch('/api/local/time-control.ps1?args=-StatusJson');
                    data = await res.json();
                } else {
                    const res = await fetch(`/api/remote/${pc}/time-control.ps1?args=-StatusJson`);
                    data = await res.json();
                }
                
                if (data.error) {
                    container.innerHTML = `<p style="color: var(--danger);">${data.error}</p>`;
                    return;
                }
                
                container.innerHTML = `
                    <div style="margin-bottom: 20px;">
                        <h4>Denni limit</h4>
                        <p>Limit: ${data.dailyLimit?.limitHours || '?'}h / den</p>
                        <p>Pouzito: ${data.dailyLimit?.usedMinutes || 0} min</p>
                        <p>Zbyva: <strong style="color: ${(data.dailyLimit?.remainingMinutes || 0) > 30 ? 'var(--success)' : 'var(--warning)'}">
                            ${data.dailyLimit?.remainingMinutes || 0} min</strong></p>
                    </div>
                    <div>
                        <h4>Rozvrh dnes</h4>
                        <p>Povoleno: ${data.schedule?.todayWindow || 'Nenastaveno'}</p>
                        <p>Stav: ${data.schedule?.withinSchedule ? '<span style="color:var(--success)">V povolenem case</span>' : '<span style="color:var(--danger)">Mimo povoleny cas</span>'}</p>
                    </div>
                `;
            } catch (e) {
                container.innerHTML = `<p style="color: var(--danger);">Chyba: ${e}</p>`;
            }
        }
        
        // Apps
        async function loadAppsStatus() {
            const pc = document.getElementById('apps-pc').value;
            const container = document.getElementById('apps-list');
            container.innerHTML = '<p>Nacitam...</p>';
            
            try {
                let data;
                if (pc === 'local') {
                    const res = await fetch('/api/local/app-limits.ps1?args=-StatusJson');
                    data = await res.json();
                } else {
                    const res = await fetch(`/api/remote/${pc}/app-limits.ps1?args=-StatusJson`);
                    data = await res.json();
                }
                
                if (data.error) {
                    container.innerHTML = `<p style="color: var(--danger);">${data.error}</p>`;
                    return;
                }
                
                if (!data.apps || data.apps.length === 0) {
                    container.innerHTML = '<p style="color: var(--muted);">Zadne aplikace nejsou omezeny. Kliknete na "Detekovat aplikace".</p>';
                    return;
                }
                
                container.innerHTML = data.apps.map(app => `
                    <div class="app-item">
                        <div class="app-info">
                            <span class="app-icon">${getAppIcon(app.category)}</span>
                            <div>
                                <div class="app-name">${app.name}</div>
                                <div class="app-category">${app.category} - Limit: ${app.limitMinutes}m</div>
                            </div>
                        </div>
                        <div>
                            <span style="color: ${app.remainingMinutes > 10 ? 'var(--success)' : 'var(--warning)'}">
                                ${app.remainingMinutes}m zbyva
                            </span>
                            ${app.running ? '<span class="status online" style="margin-left:10px;"><span class="status-dot"></span> Bezi</span>' : ''}
                        </div>
                    </div>
                `).join('');
            } catch (e) {
                container.innerHTML = `<p style="color: var(--danger);">Chyba: ${e}</p>`;
            }
        }
        
        async function detectApps() {
            const pc = document.getElementById('apps-pc').value;
            const container = document.getElementById('apps-list');
            container.innerHTML = '<p>Detekuji nainstalovane aplikace...</p>';
            
            try {
                let data;
                if (pc === 'local') {
                    const res = await fetch('/api/local/app-limits.ps1?args=-DetectJson');
                    data = await res.json();
                } else {
                    const res = await fetch(`/api/remote/${pc}/app-limits.ps1?args=-DetectJson`);
                    data = await res.json();
                }
                
                if (data.apps) {
                    container.innerHTML = data.apps.map(app => `
                        <div class="app-item">
                            <div class="app-info">
                                <span class="app-icon">${getAppIcon(app.category)}</span>
                                <div>
                                    <div class="app-name">${app.name}</div>
                                    <div class="app-category">${app.category}</div>
                                </div>
                            </div>
                            ${app.running ? '<span class="status online"><span class="status-dot"></span> Bezi</span>' : ''}
                        </div>
                    `).join('');
                } else {
                    container.innerHTML = `<p style="color: var(--danger);">${data.error || 'Chyba'}</p>`;
                }
            } catch (e) {
                container.innerHTML = `<p style="color: var(--danger);">${e}</p>`;
            }
        }
        
        function getAppIcon(category) {
            const icons = {
                'Games': '🎮',
                'Social': '💬',
                'Media': '🎵',
                'Browser': '🌐',
                'UWP App': '📦',
                'Other': '📁'
            };
            return icons[category] || '📁';
        }
        
        // Settings
        async function detectPath() {
            const res = await fetch('/api/detect-path');
            const data = await res.json();
            document.getElementById('project-path').value = data.path;
        }
        
        async function savePath() {
            const path = document.getElementById('project-path').value;
            await fetch('/api/settings', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({project_path: path})
            });
            alert('Ulozeno');
        }
        
        async function saveCredentials() {
            await fetch('/api/settings', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    admin_user: document.getElementById('admin-user').value,
                    admin_pass: document.getElementById('admin-pass').value
                })
            });
            alert('Ulozeno. Nove prihlaseni po odhlaseni.');
        }
        
        // Init
        loadHomePcs();
    </script>
</body>
</html>
'''

LOGIN_HTML = '''
<!DOCTYPE html>
<html lang="cs">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Prihlaseni - Parental Control</title>
    <style>
        body {
            font-family: 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #0f0f1a, #1a1a2e);
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            color: #fff;
            margin: 0;
        }
        .box {
            background: rgba(255,255,255,0.05);
            padding: 40px;
            border-radius: 20px;
            border: 1px solid rgba(255,255,255,0.1);
            width: 100%;
            max-width: 360px;
        }
        h1 { color: #00d4ff; text-align: center; margin-bottom: 30px; }
        input {
            width: 100%;
            padding: 14px;
            margin: 10px 0;
            border: 1px solid rgba(255,255,255,0.2);
            border-radius: 10px;
            background: rgba(255,255,255,0.05);
            color: #fff;
            font-size: 16px;
        }
        button {
            width: 100%;
            padding: 14px;
            background: #00d4ff;
            border: none;
            border-radius: 10px;
            color: #000;
            font-weight: bold;
            font-size: 16px;
            cursor: pointer;
            margin-top: 20px;
        }
        .error { background: rgba(255,68,68,0.2); color: #ff4444; padding: 12px; border-radius: 8px; text-align: center; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="box">
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
        if request.form['username'] == SETTINGS['admin_user'] and request.form['password'] == SETTINGS['admin_pass']:
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
    return render_template_string(HTML, session=session, pcs=SETTINGS.get('remote_pcs', []), settings=SETTINGS)

# API
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

@app.route('/api/test/<pc_name>')
@login_required
def api_test(pc_name):
    pc = next((p for p in SETTINGS.get('remote_pcs', []) if p['name'] == pc_name), None)
    if not pc:
        return jsonify({"connected": False, "error": "PC nenalezeno"})
    return jsonify(test_connection(pc))

@app.route('/api/pcs', methods=['GET', 'POST'])
@login_required
def api_pcs():
    global SETTINGS
    if request.method == 'POST':
        pc = request.json
        if 'remote_pcs' not in SETTINGS:
            SETTINGS['remote_pcs'] = []
        SETTINGS['remote_pcs'].append(pc)
        save_settings(SETTINGS)
        return jsonify({"ok": True})
    return jsonify(SETTINGS.get('remote_pcs', []))

@app.route('/api/pcs/<name>', methods=['DELETE'])
@login_required
def api_pcs_delete(name):
    global SETTINGS
    SETTINGS['remote_pcs'] = [p for p in SETTINGS.get('remote_pcs', []) if p['name'] != name]
    save_settings(SETTINGS)
    return jsonify({"ok": True})

@app.route('/api/settings', methods=['POST'])
@login_required
def api_settings():
    global SETTINGS
    data = request.json
    SETTINGS.update(data)
    save_settings(SETTINGS)
    return jsonify({"ok": True})

@app.route('/api/detect-path')
@login_required
def api_detect_path():
    path = find_project_path()
    return jsonify({"path": str(path)})

if __name__ == '__main__':
    print("\n" + "="*50)
    print("  Parental Control Web Server")
    print("="*50)
    print(f"\n  Cesta: {BASE_DIR}")
    print(f"  URL: http://localhost:5000")
    print(f"  Login: {SETTINGS['admin_user']} / {SETTINGS['admin_pass']}")
    print("="*50 + "\n")
    
    app.run(host='0.0.0.0', port=5000, debug=True)

