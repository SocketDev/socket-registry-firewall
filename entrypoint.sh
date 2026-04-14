#!/bin/sh
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
    
    # External registry cooldown is now handled directly in Lua (no daemon needed).
    # "api" mode calls Socket cooldown API; "local" mode queries registries via Lua cosocket.
    log "External registry cooldown: handled inline by Lua (no daemon)"
    
    # Start config refresh daemon in background if deployment is configured
    # The daemon checks socket.deployment internally and exits if not set
    log "Checking remote config refresh configuration..."
    /usr/local/bin/socket-proxy-config-tool config-refresh --config "$config_file" &
    CONFIG_REFRESH_PID=$!
    sleep 1
    if kill -0 "$CONFIG_REFRESH_PID" 2>/dev/null; then
        log "Config refresh daemon running in background (PID: $CONFIG_REFRESH_PID)"
    else
        log "Config refresh daemon not needed (no socket.deployment configured)"
    fi
    
    # Start nginx in foreground, with signal handling to clean up background daemons
    log "Starting nginx..."

    # Trap SIGTERM/SIGINT to forward signal to nginx and kill background daemons
    cleanup() {
        log "Received shutdown signal, forwarding to nginx (PID: $NGINX_PID)..."
        kill -SIGTERM "$NGINX_PID" 2>/dev/null || true
        kill "$DAEMON_PID" "$CONFIG_REFRESH_PID" 2>/dev/null || true
        wait "$NGINX_PID" 2>/dev/null || true
        log "Nginx and background daemons stopped"
    }
    trap cleanup TERM INT

    /usr/local/openresty/nginx/sbin/nginx -g 'daemon off;' -c /app/nginx.conf &
    NGINX_PID=$!
    wait "$NGINX_PID"
    EXIT_CODE=$?
    cleanup
    exit $EXIT_CODE
}

# Run main
main "$@"
