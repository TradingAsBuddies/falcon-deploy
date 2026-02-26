#!/bin/bash
# Falcon Distributed Deployment Script
# Wrapper for Ansible playbooks and manual operations
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
    echo "Usage: $0 <command> [node] [options]"
    echo ""
    echo "Commands:"
    echo "  setup <node>    - Full node setup via Ansible (compute|web|db|all)"
    echo "  deploy <node>   - Deploy/update packages via Ansible (compute|web|all)"
    echo "  secrets <node>  - Copy secrets to node (compute|web|all)"
    echo "  start <node>    - Start services on node"
    echo "  stop <node>     - Stop services on node"
    echo "  status <node>   - Check service status on node"
    echo "  logs <node>     - View logs on node"
    echo "  check <node>    - Dry-run Ansible playbook (--check mode)"
    echo ""
    echo "Options:"
    echo "  --tags <tags>   - Run only specific Ansible tags"
    echo "  --ask-vault     - Prompt for Ansible Vault password"
    echo "  -v, -vv, -vvv   - Ansible verbosity levels"
    echo ""
    echo "Nodes: compute (192.168.1.232), web (192.168.1.162), db (192.168.1.194)"
    echo ""
    echo "Examples:"
    echo "  $0 setup compute              # Full compute node setup"
    echo "  $0 setup web --tags nginx     # Only nginx setup on web"
    echo "  $0 check all                  # Dry-run all playbooks"
    echo "  $0 deploy compute --ask-vault # Deploy with vault prompt"
}

# Check if Ansible is available
check_ansible() {
    if ! command -v ansible-playbook &> /dev/null; then
        log_error "Ansible not found. Install with: pip install ansible"
        exit 1
    fi
}

# Build Ansible command with options
run_ansible() {
    local playbook=$1
    shift
    local extra_args=("$@")

    check_ansible
    cd "$DEPLOY_DIR"

    log_step "Running: ansible-playbook playbooks/${playbook}.yml ${extra_args[*]}"
    ansible-playbook "playbooks/${playbook}.yml" "${extra_args[@]}"
}

# Run command on remote host
remote_run() {
    local host=$1
    local user=$2
    shift 2
    ssh "${user}@${host}" "$@"
}

# Copy files to remote host
remote_copy() {
    local host=$1
    local user=$2
    local src=$3
    local dest=$4
    scp -r "$src" "${user}@${host}:${dest}"
}

# Ansible-based setup
setup_node() {
    local node=$1
    shift
    local extra_args=("$@")

    case "$node" in
        compute)
            log_step "Setting up COMPUTE node via Ansible..."
            run_ansible compute "${extra_args[@]}"
            ;;
        web)
            log_step "Setting up WEB node via Ansible..."
            run_ansible web "${extra_args[@]}"
            ;;
        db)
            log_step "Setting up DATABASE node via Ansible..."
            run_ansible database "${extra_args[@]}"
            ;;
        all)
            log_step "Setting up ALL nodes via Ansible..."
            run_ansible site "${extra_args[@]}"
            ;;
        *)
            log_error "Unknown node: $node"
            exit 1
            ;;
    esac
}

# Dry-run check
check_node() {
    local node=$1
    shift
    local extra_args=("--check" "$@")

    case "$node" in
        compute)
            log_step "Checking COMPUTE node (dry-run)..."
            run_ansible compute "${extra_args[@]}"
            ;;
        web)
            log_step "Checking WEB node (dry-run)..."
            run_ansible web "${extra_args[@]}"
            ;;
        db)
            log_step "Checking DATABASE node (dry-run)..."
            run_ansible database "${extra_args[@]}"
            ;;
        all)
            log_step "Checking ALL nodes (dry-run)..."
            run_ansible site "${extra_args[@]}"
            ;;
        *)
            log_error "Unknown node: $node"
            exit 1
            ;;
    esac
}

# Legacy: Manual secrets deployment (fallback if vault not configured)
deploy_secrets() {
    local node=$1

    case "$node" in
        compute)
            log_info "Deploying secrets to compute node..."
            if [[ -f "$DEPLOY_DIR/config/falcon-compute.env" ]]; then
                remote_copy $COMPUTE_HOST $COMPUTE_USER "$DEPLOY_DIR/config/falcon-compute.env" "/tmp/secrets.env"
                remote_run $COMPUTE_HOST $COMPUTE_USER "sudo mv /tmp/secrets.env /etc/falcon/secrets.env && sudo chmod 600 /etc/falcon/secrets.env && sudo chown falcon:falcon /etc/falcon/secrets.env"
            else
                log_error "Config file not found: config/falcon-compute.env"
                exit 1
            fi
            ;;
        web)
            log_info "Deploying secrets to web node..."
            if [[ -f "$DEPLOY_DIR/config/falcon-web.env" ]]; then
                remote_copy $WEB_HOST $WEB_USER "$DEPLOY_DIR/config/falcon-web.env" "/tmp/secrets.env"
                remote_run $WEB_HOST $WEB_USER "sudo mv /tmp/secrets.env /etc/falcon/secrets.env && sudo chmod 600 /etc/falcon/secrets.env && sudo chown falcon:falcon /etc/falcon/secrets.env"
            else
                log_error "Config file not found: config/falcon-web.env"
                exit 1
            fi
            ;;
        all)
            deploy_secrets compute
            deploy_secrets web
            ;;
        *)
            log_error "Unknown node: $node"
            exit 1
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
        *)
            log_error "Unknown node: $node"
            exit 1
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
        *)
            log_error "Unknown node: $node"
            exit 1
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
        db)
            log_info "Status on database node ($DB_HOST):"
            remote_run $DB_HOST $DB_USER "systemctl status postgresql --no-pager" || true
            ;;
        all)
            show_status compute
            echo ""
            show_status web
            echo ""
            show_status db
            ;;
        *)
            log_error "Unknown node: $node"
            exit 1
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
        db)
            remote_run $DB_HOST $DB_USER "journalctl -u postgresql -f"
            ;;
        *)
            log_error "Unknown node: $node"
            exit 1
            ;;
    esac
}

# Parse arguments
COMMAND="${1:-}"
NODE="${2:-all}"
shift 2 2>/dev/null || true
EXTRA_ARGS=("$@")

case "$COMMAND" in
    setup)
        setup_node "$NODE" "${EXTRA_ARGS[@]}"
        ;;
    deploy)
        setup_node "$NODE" "${EXTRA_ARGS[@]}"
        ;;
    check)
        check_node "$NODE" "${EXTRA_ARGS[@]}"
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
