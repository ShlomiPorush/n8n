# n8n Backup Script

A comprehensive Bash script for automated backup of n8n workflows and credentials from Docker containers, with support for encryption and detailed logging.

## Features

- **Automatic Container Detection**: Finds all running n8n containers automatically
- **Manual Container Selection**: Option to specify specific containers
- **Encrypted Backups**: Creates password-protected ZIP archives
- **Detailed Logging**: Maintains comprehensive logs of all backup operations
- **Batch Processing**: Handles multiple n8n containers in one run
- **Error Handling**: Robust error checking and reporting
- **Credential Export**: Backs up credentials in decrypted format for easy restoration

## Prerequisites

- Docker installed and running
- `zip` utility installed on the host system
- Sufficient permissions to execute Docker commands
- Running n8n container(s)

## Installation

1. Clone this repository:
```bash
git clone <repository-url>
cd n8n-backup-script
```

2. Make the script executable:
```bash
chmod +x backup.sh
```

## Configuration

Edit the `backup.sh` file to customize the following settings:

### Container Selection

```bash
# Manual container names
MANUAL_CONTAINERS=(
    # "n8n1"
    # "n8n2"
)

# Auto-detect containers with 'n8n' in name
AUTO_DETECT_N8N=true
```

### Encryption Settings

```bash
# Enable/disable encryption
ENABLE_ENCRYPTION=true

# Prompt for password or use default
PROMPT_FOR_PASSWORD=true

# Default password (only if PROMPT_FOR_PASSWORD=false)
DEFAULT_PASSWORD=""
```

### Directory Configuration

By default, the script creates the following structure:
```
script-directory/
├── backup.sh
├── files/           # Temporary backup files
├── logs/            # Backup logs
└── n8n_backup_YYYYMMDD_HHMMSS.zip
```

## Usage

### Basic Usage (Auto-detect)

```bash
./backup.sh
```

This will automatically find and backup all running containers with "n8n" in their name.

### Specify Additional Containers

```bash
./backup.sh container1 container2
```

### Manual Container Configuration

Edit the `MANUAL_CONTAINERS` array in the script:
```bash
MANUAL_CONTAINERS=(
    "n8n_production"
    "n8n_staging"
)
```

Then run:
```bash
./backup.sh
```

## Output

### Backup File

The script creates a timestamped ZIP file:
```
n8n_backup_20240115_143022.zip
```

If encryption is disabled:
```
n8n_backup_20240115_143022_unencrypted.zip
```

### Directory Structure Inside ZIP

```
files/
├── container1/
│   ├── workflows/
│   │   └── [workflow JSON files]
│   └── credentials/
│       └── [credential JSON files]
└── container2/
    ├── workflows/
    └── credentials/
```

### Log Files

Detailed logs are saved in the `logs/` directory:
```
logs/n8n_backup_20240115_143022.log
```

## Restoring Backups

To restore workflows and credentials:

1. Extract the ZIP file (enter password if encrypted)
2. Navigate to the container's directory
3. Import workflows:
```bash
docker exec -u node <container_name> n8n import:workflow --input=/path/to/workflows/
```
4. Import credentials:
```bash
docker exec -u node <container_name> n8n import:credentials --input=/path/to/credentials/
```

## Security Considerations

⚠️ **Important Security Notes**:

- Credentials are exported in **decrypted format**
- Backup files contain **sensitive information**
- Always use **strong passwords** for encryption
- Store backups in **secure locations**
- Consider adding `*.zip` and `files/` to `.gitignore`
- Never commit backup files to version control

## Troubleshooting

### Container Not Found
```
ERROR: Container <name> not found
```
**Solution**: Verify container name with `docker ps` and update configuration.

### Permission Denied
```
ERROR: Permission denied
```
**Solution**: Ensure script has execute permissions (`chmod +x backup.sh`) and user has Docker access.

### ZIP Command Not Found
```
ERROR: zip command not installed on system
```
**Solution**: Install zip utility:
```bash
# Ubuntu/Debian
sudo apt-get install zip

# CentOS/RHEL
sudo yum install zip

# macOS
brew install zip
```

### Export Failed
```
ERROR: Workflows export failed for <container>
```
**Solution**: Check that n8n is running properly in the container and has data to export.

## Automation

### Cron Job Setup

To run automatic backups daily at 2 AM:

```bash
crontab -e
```

Add:
```
0 2 * * * /path/to/backup.sh
```

For password-protected backups with cron, set:
```bash
PROMPT_FOR_PASSWORD=false
DEFAULT_PASSWORD="your-secure-password"
```

## Advanced Configuration

### Custom Export Paths

Modify these variables to change temporary paths inside containers:
```bash
CONTAINER_WORKFLOWS_PATH="/tmp/n8n_backup/workflows/"
CONTAINER_CREDENTIALS_PATH="/tmp/n8n_backup/credentials/"
```

### Docker User

Change the user for n8n commands:
```bash
DOCKER_USER="node"  # Default for n8n containers
```

### Log Level

Adjust verbosity:
```bash
LOG_LEVEL="INFO"  # Options: DEBUG, INFO, WARNING, ERROR
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

For issues and questions, please open an issue on GitHub.

## Changelog

### Version 1.0
- Initial release
- Auto-detection of n8n containers
- Encrypted ZIP backups
- Comprehensive logging
- Multi-container support
