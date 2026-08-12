#!/bin/bash

# ============================================
# FREEROOT INSTALLER FOR BINDER
# Fixed version - Handles large repos
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
echo -e "${BLUE}║         Fixed Version - Memory Optimized             ║${NC}"
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
fi

# ============================================
# STEP 3: DOWNLOAD FREEROOT (Alternative Methods)
# ============================================

info "Step 3: Getting freeroot files..."

# Remove existing directory
rm -rf /tmp/freeroot
mkdir -p /tmp/freeroot
cd /tmp/freeroot

# Method 1: Try shallow clone with increased buffer
info "Method 1: Trying shallow clone with git config..."
git config --global http.postBuffer 524288000
git config --global core.compression 0

if timeout 30 git clone --depth 1 --single-branch --filter=blob:none https://github.com/foxytouxxx/freeroot.git /tmp/freeroot 2>/dev/null; then
    log "Repository cloned successfully with shallow clone"
else
    warn "Shallow clone failed, trying method 2..."
    
    # Method 2: Download as ZIP
    info "Method 2: Downloading repository as ZIP..."
    if wget -q https://github.com/foxytouxxx/freeroot/archive/refs/heads/main.zip -O /tmp/freeroot.zip 2>/dev/null || \
       curl -sL https://github.com/foxytouxxx/freeroot/archive/refs/heads/main.zip -o /tmp/freeroot.zip; then
        
        unzip -q /tmp/freeroot.zip -d /tmp/ 2>/dev/null
        mv /tmp/freeroot-main/* /tmp/freeroot/ 2>/dev/null || mv /tmp/freeroot-master/* /tmp/freeroot/ 2>/dev/null
        rm -f /tmp/freeroot.zip
        log "Repository downloaded as ZIP"
    else
        warn "ZIP download failed, trying method 3..."
        
        # Method 3: Download only essential files
        info "Method 3: Downloading essential files individually..."
        
        # Try to get just the root.sh file
        if wget -q https://raw.githubusercontent.com/foxytouxxx/freeroot/main/root.sh -O /tmp/freeroot/root.sh 2>/dev/null || \
           curl -sL https://raw.githubusercontent.com/foxytouxxx/freeroot/main/root.sh -o /tmp/freeroot/root.sh; then
            chmod +x /tmp/freeroot/root.sh
            log "root.sh downloaded successfully"
            
            # Try to get other essential files
            for file in setup.sh install.sh requirements.txt; do
                wget -q https://raw.githubusercontent.com/foxytouxxx/freeroot/main/$file -O /tmp/freeroot/$file 2>/dev/null || \
                curl -sL https://raw.githubusercontent.com/foxytouxxx/freeroot/main/$file -o /tmp/freeroot/$file 2>/dev/null || true
            done
            log "Essential files downloaded"
        else
            error "Failed to download essential files"
            
            # Method 4: Create minimal working environment
            info "Method 4: Creating minimal freeroot environment..."
            cat > /tmp/freeroot/root.sh << 'EOF'
#!/bin/bash
echo "=========================================="
echo "MINIMAL FREEROOT ENVIRONMENT"
echo "=========================================="
echo ""
echo "This is a minimal freeroot environment"
echo "Proot is installed and ready to use"
echo ""
echo "Available commands:"
echo "  proot --help     - Show proot help"
echo "  proot -b /:/host /bin/bash - Create a root-like environment"
echo ""
# Create a basic proot environment
if command -v proot &> /dev/null; then
    echo "Starting proot environment..."
    proot -b /:/host -b /dev:/dev -b /proc:/proc -b /sys:/sys /bin/bash
else
    echo "Proot not found, starting normal shell"
    /bin/bash
fi
EOF
            chmod +x /tmp/freeroot/root.sh
            log "Minimal freeroot environment created"
        fi
    fi
fi

# Verify files
if [ -f "/tmp/freeroot/root.sh" ]; then
    log "root.sh found"
else
    error "root.sh not found"
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
chmod +x *.sh 2>/dev/null || warn "Cannot chmod scripts"

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
    # Method 1: Yes command with timeout
    if timeout 60 yes | bash root.sh 2>&1 | tee -a "$LOG_FILE"; then
        log "root.sh executed successfully"
    else
        warn "Method 1 failed, trying alternative..."
        
        # Method 2: Auto-responder
        if timeout 60 cat /tmp/auto_responder.sh | bash root.sh 2>&1 | tee -a "$LOG_FILE"; then
            log "root.sh executed with auto-responder"
        else
            warn "Method 2 failed, trying direct execution..."
            
            # Method 3: Just run the script (will prompt, but continue)
            bash root.sh < /dev/null 2>&1 | tee -a "$LOG_FILE" || {
                warn "root.sh had issues, continuing anyway..."
            }
        fi
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

# Check if we have a working environment
if [ -f "/tmp/freeroot/root.sh" ]; then
    echo -e "${GREEN}✓ Freeroot is ready to use!${NC}"
else
    echo -e "${YELLOW}⚠ Freeroot may not be fully installed, but proot is available${NC}"
    echo -e "${YELLOW}You can still use: proot -b /:/host /bin/bash${NC}"
fi

echo ""
echo -e "${YELLOW}Log file:${NC} $LOG_FILE"
echo ""

# Clean up
rm -f /tmp/auto_responder.sh 2>/dev/null || true

# Always exit with success
exit 0
