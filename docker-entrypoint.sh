#!/bin/bash
# VERSION 0.2.3 by @d3vilh@github.com aka Mr. Philipp
set -e

# Variables
EASY_RSA=/usr/share/easy-rsa
OPENVPN_DIR=/etc/openvpn
echo "EasyRSA path: $EASY_RSA OVPN path: $OPENVPN_DIR"

if [[ ! -f $OPENVPN_DIR/pki/ca.crt ]]; then
    export EASYRSA_BATCH=1
    cd $EASY_RSA

    echo 'Setting up public key infrastructure...'
    $EASY_RSA/easyrsa init-pki

    cp $OPENVPN_DIR/config/easy-rsa.vars $EASY_RSA/pki/vars

    echo "Following EASYRSA variables will be used:"
    cat $EASY_RSA/pki/vars | awk '{$1=""; print $0}';

    echo 'Generating certificate authority...'
    $EASY_RSA/easyrsa build-ca nopass

    echo 'Creating the Server Certificate...'
    $EASY_RSA/easyrsa gen-req server nopass

    echo 'Sign request...'
    $EASY_RSA/easyrsa sign-req server server

    echo 'Generate Diffie-Hellman key...'
    $EASY_RSA/easyrsa gen-dh

    echo 'Generate HMAC signature...'
    openvpn --genkey --secret $EASY_RSA/pki/ta.key

    echo 'Create certificate revocation list (CRL)...'
    $EASY_RSA/easyrsa gen-crl
    chmod +r $EASY_RSA/pki/crl.pem

    cp -r $EASY_RSA/pki/. $OPENVPN_DIR/pki
else
    echo 'PKI already set up.'
fi

echo "Following EASYRSA variables were set during CA init:"
cat $OPENVPN_DIR/pki/vars | awk '{$1=""; print $0}';

# Configure network
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi

echo 'Configuring networking rules...'
if ! grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf; then
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
  echo 'IP forwarding configuration now applied:'
else
  echo 'IP forwarding configuration already applied:'
fi
sysctl -p /etc/sysctl.conf

echo 'Configuring iptables...'
echo 'NAT for OpenVPN clients'
iptables -t nat -A POSTROUTING -s $TRUST_SUB -o eth0 -j MASQUERADE
iptables -t nat -A POSTROUTING -s $GUEST_SUB -o eth0 -j MASQUERADE

echo 'Blocking ICMP for external clients'
iptables -A FORWARD -p icmp -j DROP --icmp-type echo-request -s $GUEST_SUB 
iptables -A FORWARD -p icmp -j DROP --icmp-type echo-reply -s $GUEST_SUB 

echo 'Blocking internal home subnet to access from external openvpn clients (Internet still available)'
iptables -A FORWARD -s $GUEST_SUB -d $HOME_SUB -j DROP

if [[ ! -s fw-rules.sh ]]; then
    echo "No additional firewall rules to apply."
else
    echo "Applying firewall rules"
    ./fw-rules.sh
    echo 'Additional firewall rules applied.'
fi

echo 'IPT MASQ Chains:'
iptables -t nat -L | grep MASQ
echo 'IPT FWD Chains:'
iptables -v -x -n -L | grep DROP 

### ✅ Inject subnet values from env into old-server.conf and/or server.conf
for CONF_FILE in "$OPENVPN_DIR/config/old-server.conf" "$OPENVPN_DIR/server.conf"; do
    if [ -f "$CONF_FILE" ]; then
        echo "Injecting subnets into $CONF_FILE"
        
        TRUST_BASE=$(echo "$TRUST_SUB" | cut -d'/' -f1)
        GUEST_BASE=$(echo "$GUEST_SUB" | cut -d'/' -f1)
        HOME_BASE=$(echo "$HOME_SUB" | cut -d'/' -f1)

        sed -i "s|^server .*|server ${TRUST_BASE} 255.255.255.0|" "$CONF_FILE"
        sed -i "s|^route .*|route ${GUEST_BASE} 255.255.255.0|" "$CONF_FILE"
        sed -i 's|^push "route .*|push "route '"${HOME_BASE}"' 255.255.255.0"|' "$CONF_FILE"

        echo "✅ Updated subnet lines in $CONF_FILE:"
        grep -E '^(server|route|push "route)' "$CONF_FILE"
    else
        echo "Skipping $CONF_FILE — file does not exist."
    fi
done

echo 'Start openvpn process...'
/usr/sbin/openvpn --cd $OPENVPN_DIR --script-security 2 --config $OPENVPN_DIR/server.conf
