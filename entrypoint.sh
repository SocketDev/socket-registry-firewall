#!/bin/bash
# Simplified entrypoint script using socket-proxy-config-tool

set -e

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*" >&2
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Unpack tarball if the SOCKET_TARBALL_PATH environment variable is set.
# Set this via ENV in your Dockerfile or with -e at docker run / in docker-compose.
# Allows users to embed a release tarball in their own Docker image alongside
# this entrypoint.sh and have it self-install at startup, replicating the same
# layout as the pre-built socketdev/socket-registry-firewall image.
#
# Example Dockerfile usage:
#   ENV SOCKET_TARBALL_PATH=/app/socket-firewall.1.1.86.amd64.tgz
install_from_tarball() {
    if [ -z "$SOCKET_TARBALL_PATH" ]; then
        return 0
    fi

    if [ ! -f "$SOCKET_TARBALL_PATH" ]; then
        error "SOCKET_TARBALL_PATH is set to '$SOCKET_TARBALL_PATH' but file not found"
        exit 1
    fi

    log "Installing from tarball: $SOCKET_TARBALL_PATH"
    tar -xzf "$SOCKET_TARBALL_PATH" -C /
    chmod +x /usr/local/bin/socket-proxy-config-tool
    log "Tarball installed successfully"
}

# Run dev environment scripts
run_dev_scripts() {
    local scripts_dir="/entrypoint/scripts"
    
    if [ ! -d "$scripts_dir" ]; then
        return 0
    fi
    chmod +x "$scripts_dir"/*.sh
    log "Running dev environment scripts..."
    
    # Find and execute all .sh scripts in the scripts directory
    for script in "$scripts_dir"/*.sh; do
        if [ -f "$script" ]; then
            log "Executing dev script: $(basename "$script")"
            if bash "$script"; then
                log "Successfully executed: $(basename "$script")"
            else
                warn "Script $(basename "$script") failed with exit code $?"
            fi
        fi
    done
}

# Main entrypoint logic
main() {
    log "Starting Socket Firewall"
    
    # Run dev scripts if SOCKET_ENV is set to 'dev'
    if [ "$SOCKET_ENV" = "dev" ]; then
        log "SOCKET_ENV=dev detected, running dev scripts..."
        run_dev_scripts
    fi

    # Install from tarball if SOCKET_TARBALL_PATH is set
    install_from_tarball

    # Configuration file location
    local config_file="${CONFIG_FILE:-/app/socket.yml}"
    
    if [ -f "$config_file" ]; then
        log "Using configuration: $config_file"
    else
        warn "No configuration file found at $config_file, using defaults"
    fi
    
    # Generate all nginx configurations using the config tool
    log "Generating nginx configurations..."
    
    if ! /usr/local/bin/socket-proxy-config-tool generate --config "$config_file"; then
        error "Failed to generate configurations"
        exit 1
    fi
    
    log "Configuration generation complete"
    
    # Source environment variables from config.env if it exists
    if [ -f /app/config.env ]; then
        log "Loading environment variables from config.env"
        # shellcheck disable=SC1091
        source /app/config.env
        
        # Log key proxy settings for debugging
        if [ -n "$SOCKET_OUTBOUND_PROXY" ]; then
            log "Outbound proxy configured: $SOCKET_OUTBOUND_PROXY"
        fi
    else
        warn "No config.env file found, environment variables from socket.yml may not be set"
    fi
    
    # Validate nginx configuration
    log "Validating nginx configuration..."
    if ! /usr/local/openresty/nginx/sbin/nginx -t -c /app/nginx.conf; then
        error "Nginx configuration validation failed"
        exit 1
    fi
    
    log "Nginx configuration is valid"
    
    # Start auto-discovery daemon in background if configured
    # The daemon checks the mode internally and exits immediately if mode=local
    log "Checking auto-discovery configuration..."
    /usr/local/bin/socket-proxy-config-tool daemon --config "$config_file" &
    DAEMON_PID=$!
    # Give it a moment to start or exit
    sleep 1
    if kill -0 "$DAEMON_PID" 2>/dev/null; then
        log "Route sync daemon running in background (PID: $DAEMON_PID)"
    else
        log "Route sync daemon not needed (mode=local or not configured)"
    fi
    
    # Start nginx in foreground
    log "Starting nginx..."
    exec /usr/local/openresty/nginx/sbin/nginx -g 'daemon off;' -c /app/nginx.conf
}

# Run main
main "$@"
