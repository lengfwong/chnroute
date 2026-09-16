#!/usr/bin/env bash

# Set Bash strict （Corresponds to SHELLFLAGS := -eu -o pipefail -c）
set -euo pipefail

export LC_ALL=POSIX

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCRIPT="${SCRIPT_DIR}/generate.sh"
GFW_SCRIPT="${SCRIPT_DIR}/gfwlist2dnsmasq.sh"
VERSION=$(awk -F'"' '/^readonly SCRIPT_VERSION/ {print $2}' "${LIB_DIR}/config.sh" 2>/dev/null | head -n1 || echo unknown)
# shellcheck source=lib/config.sh
. "${LIB_DIR}/config.sh"
# shellcheck source=lib/logger.sh
. "${LIB_DIR}/logger.sh"

# List of output files
#OUTPUT_FILES=("CN.rsc" "CN_mem.rsc" "gfwlist_v7.rsc" "gfwlist.txt" "03-gfwlist.conf")
OUTPUT_FILES=("${SCRIPT_DIR}/gfwlist_v7.rsc" "${SCRIPT_DIR}/gfwlist.txt")
# Check dependencies (check-deps)
check_deps() {
    log_info "Checking dependencies..."
    
    local missing=0
    local required_cmds=("bash" "curl" "awk" "sort" "base64" "grep" "sed" "tar")

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Command \"$cmd\" is required but not found"
            missing=$((missing + 1))
        fi
    done

    if [ ! -x /usr/bin/time ]; then
        log_warn "/usr/bin/time not available -- detailed timing output reduced"
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        log_warn "python3 not found -- benchmarks will skip average calculation"
    fi

    if ! command -v shellcheck >/dev/null 2>&1; then
        log_warn "shellcheck not available -- static analysis skipped"
    fi

    if [ "$missing" -gt 0 ]; then
        log_error "$missing required commands are missing"
        exit 1
    fi

    log_success "All mandatory dependencies are available"
}

# Validate script syntax (validate-syntax)
validate_syntax() {
    log_info "Validating script syntax..."

    bash -n "$SCRIPT" >/dev/null
    bash -n "$GFW_SCRIPT" >/dev/null

    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "${SCRIPT_DIR}"/*.sh || log_warn "ShellCheck reported issues"
    else
        log_warn "shellcheck not installed -- skipping lint"
    fi

    log_success "Syntax validation completed"
}

# Comprehensive inspection (check)
check() {
    log_info "Chnroute version ${VERSION}"
    check_deps
    validate_syntax
}

# Generate routing rule file (generate)
generate() {
    check
    log_info "get openwrt list rule"
    getop_rule
    log_info "Generating China route artifacts..."

    if bash "$SCRIPT"; then
        log_success "Generation completed"
    else
        log_error "Generation failed"
        exit 1
    fi
}

# Validate the generated file structure (validate-output)
validate_output() {
    log_info "Validating output files..."
    
    local missing=0
    local size
    local lines

    for file in "${OUTPUT_FILES[@]}"; do
        if [ -f "$file" ]; then
            size=$(wc -c < "$file")
            lines=$(wc -l < "$file")
            printf '  %s: %s lines, %s bytes\n' "$file" "$lines" "$size"
            
            if [ "$size" -eq 0 ]; then
                log_warn "$file is empty"
                missing=$((missing + 1))
            fi
        else
            log_error "$file not found"
            missing=$((missing + 1))
        fi
    done

    if [ "$missing" -gt 0 ]; then
        log_error "Output validation failed"
        exit 1
    fi

    log_success "All output files look good"
}


getop_rule() {

local include_path="${SCRIPT_DIR}/${INCLUDE_LIST_TXT}"
local exclude_path="${SCRIPT_DIR}/${EXCLUDE_LIST_TXT}"
local gfwpluslist="${SCRIPT_DIR}/openwrt/gfwplus_list.txt"
local greylist="${SCRIPT_DIR}/openwrt/greylist.txt"
local excludelist="${SCRIPT_DIR}/openwrt/excludegfw.txt"


rsync -avP --include={gfwplus_list.txt,greylist.txt,excludegfw.txt} --exclude="/*" root@opx86:/etc/mosdns/rule/ "${SCRIPT_DIR}/openwrt/"
cp "${gfwpluslist}" "${include_path}"
cp "${excludelist}" "${exclude_path}"
cat "${greylist}" >> "${include_path}"

}

transros() {

local fileold="${SCRIPT_DIR}/gfwlist_v7old.rsc"
local filenew="${SCRIPT_DIR}/gfwlist_v7.rsc"
local diff="${SCRIPT_DIR}/diff.txt"

    if [[ ! -f "$fileold" ]]; then
         log_warn "$(basename "$fileold") not found, creating empty file" || true
         : >"$fileold"
     fi

diff "$fileold" "$filenew" > "$diff" || true
# [ -s $diff ] testify diff.txt empty or not
if [ -s "$diff" ] ; then
        scp -P 6223 "$filenew" wangyf@miros:/
        cp "$filenew" "$fileold"
        log_success "gfwlist transfer to Ros"
   else
        log_info "gfwlist has not changed"
fi
}

show_help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Available commands:"
    echo "  (none)           Default: Run check, generate, and validate-output in sequence"
    echo "  check-deps       Check for required system dependencies"
    echo "  validate-syntax  Validate syntax of shell scripts using bash -n & shellcheck"
    echo "  check            Run both check-deps and validate-syntax"
    echo "  generate         Generate China route artifacts"
    echo "  validate-output  Validate presence and size of generated output files"
    echo "  transros         transfer gfwlist_v7.rsc to MIROS"
    echo "  help             Show this help message"
}

# ------------------------------------------------------------------------------
# Main Entry Point and Parameter Distribution (main)
# ------------------------------------------------------------------------------
main() {
    # If no arguments are passed, the default execution sequence is check -> generate -> validate_output -> transros.
    if [ $# -eq 0 ]; then
        log_info "No command specified, running default pipeline..."
        check_deps
        generate
        validate_output
        transros
        exit 0
    fi

    case "$1" in
        check-deps)
            check_deps
            ;;
        validate-syntax)
            validate_syntax
            ;;
        check)
            check
            ;;
        generate)
            generate
            ;;
        validate-output)
            validate_output
            ;;
        transros)
            transros
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
