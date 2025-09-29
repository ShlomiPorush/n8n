#!/bin/bash

# n8n Backup Script
# Exports workflows and credentials from all n8n containers
# Creates encrypted ZIP and maintains detailed logs

set -e  # Exit on error
# Debug
# set -x  # Print each command before executing it (Trace mode)

#==============================================================================
# USER CONFIGURATION - Edit these variables as needed
#==============================================================================

# Manual container names - Add specific container names here
# Leave empty array () to rely only on auto-detection
MANUAL_CONTAINERS=(
    # "n8n1"
    # "n8n2"
)

# Auto-detect containers with 'n8n' in name (true/false)
AUTO_DETECT_N8N=true

# Directory structure configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR"
FILES_DIR="${BASE_DIR}/files"
LOGS_DIR="${BASE_DIR}/logs"

# Encryption settings
ENABLE_ENCRYPTION=true  # Set to false to skip encryption
PROMPT_FOR_PASSWORD=true  # Set to false to use DEFAULT_PASSWORD
DEFAULT_PASSWORD=""  # Only used if PROMPT_FOR_PASSWORD=false - CHANGE THIS!

# Export paths inside containers (temporary paths inside container, no mount required)
CONTAINER_WORKFLOWS_PATH="/tmp/n8n_backup/workflows/"
CONTAINER_CREDENTIALS_PATH="/tmp/n8n_backup/credentials/"

# Docker user for n8n commands
DOCKER_USER="node"

# Log configuration
LOG_LEVEL="INFO"  # DEBUG, INFO, WARNING, ERROR

#==============================================================================
# END USER CONFIGURATION
#==============================================================================

# System configuration (usually no need to change)
LOG_FILE="${LOGS_DIR}/n8n_backup_$(date +%Y%m%d_%H%M%S).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Function to write logs
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to log separator for container processing
log_separator() {
    local message="$1"
    local separator="===================="
    echo "" | tee -a "$LOG_FILE"
    echo "$separator" | tee -a "$LOG_FILE"
    echo "$message" | tee -a "$LOG_FILE"
    echo "$separator" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# Function to check if container exists and is running
check_container_exists() {
    local container_name="$1"
    if ! docker ps -q -f name="^${container_name}$" | grep -q .; then
        if ! docker ps -a -q -f name="^${container_name}$" | grep -q .; then
            log_message "ERROR" "Container $container_name not found"
            return 1
        else
            log_message "ERROR" "Container $container_name exists but is not running"
            return 1
        fi
    fi
    return 0
}

# Function to export workflows
export_workflows() {
    local container_name="$1"
    local host_workflows_dir="$2"
    
    log_message "INFO" "Starting workflows export for container: $container_name"
    
    # Create temp dir inside container
    docker exec -u "$DOCKER_USER" "$container_name" mkdir -p "$CONTAINER_WORKFLOWS_PATH"
    
    if docker exec -u "$DOCKER_USER" "$container_name" n8n export:workflow --backup --output="$CONTAINER_WORKFLOWS_PATH" 2>&1 | tee -a "$LOG_FILE"; then
        # Copy files to host
        if docker cp "$container_name:$CONTAINER_WORKFLOWS_PATH/." "$host_workflows_dir/" 2>&1 | tee -a "$LOG_FILE"; then
            log_message "SUCCESS" "Workflows export and copy completed successfully for $container_name"
            # Clean up inside container
            docker exec -u "$DOCKER_USER" "$container_name" rm -rf "$CONTAINER_WORKFLOWS_PATH" || true
            return 0
        else
            log_message "ERROR" "Workflows copy failed for $container_name"
            return 1
        fi
    else
        log_message "ERROR" "Workflows export failed for $container_name"
        return 1
    fi
}

# Function to export credentials
export_credentials() {
    local container_name="$1"
    local host_credentials_dir="$2"
    
    log_message "INFO" "Starting credentials export for container: $container_name"
    
    # Create temp dir inside container
    docker exec -u "$DOCKER_USER" "$container_name" mkdir -p "$CONTAINER_CREDENTIALS_PATH"
    
    if docker exec -u "$DOCKER_USER" "$container_name" n8n export:credentials --backup --decrypted --output="$CONTAINER_CREDENTIALS_PATH" 2>&1 | tee -a "$LOG_FILE"; then
        # Copy files to host
        if docker cp "$container_name:$CONTAINER_CREDENTIALS_PATH/." "$host_credentials_dir/" 2>&1 | tee -a "$LOG_FILE"; then
            log_message "SUCCESS" "Credentials export and copy completed successfully for $container_name"
            # Clean up inside container
            docker exec -u "$DOCKER_USER" "$container_name" rm -rf "$CONTAINER_CREDENTIALS_PATH" || true
            return 0
        else
            log_message "ERROR" "Credentials copy failed for $container_name"
            return 1
        fi
    else
        log_message "ERROR" "Credentials export failed for $container_name"
        return 1
    fi
}

# Function to create encrypted ZIP
create_encrypted_zip() {
    local source_dir="$1"
    local zip_filename="$2"
    local password="$3"
    
    log_message "INFO" "Creating encrypted ZIP: $zip_filename"
    
    parent_dir=$(dirname "$source_dir")
    dir_name=$(basename "$source_dir")

    if command -v zip >/dev/null 2>&1; then
        cd "$parent_dir" || { log_message "ERROR" "Failed to change directory to $parent_dir"; return 1; }
        if zip -r -P "$password" "$zip_filename" "$dir_name" 2>&1 | tee -a "$LOG_FILE"; then
            log_message "SUCCESS" "Encrypted ZIP created successfully: $zip_filename"
            return 0
        else
            log_message "ERROR" "Encrypted ZIP creation failed"
            return 1
        fi
    else
        log_message "ERROR" "zip command not installed on system"
        return 1
    fi
}

# Function to find all n8n containers
find_n8n_containers() {
    local containers=()
    
    # Add manual containers first
    for container in "${MANUAL_CONTAINERS[@]}"; do
        if [ -n "$container" ]; then
            containers+=("$container")
        fi
    done
    
    # Find containers with n8n in name if auto-detect is enabled
    if [ "$AUTO_DETECT_N8N" = true ]; then
        while IFS= read -r container; do
            if [ -n "$container" ]; then
                # Check if container is not already in manual list
                local found=false
                for existing in "${MANUAL_CONTAINERS[@]}"; do
                    if [ "$existing" = "$container" ]; then
                        found=true
                        break
                    fi
                done
                if [ "$found" = false ]; then
                    containers+=("$container")
                fi
            fi
        done < <(docker ps --format "{{.Names}}" | grep -i n8n || true)
    fi
    
    # Add any additional containers passed as parameters
    for param in "$@"; do
        # Check if container is not already in the list
        local found=false
        for existing in "${containers[@]}"; do
            if [ "$existing" = "$param" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            containers+=("$param")
        fi
    done
    
    printf '%s\n' "${containers[@]}"
}

# Main function
main() {
    # Create required directories
    mkdir -p "$FILES_DIR"
    mkdir -p "$LOGS_DIR"
    
    log_message "INFO" "Starting n8n backup script"
    log_message "INFO" "Base directory: $BASE_DIR"
    log_message "INFO" "Files directory: $FILES_DIR"
    log_message "INFO" "Logs directory: $LOGS_DIR"
    
    # Clear previous backups in files/
    rm -rf "$FILES_DIR"/* 2>/dev/null || true
    
    # Find all relevant containers
    local containers=()
    while IFS= read -r container; do
        if [ -n "$container" ]; then
            containers+=("$container")
        fi
    done < <(find_n8n_containers "$@")
    
    if [ ${#containers[@]} -eq 0 ]; then
        log_message "ERROR" "No n8n containers found running"
        log_message "INFO" "Usage: $0 [additional_container1] [additional_container2] ..."
        log_message "INFO" "Script automatically finds containers with 'n8n' in name"
        exit 1
    fi
    
    log_message "INFO" "Containers to backup: ${containers[*]}"
    
    local success_count=0
    local total_containers=${#containers[@]}
    
    # Process each container
    for container in "${containers[@]}"; do
        log_separator "Processing container: $container"
        
        if ! check_container_exists "$container"; then
            log_message "ERROR" "Skipping container: $container"
            continue
        fi
        
        local container_dir="$FILES_DIR/$container"
        local workflows_dir="$container_dir/workflows"
        local credentials_dir="$container_dir/credentials"
        
        mkdir -p "$workflows_dir" "$credentials_dir"
        
        local container_success=true
        
        # Export workflows
        if ! export_workflows "$container" "$workflows_dir"; then
            container_success=false
        fi
        
        # Export credentials
        if ! export_credentials "$container" "$credentials_dir"; then
            container_success=false
        fi
        
        if $container_success; then
            success_count=$((success_count + 1))
            log_message "SUCCESS" "Backup completed successfully for container: $container"
        else
            log_message "ERROR" "Backup failed for container: $container"
            # Clean failed container dir
            rm -rf "$container_dir"
        fi
        
        log_message "INFO" "Finished processing container: $container"
    done
    
    # Backup summary
    log_separator "Backup Summary"
    log_message "INFO" "Container processing completed. Successes: $success_count/$total_containers"
    
    if [ $success_count -eq 0 ]; then
        log_message "ERROR" "No containers backed up successfully. Cleaning up files directory"
        rm -rf "$FILES_DIR"/*
        exit 1
    fi
    
    # Create encrypted ZIP
    local zip_filename="${BASE_DIR}/n8n_backup_$(date +%Y%m%d_%H%M%S).zip"
    
    if [ "$ENABLE_ENCRYPTION" = true ]; then
        local password=""
        
        if [ "$PROMPT_FOR_PASSWORD" = true ]; then
            # Request password for encryption
            echo -n "Enter password for backup encryption: "
            read -s password
            echo
        else
            password="$DEFAULT_PASSWORD"
        fi
        
        if [ -z "$password" ]; then
            log_message "WARNING" "No password provided. Creating regular ZIP without encryption"
            zip_filename="${zip_filename%.zip}_unencrypted.zip"
            zip -r "$zip_filename" "$FILES_DIR" 2>&1 | tee -a "$LOG_FILE"
        else
            create_encrypted_zip "$FILES_DIR" "$zip_filename" "$password"
        fi
    else
        log_message "INFO" "Encryption disabled. Creating regular ZIP file"
        zip_filename="${zip_filename%.zip}_unencrypted.zip"
        zip -r "$zip_filename" "$FILES_DIR" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # No cleanup of files/ as it holds the latest backups
    
    # Final summary
    log_separator "Script Completion Summary"
    log_message "INFO" "Backup script completed successfully"
    log_message "INFO" "Backup file: $zip_filename"
    log_message "INFO" "Log file: $LOG_FILE"
    log_message "INFO" "Files directory: $FILES_DIR"
    log_message "INFO" "Logs directory: $LOGS_DIR"
    
    echo ""
    echo "=== Backup Summary ==="
    echo "Containers processed: $total_containers"
    echo "Containers backed up successfully: $success_count"
    echo "Backup file: $zip_filename"
    echo "Log file: $LOG_FILE"
    echo ""
    
    if [ -f "$zip_filename" ]; then
        echo "Backup file size: $(du -h "$zip_filename" | cut -f1)"
    fi

    # Clear backup files/
    rm -rf "$FILES_DIR"/* 2>/dev/null || true
}

# Execute main function
main "$@"