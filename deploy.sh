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


# ==============================================================
# PART 10 — IDEMPOTENCY & CLEANUP HANDLING(At THE BOTTOM SCRIPT)
# ==============================================================

# --- Define cleanup flag ---
CLEANUP_MODE=false

# Check if user passed the --cleanup flag when running script
for arg in "$@"; do
    if [[ "$arg" == "--cleanup" ]]; then
        CLEANUP_MODE=true
    fi
done


# --- Idempotent setup before new deployment ---
log_info " Ensuring idempotency before redeployment..."

ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" bash -s <<EOF
    set -e

    echo "Checking for existing containers on port $APP_PORT..."
    EXISTING_CONTAINER=\$(sudo docker ps --filter "publish=$APP_PORT" --format "{{.ID}}")
    if [[ -n "\$EXISTING_CONTAINER" ]]; then
        echo "Stopping existing container using port $APP_PORT..."
        sudo docker stop "\$EXISTING_CONTAINER" || true
        sudo docker rm "\$EXISTING_CONTAINER" || true
    fi

    echo "Cleaning up old Docker networks..."
    sudo docker network prune -f || true

    echo "Ensuring Nginx config symlink is unique..."
    sudo rm -f /etc/nginx/sites-enabled/app_proxy
    sudo ln -sf /etc/nginx/sites-available/app_proxy /etc/nginx/sites-enabled/app_proxy || true
EOF

if [[ $? -eq 0 ]]; then
    log_info " Idempotent checks completed. Safe to redeploy."
else
    log_error " Idempotent check failed during remote execution."
    exit 1
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


# ==========================================
# Part 6 - DEPLOY THE DOCKERIZED APPLICATION
# ==========================================

log_info "Deploying the Dockerized application to remote server..."

# --- Define directories ---
CLONE_DIR="$HOME/deployment/$(basename -s .git "$GIT_REPO_URL")"

# Remote deployment directory
REMOTE_APP_DIR="/home/$SSH_USER/app"

# --- Verify cloned repo exists locally ---
if [[ ! -d "$CLONE_DIR" ]]; then
    log_error "Local cloned directory not found at: $CLONE_DIR"
    exit 1
fi

# --- Step 1: Transfer project files to remote server ---
log_info "Transferring project files to $SERVER_IP..."

rsync -avz -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" \
    --exclude '.git' --exclude 'node_modules' --exclude '.env' \
    "$CLONE_DIR/" "$SSH_USER@$SERVER_IP:$REMOTE_APP_DIR" >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
    log_error "File transfer to remote server failed."
    exit 1
else
    log_info "Project files transferred successfully."
fi

# --- Step 2: Build and run containers remotely ---
log_info "Building and running Docker containers on $SERVER_IP..."

ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" bash <<EOF
set -e

cd $REMOTE_APP_DIR

# --- Detect Docker configuration ---
if [[ -f "docker-compose.yml" ]]; then
    echo "docker-compose.yml found. Starting with Docker Compose..."
    sudo docker-compose pull
    sudo docker-compose build
    sudo docker-compose up -d
elif [[ -f "Dockerfile" ]]; then
    echo "Dockerfile found. Building and running manually..."
    APP_NAME=\$(basename \$(pwd))
    sudo docker build -t \$APP_NAME .
    sudo docker run -d -p $APP_PORT:$APP_PORT --name \$APP_NAME \$APP_NAME
else
    echo "No Dockerfile or docker-compose.yml found in project directory."
    exit 1
fi

# --- Step 3: Validate container health ---
echo "Checking running containers..."
sudo docker ps

# --- Step 4: Verify app is accessible on the specified port ---
echo "Validating application accessibility on port $APP_PORT..."
sleep 5
if curl -s "http://localhost:$APP_PORT" >/dev/null; then
    echo "Application is running and accessible on port $APP_PORT!"
else
    echo "Application did not respond on port $APP_PORT. Check container logs."
    sudo docker logs \$(sudo docker ps -q --latest)
fi
EOF

if [[ $? -ne 0 ]]; then
    log_error " Deployment failed on $SERVER_IP."
    exit 1
else
    log_info " Deployment completed successfully!"
fi


# =========================================
# PART 7 — CONFIGURE NGINX AS REVERSE PROXY
# =========================================

log_info "Configuring Nginx as reverse proxy..."

# Ensure DOMAIN_NAME exists (optional override)
DOMAIN_NAME="${DOMAIN_NAME:-example.com}"

# Create a temporary nginx config locally with correct escaping for nginx $-vars
TMP_NGINX_CONF="$(mktemp /tmp/app_proxy.XXXXXX.conf)"

cat > "$TMP_NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    access_log /var/log/nginx/app_access.log;
    error_log /var/log/nginx/app_error.log;
}

# SSL placeholder (Certbot or self-signed)
# server {
#     listen 443 ssl;
#     server_name ${DOMAIN_NAME};
#     ssl_certificate /etc/ssl/certs/app.crt;
#     ssl_certificate_key /etc/ssl/private/app.key;
#     location / {
#         proxy_pass http://127.0.0.1:${APP_PORT};
#         proxy_set_header Host \$host;
#     }
# }
EOF

log_info "Uploading nginx config to remote host..."

# Paths on remote
NGINX_CONFIG_PATH="/etc/nginx/sites-available/app_proxy"
NGINX_ENABLED_PATH="/etc/nginx/sites-enabled/app_proxy"

# Copy config to remote /tmp then move with sudo to proper location to avoid permission issues
scp -i "$SSH_KEY_PATH" "$TMP_NGINX_CONF" "$SSH_USER@$SERVER_IP:/tmp/app_proxy.conf" >/dev/null 2>&1 || {
  log_error "Failed to upload nginx config to remote host."
  rm -f "$TMP_NGINX_CONF"
  exit 1
}

rm -f "$TMP_NGINX_CONF"

# Apply config remotely: install nginx if missing, remove default, move config, enable, test, reload
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" bash -s <<'REMOTE_EOF'
set -e

NGINX_CONFIG_PATH="/etc/nginx/sites-available/app_proxy"
NGINX_ENABLED_PATH="/etc/nginx/sites-enabled/app_proxy"

# Install nginx if missing
if ! command -v nginx &>/dev/null; then
  echo "Installing nginx..."
  sudo apt-get update -y
  sudo apt-get install -y nginx
fi

# Remove default site if present
if [ -f /etc/nginx/sites-enabled/default ]; then
  echo "Removing default nginx site..."
  sudo rm -f /etc/nginx/sites-enabled/default
fi

# Move uploaded config into place
sudo mv /tmp/app_proxy.conf "$NGINX_CONFIG_PATH"
sudo chown root:root "$NGINX_CONFIG_PATH"
sudo chmod 644 "$NGINX_CONFIG_PATH"

# Enable site (idempotent)
sudo ln -sf "$NGINX_CONFIG_PATH" "$NGINX_ENABLED_PATH"

# Test and reload
if sudo nginx -t; then
  echo "nginx config OK - reloading"
  sudo systemctl reload nginx
else
  echo "nginx config test FAILED"
  sudo nginx -t || true
  exit 1
fi

echo "Nginx reverse proxy configured"
REMOTE_EOF

if [[ $? -eq 0 ]]; then
  log_info " Nginx reverse proxy configured successfully!"
  log_info "Access your app at: http://$SERVER_IP (or http://$DOMAIN_NAME)"
else
  log_error " Failed to configure Nginx reverse proxy."
  exit 1
fi



# ===========================
# PART 8: VALIDATE DEPLOYMENT
# ===========================

log_info " Validating deployment..."

# 1. Check Docker service status
if ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "systemctl is-active --quiet docker"; then
  log_info " Docker service is active."
else
  log_error " Docker service is not running!"
  exit 1
fi

# 2. Verify running containers
log_info "Checking for running containers..."
ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || {
  log_error " Failed to list containers!"
  exit 1
}

# 3. Confirm Nginx is active
if ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "systemctl is-active --quiet nginx"; then
  log_info " Nginx service is active."
else
  log_error " Nginx service is not running!"
  exit 1
fi

# 4. Test Nginx reverse proxy locally (inside EC2)
log_info "Testing Nginx proxy locally..."
ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" "curl -I http://localhost" || {
  log_error " Local Nginx test failed!"
  exit 1
}

# 5. Test app accessibility remotely (from your local machine)
log_info "Testing app accessibility remotely..."
if curl -I "http://$SERVER_IP" | grep -qE "200|301|302"; then
  log_info " App is accessible via Nginx reverse proxy at http://$SERVER_IP"
else
  log_error " App is not accessible at http://$SERVER_IP. Check Nginx config or container port mapping."
fi


# --- Handle cleanup mode ---
if [[ "$CLEANUP_MODE" == true ]]; then
    log_info " Cleanup mode activated. Removing deployed resources from remote server..."

    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" bash -s <<EOF
        set -e

        echo "Stopping and removing Docker containers..."
        if sudo docker ps -q | grep .; then
            sudo docker stop \$(sudo docker ps -q)
            sudo docker rm \$(sudo docker ps -a -q)
        fi

        echo "Removing all app-related Docker images..."
        sudo docker image prune -af

        echo "Removing old Docker networks if any..."
        sudo docker network prune -f

        echo "Removing Nginx configuration..."
        sudo rm -f /etc/nginx/sites-available/app_proxy /etc/nginx/sites-enabled/app_proxy
        sudo nginx -t && sudo systemctl reload nginx

        echo "Removing application directory..."
        rm -rf "/home/$SSH_USER/app"

        echo "Cleanup complete!"
EOF

    if [[ $? -eq 0 ]]; then
        log_info " Cleanup completed successfully."
        exit 0
    else
        log_error " Cleanup failed during remote execution."
        exit 1
    fi
fi