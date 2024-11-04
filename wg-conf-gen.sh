#!/bin/bash

# Convert IP address to integer
ip_to_int() {
    local ip=$1
    local a b c d
    IFS=. read -r a b c d <<< "$ip"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

# Convert integer to IP address
int_to_ip() {
    local int=$1
    echo "$(( (int >> 24) & 255 )).$(( (int >> 16) & 255 )).$(( (int >> 8) & 255 )).$(( int & 255 ))"
}

# Check if the correct number of arguments are provided
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <Name> <Server Port> <Server IP> <Starting Peer IP> <netmask> <step> <Number of Peers> <AllowedIPs of Peers>"
    echo "Example: $0 wg1 18201 10.182.255.254/24 10.182.255.0 28 16 16 10.182.255.0/24"
    exit 1
fi

# Read arguments
CONF_DIR=$1                       # Peer configuration folder
WG_CONF="${CONF_DIR}/${1}.conf"   # Server configuration file path
SERVER_PORT=$2                    # Server listening port
SERVER_IP=$3                      # Server IP address
STARTING_PEER_IP=$4               # Starting Peer IP address
PEER_IP_NETMASK=$5
PEER_IP_STEP=$6
PEER_COUNT=$7                     # Number of Peers
PeerAllowedIPs=$8                 # AllowedIPs of Peers
DNS_SERVERS="8.8.4.4, 8.8.8.8"    # Default DNS servers

# Fetch the public IP address of the server
PUBLIC_IP=$(curl -s ip.sb)

# Check if the public IP was successfully fetched
if [ -z "$PUBLIC_IP" ]; then
    echo "Failed to retrieve public IP. Please check your internet connection."
    exit 1
fi

# Create Peer configuration folder
mkdir -p $CONF_DIR

# Generate server private and public keys
SERVER_PRIVATE_KEY=$(wg genkey)
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)

# Create server configuration file and add basic server configuration
cat > $WG_CONF <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $SERVER_IP
ListenPort = $SERVER_PORT
# DNS = $DNS_SERVERS
# PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.0/8 -j MASQUERADE
# PostDown = iptables -t nat -D POSTROUTING -s 10.0.0.0/8 -j MASQUERADE

EOF

# Convert starting IP to an integer
STARTING_IP_INT=$(ip_to_int "$STARTING_PEER_IP")

# Generate configurations for the specified number of Peers
for ((i=0; i<PEER_COUNT; i=i+PEER_IP_STEP)); do
    PEER_PRIVATE_KEY=$(wg genkey)
    PEER_PUBLIC_KEY=$(echo "$PEER_PRIVATE_KEY" | wg pubkey)

    # Calculate current Peer IP address
    CURRENT_IP_INT=$((STARTING_IP_INT + i))
    PEER_IP=$(int_to_ip "$CURRENT_IP_INT")
    
    # Add Peer to server configuration
    cat >> $WG_CONF <<EOF

[Peer]
# Peer $((i + 1)) configuration
PublicKey = $PEER_PUBLIC_KEY
AllowedIPs = $PEER_IP/$PEER_IP_NETMASK
EOF

    # Create individual configuration file for each Peer with the naming convention
    PEER_CONF="${CONF_DIR}/wg_peer-${PEER_IP//./_}.conf"
    cat > $PEER_CONF <<EOF
[Interface]
PrivateKey = $PEER_PRIVATE_KEY
Address = $PEER_IP/32
DNS = $DNS_SERVERS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $PUBLIC_IP:$SERVER_PORT
AllowedIPs = $PeerAllowedIPs
EOF

    echo "Generated configuration file for Peer $((i + 1)): $PEER_CONF"
done

echo "Server configuration file $WG_CONF and client configuration files have been generated."
