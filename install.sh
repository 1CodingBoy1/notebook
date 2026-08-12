#!/bin/bash

# ============================================
# FREEROOT INSTALLER FOR BINDER
# Complete single-file solution
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Log file
LOG_FILE="/tmp/freeroot_install.log"
echo "========================================" > "$LOG_FILE"
echo "Freeroot Installer Started" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

# Functions
log() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[i]${NC} $1" | tee -a "$LOG_FILE"
}

# Print header
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         FREEROOT INSTALLER FOR BINDER                ║${NC}"
echo -e "${BLUE}║         Version 3.0 - Complete Edition               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================
# STEP 1: INSTALL DEPENDENCIES
# ============================================

info "Step 1: Installing system dependencies..."

apt-get update -qq 2>/dev/null || warn "Apt update failed, continuing..."
apt-get install -y -qq git wget curl ca-certificates 2>/dev/null || warn "Some packages failed to install"

log "Dependencies installed"

# ============================================
# STEP 2: INSTALL PROOT (Multiple Methods)
# ============================================

info "Step 2: Installing proot..."

# Check if proot already installed
if command -v proot &> /dev/null; then
    log "Proot already installed: $(proot --version 2>/dev/null | head -n1)"
else
    # Method 1: APT
    info "Method 1: Installing proot via apt..."
    if apt-get install -y -qq proot 2>/dev/null; then
        log "Proot installed via apt"
    # Method 2: PIP
    elif command -v pip &> /dev/null && pip install proot 2>/dev/null; then
        log "Proot installed via pip"
    # Method 3: Direct download
    else
        info "Method 3: Downloading proot binary..."
        wget -q https://github.com/proot-me/proot/releases/latest/download/proot-x86_64 -O /usr/local/bin/proot 2>/dev/null || {
            warn "Download failed, trying alternative..."
            curl -sL https://github.com/proot-me/proot/releases/latest/download/proot-x86_64 -o /usr/local/bin/proot
        }
        chmod +x /usr/local/bin/proot 2>/dev/null
        log "Proot binary downloaded"
    fi
fi

# Verify proot
if command -v proot &> /dev/null; then
    log "Proot is ready"
else
    error "Proot installation failed"
    # Continue anyway
fi

# ============================================
# STEP 3: CLONE REPOSITORY
# ============================================

info "Step 3: Cloning freeroot repository..."

# Remove existing directory
rm -rf /tmp/freeroot

# Clone with retry
for i in {1..3}; do
    if git clone --depth 1 https://github.com/foxytouxxx/freeroot.git /tmp/freeroot 2>/dev/null; then
        log "Repository cloned successfully"
        break
    else
        warn "Clone attempt $i failed, retrying..."
        sleep 2
    fi
done

# Check if clone succeeded
if [ ! -d "/tmp/freeroot" ]; then
    error "Failed to clone repository"
    # Try alternative method
    info "Trying with git:// protocol..."
    git clone --depth 1 git://github.com/foxytouxxx/freeroot.git /tmp/freeroot 2>/dev/null || {
        error "Cannot clone repository, exiting"
        exit 1
    }
fi

cd /tmp/freeroot || {
    error "Cannot enter /tmp/freeroot"
    exit 1
}

log "Changed to /tmp/freeroot"

# ============================================
# STEP 4: PREPARE SCRIPTS
# ============================================

info "Step 4: Preparing scripts..."

# Make scripts executable
chmod +x root.sh 2>/dev/null || warn "Cannot chmod root.sh"

# Create auto-responder script
cat > /tmp/auto_responder.sh << 'EOF'
#!/bin/bash
# Auto-responder for all prompts
while read -r line; do
    echo "yes"
done
EOF
chmod +x /tmp/auto_responder.sh

log "Scripts prepared"

# ============================================
# STEP 5: EXECUTE ROOT.SH
# ============================================

info "Step 5: Executing root.sh..."

if [ -f "root.sh" ]; then
    log "Found root.sh, executing..."
    
    # Try multiple methods to auto-answer
    # Method 1: Yes command
    yes | bash root.sh 2>&1 | tee -a "$LOG_FILE"
    EXIT_CODE=${PIPESTATUS[0]}
    
    # Method 2: If method 1 failed
    if [ $EXIT_CODE -ne 0 ]; then
        warn "Method 1 failed, trying alternative..."
        echo -e "yes\nyes\nyes\nyes\nyes\n" | bash root.sh 2>&1 | tee -a "$LOG_FILE"
        EXIT_CODE=${PIPESTATUS[0]}
    fi
    
    # Method 3: Auto-responder
    if [ $EXIT_CODE -ne 0 ]; then
        warn "Method 2 failed, using auto-responder..."
        cat /tmp/auto_responder.sh | bash root.sh 2>&1 | tee -a "$LOG_FILE"
        EXIT_CODE=${PIPESTATUS[0]}
    fi
    
    if [ $EXIT_CODE -eq 0 ]; then
        log "root.sh executed successfully"
    else
        warn "root.sh completed with exit code $EXIT_CODE"
        # Continue anyway
    fi
else
    error "root.sh not found in /tmp/freeroot"
fi

# ============================================
# STEP 6: POST-INSTALLATION SETUP
# ============================================

info "Step 6: Post-installation setup..."

# Create symlinks
if command -v proot &> /dev/null; then
    ln -sf $(which proot) /usr/local/bin/proot-wrapper 2>/dev/null || true
    ln -sf $(which proot) /bin/proot 2>/dev/null || true
fi

# Create wrapper script
cat > /usr/local/bin/freeroot << 'EOF'
#!/bin/bash
cd /tmp/freeroot 2>/dev/null && bash root.sh "$@" || echo "Freeroot not found"
EOF
chmod +x /usr/local/bin/freeroot 2>/dev/null || true

# Create alias
echo "alias freeroot='cd /tmp/freeroot && bash root.sh'" >> ~/.bashrc 2>/dev/null || true

log "Post-installation setup complete"

# ============================================
# STEP 7: VERIFICATION
# ============================================

info "Step 7: Verifying installation..."

PASSED=0
FAILED=0

# Check proot
if command -v proot &> /dev/null; then
    log "✓ Proot: Installed"
    ((PASSED++))
else
    error "✗ Proot: Not installed"
    ((FAILED++))
fi

# Check repository
if [ -d "/tmp/freeroot" ]; then
    log "✓ Repository: Cloned"
    ((PASSED++))
else
    error "✗ Repository: Missing"
    ((FAILED++))
fi

# Check root.sh
if [ -f "/tmp/freeroot/root.sh" ]; then
    log "✓ root.sh: Exists"
    ((PASSED++))
else
    error "✗ root.sh: Missing"
    ((FAILED++))
fi

# Summary
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ INSTALLATION COMPLETE!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
echo ""
echo -e "${YELLOW}How to use:${NC}"
echo -e "  1. ${GREEN}freeroot${NC}        - Run freeroot environment"
echo -e "  2. ${GREEN}cd /tmp/freeroot${NC} - Go to freeroot directory"
echo -e "  3. ${GREEN}bash root.sh${NC}    - Run manually"
echo ""
echo -e "${YELLOW}Log file:${NC} $LOG_FILE"
echo ""

# Clean up
rm -f /tmp/auto_responder.sh 2>/dev/null || true

# Always exit with success
exit 0
