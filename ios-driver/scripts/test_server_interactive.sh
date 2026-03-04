#!/bin/bash

# Interactive test script for iOS Runner server
# Usage: ./test_server_interactive.sh [port] [device]
#        ./test_server_interactive.sh [port]         # Interactive device selection
#        ./test_server_interactive.sh                # Port 8080 + interactive device selection

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Get port (default 8080)
PORT=${1:-8080}
DEVICE=""
DEVICE_ID=""
SERVER_PID=""
INSTALLED_APPS=""
TIMEOUT=60  # seconds to wait for server to start

# Cleanup function
cleanup() {
    if [ -n "$SERVER_PID" ]; then
        echo ""
        echo -e "${YELLOW}🧹 Cleaning up...${NC}"
        kill $SERVER_PID 2>/dev/null || true
        # Kill any remaining xcodebuild processes on this port
        lsof -ti:$PORT | xargs kill -9 2>/dev/null || true
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

# Function to extract installed apps from simulator
extract_installed_apps() {
    local device_id=$1
    echo -e "${CYAN}📦 Extracting installed applications...${NC}"
    
    # Get device data path from simctl
    local data_path=$(xcrun simctl get_app_container "$device_id" list 2>/dev/null | head -1 | xargs dirname | xargs dirname | xargs dirname)
    
    if [ -z "$data_path" ] || [ ! -d "$data_path" ]; then
        # Fallback: get from simctl list devices --json
        data_path=$(xcrun simctl list devices --json | \
            python3 -c "import sys, json; devices = json.load(sys.stdin)['devices']; \
            [print(device['dataPath']) for runtime in devices.values() for device in runtime if device.get('udid') == '$device_id']" | head -1)
    fi
    
    if [ -z "$data_path" ]; then
        echo -e "${YELLOW}⚠️  Could not determine data path, skipping app extraction${NC}"
        return
    fi
    
    local app_dir="$data_path/Containers/Bundle/Application"
    
    if [ ! -d "$app_dir" ]; then
        echo -e "${YELLOW}⚠️  No applications directory found${NC}"
        return
    fi
    
    # Extract bundle IDs from Info.plist files
    local bundle_ids=()
    for app_path in "$app_dir"/*/*.app; do
        if [ -d "$app_path" ]; then
            local info_plist="$app_path/Info.plist"
            if [ -f "$info_plist" ]; then
                local bundle_id=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$info_plist" 2>/dev/null || echo "")
                if [ -n "$bundle_id" ]; then
                    # Filter out test runner apps
                    if [[ ! "$bundle_id" =~ \.xctrunner$ ]]; then
                        bundle_ids+=("$bundle_id")
                    fi
                fi
            fi
        fi
    done
    
    if [ ${#bundle_ids[@]} -gt 0 ]; then
        # Join array with commas
        INSTALLED_APPS=$(IFS=,; echo "${bundle_ids[*]}")
        echo -e "${GREEN}✓${NC} Found ${#bundle_ids[@]} installed applications"
    else
        echo -e "${YELLOW}⚠️  No installed applications found${NC}"
    fi
}

# Function to list and select device
select_device() {
    echo ""
    echo -e "${BLUE}📱 Available iOS Simulators:${NC}"
    echo "=================================="
    echo ""
    
    # Get list of available simulators with UDIDs using JSON output
    local devices_json=$(xcrun simctl list devices --json)
    
    # Parse JSON to get device name and UDID
    local device_list=$(echo "$devices_json" | python3 -c "
import sys, json
devices = json.load(sys.stdin)['devices']
idx = 1
device_map = {}
for runtime, device_list in devices.items():
    for device in device_list:
        if device.get('isAvailable', False) and ('iPhone' in device['name'] or 'iPad' in device['name']):
            print(f\"{idx}) {device['name']}\")
            device_map[str(idx)] = {'name': device['name'], 'udid': device['udid']}
            idx += 1
" 2>/dev/null)
    
    if [ -z "$device_list" ]; then
        echo -e "${RED}❌ No available iOS simulators found${NC}"
        exit 1
    fi
    
    echo "$device_list"
    echo ""
    
    # Count devices
    local device_count=$(echo "$device_list" | wc -l | tr -d ' ')
    
    # Prompt for selection
    while true; do
        read -p "Select a device (1-$device_count): " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$device_count" ]; then
            DEVICE=$(echo "$device_list" | sed -n "${selection}p" | sed 's/^[0-9]*) //')
            
            # Get UDID for selected device
            DEVICE_ID=$(echo "$devices_json" | python3 -c "
import sys, json
devices = json.load(sys.stdin)['devices']
idx = 1
for runtime, device_list in devices.items():
    for device in device_list:
        if device.get('isAvailable', False) and ('iPhone' in device['name'] or 'iPad' in device['name']):
            if idx == $selection:
                print(device['udid'])
                sys.exit(0)
            idx += 1
" 2>/dev/null)
            
            echo ""
            echo -e "${GREEN}✅ Selected: $DEVICE${NC}"
            echo -e "${CYAN}   UDID: $DEVICE_ID${NC}"
            break
        else
            echo -e "${RED}Invalid selection. Please enter a number between 1 and $device_count${NC}"
        fi
    done
}

# Function to wait for server to be ready
wait_for_server() {
    echo ""
    echo -e "${CYAN}⏳ Waiting for server to start (timeout: ${TIMEOUT}s)...${NC}"
    
    local elapsed=0
    local interval=2
    
    while [ $elapsed -lt $TIMEOUT ]; do
        if curl -s http://localhost:$PORT/health > /dev/null 2>&1; then
            local wait_time=$((elapsed))
            echo ""
            echo -e "${GREEN}✅ Server is ready! (took ${wait_time}s)${NC}"
            return 0
        fi
        
        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    return 1
}

# Function to select app to launch
select_app_to_launch() {
    echo ""
    echo -e "${CYAN}📱 Fetching installed applications...${NC}"
    
    # Get app list from API
    local app_list_response=$(curl -s "http://localhost:$PORT/app/list")
    local apps=$(echo "$app_list_response" | jq -r '.applications[]' 2>/dev/null)
    
    # Build app array with Safari at the end
    local app_array=()
    local index=1
    
    if [ -n "$apps" ]; then
        while IFS= read -r app; do
            if [ -n "$app" ]; then
                app_array+=("$app")
            fi
        done <<< "$apps"
    fi
    
    # Always add Safari as last option
    app_array+=("com.apple.mobilesafari")
    
    # Display menu
    echo ""
    echo -e "${YELLOW}Select an app to launch:${NC}"
    echo ""
    
    for i in "${!app_array[@]}"; do
        local display_num=$((i + 1))
        local app="${app_array[$i]}"
        if [ "$app" = "com.apple.mobilesafari" ]; then
            echo -e "  ${GREEN}$display_num)${NC} $app ${CYAN}(Safari - Default)${NC}"
        else
            echo -e "  ${GREEN}$display_num)${NC} $app"
        fi
    done
    
    echo ""
    read -p "Select app (1-${#app_array[@]}): " app_choice
    
    # Validate choice
    if [[ "$app_choice" =~ ^[0-9]+$ ]] && [ "$app_choice" -ge 1 ] && [ "$app_choice" -le "${#app_array[@]}" ]; then
        local selected_index=$((app_choice - 1))
        local selected_app="${app_array[$selected_index]}"
        
        # Launch the selected app
        test_endpoint "POST" "/app/launch" "{\"bundleId\":\"$selected_app\"}" "Launch App: $selected_app"
    else
        echo -e "${RED}Invalid selection. Launching Safari by default.${NC}"
        test_endpoint "POST" "/app/launch" '{"bundleId":"com.apple.mobilesafari"}' "Launch Safari"
    fi
}

# Function to get UI tree with custom depth
get_ui_tree_with_depth() {
    echo ""
    echo -e "${CYAN}🌳 Get UI Tree${NC}"
    echo ""
    echo -e "${YELLOW}Enter max depth (default: 2, press Enter for default):${NC}"
    read -p "Max depth: " depth_input
    
    # Default to 2 if empty or invalid
    if [ -z "$depth_input" ]; then
        depth_input=2
        echo -e "${GREEN}Using default depth: 2${NC}"
    elif ! [[ "$depth_input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid input. Using default depth: 2${NC}"
        depth_input=2
    fi
    
    # Get UI tree with specified depth
    test_endpoint "GET" "/ui/tree?maxDepth=$depth_input" "" "Get UI Tree (depth $depth_input)"
}

# Function to find elements with custom criteria
find_elements_interactive() {
    echo ""
    echo -e "${CYAN}🔍 Find Elements${NC}"
    echo ""
    echo -e "Select search method:"
    echo -e "  ${GREEN}1)${NC} By Element ID (identifier)"
    echo -e "  ${GREEN}2)${NC} By Label (exact match)"
    echo -e "  ${GREEN}3)${NC} By Predicate (custom NSPredicate)"
    echo ""
    read -p "Select option (1-3): " search_method
    
    local json_body=""
    
    case $search_method in
        1)
            echo ""
            read -p "Enter element identifier: " element_id
            if [[ -z "$element_id" ]]; then
                echo -e "${RED}❌ Element ID cannot be empty${NC}"
                return
            fi
            json_body="{\"identifier\":\"$element_id\""
            ;;
        2)
            echo ""
            read -p "Enter label text (exact match): " label_text
            if [[ -z "$label_text" ]]; then
                echo -e "${RED}❌ Label cannot be empty${NC}"
                return
            fi
            json_body="{\"label\":\"$label_text\""
            ;;
        3)
            echo ""
            echo -e "${YELLOW}Example predicates:${NC}"
            echo -e "  - elementType == 46  (buttons)"
            echo -e "  - label CONTAINS 'Search'"
            echo -e "  - identifier == 'myButton'"
            echo ""
            read -p "Enter predicate: " predicate
            if [[ -z "$predicate" ]]; then
                echo -e "${RED}❌ Predicate cannot be empty${NC}"
                return
            fi
            # Escape double quotes in predicate
            predicate="${predicate//\"/\\\"}"
            json_body="{\"predicate\":\"$predicate\""
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return
            ;;
    esac
    
    # Ask for wait strategy
    echo ""
    echo -e "Select wait strategy:"
    echo -e "  ${GREEN}1)${NC} Wait (default - wait for element to exist)"
    echo -e "  ${GREEN}2)${NC} No wait (find immediately)"
    echo ""
    read -p "Select option (1-2, default: 1): " wait_strategy
    
    case $wait_strategy in
        2)
            json_body="${json_body},\"waitStrategy\":\"immediate\"}"
            ;;
        *)
            json_body="${json_body},\"waitStrategy\":\"wait\"}"
            ;;
    esac
    
    test_endpoint "POST" "/ui/find" "$json_body" "Find Elements"
}

# Function to tap on an element
tap_element_interactive() {
    echo ""
    echo -e "${CYAN}👆 Tap Element${NC}"
    echo ""
    echo -e "Select search method:"
    echo -e "  ${GREEN}1)${NC} By Element ID (identifier)"
    echo -e "  ${GREEN}2)${NC} By Label (exact match)"
    echo -e "  ${GREEN}3)${NC} By Predicate (custom NSPredicate)"
    echo ""
    read -p "Select option (1-3): " search_method
    
    local json_body=""
    
    case $search_method in
        1)
            echo ""
            read -p "Enter element identifier: " element_id
            if [[ -z "$element_id" ]]; then
                echo -e "${RED}❌ Element ID cannot be empty${NC}"
                return
            fi
            json_body="{\"identifier\":\"$element_id\""
            ;;
        2)
            echo ""
            read -p "Enter label text (exact match): " label_text
            if [[ -z "$label_text" ]]; then
                echo -e "${RED}❌ Label cannot be empty${NC}"
                return
            fi
            # Escape double quotes in label
            label_text="${label_text//\"/\\\"}"
            json_body="{\"label\":\"$label_text\""
            ;;
        3)
            echo ""
            echo -e "${YELLOW}Example predicates:${NC}"
            echo -e "  - label == 'Submit'"
            echo -e "  - identifier == 'loginButton'"
            echo -e "  - label CONTAINS 'Continue'"
            echo ""
            read -p "Enter predicate: " predicate
            if [[ -z "$predicate" ]]; then
                echo -e "${RED}❌ Predicate cannot be empty${NC}"
                return
            fi
            # Escape double quotes in predicate
            predicate="${predicate//\"/\\\"}"
            json_body="{\"predicate\":\"$predicate\""
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return
            ;;
    esac
    
    # Ask for wait strategy
    echo ""
    echo -e "Select wait strategy:"
    echo -e "  ${GREEN}1)${NC} Wait (default - wait for element to exist)"
    echo -e "  ${GREEN}2)${NC} No wait (tap immediately)"
    echo ""
    read -p "Select option (1-2, default: 1): " wait_strategy
    
    case $wait_strategy in
        2)
            json_body="${json_body},\"waitStrategy\":\"immediate\"}"
            ;;
        *)
            json_body="${json_body},\"waitStrategy\":\"wait\"}"
            ;;
    esac
    
    test_endpoint "POST" "/ui/tap" "$json_body" "Tap Element"
}

# Function to type text into an element
type_text_interactive() {
    echo ""
    echo -e "${CYAN}⌨️  Type Text${NC}"
    echo ""
    read -p "Enter text to type: " text_to_type
    
    if [[ -z "$text_to_type" ]]; then
        echo -e "${RED}❌ Text cannot be empty${NC}"
        return
    fi
    
    # Escape double quotes in text
    text_to_type="${text_to_type//\"/\\\"}"
    
    echo ""
    echo -e "Select search method for target element:"
    echo -e "  ${GREEN}1)${NC} By Element ID (identifier)"
    echo -e "  ${GREEN}2)${NC} By Label (exact match)"
    echo -e "  ${GREEN}3)${NC} By Predicate (custom NSPredicate)"
    echo ""
    read -p "Select option (1-3): " search_method
    
    local json_body="{\"text\":\"$text_to_type\""
    
    case $search_method in
        1)
            echo ""
            read -p "Enter element identifier: " element_id
            if [[ -z "$element_id" ]]; then
                echo -e "${RED}❌ Element ID cannot be empty${NC}"
                return
            fi
            json_body="${json_body},\"identifier\":\"$element_id\""
            ;;
        2)
            echo ""
            read -p "Enter label text (exact match): " label_text
            if [[ -z "$label_text" ]]; then
                echo -e "${RED}❌ Label cannot be empty${NC}"
                return
            fi
            # Escape double quotes in label
            label_text="${label_text//\"/\\\"}"
            json_body="${json_body},\"label\":\"$label_text\""
            ;;
        3)
            echo ""
            echo -e "${YELLOW}Example predicates for text fields:${NC}"
            echo -e "  - elementType == 49  (textField)"
            echo -e "  - label == 'Search'"
            echo -e "  - identifier == 'usernameField'"
            echo ""
            read -p "Enter predicate: " predicate
            if [[ -z "$predicate" ]]; then
                echo -e "${RED}❌ Predicate cannot be empty${NC}"
                return
            fi
            # Escape double quotes in predicate
            predicate="${predicate//\"/\\\"}"
            json_body="${json_body},\"predicate\":\"$predicate\""
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return
            ;;
    esac
    
    # Ask if should clear existing text first
    echo ""
    read -p "Clear existing text first? (y/N): " clear_first
    
    if [[ "$clear_first" =~ ^[Yy]$ ]]; then
        json_body="${json_body},\"clearFirst\":true"
    else
        json_body="${json_body},\"clearFirst\":false"
    fi
    
    # Ask for wait strategy
    echo ""
    echo -e "Select wait strategy:"
    echo -e "  ${GREEN}1)${NC} Wait (default - wait for element to exist)"
    echo -e "  ${GREEN}2)${NC} No wait (type immediately)"
    echo ""
    read -p "Select option (1-2, default: 1): " wait_strategy
    
    case $wait_strategy in
        2)
            json_body="${json_body},\"waitStrategy\":\"immediate\"}"
            ;;
        *)
            json_body="${json_body},\"waitStrategy\":\"wait\"}"
            ;;
    esac
    
    test_endpoint "POST" "/ui/type" "$json_body" "Type Text"
}

# Function to test endpoint
test_endpoint() {
    local method=$1
    local path=$2
    local data=$3
    local description=$4
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Testing: ${description}${NC}"
    echo -e "${YELLOW}${method} http://localhost:${PORT}${path}${NC}"
    
    if [ -n "$data" ]; then
        echo -e "${YELLOW}Body: ${data}${NC}"
    fi
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local response
    if [ "$method" = "POST" ]; then
        if [ -n "$data" ]; then
            response=$(curl -s -X POST "http://localhost:$PORT$path" \
                -H "Content-Type: application/json" \
                -d "$data")
        else
            response=$(curl -s -X POST "http://localhost:$PORT$path")
        fi
    else
        response=$(curl -s "http://localhost:$PORT$path")
    fi
    
    echo ""
    echo -e "${GREEN}Response:${NC}"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    echo ""
}

# Capture full screen screenshot
capture_full_screenshot() {
    echo ""
    echo -e "${CYAN}📸 Capture Full Screen Screenshot${NC}"
    echo ""
    
    # Generate filename with timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filename="screenshot_${timestamp}.png"
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Testing: Full Screen Screenshot"
    echo -e "GET http://localhost:$PORT/screenshot"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local response=$(curl -s -X GET "http://localhost:$PORT/screenshot")
    
    # Extract base64 image from response
    local base64_image=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'image' in data:
        print(data['image'])
    else:
        sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null)
    
    if [ -n "$base64_image" ]; then
        # Decode base64 and save to file
        echo "$base64_image" | base64 -d > "$filename"
        
        if [ -f "$filename" ]; then
            local file_size=$(ls -lh "$filename" | awk '{print $5}')
            echo -e "${GREEN}✅ Screenshot saved successfully!${NC}"
            echo -e "   File: ${YELLOW}$filename${NC}"
            echo -e "   Size: ${YELLOW}$file_size${NC}"
            echo ""
            
            # Extract dimensions from response
            local width=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('width', 'N/A'))" 2>/dev/null)
            local height=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('height', 'N/A'))" 2>/dev/null)
            echo -e "   Dimensions: ${YELLOW}${width}x${height}${NC}"
            
            # Try to open the image (macOS)
            if command -v open &> /dev/null; then
                read -p "Open screenshot? (y/n): " open_choice
                if [[ "$open_choice" == "y" || "$open_choice" == "Y" ]]; then
                    open "$filename"
                fi
            fi
        else
            echo -e "${RED}❌ Failed to save screenshot${NC}"
        fi
    else
        echo -e "${RED}❌ Failed to capture screenshot${NC}"
        echo ""
        echo "Response:"
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    fi
    
    echo ""
}

# Capture element screenshot
capture_element_screenshot() {
    echo ""
    echo -e "${CYAN}📸 Capture Element Screenshot${NC}"
    echo ""
    echo -e "Select search method:"
    echo -e "  ${GREEN}1)${NC} By Element ID (identifier)"
    echo -e "  ${GREEN}2)${NC} By Label (exact match)"
    echo -e "  ${GREEN}3)${NC} By Predicate (custom NSPredicate)"
    echo ""
    read -p "Select option (1-3): " search_method
    
    local json_body=""
    
    case $search_method in
        1)
            echo ""
            read -p "Enter element identifier: " element_id
            if [[ -z "$element_id" ]]; then
                echo -e "${RED}❌ Element ID cannot be empty${NC}"
                return
            fi
            json_body="{\"identifier\":\"$element_id\"}"
            ;;
        2)
            echo ""
            read -p "Enter label text (exact match): " label_text
            if [[ -z "$label_text" ]]; then
                echo -e "${RED}❌ Label cannot be empty${NC}"
                return
            fi
            # Escape double quotes in label
            label_text="${label_text//\"/\\\"}"
            json_body="{\"label\":\"$label_text\"}"
            ;;
        3)
            echo ""
            echo -e "${YELLOW}Example predicates:${NC}"
            echo -e "  - elementType == 46  (buttons)"
            echo -e "  - label CONTAINS 'Search'"
            echo -e "  - identifier == 'myButton'"
            echo ""
            read -p "Enter predicate: " predicate
            if [[ -z "$predicate" ]]; then
                echo -e "${RED}❌ Predicate cannot be empty${NC}"
                return
            fi
            # Escape double quotes in predicate
            predicate="${predicate//\"/\\\"}"
            json_body="{\"predicate\":\"$predicate\"}"
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return
            ;;
    esac
    
    # Generate filename with timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filename="element_screenshot_${timestamp}.png"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Testing: Element Screenshot"
    echo -e "POST http://localhost:$PORT/screenshot/element"
    echo -e "Body: $json_body"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local response=$(curl -s -X POST "http://localhost:$PORT/screenshot/element" \
        -H "Content-Type: application/json" \
        -d "$json_body")
    
    # Extract base64 image from response
    local base64_image=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'image' in data:
        print(data['image'])
    else:
        sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null)
    
    if [ -n "$base64_image" ]; then
        # Decode base64 and save to file
        echo "$base64_image" | base64 -d > "$filename"
        
        if [ -f "$filename" ]; then
            local file_size=$(ls -lh "$filename" | awk '{print $5}')
            echo -e "${GREEN}✅ Element screenshot saved successfully!${NC}"
            echo -e "   File: ${YELLOW}$filename${NC}"
            echo -e "   Size: ${YELLOW}$file_size${NC}"
            echo ""
            
            # Extract element info from response
            echo -e "${CYAN}Element Info:${NC}"
            echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'element' in data:
        elem = data['element']
        print(f\"   Type: {elem.get('type', 'N/A')}\")
        print(f\"   Identifier: {elem.get('identifier', 'N/A')}\")
        print(f\"   Label: {elem.get('label', 'N/A')}\")
except:
    pass
" 2>/dev/null
            
            echo ""
            
            # Try to open the image (macOS)
            if command -v open &> /dev/null; then
                read -p "Open screenshot? (y/n): " open_choice
                if [[ "$open_choice" == "y" || "$open_choice" == "Y" ]]; then
                    open "$filename"
                fi
            fi
        else
            echo -e "${RED}❌ Failed to save screenshot${NC}"
        fi
    else
        echo -e "${RED}❌ Failed to capture element screenshot${NC}"
        echo ""
        echo "Response:"
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    fi
    
    echo ""
}

# Soft validation - validates element properties without failing
validate_element_interactive() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Soft Validation (Multiple Checks)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Ask how to find the element
    echo ""
    echo "How would you like to find the element?"
    echo -e "  ${GREEN}1)${NC} By Identifier"
    echo -e "  ${GREEN}2)${NC} By Label (exact match)"
    echo -e "  ${GREEN}3)${NC} By Predicate"
    echo ""
    read -p "Select option (1-3): " search_method
    
    local search_field=""
    local search_value=""
    
    case $search_method in
        1)
            echo ""
            read -p "Enter element identifier: " search_value
            if [[ -z "$search_value" ]]; then
                echo -e "${RED}❌ Identifier cannot be empty${NC}"
                return
            fi
            search_field="identifier"
            ;;
        2)
            echo ""
            read -p "Enter label text (exact match): " search_value
            if [[ -z "$search_value" ]]; then
                echo -e "${RED}❌ Label cannot be empty${NC}"
                return
            fi
            search_field="label"
            ;;
        3)
            echo ""
            echo -e "${YELLOW}Example predicates:${NC}"
            echo -e "  - type == \"XCUIElementTypeTextField\""
            echo -e "  - label CONTAINS 'Search'"
            echo ""
            read -p "Enter predicate: " search_value
            if [[ -z "$search_value" ]]; then
                echo -e "${RED}❌ Predicate cannot be empty${NC}"
                return
            fi
            search_value="${search_value//\"/\\\"}"
            search_field="predicate"
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return
            ;;
    esac
    
    # Ask which properties to validate
    echo ""
    echo "Select properties to validate (comma-separated, e.g., 1,2,3):"
    echo -e "  ${GREEN}1)${NC} exists"
    echo -e "  ${GREEN}2)${NC} isEnabled"
    echo -e "  ${GREEN}3)${NC} isVisible"
    echo -e "  ${GREEN}4)${NC} label (exact match or contains:)"
    echo -e "  ${GREEN}5)${NC} value"
    echo -e "  ${GREEN}6)${NC} count"
    echo ""
    read -p "Enter properties: " properties
    
    # Build validations array
    local validations="["
    local first=true
    
    for prop in $(echo $properties | tr ',' ' '); do
        if [ "$first" = false ]; then
            validations+=","
        fi
        first=false
        
        local property_name=""
        local expected_value=""
        
        case $prop in
            1)
                property_name="exists"
                expected_value="true"
                ;;
            2)
                property_name="isEnabled"
                expected_value="true"
                ;;
            3)
                property_name="isVisible"
                expected_value="true"
                ;;
            4)
                property_name="label"
                echo ""
                read -p "Expected label value (or 'contains:text'): " expected_value
                ;;
            5)
                property_name="value"
                echo ""
                read -p "Expected value: " expected_value
                ;;
            6)
                property_name="count"
                echo ""
                echo "Enter count expectation (e.g., '1', '>0', '>=2', '<5', '<=10'):"
                read -p "Expected count: " expected_value
                ;;
            *)
                echo -e "${RED}Unknown property: $prop${NC}"
                continue
                ;;
        esac
        
        validations+="{\"property\":\"$property_name\",\"$search_field\":\"$search_value\",\"expectedValue\":\"$expected_value\"}"
    done
    
    validations+="]"
    
    # Build complete JSON body
    local json_body="{\"validations\":$validations}"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Request Body:${NC}"
    echo "$json_body" | jq . 2>/dev/null || echo "$json_body"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo ""
    echo -e "${CYAN}Sending POST /ui/validate...${NC}"
    
    local response=$(curl -s -X POST "http://localhost:$PORT/ui/validate" \
        -H "Content-Type: application/json" \
        -d "$json_body")
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo ""
}

# Hard assertion - validates a single property and fails if not met
assert_element_interactive() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Hard Assertion (Single Check - Fails on Error)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Ask how to find the element
    echo ""
    echo "How would you like to find the element?"
    echo -e "  ${GREEN}1)${NC} By Identifier"
    echo -e "  ${GREEN}2)${NC} By Label (exact match)"
    echo -e "  ${GREEN}3)${NC} By Predicate"
    echo ""
    read -p "Select option (1-3): " search_method
    
    local search_field=""
    local search_value=""
    
    case $search_method in
        1)
            echo ""
            read -p "Enter element identifier: " search_value
            if [[ -z "$search_value" ]]; then
                echo -e "${RED}❌ Identifier cannot be empty${NC}"
                return
            fi
            search_field="identifier"
            ;;
        2)
            echo ""
            read -p "Enter label text (exact match): " search_value
            if [[ -z "$search_value" ]]; then
                echo -e "${RED}❌ Label cannot be empty${NC}"
                return
            fi
            search_field="label"
            ;;
        3)
            echo ""
            echo -e "${YELLOW}Example predicates:${NC}"
            echo -e "  - type == \"XCUIElementTypeTextField\""
            echo -e "  - label CONTAINS 'Search'"
            echo ""
            read -p "Enter predicate: " search_value
            if [[ -z "$search_value" ]]; then
                echo -e "${RED}❌ Predicate cannot be empty${NC}"
                return
            fi
            search_value="${search_value//\"/\\\"}"
            search_field="predicate"
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return
            ;;
    esac
    
    # Ask which property to assert
    echo ""
    echo "Select property to assert:"
    echo -e "  ${GREEN}1)${NC} exists"
    echo -e "  ${GREEN}2)${NC} isEnabled"
    echo -e "  ${GREEN}3)${NC} isVisible"
    echo -e "  ${GREEN}4)${NC} label (exact match or contains:)"
    echo -e "  ${GREEN}5)${NC} value"
    echo -e "  ${GREEN}6)${NC} count"
    echo ""
    read -p "Select property: " prop
    
    local property_name=""
    local expected_value=""
    
    case $prop in
        1)
            property_name="exists"
            expected_value="true"
            ;;
        2)
            property_name="isEnabled"
            expected_value="true"
            ;;
        3)
            property_name="isVisible"
            expected_value="true"
            ;;
        4)
            property_name="label"
            echo ""
            read -p "Expected label value (or 'contains:text'): " expected_value
            ;;
        5)
            property_name="value"
            echo ""
            read -p "Expected value: " expected_value
            ;;
        6)
            property_name="count"
            echo ""
            echo "Enter count expectation (e.g., '1', '>0', '>=2', '<5', '<=10'):"
            read -p "Expected count: " expected_value
            ;;
        *)
            echo -e "${RED}Invalid property${NC}"
            return
            ;;
    esac
    
    # Build JSON body
    local json_body="{\"property\":\"$property_name\",\"$search_field\":\"$search_value\",\"expectedValue\":\"$expected_value\"}"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Request Body:${NC}"
    echo "$json_body" | jq . 2>/dev/null || echo "$json_body"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo ""
    echo -e "${CYAN}Sending POST /ui/assert...${NC}"
    
    local http_code=$(curl -s -o /tmp/assert_response_$$.json -w "%{http_code}" \
        -X POST "http://localhost:$PORT/ui/assert" \
        -H "Content-Type: application/json" \
        -d "$json_body")
    
    local response=$(cat /tmp/assert_response_$$.json)
    rm -f /tmp/assert_response_$$.json
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}HTTP Status: $http_code${NC}"
    echo -e "${YELLOW}Response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ Assertion passed!${NC}"
    else
        echo -e "${RED}❌ Assertion failed!${NC}"
    fi
    
    echo ""
}

# List active alerts
list_alerts_interactive() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}List Active Alerts${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo ""
    echo -e "${CYAN}Sending GET /ui/alerts...${NC}"
    
    local response=$(curl -s -X GET "http://localhost:$PORT/ui/alerts")
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Show count
    local count=$(echo "$response" | jq -r '.count' 2>/dev/null)
    if [ "$count" = "0" ]; then
        echo -e "${GREEN}✓ No alerts currently displayed${NC}"
    elif [ -n "$count" ] && [ "$count" != "null" ]; then
        echo -e "${YELLOW}⚠ $count alert(s) detected${NC}"
    fi
    
    echo ""
}

# Dismiss alert by button label
dismiss_alert_interactive() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Dismiss Alert by Button Label${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # First, show available alerts
    echo ""
    echo -e "${YELLOW}Fetching current alerts...${NC}"
    local alerts_response=$(curl -s -X GET "http://localhost:$PORT/ui/alerts")
    echo "$alerts_response" | jq . 2>/dev/null || echo "$alerts_response"
    
    local count=$(echo "$alerts_response" | jq -r '.count' 2>/dev/null)
    if [ "$count" = "0" ] || [ "$count" = "null" ]; then
        echo ""
        echo -e "${YELLOW}⚠ No alerts currently displayed. Trigger an alert first.${NC}"
        return
    fi
    
    # Show button options
    echo ""
    echo -e "${CYAN}Available buttons in alerts:${NC}"
    echo "$alerts_response" | jq -r '.alerts[].buttons[]' 2>/dev/null | sort -u | nl
    
    # Ask for button label
    echo ""
    echo -e "${YELLOW}Common button labels:${NC}"
    echo -e "  - Allow"
    echo -e "  - Don't Allow"
    echo -e "  - OK"
    echo -e "  - Cancel"
    echo ""
    read -p "Enter button label to tap (case-sensitive): " button_label
    
    if [[ -z "$button_label" ]]; then
        echo -e "${RED}❌ Button label cannot be empty${NC}"
        return
    fi
    
    # Ask for timeout
    echo ""
    read -p "Enter timeout in seconds (default: 5): " timeout
    timeout=${timeout:-5}
    
    # Build JSON body
    local json_body="{\"buttonLabel\":\"$button_label\""
    if [[ -n "$timeout" ]]; then
        json_body+=",\"timeout\":$timeout"
    fi
    json_body+="}"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Request Body:${NC}"
    echo "$json_body" | jq . 2>/dev/null || echo "$json_body"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo ""
    echo -e "${CYAN}Sending POST /ui/alert/dismiss...${NC}"
    
    local http_code=$(curl -s -o /tmp/dismiss_alert_response_$$.json -w "%{http_code}" \
        -X POST "http://localhost:$PORT/ui/alert/dismiss" \
        -H "Content-Type: application/json" \
        -d "$json_body")
    
    local response=$(cat /tmp/dismiss_alert_response_$$.json)
    rm -f /tmp/dismiss_alert_response_$$.json
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}HTTP Status: $http_code${NC}"
    echo -e "${YELLOW}Response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ Alert dismissed successfully!${NC}"
    else
        echo -e "${RED}❌ Failed to dismiss alert${NC}"
    fi
    
    echo ""
}

# Explicit wait for condition
wait_for_condition_interactive() {
    echo ""
    echo -e "${CYAN}⏳ Wait for Condition${NC}"
    echo ""
    echo -e "Select wait condition:"
    echo -e "  ${GREEN}1)${NC} exists - Element exists in UI tree"
    echo -e "  ${GREEN}2)${NC} notExists - Element does not exist (useful for loading spinners)"
    echo -e "  ${GREEN}3)${NC} isEnabled - Element is enabled/interactable"
    echo -e "  ${GREEN}4)${NC} isDisabled - Element is disabled"
    echo -e "  ${GREEN}5)${NC} isVisible - Element is visible on screen"
    echo -e "  ${GREEN}6)${NC} isNotVisible - Element is not visible"
    echo -e "  ${GREEN}7)${NC} textContains - Element text contains value"
    echo -e "  ${GREEN}8)${NC} textEquals - Element text equals value"
    echo -e "  ${GREEN}9)${NC} valueContains - Element value contains value"
    echo -e "  ${GREEN}10)${NC} valueEquals - Element value equals value"
    echo ""
    read -p "Select condition (1-10): " condition_choice
    
    local condition=""
    case $condition_choice in
        1) condition="exists" ;;
        2) condition="notExists" ;;
        3) condition="isEnabled" ;;
        4) condition="isDisabled" ;;
        5) condition="isVisible" ;;
        6) condition="isNotVisible" ;;
        7) condition="textContains" ;;
        8) condition="textEquals" ;;
        9) condition="valueContains" ;;
        10) condition="valueEquals" ;;
        *)
            echo -e "${RED}❌ Invalid condition${NC}"
            return
            ;;
    esac
    
    # Ask for search method
    echo ""
    echo -e "Select search method:"
    echo -e "  ${GREEN}1)${NC} By identifier (accessibility ID)"
    echo -e "  ${GREEN}2)${NC} By label (accessibility label)"
    echo -e "  ${GREEN}3)${NC} By predicate (NSPredicate query)"
    echo ""
    read -p "Select method (1-3): " method_choice
    
    local body="{"
    case $method_choice in
        1)
            read -p "Enter element identifier: " identifier
            body="${body}\"identifier\":\"$identifier\""
            ;;
        2)
            read -p "Enter element label: " label
            body="${body}\"label\":\"$label\""
            ;;
        3)
            read -p "Enter predicate (e.g., label CONTAINS 'text'): " predicate
            body="${body}\"predicate\":\"$predicate\""
            ;;
        *)
            echo -e "${RED}❌ Invalid method${NC}"
            return
            ;;
    esac
    
    # Add condition to body
    body="${body},\"condition\":\"$condition\""
    
    # Ask for value if needed for text/value conditions
    if [[ "$condition" =~ ^(textContains|textEquals|valueContains|valueEquals)$ ]]; then
        echo ""
        read -p "Enter expected value: " value
        body="${body},\"value\":\"$value\""
    fi
    
    # Ask for timeout
    echo ""
    read -p "Timeout in seconds (leave empty for default): " timeout
    if [ -n "$timeout" ]; then
        body="${body},\"timeout\":$timeout"
    fi
    
    # Close JSON
    body="${body}}"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Testing: Wait for Condition${NC}"
    echo -e "${YELLOW}POST http://localhost:$PORT/ui/wait${NC}"
    echo -e "${YELLOW}Body:${NC}"
    echo "$body" | jq . 2>/dev/null || echo "$body"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$body" \
        "http://localhost:$PORT/ui/wait")
    http_code=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    response=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}HTTP Status: $http_code${NC}"
    echo -e "${YELLOW}Response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ Condition met successfully!${NC}"
    else
        echo -e "${RED}❌ Condition not met or error occurred${NC}"
    fi
    
    echo ""
}

# Get current configuration
get_configuration_interactive() {
    echo ""
    echo -e "${CYAN}⚙️  Get Current Configuration${NC}"
    echo ""
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Testing: Get Configuration${NC}"
    echo -e "${YELLOW}GET http://localhost:$PORT/config${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" "http://localhost:$PORT/config")
    http_code=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    response=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}HTTP Status: $http_code${NC}"
    echo -e "${YELLOW}Response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ Configuration retrieved successfully!${NC}"
    else
        echo -e "${RED}❌ Failed to get configuration${NC}"
    fi
    
    echo ""
}

# Update configuration
update_configuration_interactive() {
    echo ""
    echo -e "${CYAN}⚙️  Update Configuration${NC}"
    echo ""
    echo -e "You can update any combination of settings."
    echo -e "Leave a field empty to keep current value."
    echo ""
    
    # Ask for timeout
    read -p "Default timeout in seconds (leave empty to keep current): " timeout
    
    # Ask for error verbosity
    echo ""
    echo -e "Error verbosity mode:"
    echo -e "  ${GREEN}1)${NC} Simple (user-friendly, minimal details)"
    echo -e "  ${GREEN}2)${NC} Verbose (detailed errors with stack traces)"
    echo -e "  ${GREEN}3)${NC} Keep current"
    echo ""
    read -p "Select option (1-3, default: 3): " verbosity_choice
    
    local verbosity=""
    case ${verbosity_choice:-3} in
        1) verbosity="simple" ;;
        2) verbosity="verbose" ;;
        3) verbosity="" ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            return
            ;;
    esac
    
    # Ask for max concurrent requests
    read -p "Max concurrent requests (leave empty to keep current): " maxRequests
    
    # Build JSON body with only provided fields
    local body="{"
    local first=true
    
    if [ -n "$timeout" ]; then
        body="${body}\"defaultTimeout\":$timeout"
        first=false
    fi
    
    if [ -n "$verbosity" ]; then
        if [ "$first" = false ]; then
            body="${body},"
        fi
        body="${body}\"errorVerbosity\":\"$verbosity\""
        first=false
    fi
    
    if [ -n "$maxRequests" ]; then
        if [ "$first" = false ]; then
            body="${body},"
        fi
        body="${body}\"maxConcurrentRequests\":$maxRequests"
        first=false
    fi
    
    body="${body}}"
    
    # Check if any field was provided
    if [ "$body" = "{}" ]; then
        echo ""
        echo -e "${YELLOW}⚠️  No changes provided. Configuration remains unchanged.${NC}"
        return
    fi
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Testing: Update Configuration${NC}"
    echo -e "${YELLOW}POST http://localhost:$PORT/config${NC}"
    echo -e "${YELLOW}Body:${NC}"
    echo "$body" | jq . 2>/dev/null || echo "$body"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$body" \
        "http://localhost:$PORT/config")
    http_code=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    response=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}HTTP Status: $http_code${NC}"
    echo -e "${YELLOW}Response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ Configuration updated successfully!${NC}"
    else
        echo -e "${RED}❌ Failed to update configuration${NC}"
    fi
    
    echo ""
}

# Reset configuration to defaults
reset_configuration_interactive() {
    echo ""
    echo -e "${CYAN}⚙️  Reset Configuration to Defaults${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  This will reset all settings to their default values:${NC}"
    echo -e "  - Default timeout: ${GREEN}5 seconds${NC}"
    echo -e "  - Error verbosity: ${GREEN}simple${NC}"
    echo -e "  - Max concurrent requests: ${GREEN}10${NC}"
    echo ""
    read -p "Are you sure you want to reset? (y/n, default: n): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e "${YELLOW}Reset cancelled.${NC}"
        return
    fi
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Testing: Reset Configuration${NC}"
    echo -e "${YELLOW}POST http://localhost:$PORT/config/reset${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
        "http://localhost:$PORT/config/reset")
    http_code=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    response=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}HTTP Status: $http_code${NC}"
    echo -e "${YELLOW}Response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ Configuration reset to defaults successfully!${NC}"
    else
        echo -e "${RED}❌ Failed to reset configuration${NC}"
    fi
    
    echo ""
}

# Interactive menu for testing endpoints
show_menu() {
    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║      iOS Runner - Interactive Menu       ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Server Info:${NC}"
    echo -e "  Port:   ${YELLOW}$PORT${NC}"
    echo -e "  Device: ${YELLOW}$DEVICE${NC}"
    echo ""
    echo -e "${CYAN}Available Tests:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} GET  /health                 - Health check"
    echo -e "  ${GREEN}2)${NC} GET  /app/list               - List installed apps"
    echo -e "  ${GREEN}3)${NC} POST /app/launch             - Launch app (select from list)"
    echo -e "  ${GREEN}4)${NC} GET  /app/state              - Get app state"
    echo -e "  ${GREEN}5)${NC} POST /app/activate           - Activate app"
    echo -e "  ${GREEN}6)${NC} POST /app/terminate          - Terminate app"
    echo -e "  ${GREEN}7)${NC} GET  /ui/tree                 - Get UI tree (specify depth)"
    echo -e "  ${GREEN}8)${NC} POST /ui/find                - Find elements (specify criteria)"
    echo -e "  ${GREEN}9)${NC} POST /ui/tap                 - Tap element (specify criteria)"
    echo -e "  ${GREEN}10)${NC} POST /ui/type               - Type text (specify criteria)"
    echo -e "  ${GREEN}11)${NC} POST /ui/swipe              - Swipe gesture (specify direction)"
    echo -e "  ${GREEN}12)${NC} POST /ui/scroll             - Scroll to element"
    echo -e "  ${GREEN}13)${NC} POST /ui/keyboard/type      - Hardware keyboard typing"
    echo -e "  ${GREEN}14)${NC} GET  /screenshot            - Capture full screen screenshot"
    echo -e "  ${GREEN}15)${NC} POST /screenshot/element    - Capture element screenshot"
    echo -e "  ${GREEN}16)${NC} POST /ui/validate           - Soft validation (multiple checks)"
    echo -e "  ${GREEN}17)${NC} POST /ui/assert             - Hard assertion (fails on error)"
    echo -e "  ${GREEN}18)${NC} GET  /ui/alerts             - List active alerts"
    echo -e "  ${GREEN}19)${NC} POST /ui/alert/dismiss      - Dismiss alert by button label"
    echo -e "  ${GREEN}20)${NC} POST /ui/wait               - Wait for condition (explicit wait)"
    echo -e "  ${GREEN}21)${NC} GET  /config                - Get current configuration"
    echo -e "  ${GREEN}22)${NC} POST /config                - Update configuration"
    echo -e "  ${GREEN}23)${NC} POST /config/reset          - Reset configuration to defaults"
    echo ""
    echo -e "  ${RED}q)${NC} Quit"
    echo ""
    read -p "Select option: " choice
}

# Swipe gesture - swipes in specified direction
swipe_gesture_interactive() {
    echo ""
    echo -e "${CYAN}👆💨 Swipe Gesture${NC}"
    echo ""
    echo -e "Select swipe direction:"
    echo -e "  ${GREEN}1)${NC} Up"
    echo -e "  ${GREEN}2)${NC} Down"
    echo -e "  ${GREEN}3)${NC} Left"
    echo -e "  ${GREEN}4)${NC} Right"
    echo ""
    read -p "Select direction (1-4): " dir_choice
    
    local direction=""
    case $dir_choice in
        1) direction="up" ;;
        2) direction="down" ;;
        3) direction="left" ;;
        4) direction="right" ;;
        *)
            echo -e "${RED}❌ Invalid direction${NC}"
            return
            ;;
    esac
    
    echo ""
    echo -e "Target element (leave empty to swipe on entire screen):"
    echo -e "  ${GREEN}1)${NC} By Element ID (identifier)"
    echo -e "  ${GREEN}2)${NC} By Predicate (custom NSPredicate)"
    echo -e "  ${GREEN}3)${NC} Entire screen (no element specified)"
    echo ""
    read -p "Select option (1-3, default: 3): " method_choice
    
    local identifier=""
    local predicate=""
    local body=""
    
    case ${method_choice:-3} in
        1)
            read -p "Enter element identifier: " identifier
            if [ -z "$identifier" ]; then
                echo -e "${RED}❌ Identifier cannot be empty${NC}"
                return
            fi
            body="{\"direction\":\"$direction\",\"identifier\":\"$identifier\""
            ;;
        2)
            read -p "Enter predicate (e.g., label CONTAINS 'text'): " predicate
            if [ -z "$predicate" ]; then
                echo -e "${RED}❌ Predicate cannot be empty${NC}"
                return
            fi
            # Escape double quotes in predicate
            predicate="${predicate//\"/\\\"}"
            body="{\"direction\":\"$direction\",\"predicate\":\"$predicate\""
            ;;
        3)
            body="{\"direction\":\"$direction\""
            ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            return
            ;;
    esac
    
    # Ask for wait strategy
    echo ""
    echo -e "Select wait strategy:"
    echo -e "  ${GREEN}1)${NC} Wait (default - wait for element to exist)"
    echo -e "  ${GREEN}2)${NC} No wait (swipe immediately)"
    echo ""
    read -p "Select option (1-2, default: 1): " wait_choice
    
    local waitStrategy="wait"
    case ${wait_choice:-1} in
        1) waitStrategy="wait" ;;
        2) waitStrategy="immediate" ;;
        *)
            echo -e "${RED}❌ Invalid wait strategy${NC}"
            return
            ;;
    esac
    
    # Close JSON body
    body="$body,\"waitStrategy\":\"$waitStrategy\"}"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Testing: Swipe $direction"
    echo -e "POST http://localhost:$PORT/ui/swipe"
    echo -e "Body: $body"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local response=$(curl -s -X POST "http://localhost:$PORT/ui/swipe" \
        -H "Content-Type: application/json" \
        -d "$body")
    
    echo "Response:"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    echo ""
    echo ""
    
    read -p "Press Enter to continue..."
}

# Find and tap - combines find with tap

# Scroll to element - scrolls until element is visible
scroll_to_element_interactive() {
    echo ""
    echo -e "${CYAN}📜 Scroll to Element${NC}"
    echo ""
    echo -e "Select target element search method:"
    echo -e "  ${GREEN}1)${NC} By Element ID (identifier)"
    echo -e "  ${GREEN}2)${NC} By Predicate (custom NSPredicate)"
    echo ""
    read -p "Select option (1-2): " method_choice
    
    local body=""
    
    case $method_choice in
        1)
            read -p "Enter target element identifier: " identifier
            if [ -z "$identifier" ]; then
                echo -e "${RED}❌ Identifier cannot be empty${NC}"
                return
            fi
            body="{\"toElementIdentifier\":\"$identifier\""
            ;;
        2)
            read -p "Enter target element predicate: " predicate
            if [ -z "$predicate" ]; then
                echo -e "${RED}❌ Predicate cannot be empty${NC}"
                return
            fi
            # Escape double quotes
            predicate="${predicate//\"/\\\"}"
            body="{\"toElementPredicate\":\"$predicate\""
            ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            return
            ;;
    esac
    
    # Optional: specify scroll container
    echo ""
    read -p "Specify scroll container? (y/N): " specify_container
    if [[ "$specify_container" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "Select scroll container method:"
        echo -e "  ${GREEN}1)${NC} By Element ID"
        echo -e "  ${GREEN}2)${NC} By Predicate"
        echo ""
        read -p "Select option (1-2): " container_method
        
        case $container_method in
            1)
                read -p "Enter scroll container identifier: " container_id
                if [ -n "$container_id" ]; then
                    body="$body,\"scrollContainerIdentifier\":\"$container_id\""
                fi
                ;;
            2)
                read -p "Enter scroll container predicate: " container_pred
                if [ -n "$container_pred" ]; then
                    container_pred="${container_pred//\"/\\\"}"
                    body="$body,\"scrollContainerPredicate\":\"$container_pred\""
                fi
                ;;
        esac
    fi
    
    # Close JSON
    body="$body,\"waitStrategy\":\"wait\"}"
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Testing: Scroll to Element"
    echo -e "POST http://localhost:$PORT/ui/scroll"
    echo -e "Body: $body"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local response=$(curl -s -X POST "http://localhost:$PORT/ui/scroll" \
        -H "Content-Type: application/json" \
        -d "$body")
    
    echo "Response:"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    echo ""
    echo ""
    
    read -p "Press Enter to continue..."
}

# Hardware keyboard typing - types using system keyboard
keyboard_type_interactive() {
    echo ""
    echo -e "${CYAN}⌨️  Hardware Keyboard Type${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Note: Requires an element to have keyboard focus!${NC}"
    echo -e "${YELLOW}   Use option 9 (tap) first to focus a text field.${NC}"
    echo ""
    echo -e "What to type:"
    echo -e "  ${GREEN}1)${NC} Text"
    echo -e "  ${GREEN}2)${NC} Special keys"
    echo -e "  ${GREEN}3)${NC} Both (text then keys)"
    echo ""
    read -p "Select option (1-3): " type_choice
    
    local text=""
    local keys=""
    local body=""
    
    case $type_choice in
        1)
            read -p "Enter text to type: " text
            if [ -z "$text" ]; then
                echo -e "${RED}❌ Text cannot be empty${NC}"
                return
            fi
            body="{\"text\":\"$text\"}"
            ;;
        2)
            echo ""
            echo -e "Available keys: return, delete, tab, escape, space"
            read -p "Enter keys (comma-separated, e.g., return,tab): " keys_input
            if [ -z "$keys_input" ]; then
                echo -e "${RED}❌ Keys cannot be empty${NC}"
                return
            fi
            # Convert to JSON array
            IFS=',' read -ra KEYS_ARRAY <<< "$keys_input"
            keys="["
            for i in "${!KEYS_ARRAY[@]}"; do
                key=$(echo "${KEYS_ARRAY[$i]}" | xargs) # trim whitespace
                if [ $i -gt 0 ]; then
                    keys="$keys,"
                fi
                keys="$keys\"$key\""
            done
            keys="$keys]"
            body="{\"keys\":$keys}"
            ;;
        3)
            read -p "Enter text to type: " text
            if [ -z "$text" ]; then
                echo -e "${RED}❌ Text cannot be empty${NC}"
                return
            fi
            echo ""
            echo -e "Available keys: return, delete, tab, escape, space"
            read -p "Enter keys (comma-separated): " keys_input
            if [ -z "$keys_input" ]; then
                echo -e "${RED}❌ Keys cannot be empty${NC}"
                return
            fi
            # Convert to JSON array
            IFS=',' read -ra KEYS_ARRAY <<< "$keys_input"
            keys="["
            for i in "${!KEYS_ARRAY[@]}"; do
                key=$(echo "${KEYS_ARRAY[$i]}" | xargs)
                if [ $i -gt 0 ]; then
                    keys="$keys,"
                fi
                keys="$keys\"$key\""
            done
            keys="$keys]"
            body="{\"text\":\"$text\",\"keys\":$keys}"
            ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            return
            ;;
    esac
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Testing: Hardware Keyboard Type"
    echo -e "POST http://localhost:$PORT/ui/keyboard/type"
    echo -e "Body: $body"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local response=$(curl -s -X POST "http://localhost:$PORT/ui/keyboard/type" \
        -H "Content-Type: application/json" \
        -d "$body")
    
    echo "Response:"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    echo ""
    echo ""
    
    read -p "Press Enter to continue..."
}

# Main execution
echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  iOS Runner Interactive Test Server       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"

# Device selection
if [ -z "$2" ]; then
    select_device
else
    DEVICE="$2"
    # Get device ID for the named device
    DEVICE_ID=$(xcrun simctl list devices --json | python3 -c "
import sys, json
devices = json.load(sys.stdin)['devices']
for runtime, device_list in devices.items():
    for device in device_list:
        if device['name'] == '$DEVICE':
            print(device['udid'])
            sys.exit(0)
" 2>/dev/null)
    
    if [ -z "$DEVICE_ID" ]; then
        echo -e "${RED}❌ Device '$DEVICE' not found${NC}"
        exit 1
    fi
fi

# Extract installed applications
extract_installed_apps "$DEVICE_ID"

echo ""
echo -e "${BLUE}🧪 Starting iOS Runner Server${NC}"
echo "=================================="
echo -e "Port:   ${YELLOW}$PORT${NC}"
echo -e "Device: ${YELLOW}$DEVICE${NC}"
if [ -n "$INSTALLED_APPS" ]; then
    app_count=$(echo "$INSTALLED_APPS" | tr ',' '\n' | wc -l | tr -d ' ')
    echo -e "Apps:   ${YELLOW}$app_count installed${NC}"
fi
echo ""

# Get script directory and navigate to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Validate project directory
echo ""
echo -e "${CYAN}📂 Project Directory:${NC} $PROJECT_DIR"

if [ ! -f "$PROJECT_DIR/Project.swift" ]; then
    echo -e "${RED}❌ Error: Not in IOSAgentDriver project directory${NC}"
    echo -e "${RED}   Expected to find Project.swift in: $PROJECT_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Directory validation passed"

cd "$PROJECT_DIR"

# Start the server in background
echo -e "${CYAN}🚀 Starting server...${NC}"

# Generate test plan with environment variables
echo -e "${YELLOW}Generating test plan...${NC}"
"$SCRIPT_DIR/generate_testplan.sh" "$PORT" "$INSTALLED_APPS" > /dev/null

if [ -n "$INSTALLED_APPS" ]; then
    echo -e "${YELLOW}Test Plan: RUNNER_PORT=$PORT, INSTALLED_APPLICATIONS=\"$INSTALLED_APPS\"${NC}"
else
    echo -e "${YELLOW}Test Plan: RUNNER_PORT=$PORT${NC}"
fi
echo -e "${CYAN}Command: tuist test IOSAgentDriverUITests --device \"$DEVICE\"${NC}"
echo ""

cd "$PROJECT_DIR"
tuist test IOSAgentDriverUITests --device "$DEVICE" > /tmp/ios-agent-driver-test-$PORT.log 2>&1 &

SERVER_PID=$!
echo ""
echo -e "${GREEN}✓${NC} Server started (PID: $SERVER_PID)"

# Wait for server to be ready
if ! wait_for_server; then
    echo ""
    echo -e "${RED}❌ Server failed to start${NC}"
    echo ""
    echo -e "${YELLOW}Last 20 lines of log:${NC}"
    tail -20 /tmp/ios-agent-driver-$PORT.log
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Server is running successfully!${NC}"
echo -e "${CYAN}ℹ️  Log file: /tmp/ios-agent-driver-$PORT.log${NC}"

# Interactive menu loop
while true; do
    show_menu
    
    case $choice in
        1)
            test_endpoint "GET" "/health" "" "Health Check"
            ;;
        2)
            test_endpoint "GET" "/app/list" "" "List Installed Apps"
            ;;
        3)
            select_app_to_launch
            ;;
        4)
            test_endpoint "GET" "/app/state" "" "Get App State"
            ;;
        5)
            test_endpoint "POST" "/app/activate" "" "Activate App"
            ;;
        6)
            test_endpoint "POST" "/app/terminate" "" "Terminate App"
            ;;
        7)
            get_ui_tree_with_depth
            ;;
        8)
            find_elements_interactive
            ;;
        9)
            tap_element_interactive
            ;;
        10)
            type_text_interactive
            ;;
        11)
            swipe_gesture_interactive
            ;;
        12)
            scroll_to_element_interactive
            ;;
        13)
            keyboard_type_interactive
            ;;
        14)
            capture_full_screenshot
            ;;
        15)
            capture_element_screenshot
            ;;
        16)
            validate_element_interactive
            ;;
        17)
            assert_element_interactive
            ;;
        18)
            list_alerts_interactive
            ;;
        19)
            dismiss_alert_interactive
            ;;
        20)
            wait_for_condition_interactive
            ;;
        21)
            get_configuration_interactive
            ;;
        22)
            update_configuration_interactive
            ;;
        23)
            reset_configuration_interactive
            ;;
        q|Q)
            echo ""
            echo -e "${YELLOW}👋 Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
done
