#!/bin/bash

# Prompt for Compartment OCID
echo "Enter your Compartment OCID:"
read COMPARTMENT_OCID

# Validate if the Compartment OCID is provided
if [ -z "$COMPARTMENT_OCID" ]; then
    echo "Compartment OCID is required. Exiting."
    exit 1
fi

# Prompt for VCN OCID
echo "Enter your VCN OCID:"
read VCN_OCID

# Validate if the VCN OCID is provided
if [ -z "$VCN_OCID" ]; then
    echo "VCN OCID is required. Exiting."
    exit 1
fi

# List Load Balancers and get the most recently created one using pagination
LB_ID_JSON=$(oci lb load-balancer list --compartment-id $COMPARTMENT_OCID --sort-by TIMECREATED --all --query "data[0].id" --output json)

# Check if Load Balancer ID is found in the JSON output
if [ -z "$LB_ID_JSON" ] || [[ "$LB_ID_JSON" == *"null"* ]]; then
    echo "No Load Balancer found in the specified compartment."
    exit 1
fi

echo "Most recently created Load Balancer ID (in JSON): $LB_ID_JSON"

# Fetch the Load Balancer details to retrieve the Network Interface (NIC) or other details
LB_METADATA_JSON=$(oci lb load-balancer get --load-balancer-id $LB_ID_JSON --output json)

# Check if the NIC ID exists and parse it
NIC_ID=$(echo "$LB_METADATA_JSON" | grep -o '"nics":\[.*\]' | sed 's/.*"id":"\([^"]*\)".*/\1/')

# If NIC ID is not found, print full output for inspection
if [ -z "$NIC_ID" ]; then
    echo "NIC ID not found. Full raw output:"
    echo "$LB_METADATA_JSON"
    exit 1
fi

echo "Load Balancer's NIC ID: $NIC_ID"

# Create Network Security Group (NSG)
NSG_NAME="LB-Network-Security-Group"
NSG_ID_JSON=$(oci network nsg create --compartment-id $COMPARTMENT_OCID --vcn-id $VCN_OCID --display-name $NSG_NAME --query "data.id" --output json)

# Check if NSG creation was successful
if [ -z "$NSG_ID_JSON" ] || [[ "$NSG_ID_JSON" == *"null"* ]]; then
    echo "Failed to create Network Security Group."
    exit 1
fi

echo "Created NSG with ID: $NSG_ID_JSON"

# Attach the NSG to the Load Balancer's Network Interface (NIC)
oci network nsg add-security-list --nsg-id $NSG_ID_JSON --network-interface-id $NIC_ID --output json

echo "Attached NSG to the Load Balancer's NIC."

# Add rule to expose port 9090 to the world (source CIDR 0.0.0.0/0)
oci network nsg update --nsg-id $NSG_ID_JSON --ingress-security-rules '[{
    "protocol": "6",
    "source": "0.0.0.0/0",
    "destination-port-range": "9090",
    "source-port-range": "ALL"
}]' --output json

echo "Added rule to expose port 9090 to the world on the NSG."

echo "Script completed successfully."
