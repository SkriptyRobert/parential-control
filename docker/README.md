# AdGuard Home - Docker Installation

Alternative installation method using Docker containers.

## Requirements

- Windows 10/11 with Docker Desktop
- OR Linux with Docker and docker-compose
- Administrator privileges
- WSL 2 (Windows only)

## When to Use Docker

Use Docker installation when:
- You need to run AdGuard Home alongside other containers
- You prefer container-based deployment
- You want easy backup/restore via volume management
- WSL 2 is working properly on your system

**Recommended:** For Windows, use the native Windows Service installation (main project folder) for better reliability.

## Installation

### Windows

1. Install Docker Desktop from https://docker.com
2. Start Docker Desktop and wait for initialization
3. Run PowerShell as Administrator:

```powershell
cd docker
.\install-docker-adguard.ps1
```

### Linux

```bash
cd docker
docker-compose up -d
```

## Configuration

Configuration files are stored in:
- `docker/config/conf/` - AdGuard Home configuration
- `docker/config/work/` - Working data (logs, databases)

## Commands

| Action | Command |
|--------|---------|
| Start | `docker-compose up -d` |
| Stop | `docker-compose down` |
| Restart | `docker-compose restart` |
| View logs | `docker-compose logs -f` |
| Status | `docker ps` |

## Uninstallation

```powershell
.\uninstall-docker-adguard.ps1

# To also remove configuration data:
.\uninstall-docker-adguard.ps1 -RemoveData
```

## Troubleshooting

### Docker not running
- Start Docker Desktop from Start menu
- Wait for the whale icon in system tray to stop animating

### WSL issues on Windows 10
- Run: `wsl --update`
- If hanging, try: `wsl --update --web-download`
- Consider using Windows Service installation instead

### Port 53 already in use
- Check for other DNS services: `netstat -ano | findstr :53`
- Stop conflicting service or change port in docker-compose.yml

