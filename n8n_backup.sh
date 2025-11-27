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
DEFAULT_PASSWORD=""  # Only used if PROMPT_FOR_PASSWORD=false

# Export paths inside containers (temporary paths inside container, no mount required)
CONTAINER_WORKFLOWS_PATH="/tmp/n8n_backup/workflows/"
CONTAINER_CREDENTIALS_PATH="/tmp/n8n_backup/credentials/"

# Docker user for n8n commands
DOCKER_USER="node"

# Log configuration
LOG_LEVEL="INFO"  # DEBUG, INFO, WARNING, ERROR

# Email configuration
ENABLE_EMAIL=false  # Set to false to skip email notification
# Use semicolon (;) or comma (,) to separate multiple email addresses
EMAIL_TO="your-email@example.com"
EMAIL_FROM="backup@example.com"
EMAIL_FROM_NAME="n8n Backup"
EMAIL_SUBJECT_BASE="n8n Backup Report"
SMTP_SERVER="smtp.example.com"
SMTP_PORT="587"
SMTP_USER="your-smtp-user"
SMTP_PASSWORD="your-smtp-password"

# Webhook configuration
ENABLE_WEBHOOK=false  # Set to false to skip webhook notification
WEBHOOK_URL="https://your-webhook-url.com/endpoint"

#==============================================================================
# END USER CONFIGURATION
#==============================================================================

# System configuration (usually no need to change)
LOG_FILE="${LOGS_DIR}/n8n_backup_$(date +%Y%m%d_%H%M%S).log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Declare associative arrays for tracking container results
declare -A CONTAINER_WORKFLOWS_STATUS
declare -A CONTAINER_WORKFLOWS_COUNT
declare -A CONTAINER_CREDENTIALS_STATUS
declare -A CONTAINER_CREDENTIALS_COUNT

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

# Function to extract count from export output
extract_count() {
    local output="$1"
    local count=$(echo "$output" | grep -oP 'Successfully exported \K\d+' | head -1)
    echo "${count:-0}"
}

# Function to export workflows
export_workflows() {
    local container_name="$1"
    local host_workflows_dir="$2"
    
    log_message "INFO" "Starting workflows export for container: $container_name"
    
    # Create temp dir inside container
    docker exec -u "$DOCKER_USER" "$container_name" mkdir -p "$CONTAINER_WORKFLOWS_PATH"
    
    local export_output
    export_output=$(docker exec -u "$DOCKER_USER" "$container_name" n8n export:workflow --backup --output="$CONTAINER_WORKFLOWS_PATH" 2>&1)
    echo "$export_output" | tee -a "$LOG_FILE"
    
    local export_status=$?
    local count=$(extract_count "$export_output")
    CONTAINER_WORKFLOWS_COUNT["$container_name"]=$count
    
    if [ $export_status -eq 0 ]; then
        # Copy files to host
        if docker cp "$container_name:$CONTAINER_WORKFLOWS_PATH/." "$host_workflows_dir/" 2>&1 | tee -a "$LOG_FILE"; then
            CONTAINER_WORKFLOWS_STATUS["$container_name"]="SUCCESS"
            log_message "SUCCESS" "Workflows export and copy completed successfully for $container_name"
            # Clean up inside container
            docker exec -u "$DOCKER_USER" "$container_name" rm -rf "$CONTAINER_WORKFLOWS_PATH" || true
            return 0
        else
            CONTAINER_WORKFLOWS_STATUS["$container_name"]="FAILED"
            log_message "ERROR" "Workflows copy failed for $container_name"
            return 1
        fi
    else
        CONTAINER_WORKFLOWS_STATUS["$container_name"]="FAILED"
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
    
    local export_output
    export_output=$(docker exec -u "$DOCKER_USER" "$container_name" n8n export:credentials --backup --decrypted --output="$CONTAINER_CREDENTIALS_PATH" 2>&1)
    echo "$export_output" | tee -a "$LOG_FILE"
    
    local export_status=$?
    local count=$(extract_count "$export_output")
    CONTAINER_CREDENTIALS_COUNT["$container_name"]=$count
    
    if [ $export_status -eq 0 ]; then
        # Copy files to host
        if docker cp "$container_name:$CONTAINER_CREDENTIALS_PATH/." "$host_credentials_dir/" 2>&1 | tee -a "$LOG_FILE"; then
            CONTAINER_CREDENTIALS_STATUS["$container_name"]="SUCCESS"
            log_message "SUCCESS" "Credentials export and copy completed successfully for $container_name"
            # Clean up inside container
            docker exec -u "$DOCKER_USER" "$container_name" rm -rf "$CONTAINER_CREDENTIALS_PATH" || true
            return 0
        else
            CONTAINER_CREDENTIALS_STATUS["$container_name"]="FAILED"
            log_message "ERROR" "Credentials copy failed for $container_name"
            return 1
        fi
    else
        CONTAINER_CREDENTIALS_STATUS["$container_name"]="FAILED"
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

# Function to generate HTML email table
generate_email_html() {
    local containers=("$@")
    local html_body=""
    
    html_body+='<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: auto; max-width: 800px; margin: 20px 0; font-size: 14px; }
        th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; white-space: nowrap; }
        th { background-color: #4CAF50; color: white; font-weight: bold; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        tr:hover { background-color: #f5f5f5; }
        .success { color: green; font-weight: bold; }
        .failed { color: red; font-weight: bold; }
        .skipped { color: orange; font-weight: bold; }
        .info { margin: 10px 0; font-size: 14px; }
        h2 { color: #333; margin-bottom: 10px; }
    </style>
</head>
<body>
    <h2>n8n Backup Report</h2>
    <p class="info"><strong>Date:</strong> '"$(date '+%Y-%m-%d %H:%M:%S')"'</p>
    <p class="info"><strong>Total Containers:</strong> '"${#containers[@]}"'</p>
    
    <table>
        <thead>
            <tr>
                <th>Container Name</th>
                <th>Workflows Status</th>
                <th>Credentials Status</th>
            </tr>
        </thead>
        <tbody>'
    
    for container in "${containers[@]}"; do
        local wf_status="${CONTAINER_WORKFLOWS_STATUS[$container]:-N/A}"
        local wf_count="${CONTAINER_WORKFLOWS_COUNT[$container]:-0}"
        local cred_status="${CONTAINER_CREDENTIALS_STATUS[$container]:-N/A}"
        local cred_count="${CONTAINER_CREDENTIALS_COUNT[$container]:-0}"
        
        local wf_class="success"
        local cred_class="success"
        
        [ "$wf_status" = "FAILED" ] && wf_class="failed"
        [ "$wf_status" = "SKIPPED" ] && wf_class="skipped"
        [ "$cred_status" = "FAILED" ] && cred_class="failed"
        [ "$cred_status" = "SKIPPED" ] && cred_class="skipped"
        
        html_body+='
            <tr>
                <td>'"$container"'</td>
                <td class="'"$wf_class"'">'"$wf_status"' ('"$wf_count"')</td>
                <td class="'"$cred_class"'">'"$cred_status"' ('"$cred_count"')</td>
            </tr>'
    done
    
    html_body+='
        </tbody>
    </table>
</body>
</html>'
    
    echo "$html_body"
}

# Function to determine overall backup status
determine_backup_status() {
    local total_containers=$1
    local success_count=$2
    local failed_count=0
    
    for container in "${!CONTAINER_WORKFLOWS_STATUS[@]}"; do
        local wf_status="${CONTAINER_WORKFLOWS_STATUS[$container]:-N/A}"
        local cred_status="${CONTAINER_CREDENTIALS_STATUS[$container]:-N/A}"
        
        if [ "$wf_status" = "FAILED" ] || [ "$cred_status" = "FAILED" ]; then
            failed_count=$((failed_count + 1))
        fi
    done
    
    if [ $success_count -eq $total_containers ] && [ $failed_count -eq 0 ]; then
        echo "SUCCESS"
    elif [ $success_count -eq 0 ]; then
        echo "ERROR"
    else
        echo "WARNING"
    fi
}

# Function to parse email addresses from string
parse_email_addresses() {
    local email_string="$1"
    # Replace semicolons with spaces, then split by comma or space
    echo "$email_string" | tr ';,' ' ' | tr -s ' ' | xargs -n1 | grep -v '^$'
}

# Function to send email notification
send_email_notification() {
    local containers=("$@")
    local total_containers=${#containers[@]}
    local success_count=0
    
    if [ "$ENABLE_EMAIL" != true ]; then
        log_message "INFO" "Email notification disabled"
        return 0
    fi
    
    log_message "INFO" "Preparing email notification"
    
    # Count successful containers
    for container in "${containers[@]}"; do
        local wf_status="${CONTAINER_WORKFLOWS_STATUS[$container]:-N/A}"
        local cred_status="${CONTAINER_CREDENTIALS_STATUS[$container]:-N/A}"
        
        if [ "$wf_status" = "SUCCESS" ] && [ "$cred_status" = "SUCCESS" ]; then
            success_count=$((success_count + 1))
        fi
    done
    
    # Determine overall status
    local overall_status=$(determine_backup_status $total_containers $success_count)
    local email_subject="[${overall_status}] ${EMAIL_SUBJECT_BASE} - $(date +%Y-%m-%d)"
    
    log_message "INFO" "Email subject: $email_subject"
    
    local email_html=$(generate_email_html "${containers[@]}")
    
    # Parse email addresses
    local email_addresses=()
    while IFS= read -r email; do
        if [ -n "$email" ]; then
            email_addresses+=("$email")
        fi
    done < <(parse_email_addresses "$EMAIL_TO")
    
    if [ ${#email_addresses[@]} -eq 0 ]; then
        log_message "ERROR" "No valid email addresses found"
        return 1
    fi
    
    log_message "INFO" "Sending to ${#email_addresses[@]} recipient(s): ${email_addresses[*]}"
    
    # Send email using curl with SMTP
    if command -v curl >/dev/null 2>&1; then
        log_message "INFO" "Sending email via SMTP using curl (Status: ${overall_status})"
        
        # Build mail-rcpt parameters for each recipient
        local rcpt_params=""
        for email in "${email_addresses[@]}"; do
            rcpt_params+=" --mail-rcpt \"$email\""
        done
        
        # Create email message with all recipients in To: header
        local to_header=$(IFS=,; echo "${email_addresses[*]}")
        local email_message="From: $EMAIL_FROM_NAME <$EMAIL_FROM>
To: $to_header
Subject: $email_subject
Content-Type: text/html; charset=UTF-8

$email_html"
        
        # Create temp file for the message
        local temp_msg="/tmp/n8n_backup_email_$$.txt"
        echo "$email_message" > "$temp_msg"
        
        # Build and execute curl command
        local curl_cmd="curl --ssl-reqd --url \"smtp://${SMTP_SERVER}:${SMTP_PORT}\" --user \"${SMTP_USER}:${SMTP_PASSWORD}\" --mail-from \"$EMAIL_FROM\""
        
        for email in "${email_addresses[@]}"; do
            curl_cmd+=" --mail-rcpt \"$email\""
        done
        
        curl_cmd+=" --upload-file \"$temp_msg\""
        
        # Execute the command
        eval "$curl_cmd" 2>&1 | tee -a "$LOG_FILE"
        local curl_status=$?
        
        # Clean up temp file
        rm -f "$temp_msg"
        
        if [ $curl_status -eq 0 ]; then
            log_message "SUCCESS" "Email sent successfully to: ${email_addresses[*]}"
        else
            log_message "ERROR" "Failed to send email (curl exit code: $curl_status)"
            return 1
        fi
    else
        log_message "WARNING" "curl not found, cannot send email"
        return 1
    fi
    
    return 0
}

# Function to send webhook notification
send_webhook_notification() {
    local backup_filename="$1"
    
    if [ "$ENABLE_WEBHOOK" != true ]; then
        log_message "INFO" "Webhook notification disabled"
        return 0
    fi
    
    log_message "INFO" "Sending webhook notification"
    
    if command -v curl >/dev/null 2>&1; then
        local json_payload=$(cat <<EOF
{
    "backup_file": "$(basename "$backup_filename")",
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
    "status": "completed"
}
EOF
)
        
        curl -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$json_payload" 2>&1 | tee -a "$LOG_FILE" || {
            log_message "ERROR" "Failed to send webhook"
        }
        
        if [ $? -eq 0 ]; then
            log_message "SUCCESS" "Webhook notification sent successfully"
        else
            log_message "ERROR" "Failed to send webhook notification"
        fi
    else
        log_message "WARNING" "curl not found, cannot send webhook"
    fi
    
    return 0
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
            CONTAINER_WORKFLOWS_STATUS["$container"]="SKIPPED"
            CONTAINER_WORKFLOWS_COUNT["$container"]=0
            CONTAINER_CREDENTIALS_STATUS["$container"]="SKIPPED"
            CONTAINER_CREDENTIALS_COUNT["$container"]=0
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
            echo "Before increment: success_count is '$success_count'"
            success_count=$((success_count + 1))
            echo "After increment: success_count is now '$success_count'"
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
    
    # ============================================================================
    # EMAIL AND WEBHOOK NOTIFICATIONS - Added functionality
    # ============================================================================
    
    log_separator "Sending Notifications"
    
    # Send email notification with backup report
    send_email_notification "${containers[@]}"
    
    # Send webhook notification with backup file info
    send_webhook_notification "$zip_filename"
    
    log_message "INFO" "All notifications completed"
}

# Execute main function
main "$@"
