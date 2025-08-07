#!/bin/vbash
source /opt/vyatta/etc/functions/script-template

# Prompt the user for input 
runBashPrompt() {
    read -p "Enter Virtual Tunnel IP address: " VTI_IP
    read -p "Enter Local Identity: " LOCAL_ID
    read -p "Enter Remote Identity: " REMOTE_ID
    read -p "Enter PSK Secret: " PSK_SECRET
    read -p "Enter Service IP (used for protocol services): " SERVICE_IP
    read -p "Enter Cloud Service IP address: " CLOUD_IP
    read -p "Enter Primary Neighbor IP: " PRIMARY_IP
    read -p "Enter Secondary Neighbor IP: " SECONDARY_IP
    read -p "Do you want to configure Static or Dynamic (BGP) routing? [static/dynamic]: " ROUTING_TYPE

    if [[ "$ROUTING_TYPE" == "dynamic" ]]; then
        read -p "Enter VyOS AS number: " VYOS_AS
        read -p "Enter Infoblox AS number: " INFOBLOX_AS
    fi

    export VTI_IP LOCAL_ID PSK_SECRET SERVICE_IP CLOUD_IP PRIMARY_IP SECONDARY_IP ROUTING_TYPE VYOS_AS INFOBLOX_AS REMOTE_ID
}

runBashPrompt

configure

# IPsec tunnel and authentication setup
set interfaces vti vti0 address "${VTI_IP}/32"
set vpn ipsec authentication psk niosxaas-identity id "$LOCAL_ID"
set vpn ipsec authentication psk niosxaas-identity secret "$PSK_SECRET"

# IKE group configuration
set vpn ipsec ike-group niosxaas-ike proposal 1 dh-group 14
set vpn ipsec ike-group niosxaas-ike proposal 1 encryption aes256gcm128
set vpn ipsec ike-group niosxaas-ike proposal 1 hash sha256
set vpn ipsec ike-group niosxaas-ike proposal 1 prf prfsha256
set vpn ipsec ike-group niosxaas-ike key-exchange ikev2

# ESP group configuration
set vpn ipsec esp-group niosxaas-esp proposal 1 encryption aes256gcm128
set vpn ipsec esp-group niosxaas-esp proposal 1 hash sha256

# IPsec system config
set vpn ipsec interface vti0
set vpn ipsec interface eth0
set vpn ipsec log level 2
set vpn ipsec options disable-route-autoinstall

# Site-to-site peer config
set vpn ipsec site-to-site peer niosxaas-s2s authentication local-id "$LOCAL_ID"
set vpn ipsec site-to-site peer niosxaas-s2s authentication mode pre-shared-secret
set vpn ipsec site-to-site peer niosxaas-s2s authentication remote-id "$REMOTE_ID"
set vpn ipsec site-to-site peer niosxaas-s2s connection-type initiate
set vpn ipsec site-to-site peer niosxaas-s2s default-esp-group niosxaas-esp
set vpn ipsec site-to-site peer niosxaas-s2s ike-group niosxaas-ike
set vpn ipsec site-to-site peer niosxaas-s2s ikev2-reauth inherit
set vpn ipsec site-to-site peer niosxaas-s2s local-address any
set vpn ipsec site-to-site peer niosxaas-s2s remote-address "$CLOUD_IP"
set vpn ipsec site-to-site peer niosxaas-s2s tunnel 1 local prefix 0.0.0.0/0
set vpn ipsec site-to-site peer niosxaas-s2s tunnel 1 remote prefix 0.0.0.0/0

# VTI binding
set vpn ipsec site-to-site peer niosxaas-s2s vti bind vti0
set vpn ipsec site-to-site peer niosxaas-s2s vti esp-group niosxaas-esp

# Routing configuration
if [[ "$ROUTING_TYPE" == "static" ]]; then
    echo "Configuring static routes..."
    set protocols static route "${SERVICE_IP}/32" interface vti0
    set protocols static route "${PRIMARY_IP}/32" interface vti0

elif [[ "$ROUTING_TYPE" == "dynamic" ]]; then
    echo "Configuring dynamic BGP routing..."
    set protocols bgp system-as "$VYOS_AS"
    set protocols bgp timers holdtime 90
    set protocols bgp timers keepalive 30
    set protocols bgp address-family ipv4-unicast network 192.168.0.0/16
    set protocols bgp address-family ipv4-unicast network 172.17.0.0/16
    set protocols bgp address-family ipv4-unicast network 10.0.0.0/8
    set protocols bgp neighbor "$PRIMARY_IP" address-family ipv4-unicast
    set protocols bgp neighbor "$PRIMARY_IP" remote-as "$INFOBLOX_AS"
    set protocols bgp neighbor "$PRIMARY_IP" update-source "$VTI_IP"
    set protocols bgp neighbor "$SECONDARY_IP" address-family ipv4-unicast
    set protocols bgp neighbor "$SECONDARY_IP" remote-as "$INFOBLOX_AS"
    set protocols bgp neighbor "$SECONDARY_IP" update-source "$VTI_IP"
    set protocols bgp neighbor "$PRIMARY_IP" ebgp-multihop 2
    set protocols bgp parameters router-id "$VTI_IP"
    set protocols static route "${PRIMARY_IP}/32" interface vti0
else
    echo "Invalid routing type specified. Skipping routing configuration."
fi

commit
save
exit
