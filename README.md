# Socket Registry Firewall

Enterprise-grade security proxy that protects your package registries (npm, PyPI, Maven, Cargo, RubyGems, OpenVSX, NuGet, Go) by scanning packages with Socket's security API in real-time to block malicious packages before they reach your systems.

## Supported Registries

- **npm** (JavaScript/Node.js) - `registry.npmjs.org`
- **PyPI** (Python) - `pypi.org`
- **Maven** (Java) - `repo1.maven.org`
- **Cargo** (Rust) - `crates.io`
- **RubyGems** (Ruby) - `rubygems.org`
- **OpenVSX** (VS Code Extensions) - `open-vsx.org`
- **NuGet** (.NET) - `nuget.org`
- **Go** (Go Modules) - `proxy.golang.org`
- **Conda** (Python/R/etc.) - `conda.anaconda.org` *(treated as PyPI until native support)*

## Key Features

✅ **Real-time Security** - Blocks malicious packages before installation  
✅ **Multi-Registry** - Protects all 8 major package ecosystems  
✅ **Flexible Routing** - Domain-based or path-based routing  
✅ **Auto-Discovery** - Sync routes from Artifactory/Nexus automatically  
✅ **High Performance** - Intelligent caching with Redis support  
✅ **Enterprise Ready** - Outbound proxy, custom CAs, Splunk logging  
✅ **Zero Config** - Works with public registries out-of-the-box  

## Quick Start

### 1. Get Socket API Key

1. Sign up at [Socket.dev](https://socket.dev/)
2. Go to [Settings → API Keys](https://socket.dev/dashboard/organization/settings/api-keys)
3. Create API key with scopes: `packages`, `entitlements:list`

### 2. Set API Token

```bash
# Create .env file with your Socket API token
cat > .env <<EOF
SOCKET_SECURITY_API_TOKEN=your-api-key-here
EOF
```

Or export it in your shell:

```bash
export SOCKET_SECURITY_API_TOKEN=your-api-key-here
```

### 3. Create Docker Compose File

Create a `docker-compose.yml`:

```yaml
services:
  socket-firewall:
    image: socketdev/socket-registry-firewall:latest
    ports:
      - "8080:8080"   # HTTP (redirects to HTTPS)
      - "8443:8443"   # HTTPS
    environment:
      # Required: Socket.dev API token
      - SOCKET_SECURITY_API_TOKEN=${SOCKET_SECURITY_API_TOKEN}
    volumes:
      # Configuration file
      - ./socket.yml:/app/socket.yml:ro
      # SSL certificates directory
      - ./ssl:/etc/nginx/ssl
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-fk", "https://localhost:8443/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

Create a minimal `socket.yml`:

```yaml
# Minimal configuration - uses defaults for all public registries
# Access registries at: https://localhost:8443/npm/, /pypi/, /maven/, etc.

socket:
  api_url: https://api.socket.dev

# Set internal container ports the firewall will bind to
ports:
  http: 8080
  https: 8443

path_routing:
  enabled: true
  domain: sfw.your_company.com
  routes:
    - path: /npm
      upstream: https://registry.npmjs.org
      registry: npm
  
# Optional: Customize performance settings
nginx:
  worker_processes: 2
  worker_connections: 4096
```

### 4. Add host entry (edit /etc/hosts)
```
sudo sh -c 'printf "127.0.0.1   sfw.your_company.com\n::1         sfw.your_company.com\n" >> /etc/hosts'
```

### 5. Pull the Firewall from Docker
```
docker pull socketdev/socket-registry-firewall
```

### 6. Start the Firewall

```bash
docker compose up -d
```

That's it! The firewall is now protecting the npm registry at `http://sfw.your_company.com:8080/npm/`.

## Testing It Works

**Test npm:**
```bash
# Configure npm to use the firewall
npm config set registry http://sfw.your_company.com:8080/npm/
npm config set strict-ssl false  # Only for self-signed certs

# Install a package
npm install lodash --loglevel verbose

# Try to install a malicious package and watch Socket Firewall block the package.
npm install lodahs
```

### Additional ecosystem samples

- Add more ecosystems into the `socket.yml`, then test with these common language samples below. 

**Test pip:**
```bash
# Configure pip to use the firewall
pip config set global.index-url https://localhost:8443/pypi/simple
pip config set global.trusted-host "localhost"

# Install a package
pip install requests
```

**Test Maven:**
```bash
# Add to ~/.m2/settings.xml
cat > ~/.m2/settings.xml <<'EOF'
<settings>
  <mirrors>
    <mirror>
      <id>socket-firewall</id>
      <url>https://localhost:8443/maven</url>
      <mirrorOf>*</mirrorOf>
    </mirror>
  </mirrors>
</settings>
EOF

# Build your project
mvn install -Dmaven.wagon.http.ssl.insecure=true -Dmaven.wagon.http.ssl.allowall=true
```

**Test Gradle:**

edit your `settings.gradle`:
```groovy
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS) // or FAIL_ON_PROJECT_REPOS
    repositories {
        maven { url "https://localhost:8443/maven" }
    }
}
```

## Configuration

### Basic: Custom Domains

Create `socket.yml` for custom domains:

```yaml
registries:
  npm:
    domains:
      - npm.company.com
  pypi:
    domains:
      - pypi.company.com
  maven:
    domains:
      - maven.company.com
```

### Advanced: Path Routing (Artifactory/Nexus)

Single domain with path prefixes:

```yaml
path_routing:
  enabled: true
  domain: firewall.company.com
  
  routes:
    - path: /npm
      upstream: https://registry.npmjs.org
      registry: npm
    
    - path: /pypi
      upstream: https://pypi.org
      registry: pypi
    
    - path: /maven
      upstream: https://repo1.maven.org/maven2
      registry: maven
```

### Enterprise: Auto-Discovery from Artifactory/Nexus

Automatically sync repository routes:

```yaml
path_routing:
  enabled: true
  domain: firewall.company.com
  mode: nexus  # or 'artifactory'
  
  private_registry:
    api_url: https://nexus.company.com
    api_key: your-nexus-api-token
    interval: 5m  # Auto-sync every 5 minutes
    
    # Optional filters
    include_pattern: ".*"
    exclude_pattern: "(tmp|test)-.*"
```

Routes update automatically when you add/remove repositories - no manual configuration!

See [docs/AUTO-DISCOVERY.md](docs/AUTO-DISCOVERY.md) for details.

## SSL/TLS Certificates

### Option 1: Use Provided Self-Signed Certificates

The firewall auto-generates self-signed certificates on first run. Trust them:

**macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ssl/fullchain.pem
```

**Linux:**
```bash
sudo cp ssl/fullchain.pem /usr/local/share/ca-certificates/socket-firewall.crt
sudo update-ca-certificates
```

### Option 2: Use Your Own Certificates

Place your certificates in the `ssl/` directory:

```bash
cp /path/to/cert.pem ssl/fullchain.pem
cp /path/to/key.pem ssl/privkey.pem
```

### Option 3: Generate Custom Self-Signed Cert

```bash
mkdir -p ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/privkey.pem \
  -out ssl/fullchain.pem \
  -subj "/CN=*.company.com" \
  -addext "subjectAltName=DNS:firewall.company.com,DNS:npm.company.com,DNS:pypi.company.com"
```

## Common Configuration Options

### Outbound Proxy

Route all upstream traffic through a corporate proxy:

```yaml
socket:
  outbound_proxy: http://proxy.company.com:3128
  no_proxy: localhost,127.0.0.1,internal.company.com
```

### SSL Verification (Corporate MITM Proxy)

```yaml
socket:
  outbound_proxy: http://proxy.company.com:3128
  
  # Verify SSL with corporate CA
  api_ssl_verify: true
  api_ssl_ca_cert: /path/to/corporate-ca.crt
  
  # Apply same CA to upstream registries
  # (or set upstream_ssl_verify separately if different)
```

### Redis Caching (Multi-Instance)

For distributed deployments:

```yaml
redis:
  enabled: true
  host: redis.company.com
  port: 6379
  password: your-redis-password
  ttl: 86400  # 24 hours
```

### Performance Tuning

```yaml
# Match worker_processes to CPU cores
worker_processes: 4
worker_connections: 8192

proxy:
  connect_timeout: 60
  send_timeout: 60
  read_timeout: 60
```

### Fail-Safe Behavior

```yaml
socket:
  fail_open: true  # Allow packages if Socket API is down (default)
  # fail_open: false  # Block all packages if Socket API is down
```

## Environment Variables

Override configuration via environment variables:

```bash
# Core settings
SOCKET_SECURITY_API_TOKEN=your-api-key     # Required
SOCKET_API_URL=https://api.socket.dev      # Default
SOCKET_CACHE_TTL=600                       # Seconds, default: 600
SOCKET_FAIL_OPEN=true                      # Allow on API error

# Ports
HTTP_PORT=8080                             # Default: 8080
HTTPS_PORT=8443                            # Default: 8443

# Redis (optional)
REDIS_ENABLED=true
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=secret

# Proxy (optional)
SOCKET_OUTBOUND_PROXY=http://proxy:3128
SOCKET_NO_PROXY=localhost,127.0.0.1
```

## Health Checks

```bash
# Health endpoint (no auth required)
curl https://localhost:8443/health

# Expected response:
# {"status":"healthy","version":"1.1.23"}
```

## Monitoring & Logging

### View Logs

```bash
# All logs
docker compose logs -f socket-firewall

# Errors only
docker compose logs socket-firewall | grep -i error

# Security events
docker compose logs socket-firewall | grep -i block
```

### Splunk Integration

Forward security events to Splunk:

```yaml
splunk:
  enabled: true
  hec_url: https://splunk.company.com:8088/services/collector/event
  hec_token: your-splunk-hec-token
  index: security
  source: socket-firewall
```

See [docs/SPLUNK.md](docs/SPLUNK.md) for details.

## Troubleshooting

### Docker Container Won't Start

```bash
# Check logs
docker compose logs socket-firewall

# Verify environment variables
docker compose exec socket-firewall env | grep SOCKET

# Test config generation
docker compose exec socket-firewall socket-proxy-config-tool generate --config /app/socket.yml
```

### Package Installation Fails

```bash
# Check if package is blocked
docker compose logs socket-firewall | grep -i block

# Verify firewall is reachable
curl -I https://localhost:8443/health

# Test upstream connectivity from container
docker compose exec socket-firewall curl -I https://registry.npmjs.org
```

### SSL Certificate Errors

```bash
# For testing, bypass SSL verification:

# npm
npm config set strict-ssl false

# pip
PIP_TRUSTED_HOST='localhost' pip install package

# Maven (add flags)
mvn install -Dmaven.wagon.http.ssl.insecure=true -Dmaven.wagon.http.ssl.allowall=true

# For production, trust the CA certificate (see SSL/TLS section above)
```

### Firewall Not Blocking Malicious Packages

```bash
# Verify API token is set
docker compose exec socket-firewall env | grep SOCKET_SECURITY_API_TOKEN

# Check API connectivity (from container)
docker compose exec socket-firewall curl https://api.socket.dev/v0/health

# Review fail_open setting
cat socket.yml | grep fail_open
```

## Advanced Features

### Metadata Filtering

Remove blocked/warned packages from registry metadata responses:

```yaml
metadata_filtering:
  enabled: true
  filter_blocked: true   # Remove blocked packages
  filter_warn: false     # Keep warned packages (show warnings only)
```

### Bulk PURL Lookup

Pre-cache security status for faster lookups:

```yaml
bulk_purl_lookup:
  enabled: true
  batch_size: 5000  # PURLs per batch
```

### External Routes File

For 50+ routes, use external file:

```yaml
path_routing:
  enabled: true
  domain: firewall.company.com
  routes_file: /config/routes.yml
```

See [docs/EXTERNAL-ROUTES.md](docs/EXTERNAL-ROUTES.md) for format.

## Architecture

```
Client (npm/pip/mvn)
    ↓
Socket Firewall (this)
    ↓
Socket.dev API (security check)
    ↓
Upstream Registry (npmjs.org, pypi.org, etc.)
```

**Request Flow:**
1. Client requests package from firewall
2. Firewall extracts package name/version
3. Firewall checks Socket API for security issues
4. If safe: proxy to upstream and return package
5. If malicious: return 403 Forbidden with reason

## Documentation

- **Getting Started**: This file
- **Auto-Discovery**: [docs/AUTO-DISCOVERY.md](docs/AUTO-DISCOVERY.md)
- **External Routes**: [docs/EXTERNAL-ROUTES.md](docs/EXTERNAL-ROUTES.md)
- **Redis Caching**: [docs/REDIS.md](docs/REDIS.md)
- **Splunk Integration**: [docs/SPLUNK.md](docs/SPLUNK.md)
- **Artifactory Auth**: [docs/ARTIFACTORY-AUTH.md](docs/ARTIFACTORY-AUTH.md)

## Examples

### Example 1: Protect Public Registries

```yaml
# Minimal config - no custom domains needed
# Just start with docker compose up -d
# Access at https://localhost:8443/npm/, /pypi/, /maven/, etc.
```

### Example 2: Custom Domains for Each Registry

```yaml
registries:
  npm:
    domains: [npm.company.com]
  pypi:
    domains: [pypi.company.com]
  maven:
    domains: [maven.company.com]
  cargo:
    domains: [cargo.company.com]
  rubygems:
    domains: [rubygems.company.com]
  openvsx:
    domains: [vsx.company.com]
  nuget:
    domains: [nuget.company.com]
  go:
    domains: [go.company.com]
```

### Example 3: Single Domain for All Registries

```yaml
path_routing:
  enabled: true
  domain: packages.company.com
  
  routes:
    - { path: /npm, upstream: https://registry.npmjs.org, registry: npm }
    - { path: /pypi, upstream: https://pypi.org, registry: pypi }
    - { path: /maven, upstream: https://repo1.maven.org/maven2, registry: maven }
    - { path: /cargo, upstream: https://index.crates.io, registry: cargo }
    - { path: /rubygems, upstream: https://rubygems.org, registry: rubygems }
    - { path: /openvsx, upstream: https://open-vsx.org, registry: openvsx }
    - { path: /nuget, upstream: https://api.nuget.org, registry: nuget }
    - { path: /go, upstream: https://proxy.golang.org, registry: go }
```

### Example 4: Private Artifactory/Nexus

```yaml
path_routing:
  enabled: true
  domain: firewall.company.com
  mode: artifactory  # or 'nexus'
  
  private_registry:
    api_url: https://artifactory.company.com/artifactory
    api_key: your-artifactory-api-key
    interval: 5m
    default_registry: maven  # Fallback for unknown repos
```

## Support

- **GitHub Issues**: https://github.com/SocketDev/socket-nginx-firewall/issues
- **Email**: support@socket.dev
- **Documentation**: https://docs.socket.dev
- **Socket Dashboard**: https://socket.dev/dashboard

## License

Proprietary - Socket Security Inc.

---

**Need help?** Check [docs/](docs/) for detailed guides or contact support@socket.dev
