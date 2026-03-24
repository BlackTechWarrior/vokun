#!/usr/bin/env bash
# shellcheck disable=SC2034
# vokun - TOML parser (subset)
# Handles: [section] headers, key = "value", key = ["array"], comments
# Uses associative arrays (bash 4+)

# Parse a TOML file into the global TOML_DATA associative array
# Also populates TOML_SECTIONS (indexed array) and TOML_SECTION_KEYS (assoc array)
# Usage: vokun::toml::parse "/path/to/file.toml"
vokun::toml::parse() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        vokun::core::error "TOML file not found: $file"
        return 1
    fi

    # Clear previous data
    unset TOML_DATA TOML_SECTIONS TOML_SECTION_KEYS
    declare -gA TOML_DATA
    declare -ga TOML_SECTIONS=()
    declare -gA TOML_SECTION_KEYS

    local section=""
    local in_array=false
    local array_key=""
    local array_value=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip trailing carriage return
        line="${line%$'\r'}"

        # Strip inline comments (not inside quotes)
        # Simple approach: if line has # outside quotes, strip it
        if [[ "$in_array" == false ]]; then
            # Remove comments that aren't inside quotes
            local stripped
            stripped=$(vokun::toml::_strip_comment "$line")
            line="$stripped"
        fi

        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Handle multi-line arrays
        if [[ "$in_array" == true ]]; then
            # Check if this line closes the array
            if [[ "$line" == *"]"* ]]; then
                # Extract content before the closing bracket
                local before_bracket="${line%%]*}"
                before_bracket="${before_bracket#"${before_bracket%%[![:space:]]*}"}"
                if [[ -n "$before_bracket" ]]; then
                    # Parse comma-separated quoted strings
                    vokun::toml::_parse_array_items "$before_bracket" array_value
                fi
                # Store the accumulated array value
                TOML_DATA["${section}.${array_key}"]="$array_value"
                vokun::toml::_add_section_key "$section" "$array_key"
                in_array=false
                array_key=""
                array_value=""
                continue
            fi
            # Accumulate array items from this line
            vokun::toml::_parse_array_items "$line" array_value
            continue
        fi

        # Section header: [meta] or [packages.aur]
        if [[ "$line" =~ ^\[([a-zA-Z0-9._-]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            # Track sections in order
            local found=false
            for s in "${TOML_SECTIONS[@]}"; do
                [[ "$s" == "$section" ]] && found=true && break
            done
            [[ "$found" == false ]] && TOML_SECTIONS+=("$section")
            continue
        fi

        # Key-value with array: key = ["a", "b", "c"]
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*=[[:space:]]*\[(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local rest="${BASH_REMATCH[2]}"

            # Check if array closes on same line
            if [[ "$rest" == *"]"* ]]; then
                local content="${rest%%]*}"
                local val=""
                vokun::toml::_parse_array_items "$content" val
                TOML_DATA["${section}.${key}"]="$val"
                vokun::toml::_add_section_key "$section" "$key"
            else
                # Multi-line array
                in_array=true
                array_key="$key"
                array_value=""
                vokun::toml::_parse_array_items "$rest" array_value
            fi
            continue
        fi

        # Key-value with quoted string: key = "value"
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*=[[:space:]]*\"(.*)\"$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            TOML_DATA["${section}.${key}"]="$val"
            vokun::toml::_add_section_key "$section" "$key"
            continue
        fi

        # Key-value with unquoted value (booleans, numbers): key = true
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            # Strip trailing whitespace from value
            val="${val%"${val##*[![:space:]]}"}"
            TOML_DATA["${section}.${key}"]="$val"
            vokun::toml::_add_section_key "$section" "$key"
            continue
        fi

    done < "$file"
}

# Get a value by section.key
# Usage: vokun::toml::get "meta.name"
# Optional second arg is default value
vokun::toml::get() {
    local key="$1"
    local default="${2:-}"
    if [[ -v "TOML_DATA[$key]" ]]; then
        printf '%s' "${TOML_DATA[$key]}"
    else
        printf '%s' "$default"
    fi
}

# Get all keys in a section
# Usage: vokun::toml::keys "packages"
# Returns newline-separated list
vokun::toml::keys() {
    local section="$1"
    if [[ -v "TOML_SECTION_KEYS[$section]" ]]; then
        printf '%s' "${TOML_SECTION_KEYS[$section]}"
    fi
}

# Check if a key exists
vokun::toml::has() {
    local key="$1"
    [[ -v "TOML_DATA[$key]" ]]
}

# List all sections
vokun::toml::sections() {
    printf '%s\n' "${TOML_SECTIONS[@]}"
}

# Get array value as newline-separated items
# Usage: vokun::toml::get_array "meta.tags"
vokun::toml::get_array() {
    local key="$1"
    if [[ -v "TOML_DATA[$key]" ]]; then
        printf '%s' "${TOML_DATA[$key]}"
    fi
}

# --- Internal helpers ---

# Strip inline comment from a line (simple: first # not inside quotes)
vokun::toml::_strip_comment() {
    local line="$1"
    local in_quote=false
    local i char result=""

    for (( i=0; i<${#line}; i++ )); do
        char="${line:$i:1}"
        if [[ "$char" == '"' ]]; then
            if [[ "$in_quote" == true ]]; then
                in_quote=false
            else
                in_quote=true
            fi
        elif [[ "$char" == '#' && "$in_quote" == false ]]; then
            break
        fi
        result+="$char"
    done

    printf '%s' "$result"
}

# Add a key to the section's key list
vokun::toml::_add_section_key() {
    local section="$1"
    local key="$2"
    if [[ -v "TOML_SECTION_KEYS[$section]" ]]; then
        TOML_SECTION_KEYS["$section"]+=$'\n'"$key"
    else
        TOML_SECTION_KEYS["$section"]="$key"
    fi
}

# Parse comma-separated quoted strings from an array line, appending to named var
# Usage: vokun::toml::_parse_array_items "\"a\", \"b\"" varname
vokun::toml::_parse_array_items() {
    local input="$1"
    # shellcheck disable=SC2178
    local -n _result="$2"

    # Extract all quoted strings
    local regex='"([^"]*)"'
    local tmp="$input"
    while [[ "$tmp" =~ $regex ]]; do
        if [[ -n "$_result" ]]; then
            _result+=$'\n'"${BASH_REMATCH[1]}"
        else
            _result="${BASH_REMATCH[1]}"
        fi
        # Remove the matched portion and continue
        tmp="${tmp#*"${BASH_REMATCH[0]}"}"
    done
}
