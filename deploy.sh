#!/usr/bin/env bash
set -euo pipefail

# ===========================
# Automated Docker Deployment Script
# Part 1: User Input Collection
# ===========================

# Handle unexpected errors
trap 'echo "An unexpected error occurred on line $LINENO"; exit 1' ERR

echo "Starting Automated Docker Deployment..."
echo "........................................"

# --- Helper functions ---
log_info() {
    echo -e "ℹ️ $1"
}

log_error() {
    echo -e "❌ $1" >&2
}

# --- Prompt for user inputs ---

# Git Repository URL
while [[ -z "${GIT_REPO_URL:-}" ]]; do
    read -rp "Enter the git repository URL: " GIT_REPO_URL
    [[ -z "$GIT_REPO_URL" ]] && log_error "Repository URL cannot be empty."
done

# Personal Access Token (PAT) - hidden input
while [[ -z "${GIT_PAT:-}" ]]; do
  read -rsp "Enter your Git Personal Access Token (PAT): " GIT_PAT
  echo ""
  [[ -z "$GIT_PAT" ]] && log_error "Personal Access Token cannot be empty."
done

# Branch name (default = main)
read -rp "Enter branch name [default: main]: " GIT_BRANCH
GIT_BRANCH=${GIT_BRANCH:-main}

#SSH username
while [[ -z "${SSH_USER:-}" ]]; do
    read -rp "Enter remote server SSH username: " SSH_USER
    [[ -z "$SSH_USER" ]] && log_error "SSH username cannot be empty."
done

#Server IP address
while [[ -z "${SERVER_IP:-}" ]]; do
    read -rp "Enter remote server IP address: " SERVER_IP
    if [[ ! "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        log_error "Invalid IP format. Please enter a valid IPV4 address."
        SERVER_IP=""
    fi
done

# SSH key path
while [[ -z "${SSH_KEY_PATH:-}" ]]; do
    read -rp "Enter path to SSH private key: " SSH_KEY_PATH
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log_error "SSH key file not found at $SSH_KEY_PATH"
        SSH_KEY_PATH=""
    fi
done

# Application port (internal container port)
while [[ -z "${APP_PORT:-}" ]]; do
    read -rp "Enter internal application (container) port (e.g., 8080): " APP_PORT
    if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port. Please enter a numeric value."
        APP_PORT=""
    fi
done

# --- Summary before proceeding ---
echo ""
echo "Summary of inputs:"
echo "..................."
echo "Repository URL:   $GIT_REPO_URL"
echo "Branch:           $GIT_BRANCH"
echo "Server IP:        $SERVER_IP"
echo "SSH User:         $SSH_USER"
echo "SSH Key Path:     $SSH_KEY_PATH"
echo "App Port:         $APP_PORT"
# echo "GIT PAT:          $GIT_PAT"
echo ""

# read -rp "Proceed with these settings? (y/n): " CONFIRM
# if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
#     log_info " Deployment aborted by user."
#     exit 0
# fi

# =================================
# Part 2: Setup and clone repository
# =================================
log_info " All parameters collected successfully"
log_info " Starting repository setup..."

REPO_NAME=$(basename -s .git "$GIT_REPO_URL")
WORK_DIR="$HOME/deployment/$REPO_NAME"

# Create deployment directory if not exists
mkdir -p "$(dirname "$WORK_DIR")"

# Authenticated URL (PAT safely embedded)
GIT_USERNAME=$(echo "$GIT_REPO_URL" | awk -F[/:] '{print $(NF-1)}')
AUTH_REPO_URL=$(echo "$GIT_REPO_URL" | sed "s#https://#https://$GIT_USERNAME:$GIT_PAT@#")
if [[ -d "$WORK_DIR/.git" ]]; then
    log_info " Repository already exists. Pulling latest changes..."
    cd "$WORK_DIR"
    git reset --hard
    git clean -fd
    git fetch origin "$GIT_BRANCH"
    git checkout "$GIT_BRANCH"
    git pull origin "$GIT_BRANCH" || {
        log_error " Failed to pull latest changes from $GIT_BRANCH"
        exit 1
    }
else
    log_info " Cloning repository into $WORK_DIR..."
    git clone --branch "$GIT_BRANCH" "$AUTH_REPO_URL" "$WORK_DIR" || {
        log_error " Failed to clone repository. Please check your URL or PAT"
        exit 1
    }
    cd "$WORK_DIR"
fi

log_info " Repository is ready at: $WORK_DIR"
echo "......................................."

# ==========================
# Part 3: Verify Docker Setup
# ==========================
log_info " Navigating into the cloned directory"

# Ensure work_dir is the correct directory
cd "$WORK_DIR" || {
    log_error " Failed to enter repository directory: $WORK_DIR"
    exit 1
}

log_info " Checking Docker setup in repository..."

# Check for Docker configuration  files
if [[ -f "Dockerfile" ]]; then
    log_info " Found Dockerfile - ready for Docker build."
elif [[ -f "compose.yaml" || -f "compose.yml" || -f "docker-compose.yaml" || -f "docker-compose.yml" ]]; then
    log_info " Found docker-compose.yml - ready for multi-service deployment"
else
    log_error " No Dockerfile or docker-compose.yml found. Cannot continue deployment."
    exit 1
fi

log_info " Docker Configuration verified successfully."

# ========================================================
# Part 4 - SSH INTO REMOTE SERVER AND VERIFY CONNECTION
# ========================================================
echo " Verifying SSH connection to remote server..."

# Validate SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "SSH key ot found at: $SSH_KEY_PATH"
    exit 1
fi

# Test SSH connection (non-interactive)
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o BatchMode=yes "$SSH_USER@$SERVER_IP" "echo 'SSH connection successful!'" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Unable to connect to remote server via SSH. Please verify credentials, key permissions, and IP address."
    exit 1
else
    echo "SSH connection verified successfully."
fi

# ========================================================
# Part 5 - PREPARE REMOTE ENVIRONMENT ---
# ========================================================

log_info "Preparing remote environment on $SERVER_IP..."

ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" bash <<EOF
set -e

echo "Updating system packages..."
sudo apt-get update -y && sudo apt-get upgrade -y

echo "Installing required packages (curl, ca-certificates, gnupg, lsb-release)..."
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# --- Install Docker if not installed ---
if ! command -v docker &>/dev/null; then
    echo "Docker not found. Installing Docker..."
    curl -fsSL https://get.docker.com | sudo bash
else
    echo "Docker already installed."
fi

# --- Install Docker Compose if not installed ---
if ! command -v docker-compose &>/dev/null; then
    echo "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "Docker Compose already installed."
fi

# --- Install nginx if not installed ---
if ! command -v nginx &>/dev/null; then
    echo "Installing nginx..."
    sudo apt-get install -y nginx
else
    echo "nginx already installed."
fi

# --- Add SSH user to docker group ---
if ! groups $SSH_USER | grep -q docker; then
    echo "Adding user '$SSH_USER' to docker group..."
    sudo usermod -aG docker $SSH_USER
    echo "You may need to log out and back in for this to take effect."
else
    echo "User '$SSH_USER' already in docker group."
fi

# --- Enable and start services ---
sudo systemctl enable docker
sudo systemctl start docker
sudo systemctl enable nginx
sudo systemctl start nginx

# --- Confirm installation versions ---
echo "Confirming versions..."
docker --version
docker-compose --version
nginx -v

echo "Remote environment setup complete."
EOF

if [[ $? -ne 0 ]]; then
    log_error " Failed to prepare remote environment on $SERVER_IP."
    exit 1
else
    log_info " Remote environment prepared successfully!"
fi
