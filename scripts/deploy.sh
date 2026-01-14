#!/bin/bash
# Falcon Distributed Deployment Script
# Deploys to all nodes defined in inventory/hosts.yaml

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

# Node definitions (from inventory)
COMPUTE_HOST="192.168.1.232"
COMPUTE_USER="davdunc"

WEB_HOST="192.168.1.162"
WEB_USER="ospartners"

DB_HOST="192.168.1.194"
DB_USER="ospartners"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

usage() {
    echo "Usage: $0 <command> [node]"
    echo ""
    echo "Commands:"
    echo "  setup <node>    - Initial node setup (compute|web|db|all)"
    echo "  deploy <node>   - Deploy/update packages (compute|web|all)"
    echo "  secrets <node>  - Copy secrets to node (compute|web|all)"
    echo "  start <node>    - Start services on node"
    echo "  stop <node>     - Stop services on node"
    echo "  status <node>   - Check service status on node"
    echo "  logs <node>     - View logs on node"
    echo ""
    echo "Nodes: compute (192.168.1.232), web (192.168.1.162), db (192.168.1.194)"
}

# Copy files to remote host
remote_copy() {
    local host=$1
    local user=$2
    local src=$3
    local dest=$4
    scp -r "$src" "${user}@${host}:${dest}"
}

# Run command on remote host
remote_run() {
    local host=$1
    local user=$2
    shift 2
    ssh "${user}@${host}" "$@"
}

setup_compute() {
    log_step "Setting up COMPUTE node ($COMPUTE_HOST)..."

    # Copy deploy files
    log_info "Copying deployment files..."
    remote_run $COMPUTE_HOST $COMPUTE_USER "mkdir -p ~/falcon-deploy"
    remote_copy $COMPUTE_HOST $COMPUTE_USER "$DEPLOY_DIR/services" "~/falcon-deploy/"
    remote_copy $COMPUTE_HOST $COMPUTE_USER "$DEPLOY_DIR/scripts/setup-node.sh" "~/falcon-deploy/"

    # Run setup
    log_info "Running setup script..."
    remote_run $COMPUTE_HOST $COMPUTE_USER "cd ~/falcon-deploy && chmod +x setup-node.sh && sudo ./setup-node.sh compute"

    log_info "Compute node setup complete!"
}

setup_web() {
    log_step "Setting up WEB node ($WEB_HOST)..."

    # Copy deploy files
    log_info "Copying deployment files..."
    remote_run $WEB_HOST $WEB_USER "mkdir -p ~/falcon-deploy"
    remote_copy $WEB_HOST $WEB_USER "$DEPLOY_DIR/services" "~/falcon-deploy/"
    remote_copy $WEB_HOST $WEB_USER "$DEPLOY_DIR/nginx" "~/falcon-deploy/"
    remote_copy $WEB_HOST $WEB_USER "$DEPLOY_DIR/scripts/setup-node.sh" "~/falcon-deploy/"

    # Run setup
    log_info "Running setup script..."
    remote_run $WEB_HOST $WEB_USER "cd ~/falcon-deploy && chmod +x setup-node.sh && sudo ./setup-node.sh web"

    log_info "Web node setup complete!"
}

deploy_secrets() {
    local node=$1

    case "$node" in
        compute)
            log_info "Deploying secrets to compute node..."
            remote_copy $COMPUTE_HOST $COMPUTE_USER "$DEPLOY_DIR/config/falcon-compute.env" "/tmp/secrets.env"
            remote_run $COMPUTE_HOST $COMPUTE_USER "sudo mv /tmp/secrets.env /etc/falcon/secrets.env && sudo chmod 600 /etc/falcon/secrets.env && sudo chown falcon:falcon /etc/falcon/secrets.env"
            ;;
        web)
            log_info "Deploying secrets to web node..."
            remote_copy $WEB_HOST $WEB_USER "$DEPLOY_DIR/config/falcon-web.env" "/tmp/secrets.env"
            remote_run $WEB_HOST $WEB_USER "sudo mv /tmp/secrets.env /etc/falcon/secrets.env && sudo chmod 600 /etc/falcon/secrets.env && sudo chown falcon:falcon /etc/falcon/secrets.env"
            ;;
        all)
            deploy_secrets compute
            deploy_secrets web
            ;;
    esac
}

start_services() {
    local node=$1

    case "$node" in
        compute)
            log_info "Starting services on compute node..."
            remote_run $COMPUTE_HOST $COMPUTE_USER "sudo systemctl start falcon-screener@morning.timer falcon-screener@midday.timer falcon-screener@evening.timer falcon-trader"
            ;;
        web)
            log_info "Starting services on web node..."
            remote_run $WEB_HOST $WEB_USER "sudo systemctl start falcon-dashboard nginx"
            ;;
        all)
            start_services compute
            start_services web
            ;;
    esac
}

stop_services() {
    local node=$1

    case "$node" in
        compute)
            log_info "Stopping services on compute node..."
            remote_run $COMPUTE_HOST $COMPUTE_USER "sudo systemctl stop falcon-trader falcon-screener@morning.timer falcon-screener@midday.timer falcon-screener@evening.timer" || true
            ;;
        web)
            log_info "Stopping services on web node..."
            remote_run $WEB_HOST $WEB_USER "sudo systemctl stop falcon-dashboard" || true
            ;;
        all)
            stop_services compute
            stop_services web
            ;;
    esac
}

show_status() {
    local node=$1

    case "$node" in
        compute)
            log_info "Status on compute node ($COMPUTE_HOST):"
            remote_run $COMPUTE_HOST $COMPUTE_USER "systemctl status falcon-trader falcon-screener@morning.timer --no-pager" || true
            ;;
        web)
            log_info "Status on web node ($WEB_HOST):"
            remote_run $WEB_HOST $WEB_USER "systemctl status falcon-dashboard nginx --no-pager" || true
            ;;
        all)
            show_status compute
            echo ""
            show_status web
            ;;
    esac
}

show_logs() {
    local node=$1

    case "$node" in
        compute)
            remote_run $COMPUTE_HOST $COMPUTE_USER "journalctl -u 'falcon-*' -f"
            ;;
        web)
            remote_run $WEB_HOST $WEB_USER "journalctl -u falcon-dashboard -f"
            ;;
    esac
}

# Main
COMMAND="${1:-}"
NODE="${2:-all}"

case "$COMMAND" in
    setup)
        case "$NODE" in
            compute) setup_compute ;;
            web) setup_web ;;
            all)
                setup_compute
                setup_web
                ;;
            *) log_error "Unknown node: $NODE"; exit 1 ;;
        esac
        ;;
    secrets)
        deploy_secrets "$NODE"
        ;;
    start)
        start_services "$NODE"
        ;;
    stop)
        stop_services "$NODE"
        ;;
    status)
        show_status "$NODE"
        ;;
    logs)
        show_logs "$NODE"
        ;;
    *)
        usage
        exit 1
        ;;
esac
