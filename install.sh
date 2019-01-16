#!/bin/bash

# Make installer interactive and select normal mode by default.
INTERACTIVE="y"
ADVANCED="n"
BOOTSTRAP="y"

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -a|--advanced)
    ADVANCED="y"
    shift
    ;;
    -n|--normal)
    ADVANCED="n"
    FAIL2BAN="y"
    UFW="y"
    BOOTSTRAP="y"
    shift
    ;;
    -i|--externalip)
    EXTERNALIP="$2"
    ARGUMENTIP="y"
    shift
    shift
    ;;
    --bindip)
    BINDIP="$2"
    shift
    shift
    ;;
    -k|--privatekey)
    KEY="$2"
    shift
    shift
    ;;
    -f|--fail2ban)
    FAIL2BAN="y"
    shift
    ;;
    --no-fail2ban)
    FAIL2BAN="n"
    shift
    ;;
    -u|--ufw)
    UFW="y"
    shift
    ;;
    --no-ufw)
    UFW="n"
    shift
    ;;
    --no-interaction)
    INTERACTIVE="n"
    shift
    ;;
    --tor)
    TOR="y"
    shift
    ;;
    -h|--help)
    cat << EOL

Vulcano Masternode installer arguments:

    -n --normal               : Run installer in normal mode
    -a --advanced             : Run installer in advanced mode
    -i --externalip <address> : Public IP address of VPS
    --bindip <address>        : Internal bind IP to use
    -k --privatekey <key>     : Private key to use
    -f --fail2ban             : Install Fail2Ban
    --no-fail2ban             : Don't install Fail2Ban
    -u --ufw                  : Install UFW
    --no-ufw                  : Don't install UFW
    -h --help                 : Display this help text.
    --no-interaction          : Do not wait for wallet activation.
    --tor                     : Install TOR and configure vulcanod to use it

EOL
    exit
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

clear

# Make sure curl is installed
apt -qqy install curl
clear

# These should automatically find the latest version of Vulcano

TARBALLURL=`curl -Ls https://api.github.com/repos/VulcanoCrypto/Vulcano/releases/latest | grep browser_download_url | grep linux64 | cut -d '"' -f 4`
TARBALLNAME=`curl -Ls https://api.github.com/repos/VulcanoCrypto/Vulcano/releases/latest | grep browser_download_url | grep linux64 | cut -d '"' -f 4 | cut -d '/' -f 9`
VULCVERSION=`curl -Ls https://api.github.com/repos/VulcanoCrypto/Vulcano/releases/latest | grep browser_download_url | grep linux64 | cut -d '"' -f 4 | cut -d '/' -f 9 | cut -d '-' -f 2`
BOOTSTRAPURL=`curl -Ls https://api.github.com/repos/VulcanoCrypto/Vulcano/releases/latest | grep bootstrap.dat.xz | grep browser_download_url | cut -d '"' -f 4`
BOOTSTRAPARCHIVE="bootstrap.dat.xz"

#!/bin/bash

# Check if we are root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root." 1>&2
   exit 1
fi

# Check if we have enough memory
if [[ `free -m | awk '/^Mem:/{print $2}'` -lt 850 ]]; then
  echo "This installation requires at least 1GB of RAM.";
  exit 1
fi

# Check if we have enough disk space
if [[ `df -k --output=avail / | tail -n1` -lt 10485760 ]]; then
  echo "This installation requires at least 10GB of free disk space.";
  exit 1
fi

# Install tools for dig and systemctl
echo "Preparing installation..."
apt-get install git dnsutils systemd -y > /dev/null 2>&1

# Check for systemd
systemctl --version >/dev/null 2>&1 || { echo "systemd is required. Are you using Ubuntu 16.04?"  >&2; exit 1; }

# Get our current IP
IPV4=$(dig +short myip.opendns.com @resolver1.opendns.com)
IPV6=$(dig +short -6 myip.opendns.com aaaa @resolver1.ipv6-sandbox.opendns.com)
if [ -z "$EXTERNALIP" ]; then
  if [ -n "$IPV4" ]; then
    EXTERNALIP="$IPV4"
  else
    EXTERNALIP="$IPV6"
  fi
fi
clear

if [[ $INTERACTIVE = "y" ]]; then
echo "

  --------------- VULCANO INSTALLER  ---------------+
 |                                                  |
 |   Welcome to the Vulcano Masternode Installer!   |::
 |                                                  |::
 +------------------------------------------------+::
   ::::::::::::::::::::::::::::::::::::::::::::::::::

"

sleep 3
fi

if [[ ("$ADVANCED" == "y" || "$ADVANCED" == "Y") ]]; then

USER=vulcano

adduser $USER --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password > /dev/null

INSTALLERUSED="#Used Advanced Install"

echo "" && echo 'Added user "vulcano"' && echo ""
sleep 1

else

USER=root

if [ -z "$FAIL2BAN" ]; then
  FAIL2BAN="y"
fi
if [ -z "$UFW" ]; then
  UFW="y"
fi
INSTALLERUSED="#Used Basic Install"
fi

USERHOME=`eval echo "~$USER"`

if [ -z "$ARGUMENTIP" ]; then
  read -e -p "Server IP Address: " -i $EXTERNALIP -e EXTERNALIP
fi

if [ -z "$BINDIP" ]; then
    BINDIP=$EXTERNALIP;
fi

if [ -z "$KEY" ]; then
  read -e -p "Masternode Private Key (e.g. 7edfjLCUzGczZi3JQw8GHp434R9kNY33eFyMGeKRymkB56G4324h # THE KEY YOU GENERATED EARLIER) : " KEY
fi

if [ -z "$FAIL2BAN" ]; then
  read -e -p "Install Fail2ban? [Y/n] : " FAIL2BAN
fi

if [ -z "$UFW" ]; then
  read -e -p "Install UFW and configure ports? [Y/n] : " UFW
fi

if [ -z "$BOOTSTRAP" ]; then
  read -e -p "Do you want to use our bootstrap file to speed the syncing process? [Y/n] : " BOOTSTRAP
fi

clear

# Generate random passwords
RPCUSER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
RPCPASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

# update packages and upgrade Ubuntu
echo "Installing dependencies..."
apt-get -qq update
apt-get -qq upgrade
apt-get -qq autoremove
apt-get -qq install wget htop xz-utils
apt-get -qq install build-essential && apt-get -qq install libtool autotools-dev autoconf automake && apt-get -qq install libssl-dev && apt-get -qq install libboost-all-dev && apt-get -qq install software-properties-common && add-apt-repository -y ppa:bitcoin/bitcoin && apt update && apt-get -qq install libdb4.8-dev && apt-get -qq install libdb4.8++-dev && apt-get -qq install libminiupnpc-dev && apt-get -qq install libqt4-dev libprotobuf-dev protobuf-compiler && apt-get -qq install libqrencode-dev && apt-get -qq install git && apt-get -qq install pkg-config && apt-get -qq install libzmq3-dev
apt-get -qq install aptitude

# Install Fail2Ban
if [[ ("$FAIL2BAN" == "y" || "$FAIL2BAN" == "Y" || "$FAIL2BAN" == "") ]]; then
  aptitude -y -q install fail2ban
  # Reduce Fail2Ban memory usage - http://hacksnsnacks.com/snippets/reduce-fail2ban-memory-usage/
  echo "ulimit -s 256" | sudo tee -a /etc/default/fail2ban
  service fail2ban restart
fi

# Install UFW
if [[ ("$UFW" == "y" || "$UFW" == "Y" || "$UFW" == "") ]]; then
  apt-get -qq install ufw
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw allow 62543/tcp
  yes | ufw enable
fi

# Install TOR
if [[ ("$TOR" == "y" || "$TOR" == "Y") ]]; then
  echo "Installing TOR..."
  apt-get -qq install tor
cat >> /etc/tor/torrc << EOL

### VULCANO CONFIGURATION ###
HiddenServiceDir /var/lib/tor/hidden_service/
ClientOnly 1
ControlPort 9051
NumEntryGuards 4
NumDirectoryGuards 3
GuardLifetime 2764800
GeoIPExcludeUnknown 1
EntryNodes 31.185.104.19/32,31.185.104.20/31,46.182.106.190/32,51.15.13.245/32,51.15.43.232/32,51.15.44.197/32,51.15.45.97/32,51.15.46.49/32,51.15.50.133/32,51.15.57.177/32,51.15.57.79/32,51.15.60.255/32,51.15.60.62/32,62.102.148.67/32,62.138.7.171/32,77.109.139.87/32,78.142.140.242/32,80.67.172.162/32,81.7.10.29/32,82.94.251.227/32,85.248.227.163/32,85.248.227.164/31,86.59.119.83/32,86.59.119.88/32,89.234.157.254/32,91.121.23.100/32,94.140.120.44/32,94.242.246.23/32,94.242.246.24/32,94.252.114.48/32,95.142.161.63/32,134.119.3.164/32,171.25.193.20/32,171.25.193.25/32,171.25.193.77/32,171.25.193.78/32,176.10.104.240/32,176.10.104.243/32,176.126.252.11/32,176.126.252.12/32,178.16.208.55/32,178.16.208.56/30,178.16.208.60/31,178.16.208.62/32,178.20.55.16/32,178.20.55.18/32,178.209.42.84/32,185.100.84.82/32,185.100.86.100/32,185.34.33.2/32,185.86.149.75/32,188.118.198.244/32,192.36.27.4/32,192.36.27.6/31,192.42.116.16/32,212.51.156.78/32
ExitNodes 31.185.104.19/32,31.185.104.20/31,46.182.106.190/32,51.15.43.232/32,51.15.44.197/32,51.15.45.97/32,51.15.46.49/32,51.15.50.133/32,51.15.57.177/32,51.15.57.79/32,51.15.60.255/32,51.15.60.62/32,62.102.148.67/32,77.109.139.87/32,80.67.172.162/32,85.248.227.163/32,85.248.227.164/31,89.234.157.254/32,94.242.246.23/32,94.242.246.24/32,95.142.161.63/32,171.25.193.20/32,171.25.193.25/32,171.25.193.77/32,171.25.193.78/32,176.10.104.240/32,176.10.104.243/32,176.126.252.11/32,176.126.252.12/32,178.20.55.16/32,178.20.55.18/32,178.209.42.84/32,185.100.84.82/32,185.100.86.100/32,185.34.33.2/32,192.36.27.4/32,192.36.27.6/31,192.42.116.16/32,212.16.104.33/32
ExcludeNodes default,Unnamed,{ae},{af},{ag},{ao},{az},{ba},{bb},{bd},{bh},{bi},{bn},{bt},{bw},{by},{cd},{cf},{cg},{ci},{ck},{cm},{cn},{cu},{cy},{dj},{dm},{dz},{eg},{er},{et},{fj},{ga},{gd},{gh},{gm},{gn},{gq},{gy},{hr},{ht},{id},{in},{iq},{ir},{jm},{jo},{ke},{kg},{kh},{ki},{km},{kn},{kp},{kw},{kz},{la},{lb},{lc},{lk},{lr},{ly},{ma},{me},{mk},{ml},{mm},{mr},{mu},{mv},{mw},{my},{na},{ng},{om},{pg},{ph},{pk},{ps},{qa},{rs},{ru},{rw},{sa},{sb},{sd},{sg},{si},{sl},{sn},{so},{st},{sy},{sz},{td},{tg},{th},{tj},{tm},{tn},{to},{tr},{tt},{tv},{tz},{ug},{uz},{vc},{ve},{vn},{ws},{ye},{zm},{zw},{??}
ExcludeExitNodes default,Unnamed,{ae},{af},{ag},{ao},{az},{ba},{bb},{bd},{bh},{bi},{bn},{bt},{bw},{by},{cd},{cf},{cg},{ci},{ck},{cm},{cn},{cu},{cy},{dj},{dm},{dz},{eg},{er},{et},{fj},{ga},{gd},{gh},{gm},{gn},{gq},{gy},{hr},{ht},{id},{in},{iq},{ir},{jm},{jo},{ke},{kg},{kh},{ki},{km},{kn},{kp},{kw},{kz},{la},{lb},{lc},{lk},{lr},{ly},{ma},{me},{mk},{ml},{mm},{mr},{mu},{mv},{mw},{my},{na},{ng},{om},{pg},{ph},{pk},{ps},{qa},{rs},{ru},{rw},{sa},{sb},{sd},{sg},{si},{sl},{sn},{so},{st},{sy},{sz},{td},{tg},{th},{tj},{tm},{tn},{to},{tr},{tt},{tv},{tz},{ug},{uz},{vc},{ve},{vn},{ws},{ye},{zm},{zw},{??}
HiddenServiceDir /var/lib/tor/hidden_service/
HiddenServicePort 62543 127.0.0.1:62543
HiddenServicePort 80 127.0.0.1:80
LongLivedPorts 80,62543
EOL
  /etc/init.d/tor stop
  sudo rm -R /var/lib/tor/hidden_service 2>/dev/null
  /etc/init.d/tor start
  echo "Starting TOR, please wait..."
  sleep 5 # Give tor enough time to connect before we continue
fi

# Install Vulcano daemon
wget $TARBALLURL
tar -xzvf $TARBALLNAME
rm $TARBALLNAME
mv ./vulcanod /usr/local/bin
mv ./vulcano-cli /usr/local/bin
mv ./vulcano-tx /usr/local/bin
rm ./vulcano-qt
rm -rf vulcano-$VULCVERSION

# Create .vulcanocore directory
mkdir $USERHOME/.vulcanocore

# Install bootstrap file
if [[ ("$BOOTSTRAP" == "y" || "$BOOTSTRAP" == "Y" || "$BOOTSTRAP" == "") ]]; then
  echo "Installing bootstrap file..."
  wget $BOOTSTRAPURL && xz -cd $BOOTSTRAPARCHIVE > $USERHOME/.vulcanocore/bootstrap.dat && rm $BOOTSTRAPARCHIVE
fi

# Install peers.dat - Can be removed after seeder issue is resolved
wget https://github.com/VulcanoCrypto/Vulcano/releases/download/v2.0.0.0/peers.dat.xz && xz -cd peers.dat.xz > $USERHOME/.vulcanocore/peers.dat && rm peers.dat.xz

# Create vulcano.conf
touch $USERHOME/.vulcanocore/vulcano.conf

# Set TORHOSTNAME if it exists.
if [[ -f /var/lib/tor/hidden_service/hostname ]]; then
  TORHOSTNAME=`cat /var/lib/tor/hidden_service/hostname`
fi

# We need a different conf for TOR support
if [[ ("$TOR" == "y" || "$TOR" == "Y") ]]; then

cat > $USERHOME/.vulcanocore/vulcano.conf << EOL
rpcuser=${RPCUSER}
rpcpassword=${RPCPASSWORD}
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
logtimestamps=1
maxconnections=256
onion=127.0.0.1:9050
onlynet=tor
bind=127.0.0.1
dnsseed=0
masternodeprivkey=${KEY}
masternode=1
externalip=${TORHOSTNAME}
addnode=138.201.245.247:62543
addnode=159.69.80.141:62543
addnode=159.69.84.71:62543
addnode=159.69.81.163:62543
addnode=159.69.83.104:62543
addnode=95.216.147.117:62543
addnode=95.216.148.73:62543
addnode=95.216.147.210:62543
addnode=159.69.49.144:62543
addnode=138.201.190.47:62543
addnode=138.201.175.10:62543
EOL

else

cat > $USERHOME/.vulcanocore/vulcano.conf << EOL
${INSTALLERUSED}
rpcuser=${RPCUSER}
rpcpassword=${RPCPASSWORD}
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
logtimestamps=1
maxconnections=256
externalip=${EXTERNALIP}
bind=[${BINDIP}]:62543
masternodeaddr=${EXTERNALIP}
masternodeprivkey=${KEY}
masternode=1
addnode=138.201.245.247:62543
addnode=159.69.80.141:62543
addnode=159.69.84.71:62543
addnode=159.69.81.163:62543
addnode=159.69.83.104:62543
addnode=95.216.147.117:62543
addnode=95.216.148.73:62543
addnode=95.216.147.210:62543
addnode=159.69.49.144:62543
addnode=138.201.190.47:62543
addnode=138.201.175.10:62543
EOL
fi
chmod 0600 $USERHOME/.vulcanocore/vulcano.conf
chown -R $USER:$USER $USERHOME/.vulcanocore

sleep 1

cat > /etc/systemd/system/vulcanod.service << EOL
[Unit]
Description=Vulcanos's distributed currency daemon
After=network.target
[Service]
Type=forking
User=${USER}
WorkingDirectory=${USERHOME}
ExecStart=/usr/local/bin/vulcanod -conf=${USERHOME}/.vulcanocore/vulcano.conf -datadir=${USERHOME}/.vulcanocore
ExecStop=/usr/local/bin/vulcano-cli -conf=${USERHOME}/.vulcanocore/vulcano.conf -datadir=${USERHOME}/.vulcanocore stop
Restart=on-failure
RestartSec=1m
StartLimitIntervalSec=5m
StartLimitInterval=5m
StartLimitBurst=3
[Install]
WantedBy=multi-user.target
EOL
systemctl enable vulcanod
echo "Starting vulcanod..."
systemctl start vulcanod

sleep 10

if ! systemctl status vulcanod | grep -q "active (running)"; then
  echo "ERROR: Failed to start vulcanod. Please contact support."
  exit
fi

echo "Waiting for wallet to load..."
until su -c "vulcano-cli getinfo 2>/dev/null | grep -q \"version\"" $USER; do
  sleep 1;
done

clear

echo "Your masternode is syncing. Please wait for this process to finish."
echo "This can take up to a few hours. Do not close this window."
if [[ ("$TOR" == "y" || "$TOR" == "Y") ]]; then
  echo "The TOR address of your masternode is: $TORHOSTNAME"
fi
echo ""

until su -c "vulcano-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null" $USER; do
  echo -ne "Current block: "`su -c "vulcano-cli getinfo" $USER | grep blocks | awk '{print $3}' | cut -d ',' -f 1`'\r'
  sleep 1
done

clear

cat << EOL

Now, you need to start your masternode. If you haven't already, please add this
node to your masternode.conf now, restart and unlock your desktop wallet, go to
the Masternodes tab, select your new node and click "Start Alias."

EOL


if [[ $INTERACTIVE = "y" ]]; then
  read -p "Press Enter to continue after you've done that. " -n1 -s
fi

clear

sleep 1
su -c "/usr/local/bin/vulcano-cli startmasternode local false" $USER
sleep 1
clear
su -c "/usr/local/bin/vulcano-cli masternode status" $USER
sleep 5

echo "" && echo "Masternode setup completed." && echo ""
