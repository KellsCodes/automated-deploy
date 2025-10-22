# Automated Docker Deployment Script

A robust, production-grade **Bash automation tool** for setting up, deploying, and managing Dockerized applications on remote Linux servers.  

This script simplifies DevOps workflows by automating repository setup, server provisioning, Docker installation, Nginx configuration, and container deployment - all securely over SSH.

---

## 🚀 Features

- 🔐 Secure SSH-based remote automation  
- 🐳 Automated Docker + Docker Compose installation  
- 🌐 Nginx reverse proxy with optional SSL support  
- 🧠 Smart idempotency — re-runs without breaking setups  
- 🪣 Auto-clones or pulls latest changes from GitHub (using PAT)  
- 🧩 Builds and deploys Docker containers or Compose stacks  
- 🔍 Health checks and deployment validation  
- 📜 Clear, color-coded logging  
- 🧹 Optional cleanup mode (`--cleanup`) for safe resets  

---

## 🧰 Prerequisites

Before running the script, ensure you have:

- A **remote Linux server** (Ubuntu 20.04+ recommended)
- **SSH access** with key-based authentication
- **sudo privileges** on the target server
- A **GitHub Personal Access Token (PAT)** for private repos
- **Bash 5.0+**, `ssh`, and `scp` installed locally

---

## 💻 Supported Platforms

| OS Distribution | Status | Notes |
|------------------|--------|-------|
| Ubuntu 20.04+    | ✅ Supported | Default target |
| Debian 11+       | ⚠️ Partial | Some commands may vary |
| Other Linux Distros | ⚠️ Partial | Untested, may need adjustments |

---

## ⚙️ Installation

Clone this project and make the script executable:

```bash
git clone https://github.com/KellsCodes/automated-deploy.git
cd automated-deploy
chmod +x deploy.sh
```

---

## 🚦 Usage

Run the deployment script:

```bash
./deploy.sh
```

You’ll be prompted for the following inputs:

| Variable | Description |
|-----------|-------------|
| **GIT_REPO_URL** | The HTTPS URL of your Git repository |
| **GIT_BRANCH** | Branch to deploy (e.g., `main`, `develop`) |
| **SERVER_IP** | Public IP of your remote server |
| **SSH_USER** | Username for SSH connection |
| **SSH_KEY_PATH** | Path to your `.pem` private key (e.g. `~/.ssh/aws-key.pem`) |
| **APP_PORT** | Application port exposed in Docker |
| **GIT_PAT** | GitHub Personal Access Token (for private repos) |

Once executed, the script will:
1. Clone or update the repository.  
2. SSH into the remote server.  
3. Install or update Docker, Compose, and Nginx.  
4. Transfer files securely.  
5. Build and run containers.  
6. Configure Nginx reverse proxy.  
7. Validate app health and connectivity.

---

## 🔁 Deployment Lifecycle

1. **Clone / Update Repo** → Authenticates with PAT and syncs the specified branch.  
2. **SSH Connection** → Establishes secure access to remote host.  
3. **Environment Setup** → Installs Docker, Compose, Nginx, and dependencies.  
4. **Deployment** → Transfers files, builds images, and starts containers.  
5. **Reverse Proxy Setup** → Configures Nginx to forward requests to the app.  
6. **Verification** → Checks container and port health.  
7. **Idempotency Check** → Ensures safe re-runs without breaking live setups.  

---

## 🧹 Cleanup (Optional)

To remove deployed containers, images, and Nginx configs, use:

```bash
./deploy.sh --cleanup
```

This safely removes Docker containers, images, and related deployment artifacts.

---

## 🔒 Security Considerations

- Use **key-based SSH authentication** (no password logins).  
- Keep your **PAT** secure — never hardcode it.  
- Limit server access to trusted IPs using firewall or security groups.  
- Run deployments with **least-privilege** principles.  

---

## 🧩 CI/CD Integration

This script can be integrated into CI/CD pipelines (e.g., GitHub Actions, GitLab CI, Jenkins) by providing environment variables non-interactively:

```bash
GIT_REPO_URL=https://github.com/KellsCodes/automated-deploy.git GIT_BRANCH=main SERVER_IP=1.2.3.4 SSH_USER=ubuntu SSH_KEY_PATH=~/.ssh/server-key.pem APP_PORT=8080 GIT_PAT=your_pat_here ./deploy.sh
```

---

## 🪵 Logging & Monitoring

- All operations are logged in real time with color-coded status indicators.  
- You can redirect logs to a file for auditing:

```bash
./deploy.sh | tee deploy.log
```

---

## 🧠 Troubleshooting

| Issue | Possible Fix |
|--------|---------------|
| **SSH connection fails** | Ensure correct IP, SSH key, and security group allow port 22 |
| **Permission denied (publickey)** | Verify the `.pem` file path and permissions (`chmod 400 key.pem`) |
| **403 during clone** | Ensure the PAT has `repo` and `read:packages` access |
| **Port already in use** | Stop old containers or change `$APP_PORT` |
| **Nginx reload fails** | Check `/etc/nginx/sites-available/` for syntax errors |

---

## 🤝 Contributing

Contributions are welcome!  
Open an issue or submit a pull request to enhance features or add platform support.

---

## 📜 License

MIT License © 2025 [KellsCodes](https://github.com/KellsCodes)

---

## 👨‍💻 Maintainers

**Author:** Ifeanyi Nworji  
**GitHub:** [@KellsCodes](https://github.com/KellsCodes)