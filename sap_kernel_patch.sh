#!/bin/bash
# Interactive SAP kernel patching script
# Run as root. Backs up current kernel, deploys pre-extracted files, sets permissions.

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }

# ============================================================
# Phase 1: Input & Validation
# ============================================================

# Must run as root
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root."
  exit 1
fi

# Prompt for SID
read -rp "Enter SAP System ID (SID): " SID
SID="${SID^^}" # uppercase

if [[ ! "$SID" =~ ^[A-Z0-9]{3}$ ]]; then
  error "Invalid SID '$SID'. Must be exactly 3 uppercase alphanumeric characters."
  exit 1
fi

SID_LOWER=$(echo "$SID" | tr '[:upper:]' '[:lower:]')
SID_ADM="${SID_LOWER}adm"
KERNEL_DIR="/sapmnt/${SID}/exe/uc/linuxx86_64"

info "SID: $SID | Admin user: $SID_ADM"
info "Kernel directory: $KERNEL_DIR"

# Validate <sid>adm user exists
if ! id "$SID_ADM" &>/dev/null; then
  error "User '$SID_ADM' does not exist on this system."
  exit 1
fi
ok "User '$SID_ADM' exists."

# Validate /sapmnt/<SID> exists
SAPMNT_DIR="/sapmnt/${SID}"
if [[ ! -d "$SAPMNT_DIR" ]]; then
  error "Directory '$SAPMNT_DIR' does not exist. Is the SID correct?"
  exit 1
fi
ok "Directory '$SAPMNT_DIR' exists."

# Prompt for source directory
read -rp "Enter path to extracted kernel files: " SOURCE_DIR

if [[ ! -d "$SOURCE_DIR" ]]; then
  error "Source directory '$SOURCE_DIR' does not exist."
  exit 1
fi

if [[ -z "$(ls -A "$SOURCE_DIR")" ]]; then
  error "Source directory '$SOURCE_DIR' is empty."
  exit 1
fi
ok "Source directory is valid and non-empty."

# Validate target kernel directory
if [[ ! -d "$KERNEL_DIR" ]]; then
  error "Target kernel directory '$KERNEL_DIR' does not exist."
  exit 1
fi

if [[ ! -f "$KERNEL_DIR/disp+work" ]]; then
  error "Target kernel directory does not contain 'disp+work'. Is this the correct path?"
  exit 1
fi
ok "Target kernel directory is valid."

# ============================================================
# Phase 2: Pre-patch Safety Checks
# ============================================================

while true; do
  info "Checking for running SAP processes ..."
  echo ""

  SAP_PROCS=$(ps aux | grep "$SID" | grep -v grep | grep -v "patch_kernel" || true)

  if [[ -n "$SAP_PROCS" ]]; then
    warn "The following SAP-related processes were found:"
    echo ""
    echo "$SAP_PROCS"
    echo ""
    warn "SAP may still be running. It is recommended to stop SAP before patching the kernel."
    echo ""
    read -rp "$(echo -e "${YELLOW}[I]${NC}gnore and proceed / ${CYAN}[r]${NC}echeck / ${RED}[a]${NC}bort? [I/r/a]: ")" CHOICE
    CHOICE="${CHOICE,,}"
    if [[ "$CHOICE" == "a" ]]; then
      info "Aborted by user."
      exit 0
    elif [[ "$CHOICE" == "r" ]]; then
      info "Rechecking ..."
      echo ""
      continue
    fi
    warn "Proceeding despite running SAP processes (user confirmed)."
  else
    ok "No SAP processes detected."
  fi
  break
done

# ============================================================
# Phase 2.5: Overview & Confirmation
# ============================================================

BACKUP_DIR="${KERNEL_DIR}_backup_${TIMESTAMP}"

echo ""
echo "============================================================"
echo "  SAP Kernel Patch — Operation Overview"
echo "============================================================"
echo ""
echo "  SID:                $SID"
echo "  Admin user:         $SID_ADM"
echo "  Source directory:    $SOURCE_DIR"
echo "  Target kernel dir:  $KERNEL_DIR"
echo "  Backup destination: $BACKUP_DIR"
echo ""
echo "  The following actions will be performed:"
echo "    1. Back up current kernel directory"
echo "    2. Copy new kernel files (overwrite existing)"
echo "    3. Set ownership to ${SID_ADM}:sapsys"
echo "    4. Run saproot.sh $SID to set permissions"
echo "    5. Verify new kernel version via disp+work"
echo ""
echo "============================================================"
echo ""

read -rp "Proceed with kernel patching? [y/N]: " CONFIRM
CONFIRM="${CONFIRM,,}"
if [[ "$CONFIRM" != "y" ]]; then
  info "Aborted by user."
  exit 0
fi

# ============================================================
# Phase 3: Backup
# ============================================================

info "Creating backup of current kernel directory ..."
cp -rp "$KERNEL_DIR" "$BACKUP_DIR"

if [[ ! -d "$BACKUP_DIR" ]]; then
  error "Backup failed — directory '$BACKUP_DIR' was not created."
  exit 1
fi
ok "Backup created: $BACKUP_DIR"

# ============================================================
# Phase 4: Deploy
# ============================================================

info "Copying new kernel files to $KERNEL_DIR ..."
\cp -rp "$SOURCE_DIR"/* "$KERNEL_DIR"/
ok "Kernel files copied successfully."

info "Setting ownership to ${SID_ADM}:sapsys ..."
chown -R "$SID_ADM":sapsys "$KERNEL_DIR"
ok "Ownership set."

info "Running saproot.sh $SID ..."
pushd "$KERNEL_DIR" > /dev/null
./saproot.sh "$SID"
popd > /dev/null
ok "saproot.sh completed."

# ============================================================
# Phase 5: Post-patch Verification
# ============================================================

info "Verifying new kernel version ..."
echo ""
su - "$SID_ADM" -c "disp+work" 2>&1 | grep -iE "^(kernel release|compiled on|compiled for|compilation mode|compile time|patch number)"
echo ""

# ============================================================
# Summary
# ============================================================

echo ""
echo "============================================================"
echo "  SAP Kernel Patch — Complete"
echo "============================================================"
echo ""
echo "  Backup location: $BACKUP_DIR"
echo ""
ok "Kernel patching finished successfully."
echo ""
read -rp "Do you want to restart the server now? [y/N]: " RESTART
RESTART="${RESTART,,}"
if [[ "$RESTART" == "y" ]]; then
  warn "Restarting server ..."
  shutdown -r now
else
  warn "Remember to restart the server to ensure all SAP services"
  warn "start correctly and kernel files are copied to all relevant locations."
fi
echo ""
