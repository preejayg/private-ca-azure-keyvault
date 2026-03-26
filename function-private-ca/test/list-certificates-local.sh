#!/bin/bash

# List certificates in Key Vault (LOCAL VERSION) with pagination
# Usage: ./list-certificates-local.sh [type] [page] [page_size] [details]
#
# PREREQUISITES:
# - VPN connection to Azure virtual network  
# - Hosts file entry: <FUNCTION_APP_PRIVATE_IP>  func-devicepki-dev-001.azurewebsites.net
# - Azure CLI logged in

set -e

# Configuration
RESOURCE_GROUP="rg-dev-aue-dcert-poc"
FUNCTION_APP="func-devicepki-dev-001"
FUNCTION_HOST="${FUNCTION_APP}.azurewebsites.net"

# Parameters
TYPE="${1:-all}"
PAGE="${2:-1}"
PAGE_SIZE="${3:-100}"
DETAILS="${4:-summary}"

if [[ ! "$TYPE" =~ ^(all|ca|device)$ ]]; then
    echo "Usage: $0 [type] [page] [page_size] [details]"
    echo ""
    echo "Arguments:"
    echo "  type:      all | ca | device (default: all)"
    echo "  page:      Page number (default: 1)"
    echo "  page_size: Items per page (default: 100, max: 500)"
    echo "  details:   summary | full (default: summary)"
    echo ""
    echo "Examples:"
    echo "  $0                    # List all certificates, page 1, 100 per page"
    echo "  $0 device 1 50        # List device certs, 50 per page"
    echo "  $0 all 2 100 full     # Page 2 with full details"
    exit 1
fi

echo "========================================="
echo "List Certificates (Paginated)"
echo "========================================="
echo "Filter:    $TYPE"
echo "Page:      $PAGE"
echo "Page Size: $PAGE_SIZE"
echo "Details:   $DETAILS"
echo ""

# Get function master key
echo "[1/3] Retrieving function master key..."
MASTER_KEY=$(az functionapp keys list \
    --name $FUNCTION_APP \
    --resource-group $RESOURCE_GROUP \
    --query "masterKey" -o tsv 2>/dev/null)

if [ -z "$MASTER_KEY" ]; then
    echo "❌ Failed to retrieve master key"
    exit 1
fi
echo "✅ Master key retrieved"
echo ""

# Call list-certificates API with pagination
echo "[2/3] Fetching certificates from function app..."

RESPONSE=$(curl -s "https://${FUNCTION_HOST}/api/list-certificates?type=$TYPE&page=$PAGE&page_size=$PAGE_SIZE&details=$DETAILS" \
    -H "x-functions-key: $MASTER_KEY" 2>&1)

# Check if response contains error
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "❌ Failed to list certificates"
    echo "Response:"
    echo "$RESPONSE" | jq .
    exit 1
fi

# Check if pagination field exists
if ! echo "$RESPONSE" | jq -e '.pagination' > /dev/null 2>&1; then
    echo "⚠️  Warning: No pagination field in response"
    echo ""
    echo "Full response:"
    echo "$RESPONSE" | jq .
    echo ""
    echo "This may indicate the function app hasn't been updated with pagination support."
    echo "Please deploy the updated function code:"
    echo "  cd scripts && ./deploy-appl-from-local.sh"
    exit 1
fi

echo "✅ Certificates retrieved"
echo ""

# Display pagination info
echo "[3/3] Pagination Info"
TOTAL_ITEMS=$(echo "$RESPONSE" | jq '.pagination.total_items')
TOTAL_PAGES=$(echo "$RESPONSE" | jq '.pagination.total_pages')
HAS_NEXT=$(echo "$RESPONSE" | jq '.pagination.has_next')
HAS_PREV=$(echo "$RESPONSE" | jq '.pagination.has_previous')

echo "  Total items: $TOTAL_ITEMS"
echo "  Total pages: $TOTAL_PAGES"
echo "  Current page: $PAGE of $TOTAL_PAGES"
if [ "$HAS_PREV" = "true" ]; then
    echo "  ← Previous: $0 $TYPE $((PAGE-1)) $PAGE_SIZE $DETAILS"
fi
if [ "$HAS_NEXT" = "true" ]; then
    echo "  → Next:     $0 $TYPE $((PAGE+1)) $PAGE_SIZE $DETAILS"
fi
echo ""

# Display CA certificates
if [ "$TYPE" = "all" ] || [ "$TYPE" = "ca" ]; then
    echo "========================================="
    echo "CA Certificates"
    echo "========================================="
    
    CA_TOTAL=$(echo "$RESPONSE" | jq '.ca_certificates.total_count // 0')
    CA_PAGE=$(echo "$RESPONSE" | jq '.ca_certificates.page_count // 0')
    
    echo "Total: $CA_TOTAL | Showing: $CA_PAGE on this page"
    echo ""
    
    if [ "$CA_PAGE" -gt 0 ]; then
        echo "$RESPONSE" | jq -r '.ca_certificates.items[] | 
            "Name:        \(.name)\n" +
            "Thumbprint:  \(.thumbprint)\n" +
            "Created:     \(.created_on)\n" +
            "Expires:     \(.expires_on)\n" +
            "Enabled:     \(.enabled)\n" +
            "Storage:     \(.storage_type)\n"'
    else
        echo "No CA certificates found on this page"
    fi
    echo ""
fi

# Display device certificates
if [ "$TYPE" = "all" ] || [ "$TYPE" = "device" ]; then
    echo "========================================="
    echo "Device Certificates"
    echo "========================================="
    
    DEVICE_TOTAL=$(echo "$RESPONSE" | jq '.device_certificates.total_count // 0')
    DEVICE_PAGE=$(echo "$RESPONSE" | jq '.device_certificates.page_count // 0')
    
    echo "Total: $DEVICE_TOTAL | Showing: $DEVICE_PAGE on this page"
    echo ""
    
    if [ "$DEVICE_PAGE" -gt 0 ]; then
        if [ "$DETAILS" = "full" ]; then
            echo "$RESPONSE" | jq -r '.device_certificates.items[] | 
                "Name:        \(.name)\n" +
                "Serial:      \(.serial_number // "N/A")\n" +
                "Subject:     \(.subject // "N/A")\n" +
                "Issuer:      \(.issuer // "N/A")\n" +
                "Not Before:  \(.not_before // "N/A")\n" +
                "Expires:     \(.expires_on // "N/A")\n" +
                "Thumbprint:  \(.thumbprint // "N/A")\n" +
                "Enabled:     \(.enabled)\n" +
                "Storage:     \(.storage_type)\n"'
        else
            echo "$RESPONSE" | jq -r '.device_certificates.items[] | 
                "Name:        \(.name)\n" +
                "Created:     \(.created_on)\n" +
                "Enabled:     \(.enabled)\n" +
                "Storage:     \(.storage_type)\n"'
        fi
    else
        echo "No device certificates found on this page"
    fi
    echo ""
fi

# Summary
echo "========================================="
echo "Summary"
echo "========================================="
echo "Total certificates: $TOTAL_ITEMS"
echo "Page $PAGE of $TOTAL_PAGES ($PAGE_SIZE per page)"

if [ "$TYPE" = "all" ]; then
    CA_COUNT=$(echo "$RESPONSE" | jq '.ca_certificates.total_count // 0')
    DEVICE_COUNT=$(echo "$RESPONSE" | jq '.device_certificates.total_count // 0')
    echo "  CA certificates:     $CA_COUNT"
    echo "  Device certificates: $DEVICE_COUNT"
fi
echo ""

# Navigation hints
if [ "$HAS_NEXT" = "true" ] || [ "$HAS_PREV" = "true" ]; then
    echo "Navigation:"
    if [ "$HAS_PREV" = "true" ]; then
        echo "  Previous page: $0 $TYPE $((PAGE-1)) $PAGE_SIZE $DETAILS"
    fi
    if [ "$HAS_NEXT" = "true" ]; then
        echo "  Next page:     $0 $TYPE $((PAGE+1)) $PAGE_SIZE $DETAILS"
    fi
    echo ""
fi
