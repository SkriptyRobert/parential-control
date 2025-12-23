#!/usr/bin/env python3
"""
Parental Control Web Server
============================
Bezi na DETSKEM PC - rodic se pripoji vzdalene z mobilu/PC.

Spusteni na detskem PC:
    python web-server.py
    
Rodic se pripoji na:
    http://[IP-DETSKEHO-PC]:5000
"""

import os
import sys
import json
import subprocess
import socket
from pathlib import Path
from datetime import datetime
from functools import wraps

try:
    from flask import Flask, render_template_string, jsonify, request, redirect, session
    from flask_cors import CORS
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "flask", "flask-cors"], check=True)
    from flask import Flask, render_template_string, jsonify, request, redirect, session
    from flask_cors import CORS

# Paths - auto detect
def find_project():
    candidates = [
        Path(__file__).parent.parent,
        Path.cwd(),
        Path("C:/ParentalControl"),
        Path.home() / "Documents" / "parential-control",
        Path.home() / "Documents" / "Parental-Control",
    ]
    for p in candidates:
        if (p / "scripts").exists() and (p / "config").exists():
            return p
    return Path(__file__).parent.parent

PROJECT = find_project()
SCRIPTS = PROJECT / "scripts"
CONFIG = PROJECT / "config"

app = Flask(__name__)
app.secret_key = os.urandom(24)
CORS(app)

# Get local IP
def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

LOCAL_IP = get_local_ip()

# Settings
def load_settings():
    settings_file = CONFIG / "web-settings.json"
    defaults = {
        "admin_user": "rodic",
        "admin_pass": "heslo123",
        "child_name": socket.gethostname(),
    }
    if settings_file.exists():
        try:
            defaults.update(json.loads(settings_file.read_text()))
        except: pass
    return defaults

def save_settings(data):
    settings_file = CONFIG / "web-settings.json"
    settings_file.parent.mkdir(parents=True, exist_ok=True)
    current = load_settings()
    current.update(data)
    settings_file.write_text(json.dumps(current, indent=2, ensure_ascii=False))

SETTINGS = load_settings()

# Auth
def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            if request.is_json:
                return jsonify({"error": "Neprihlaseno"}), 401
            return redirect('/login')
        return f(*args, **kwargs)
    return decorated

# Run PowerShell on THIS PC
def run_script(script, args=""):
    script_path = SCRIPTS / script
    if not script_path.exists():
        return {"error": f"Skript nenalezen: {script}"}
    
    cmd = f'powershell -ExecutionPolicy Bypass -File "{script_path}" {args}'
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=120)
        output = result.stdout + result.stderr
        try:
            return json.loads(output)
        except:
            return {"output": output, "success": result.returncode == 0}
    except subprocess.TimeoutExpired:
        return {"error": "Timeout - skript trva prilis dlouho"}
    except Exception as e:
        return {"error": str(e)}

# Load/Save configs
def load_config(name):
    path = CONFIG / name
    if path.exists():
        try:
            return json.loads(path.read_text())
        except: pass
    return {}

def save_config(name, data):
    path = CONFIG / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False))

# HTML
HTML = '''
<!DOCTYPE html>
<html lang="cs">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Parental Control - {{ child_name }}</title>
    <style>
        :root {
            --bg: #0a0a14;
            --card: #12121f;
            --accent: #00d4ff;
            --success: #00ff88;
            --warning: #ffaa00;
            --danger: #ff4444;
            --text: #fff;
            --muted: #666;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: var(--bg);
            color: var(--text);
            min-height: 100vh;
        }
        
        .header {
            background: linear-gradient(135deg, #1a1a2e, #16213e);
            padding: 20px;
            text-align: center;
            border-bottom: 2px solid var(--accent);
        }
        .header h1 { color: var(--accent); font-size: 24px; }
        .header .child { color: var(--muted); margin-top: 5px; }
        .header .ip { color: var(--accent); font-size: 12px; margin-top: 5px; }
        
        .nav {
            display: flex;
            justify-content: center;
            gap: 5px;
            padding: 15px;
            background: var(--card);
            flex-wrap: wrap;
        }
        .nav button {
            padding: 12px 20px;
            background: transparent;
            border: 2px solid transparent;
            color: var(--text);
            border-radius: 25px;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.3s;
        }
        .nav button:hover { border-color: var(--accent); }
        .nav button.active { background: var(--accent); color: #000; font-weight: bold; }
        
        .main { padding: 20px; max-width: 800px; margin: 0 auto; }
        .page { display: none; }
        .page.active { display: block; }
        
        .card {
            background: var(--card);
            border-radius: 16px;
            padding: 25px;
            margin-bottom: 20px;
        }
        .card-title {
            font-size: 20px;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            gap: 10px;
            color: var(--accent);
        }
        
        .stat-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .stat {
            background: rgba(0,212,255,0.1);
            padding: 20px;
            border-radius: 12px;
            text-align: center;
        }
        .stat-value { font-size: 32px; font-weight: bold; color: var(--accent); }
        .stat-label { color: var(--muted); margin-top: 5px; font-size: 13px; }
        
        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 10px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 600;
            transition: all 0.2s;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }
        .btn-primary { background: var(--accent); color: #000; }
        .btn-primary:hover { transform: translateY(-2px); box-shadow: 0 5px 20px rgba(0,212,255,0.3); }
        .btn-success { background: var(--success); color: #000; }
        .btn-danger { background: var(--danger); color: #fff; }
        .btn-secondary { background: #333; color: #fff; }
        
        .form-group { margin: 20px 0; }
        .form-group label { display: block; margin-bottom: 8px; color: var(--muted); }
        input, select {
            width: 100%;
            padding: 14px;
            background: rgba(255,255,255,0.05);
            border: 2px solid rgba(255,255,255,0.1);
            border-radius: 10px;
            color: var(--text);
            font-size: 16px;
        }
        input:focus { border-color: var(--accent); outline: none; }
        
        .toggle-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 15px;
            background: rgba(255,255,255,0.03);
            border-radius: 10px;
            margin: 10px 0;
        }
        .toggle {
            width: 60px; height: 32px;
            background: #333;
            border-radius: 16px;
            position: relative;
            cursor: pointer;
            transition: 0.3s;
        }
        .toggle.on { background: var(--success); }
        .toggle::after {
            content: '';
            position: absolute;
            width: 26px; height: 26px;
            background: white;
            border-radius: 50%;
            top: 3px; left: 3px;
            transition: 0.3s;
        }
        .toggle.on::after { left: 31px; }
        
        .schedule-day {
            display: grid;
            grid-template-columns: 100px 1fr 1fr;
            gap: 10px;
            align-items: center;
            padding: 10px;
            background: rgba(255,255,255,0.02);
            border-radius: 8px;
            margin: 8px 0;
        }
        .schedule-day label { font-weight: 500; }
        
        .app-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 15px;
            background: rgba(255,255,255,0.03);
            border-radius: 12px;
            margin: 10px 0;
        }
        .app-info { display: flex; align-items: center; gap: 15px; }
        .app-icon { font-size: 28px; }
        .app-name { font-weight: 600; }
        .app-status { font-size: 12px; color: var(--muted); }
        .app-limit input {
            width: 80px;
            text-align: center;
            padding: 8px;
        }
        
        .status-ok { color: var(--success); }
        .status-warn { color: var(--warning); }
        .status-bad { color: var(--danger); }
        
        .modal {
            display: none;
            position: fixed;
            top: 0; left: 0;
            width: 100%; height: 100%;
            background: rgba(0,0,0,0.9);
            z-index: 1000;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .modal.active { display: flex; }
        .modal-box {
            background: var(--card);
            border-radius: 20px;
            padding: 30px;
            max-width: 500px;
            width: 100%;
        }
        .modal-title { font-size: 22px; margin-bottom: 20px; color: var(--accent); }
        
        .output {
            background: #000;
            padding: 15px;
            border-radius: 10px;
            font-family: monospace;
            font-size: 13px;
            white-space: pre-wrap;
            max-height: 300px;
            overflow-y: auto;
            color: #0f0;
        }
        
        .logout { position: absolute; top: 20px; right: 20px; }
        .logout a { color: var(--muted); text-decoration: none; }
        
        @media (max-width: 600px) {
            .nav button { padding: 10px 15px; font-size: 13px; }
            .stat-value { font-size: 24px; }
            .schedule-day { grid-template-columns: 1fr; gap: 5px; }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="logout"><a href="/logout">Odhlasit</a></div>
        <h1>Parental Control</h1>
        <div class="child">{{ child_name }}</div>
        <div class="ip">{{ local_ip }}:5000</div>
    </div>
    
    <div class="nav">
        <button class="active" onclick="showPage('status', this)">Stav</button>
        <button onclick="showPage('time', this)">Cas</button>
        <button onclick="showPage('apps', this)">Aplikace</button>
        <button onclick="showPage('dns', this)">Web</button>
        <button onclick="showPage('settings', this)">Nastaveni</button>
    </div>
    
    <div class="main">
        <!-- STATUS -->
        <div id="page-status" class="page active">
            <div class="card">
                <div class="card-title">Dnesni pouzivani</div>
                <div class="stat-grid">
                    <div class="stat">
                        <div class="stat-value" id="stat-used">-</div>
                        <div class="stat-label">Pouzito minut</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value" id="stat-remaining">-</div>
                        <div class="stat-label">Zbyva minut</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value" id="stat-limit">-</div>
                        <div class="stat-label">Denni limit (h)</div>
                    </div>
                </div>
                <button class="btn btn-primary" onclick="loadStatus()">Obnovit</button>
            </div>
            
            <div class="card">
                <div class="card-title">Rychle akce</div>
                <div style="display: flex; gap: 10px; flex-wrap: wrap;">
                    <button class="btn btn-secondary" onclick="runAction('time-control.ps1', '-ShowStatus')">Detail casu</button>
                    <button class="btn btn-secondary" onclick="runAction('app-limits.ps1', '-Status')">Detail aplikaci</button>
                    <button class="btn btn-secondary" onclick="runAction('adguard-manager.ps1', '-Status')">Stav DNS</button>
                </div>
            </div>
        </div>
        
        <!-- TIME -->
        <div id="page-time" class="page">
            <div class="card">
                <div class="card-title">Denni limit</div>
                <p style="color: var(--muted); margin-bottom: 20px;">Maximalni cas, ktery muze dite denne pouzivat PC.</p>
                
                <div class="toggle-row">
                    <span>Povolit denni limit</span>
                    <div class="toggle" id="toggle-daily" onclick="toggleDaily()"></div>
                </div>
                
                <div class="form-group">
                    <label>Pocet hodin denne</label>
                    <input type="number" id="daily-hours" min="0.5" max="12" step="0.5" value="2">
                </div>
                
                <div class="form-group">
                    <label>Varovat X minut pred koncem</label>
                    <input type="number" id="daily-warning" min="5" max="30" value="15">
                </div>
            </div>
            
            <div class="card">
                <div class="card-title">Nocni rezim</div>
                <p style="color: var(--muted); margin-bottom: 20px;">PC se automaticky vypne v noci.</p>
                
                <div class="toggle-row">
                    <span>Povolit nocni vypinani</span>
                    <div class="toggle" id="toggle-night" onclick="toggleNight()"></div>
                </div>
                
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
                    <div class="form-group">
                        <label>Noc od</label>
                        <input type="time" id="night-start" value="00:00">
                    </div>
                    <div class="form-group">
                        <label>Noc do</label>
                        <input type="time" id="night-end" value="06:00">
                    </div>
                </div>
            </div>
            
            <div class="card">
                <div class="card-title">Tydenni rozvrh</div>
                <p style="color: var(--muted); margin-bottom: 20px;">Kdy muze dite pouzivat PC.</p>
                
                <div class="toggle-row">
                    <span>Povolit rozvrh</span>
                    <div class="toggle" id="toggle-schedule" onclick="toggleSchedule()"></div>
                </div>
                
                <div id="schedule-days"></div>
            </div>
            
            <button class="btn btn-success" onclick="saveTimeConfig()" style="width: 100%; margin-top: 10px;">
                Ulozit casove limity
            </button>
        </div>
        
        <!-- APPS -->
        <div id="page-apps" class="page">
            <div class="card">
                <div class="card-title">Limity aplikaci</div>
                <p style="color: var(--muted); margin-bottom: 20px;">Nastavte casove limity pro konkretni aplikace.</p>
                
                <button class="btn btn-primary" onclick="detectApps()" style="margin-bottom: 20px;">
                    Detekovat aplikace na tomto PC
                </button>
                
                <div id="apps-list">
                    <p style="color: var(--muted);">Kliknete na "Detekovat aplikace"</p>
                </div>
            </div>
            
            <button class="btn btn-success" onclick="saveAppLimits()" style="width: 100%;">
                Ulozit limity aplikaci
            </button>
        </div>
        
        <!-- DNS -->
        <div id="page-dns" class="page">
            <div class="card">
                <div class="card-title">Blokovani webu (AdGuard)</div>
                <div id="dns-status">Nacitam...</div>
                
                <div style="display: flex; gap: 10px; margin-top: 20px; flex-wrap: wrap;">
                    <button class="btn btn-secondary" onclick="runAction('adguard-manager.ps1', '-Status')">Zkontrolovat stav</button>
                    <button class="btn btn-primary" onclick="openAdguard()">Otevrit AdGuard</button>
                </div>
            </div>
            
            <div class="card">
                <div class="card-title">Blokovane kategorie</div>
                <p style="color: var(--muted);">Tyto weby jsou blokovany (nastaveno v AdGuard):</p>
                <ul style="margin: 15px 0; padding-left: 20px; color: var(--muted);">
                    <li>Socialni site (TikTok, Facebook, Instagram...)</li>
                    <li>Herni platformy (Steam, Epic Games, Discord...)</li>
                    <li>Nevhodny obsah pro deti</li>
                    <li>Hazard</li>
                </ul>
            </div>
        </div>
        
        <!-- SETTINGS -->
        <div id="page-settings" class="page">
            <div class="card">
                <div class="card-title">Nastaveni pristupu</div>
                <p style="color: var(--muted); margin-bottom: 20px;">Prihlasovaci udaje pro rodicovsky pristup.</p>
                
                <div class="form-group">
                    <label>Uzivatelske jmeno</label>
                    <input type="text" id="set-user" value="{{ settings.admin_user }}">
                </div>
                <div class="form-group">
                    <label>Heslo</label>
                    <input type="password" id="set-pass" value="{{ settings.admin_pass }}">
                </div>
                <div class="form-group">
                    <label>Jmeno ditete / PC</label>
                    <input type="text" id="set-child" value="{{ settings.child_name }}">
                </div>
                
                <button class="btn btn-primary" onclick="saveSettings()">Ulozit nastaveni</button>
            </div>
            
            <div class="card">
                <div class="card-title">Informace</div>
                <p><strong>IP adresa:</strong> {{ local_ip }}</p>
                <p><strong>Port:</strong> 5000</p>
                <p><strong>Pristup:</strong> http://{{ local_ip }}:5000</p>
                <p style="color: var(--muted); margin-top: 15px;">
                    Pripojte se z mobilu nebo jineho PC na tuto adresu.
                </p>
            </div>
            
            <div class="card">
                <div class="card-title">Pokrocile</div>
                <div style="display: flex; gap: 10px; flex-wrap: wrap;">
                    <button class="btn btn-secondary" onclick="runAction('check-status.ps1', '')">Systemovy stav</button>
                    <button class="btn btn-danger" onclick="if(confirm('Opravdu odinstalovat?')) runAction('remove-parental-control.ps1', '')">Odinstalovat</button>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Modal -->
    <div id="modal" class="modal" onclick="if(event.target===this) closeModal()">
        <div class="modal-box">
            <div class="modal-title" id="modal-title">Vysledek</div>
            <div class="output" id="modal-output"></div>
            <button class="btn btn-secondary" onclick="closeModal()" style="margin-top: 15px;">Zavrit</button>
        </div>
    </div>
    
    <script>
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        const daysCZ = ['Pondeli', 'Utery', 'Streda', 'Ctvrtek', 'Patek', 'Sobota', 'Nedele'];
        
        let timeConfig = {};
        let detectedApps = [];
        
        function showPage(name, btn) {
            document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.nav button').forEach(b => b.classList.remove('active'));
            document.getElementById('page-' + name).classList.add('active');
            if (btn) btn.classList.add('active');
            
            if (name === 'status') loadStatus();
            if (name === 'time') loadTimeConfig();
            if (name === 'dns') loadDnsStatus();
        }
        
        function showModal(title, content) {
            document.getElementById('modal-title').textContent = title;
            document.getElementById('modal-output').textContent = typeof content === 'object' ? JSON.stringify(content, null, 2) : content;
            document.getElementById('modal').classList.add('active');
        }
        
        function closeModal() {
            document.getElementById('modal').classList.remove('active');
        }
        
        // STATUS
        async function loadStatus() {
            try {
                const res = await fetch('/api/status');
                const data = await res.json();
                
                document.getElementById('stat-used').textContent = data.usedMinutes || 0;
                document.getElementById('stat-remaining').textContent = data.remainingMinutes || '-';
                document.getElementById('stat-limit').textContent = data.limitHours || '-';
                
                const remaining = document.getElementById('stat-remaining');
                if (data.remainingMinutes <= 0) {
                    remaining.className = 'stat-value status-bad';
                } else if (data.remainingMinutes <= 30) {
                    remaining.className = 'stat-value status-warn';
                } else {
                    remaining.className = 'stat-value status-ok';
                }
            } catch (e) {
                console.error(e);
            }
        }
        
        // TIME CONFIG
        async function loadTimeConfig() {
            try {
                const res = await fetch('/api/config/time-limits.json');
                timeConfig = await res.json();
                
                // Daily
                document.getElementById('toggle-daily').classList.toggle('on', timeConfig.dailyLimit?.enabled);
                document.getElementById('daily-hours').value = timeConfig.dailyLimit?.hours || 2;
                document.getElementById('daily-warning').value = timeConfig.dailyLimit?.warningAtMinutes || 15;
                
                // Night
                document.getElementById('toggle-night').classList.toggle('on', timeConfig.nightShutdown?.enabled);
                document.getElementById('night-start').value = timeConfig.nightShutdown?.startTime || '00:00';
                document.getElementById('night-end').value = timeConfig.nightShutdown?.endTime || '06:00';
                
                // Schedule
                document.getElementById('toggle-schedule').classList.toggle('on', timeConfig.schedule?.enabled);
                renderSchedule();
            } catch (e) {
                console.error(e);
            }
        }
        
        function renderSchedule() {
            const container = document.getElementById('schedule-days');
            container.innerHTML = days.map((day, i) => {
                const window = (timeConfig.schedule?.allowedWindows || []).find(w => w.day === day);
                return `
                    <div class="schedule-day">
                        <label>${daysCZ[i]}</label>
                        <input type="time" id="sched-${day}-start" value="${window?.start || '15:00'}">
                        <input type="time" id="sched-${day}-end" value="${window?.end || '20:00'}">
                    </div>
                `;
            }).join('');
        }
        
        function toggleDaily() {
            document.getElementById('toggle-daily').classList.toggle('on');
        }
        function toggleNight() {
            document.getElementById('toggle-night').classList.toggle('on');
        }
        function toggleSchedule() {
            document.getElementById('toggle-schedule').classList.toggle('on');
        }
        
        async function saveTimeConfig() {
            const config = {
                excludedUsers: timeConfig.excludedUsers || ["Administrator", "SYSTEM"],
                dailyLimit: {
                    enabled: document.getElementById('toggle-daily').classList.contains('on'),
                    hours: parseFloat(document.getElementById('daily-hours').value),
                    warningAtMinutes: parseInt(document.getElementById('daily-warning').value),
                    action: "shutdown"
                },
                nightShutdown: {
                    enabled: document.getElementById('toggle-night').classList.contains('on'),
                    startTime: document.getElementById('night-start').value,
                    endTime: document.getElementById('night-end').value,
                    action: "shutdown"
                },
                schedule: {
                    enabled: document.getElementById('toggle-schedule').classList.contains('on'),
                    allowedWindows: days.map(day => ({
                        day: day,
                        start: document.getElementById('sched-' + day + '-start').value,
                        end: document.getElementById('sched-' + day + '-end').value
                    })),
                    action: "shutdown"
                },
                trackingFile: "C:\\\\ProgramData\\\\ParentalControl\\\\usage-tracking.json"
            };
            
            try {
                await fetch('/api/config/time-limits.json', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(config)
                });
                alert('Casove limity ulozeny!');
            } catch (e) {
                alert('Chyba: ' + e);
            }
        }
        
        // APPS
        async function detectApps() {
            const container = document.getElementById('apps-list');
            container.innerHTML = '<p>Detekuji aplikace...</p>';
            
            try {
                const res = await fetch('/api/detect-apps');
                const data = await res.json();
                
                if (data.apps && data.apps.length > 0) {
                    detectedApps = data.apps;
                    
                    // Load existing limits
                    const limitsRes = await fetch('/api/config/app-limits.json');
                    const limits = await limitsRes.json();
                    const existingLimits = limits.limits || [];
                    
                    container.innerHTML = data.apps.map(app => {
                        const existing = existingLimits.find(l => l.name === app.name);
                        const limitValue = existing ? existing.dailyMinutes : '';
                        const icon = getIcon(app.category);
                        
                        return `
                            <div class="app-item">
                                <div class="app-info">
                                    <span class="app-icon">${icon}</span>
                                    <div>
                                        <div class="app-name">${app.name}</div>
                                        <div class="app-status">${app.category} ${app.running ? '- Bezi' : ''}</div>
                                    </div>
                                </div>
                                <div class="app-limit">
                                    <input type="number" placeholder="min" min="0" max="480" 
                                           data-app="${app.name}" data-category="${app.category}" 
                                           data-process="${app.processName}"
                                           value="${limitValue}">
                                </div>
                            </div>
                        `;
                    }).join('');
                } else {
                    container.innerHTML = '<p style="color: var(--warning);">Zadne aplikace nenalezeny.</p>';
                }
            } catch (e) {
                container.innerHTML = '<p style="color: var(--danger);">Chyba: ' + e + '</p>';
            }
        }
        
        function getIcon(category) {
            const icons = { 'Games': '🎮', 'Social': '💬', 'Media': '🎵', 'Browser': '🌐', 'Other': '📁' };
            return icons[category] || '📁';
        }
        
        async function saveAppLimits() {
            const inputs = document.querySelectorAll('.app-limit input');
            const limits = [];
            
            inputs.forEach(input => {
                const minutes = parseInt(input.value);
                if (minutes > 0) {
                    limits.push({
                        name: input.dataset.app,
                        category: input.dataset.category,
                        processName: input.dataset.process,
                        dailyMinutes: minutes,
                        warningAtMinutes: Math.max(5, Math.floor(minutes / 6))
                    });
                }
            });
            
            try {
                await fetch('/api/config/app-limits.json', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({ enabled: true, limits: limits })
                });
                alert('Limity aplikaci ulozeny! Nastaveno: ' + limits.length + ' aplikaci');
            } catch (e) {
                alert('Chyba: ' + e);
            }
        }
        
        // DNS
        async function loadDnsStatus() {
            const container = document.getElementById('dns-status');
            try {
                const res = await fetch('/api/run/adguard-manager.ps1?args=-Status');
                const data = await res.json();
                
                if (data.output && data.output.includes('Running')) {
                    container.innerHTML = '<p class="status-ok">AdGuard bezi - blokovani aktivni</p>';
                } else if (data.error) {
                    container.innerHTML = '<p class="status-bad">Chyba: ' + data.error + '</p>';
                } else {
                    container.innerHTML = '<p class="status-warn">AdGuard neni aktivni</p>';
                }
            } catch (e) {
                container.innerHTML = '<p class="status-bad">Chyba pripojeni</p>';
            }
        }
        
        function openAdguard() {
            window.open('http://127.0.0.1', '_blank');
        }
        
        // Settings
        async function saveSettings() {
            const settings = {
                admin_user: document.getElementById('set-user').value,
                admin_pass: document.getElementById('set-pass').value,
                child_name: document.getElementById('set-child').value
            };
            
            try {
                await fetch('/api/settings', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(settings)
                });
                alert('Nastaveni ulozeno! Nove prihlaseni po odhlaseni.');
            } catch (e) {
                alert('Chyba: ' + e);
            }
        }
        
        // Run action
        async function runAction(script, args) {
            showModal('Spoustim...', 'Cekejte...');
            try {
                const res = await fetch('/api/run/' + script + '?args=' + encodeURIComponent(args));
                const data = await res.json();
                showModal('Vysledek', data.output || data.error || JSON.stringify(data, null, 2));
            } catch (e) {
                showModal('Chyba', e.toString());
            }
        }
        
        // Init
        loadStatus();
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
            font-family: -apple-system, sans-serif;
            background: linear-gradient(135deg, #0a0a14, #1a1a2e);
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            color: #fff;
            margin: 0;
            padding: 20px;
        }
        .box {
            background: rgba(255,255,255,0.05);
            padding: 40px;
            border-radius: 20px;
            width: 100%;
            max-width: 380px;
            text-align: center;
        }
        h1 { color: #00d4ff; margin-bottom: 10px; }
        .child { color: #666; margin-bottom: 30px; }
        input {
            width: 100%;
            padding: 16px;
            margin: 10px 0;
            border: 2px solid rgba(255,255,255,0.1);
            border-radius: 12px;
            background: rgba(255,255,255,0.05);
            color: #fff;
            font-size: 16px;
        }
        button {
            width: 100%;
            padding: 16px;
            background: #00d4ff;
            border: none;
            border-radius: 12px;
            color: #000;
            font-weight: bold;
            font-size: 16px;
            cursor: pointer;
            margin-top: 20px;
        }
        .error { background: rgba(255,68,68,0.2); color: #ff4444; padding: 15px; border-radius: 10px; margin: 15px 0; }
        .info { color: #666; font-size: 13px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="box">
        <h1>Parental Control</h1>
        <div class="child">{{ child_name }}</div>
        {% if error %}<div class="error">{{ error }}</div>{% endif %}
        <form method="POST">
            <input type="text" name="username" placeholder="Uzivatel" required>
            <input type="password" name="password" placeholder="Heslo" required>
            <button type="submit">Prihlasit se</button>
        </form>
        <p class="info">Prihlaste se pro spravu tohoto pocitace.</p>
    </div>
</body>
</html>
'''

# Routes
@app.route('/login', methods=['GET', 'POST'])
def login():
    global SETTINGS
    SETTINGS = load_settings()
    error = None
    if request.method == 'POST':
        if request.form['username'] == SETTINGS['admin_user'] and request.form['password'] == SETTINGS['admin_pass']:
            session['logged_in'] = True
            return redirect('/')
        error = 'Spatne prihlasovaci udaje'
    return render_template_string(LOGIN_HTML, error=error, child_name=SETTINGS.get('child_name', 'PC'))

@app.route('/logout')
def logout():
    session.clear()
    return redirect('/login')

@app.route('/')
@login_required
def home():
    return render_template_string(HTML, 
        child_name=SETTINGS.get('child_name', socket.gethostname()),
        local_ip=LOCAL_IP,
        settings=SETTINGS
    )

# API
@app.route('/api/status')
@login_required
def api_status():
    result = run_script('time-control.ps1', '-StatusJson')
    if isinstance(result, dict) and 'dailyLimit' in result:
        return jsonify({
            'usedMinutes': result['dailyLimit'].get('usedMinutes', 0),
            'remainingMinutes': result['dailyLimit'].get('remainingMinutes', 0),
            'limitHours': result['dailyLimit'].get('limitHours', 0)
        })
    return jsonify({'usedMinutes': 0, 'remainingMinutes': '-', 'limitHours': '-'})

@app.route('/api/run/<script>')
@login_required
def api_run(script):
    args = request.args.get('args', '')
    return jsonify(run_script(script, args))

@app.route('/api/config/<name>', methods=['GET', 'POST'])
@login_required
def api_config(name):
    if request.method == 'POST':
        save_config(name, request.json)
        return jsonify({'ok': True})
    return jsonify(load_config(name))

@app.route('/api/detect-apps')
@login_required
def api_detect_apps():
    result = run_script('app-limits.ps1', '-DetectJson')
    return jsonify(result)

@app.route('/api/settings', methods=['POST'])
@login_required
def api_settings():
    global SETTINGS
    save_settings(request.json)
    SETTINGS = load_settings()
    return jsonify({'ok': True})

if __name__ == '__main__':
    print()
    print("=" * 55)
    print("  PARENTAL CONTROL - Web Server")
    print("=" * 55)
    print()
    print(f"  Tento server bezi na DETSKEM PC.")
    print(f"  Rodic se pripoji vzdalene.")
    print()
    print(f"  Lokalni pristup:  http://127.0.0.1:5000")
    print(f"  Vzdaleny pristup: http://{LOCAL_IP}:5000")
    print()
    print(f"  Prihlaseni: {SETTINGS['admin_user']} / {SETTINGS['admin_pass']}")
    print()
    print("=" * 55)
    print()
    
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
