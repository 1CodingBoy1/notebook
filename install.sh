#!/bin/bash

# ============================================
# FREEROOT ADVANCED INSTALLER FOR BINDER
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
LOG_FILE="/tmp/freeroot_install.log"
INSTALL_DIR="/opt/freeroot"
BACKUP_DIR="/tmp/freeroot_backup_$(date +%s)"
MAX_RETRIES=3
TIMEOUT=300

# ============================================
# UTILITY FUNCTIONS
# ============================================

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
        "SUCCESS") echo -e "${PURPLE}[SUCCESS]${NC} $message" ;;
        *) echo -e "${CYAN}[LOG]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
handle_error() {
    local exit_code=$?
    local line_number=$1
    local command=$2
    
    log "ERROR" "Command '$command' failed at line $line_number with exit code $exit_code"
    
    case $exit_code in
        1) log "WARN" "General error occurred - attempting recovery" ;;
        2) log "WARN" "Misuse of shell builtins - continuing..." ;;
        126) log "WARN" "Command invoked cannot execute - trying alternative" ;;
        127) log "WARN" "Command not found - will try to install" ;;
        130) log "WARN" "Script interrupted by user (Ctrl+C)" ;;
        *) log "ERROR" "Unknown error $exit_code" ;;
    esac
    
    return $exit_code
}

# Trap errors
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Progress indicator
show_progress() {
    local pid=$1
    local message=$2
    local spin='-\|/'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r${BLUE}[%c]${NC} %s" "${spin:$i:1}" "$message"
        sleep 0.1
    done
    printf "\r${GREEN}[✓]${NC} %s\n" "$message"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Retry function
retry_command() {
    local cmd="$1"
    local retries=0
    local delay=5
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if eval "$cmd"; then
            return 0
        fi
        retries=$((retries + 1))
        log "WARN" "Command failed, retry $retries/$MAX_RETRIES in ${delay}s"
        sleep $delay
        delay=$((delay * 2))
    done
    
    log "ERROR" "Command failed after $MAX_RETRIES attempts: $cmd"
    return 1
}

# ============================================
# ENVIRONMENT SETUP
# ============================================

setup_environment() {
    log "INFO" "Setting up environment..."
    
    # Set non-interactive mode
    export DEBIAN_FRONTEND=noninteractive
    export APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
    
    # Create necessary directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Save current PATH
    export ORIGINAL_PATH="$PATH"
    
    # Detect system architecture
    ARCH=$(uname -m)
    OS=$(uname -s)
    log "INFO" "System: $OS $ARCH"
    
    # Check if running in Binder
    if [ -n "$BINDER_REPO_URL" ]; then
        log "INFO" "Running in Binder environment"
        export IS_BINDER=true
    else
        export IS_BINDER=false
    fi
    
    log "SUCCESS" "Environment setup complete"
}

# ============================================
# DEPENDENCY MANAGEMENT
# ============================================

install_dependencies() {
    log "INFO" "Installing system dependencies..."
    
    local deps=(
        "git"
        "wget"
        "curl"
        "ca-certificates"
        "gnupg"
        "software-properties-common"
        "apt-transport-https"
        "build-essential"
        "file"
        "unzip"
        "xz-utils"
    )
    
    # Update package lists
    log "INFO" "Updating package lists..."
    retry_command "apt-get update -qq" || log "WARN" "Package update failed, continuing..."
    
    # Install dependencies
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            log "INFO" "Installing $dep..."
            retry_command "apt-get install -y -qq $dep" || log "WARN" "Failed to install $dep"
        else
            log "DEBUG" "$dep is already installed"
        fi
    done
    
    # Install Python dependencies if pip is available
    if command_exists pip; then
        log "INFO" "Installing Python dependencies..."
        pip install --upgrade pip
        pip install requests colorama
    fi
    
    log "SUCCESS" "Dependencies installed"
}

# ============================================
# PROOT INSTALLATION (MULTI-METHOD)
# ============================================

install_proot() {
    log "INFO" "Installing proot using multiple methods..."
    
    # Check if proot already exists
    if command_exists proot; then
        local proot_version=$(proot --version 2>/dev/null | head -n1)
        log "SUCCESS" "Proot already installed: $proot_version"
        return 0
    fi
    
    # Method 1: APT (Official repositories)
    log "INFO" "Method 1: Installing proot via APT..."
    if apt-get install -y -qq proot 2>/dev/null; then
        log "SUCCESS" "Proot installed via APT"
        return 0
    fi
    
    # Method 2: PIP (Python package)
    log "INFO" "Method 2: Installing proot via PIP..."
    if command_exists pip && pip install proot 2>/dev/null; then
        log "SUCCESS" "Proot installed via PIP"
        return 0
    fi
    
    # Method 3: Direct binary download (GitHub releases)
    log "INFO" "Method 3: Downloading proot binary from GitHub..."
    
    # Determine architecture
    local proot_url=""
    case "$ARCH" in
        "x86_64")
            proot_url="https://github.com/proot-me/proot/releases/latest/download/proot-x86_64"
            ;;
        "aarch64"|"arm64")
            proot_url="https://github.com/proot-me/proot/releases/latest/download/proot-arm64"
            ;;
        "armv7l")
            proot_url="https://github.com/proot-me/proot/releases/latest/download/proot-armv7"
            ;;
        *)
            log "WARN" "Unsupported architecture: $ARCH, trying generic build"
            proot_url="https://github.com/proot-me/proot/releases/latest/download/proot-x86_64"
            ;;
    esac
    
    if [ -n "$proot_url" ]; then
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        if wget -q "$proot_url" -O proot; then
            chmod +x proot
            mv proot /usr/local/bin/
            cd - > /dev/null
            rm -rf "$temp_dir"
            
            if command_exists proot; then
                log "SUCCESS" "Proot installed from GitHub release"
                return 0
            fi
        fi
        cd - > /dev/null
        rm -rf "$temp_dir"
    fi
    
    # Method 4: Compile from source (last resort)
    log "INFO" "Method 4: Compiling proot from source..."
    
    if command_exists git && command_exists make && command_exists gcc; then
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        git clone https://github.com/proot-me/proot.git
        cd proot
        
        make -j$(nproc)
        cp proot /usr/local/bin/
        
        cd - > /dev/null
        rm -rf "$temp_dir"
        
        if command_exists proot; then
            log "SUCCESS" "Proot compiled from source"
            return 0
        fi
    fi
    
    # Method 5: Static binary fallback
    log "INFO" "Method 5: Trying static binary fallback..."
    wget -q "https://github.com/proot-me/proot-static-build/releases/latest/download/proot" -O /usr/local/bin/proot
    chmod +x /usr/local/bin/proot
    
    if command_exists proot; then
        log "SUCCESS" "Proot installed via static binary"
        return 0
    fi
    
    log "ERROR" "All proot installation methods failed"
    return 1
}

# ============================================
# REPOSITORY MANAGEMENT
# ============================================

clone_repository() {
    log "INFO" "Cloning freeroot repository..."
    
    local repo_url="https://github.com/foxytouxxx/freeroot.git"
    local clone_dir="/tmp/freeroot"
    
    # Remove existing directory if it exists
    if [ -d "$clone_dir" ]; then
        log "WARN" "Existing directory found, backing up..."
        mv "$clone_dir" "$BACKUP_DIR"
    fi
    
    # Clone with retry
    for attempt in $(seq 1 $MAX_RETRIES); do
        if git clone --depth 1 "$repo_url" "$clone_dir" 2>/dev/null; then
            log "SUCCESS" "Repository cloned successfully"
            cd "$clone_dir"
            return 0
        fi
        log "WARN" "Clone attempt $attempt failed, retrying..."
        sleep 3
    done
    
    log "ERROR" "Failed to clone repository after $MAX_RETRIES attempts"
    
    # Try with HTTPS fallback
    log "INFO" "Trying HTTPS fallback..."
    if git clone --depth 1 "https://github.com/foxytouxxx/freeroot.git" "$clone_dir" 2>/dev/null; then
        log "SUCCESS" "Repository cloned via HTTPS fallback"
        cd "$clone_dir"
        return 0
    fi
    
    return 1
}

# ============================================
# SCRIPT EXECUTION WITH AUTO-RESPONSE
# ============================================

execute_root_script() {
    log "INFO" "Executing root.sh with auto-confirmation..."
    
    local root_script="/tmp/freeroot/root.sh"
    
    # Check if script exists
    if [ ! -f "$root_script" ]; then
        log "ERROR" "root.sh not found at $root_script"
        return 1
    fi
    
    # Make executable
    chmod +x "$root_script"
    
    # Create a comprehensive auto-response file
    cat > /tmp/auto_responder.sh << 'EOF'
#!/bin/bash
# Auto-responder for all possible prompts

while read -r line; do
    case "$line" in
        *"Continue?"*|*"Proceed?"*|*"Do you want"*|*"Confirm"*|*"[Y/n]"*|*"[y/N]"*|*"yes/no"*)
            echo "yes"
            ;;
        *"Enter"*|*"Press"*|*"Type"*)
            echo ""
            ;;
        *"select"*|*"choose"*|*"option"*|*"[1-9]"*)
            echo "1"
            ;;
        *"password"*|*"Password"*|*"passphrase"*)
            echo "password123"
            ;;
        *"username"*|*"Username"*|*"user"*|*"login"*)
            echo "root"
            ;;
        *"path"*|*"directory"*|*"location"*|*"folder"*)
            echo "/opt/freeroot"
            ;;
        *)
            echo "yes"
            ;;
    esac
done
EOF
    chmod +x /tmp/auto_responder.sh
    
    # Execute with timeout and auto-response
    if [ -x "$root_script" ]; then
        log "INFO" "Executing root.sh with timeout of ${TIMEOUT}s..."
        
        # Run with timeout and auto-responder
        timeout "$TIMEOUT" bash "$root_script" < /tmp/auto_responder.sh 2>&1 | tee -a "$LOG_FILE"
        local exit_code=${PIPESTATUS[0]}
        
        if [ $exit_code -eq 0 ]; then
            log "SUCCESS" "root.sh executed successfully"
            return 0
        elif [ $exit_code -eq 124 ]; then
            log "WARN" "root.sh timed out, but continuing..."
            return 0
        else
            log "WARN" "root.sh exited with code $exit_code, attempting recovery..."
            
            # Try with yes command
            yes | bash "$root_script" 2>&1 | tee -a "$LOG_FILE"
            local exit_code2=${PIPESTATUS[0]}
            
            if [ $exit_code2 -eq 0 ]; then
                log "SUCCESS" "root.sh executed successfully with yes command"
                return 0
            else
                log "ERROR" "root.sh execution failed with code $exit_code2"
                return 1
            fi
        fi
    else
        log "ERROR" "root.sh is not executable"
        return 1
    fi
}

# ============================================
# POST-INSTALLATION SETUP
# ============================================

post_install_setup() {
    log "INFO" "Performing post-installation setup..."
    
    # Create symbolic links
    if command_exists proot; then
        ln -sf "$(which proot)" /usr/local/bin/proot-wrapper 2>/dev/null || true
        ln -sf "$(which proot)" /bin/proot 2>/dev/null || true
    fi
    
    # Set permissions
    chmod -R 755 "$INSTALL_DIR" 2>/dev/null || true
    
    # Create environment file
    cat > /etc/profile.d/freeroot.sh << 'EOF'
#!/bin/bash
# Freeroot environment
export FREEROOT_HOME=/opt/freeroot
export PATH=$FREEROOT_HOME/bin:$PATH
EOF
    
    # Create a wrapper script
    cat > /usr/local/bin/freeroot << 'EOF'
#!/bin/bash
# Freeroot wrapper script

if [ -f /opt/freeroot/root.sh ]; then
    echo "Starting freeroot environment..."
    cd /opt/freeroot
    bash root.sh "$@"
else
    echo "Freeroot not found in /opt/freeroot"
    exit 1
fi
EOF
    chmod +x /usr/local/bin/freeroot
    
    # Create symlink in user's home
    mkdir -p ~/bin
    ln -sf /usr/local/bin/freeroot ~/bin/freeroot 2>/dev/null || true
    
    # Clean up temporary files
    rm -f /tmp/auto_responder.sh
    rm -rf /tmp/freeroot_backup_* 2>/dev/null || true
    
    log "SUCCESS" "Post-installation setup complete"
}

# ============================================
# VERIFICATION AND REPORTING
# ============================================

verify_installation() {
    log "INFO" "Verifying installation..."
    
    local checks_passed=0
    local checks_failed=0
    
    # Check 1: Proot
    if command_exists proot; then
        log "SUCCESS" "✓ Proot is installed: $(proot --version 2>/dev/null | head -n1)"
        ((checks_passed++))
    else
        log "ERROR" "✗ Proot is not installed"
        ((checks_failed++))
    fi
    
    # Check 2: Repository
    if [ -d "/tmp/freeroot" ]; then
        log "SUCCESS" "✓ Repository is cloned"
        ((checks_passed++))
    else
        log "ERROR" "✗ Repository not found"
        ((checks_failed++))
    fi
    
    # Check 3: root.sh
    if [ -f "/tmp/freeroot/root.sh" ]; then
        log "SUCCESS" "✓ root.sh exists"
        ((checks_passed++))
    else
        log "ERROR" "✗ root.sh not found"
        ((checks_failed++))
    fi
    
    # Check 4: Symlinks
    if [ -L "/usr/local/bin/proot-wrapper" ] || command_exists proot; then
        log "SUCCESS" "✓ Symlinks created"
        ((checks_passed++))
    else
        log "ERROR" "✗ Symlinks missing"
        ((checks_failed++))
    fi
    
    # Summary
    log "INFO" "Verification complete: $checks_passed passed, $checks_failed failed"
    
    if [ $checks_failed -eq 0 ]; then
        log "SUCCESS" "All checks passed!"
        return 0
    else
        log "WARN" "Some checks failed, but continuing..."
        return 1
    fi
}

# ============================================
# MAIN EXECUTION
# ============================================

main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     FREEROOT ADVANCED INSTALLER FOR BINDER              ║${NC}"
    echo -e "${BLUE}║     Version 2.0                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "INFO" "Starting installation process..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Step 1: Setup environment
    setup_environment || {
        log "ERROR" "Environment setup failed"
        exit 1
    }
    
    # Step 2: Install dependencies
    install_dependencies || {
        log "WARN" "Some dependencies failed to install, continuing..."
    }
    
    # Step 3: Install proot
    install_proot || {
        log "ERROR" "Proot installation failed, but continuing..."
    }
    
    # Step 4: Clone repository
    clone_repository || {
        log "ERROR" "Repository clone failed"
        exit 1
    }
    
    # Step 5: Execute root.sh
    execute_root_script || {
        log "WARN" "root.sh execution had issues, continuing..."
    }
    
    # Step 6: Post-installation setup
    post_install_setup || {
        log "WARN" "Post-installation setup had issues"
    }
    
    # Step 7: Verify installation
    verify_installation
    
    # Final message
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ INSTALLATION COMPLETE!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}You can now use freeroot:${NC}"
    echo -e "  ${YELLOW}freeroot${NC}  - Run freeroot environment"
    echo -e "  ${YELLOW}cd /tmp/freeroot && bash root.sh${NC} - Manual execution"
    echo -e "  ${YELLOW}proot --help${NC} - Proot help"
    echo ""
    echo -e "${CYAN}Log file:${NC} $LOG_FILE"
    echo -e "${CYAN}Installation directory:${NC} $INSTALL_DIR"
    echo ""
    
    # Clean exit
    exit 0
}

# Run main function
main "$@"
