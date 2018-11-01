#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

if [ "$1" == "clean" ]; then
  mdmmgr=`grep "#mdmmgr" /usr/local/bin/show-stats.sh | cut -d' '-f2`
  echo Removing generated files...
  rm -f /etc/systemd/system/show-stats.service
  rm -f /usr/local/bin/show-stats.sh
  rm -f /etc/udev/rules.d/10-local.rules
  rm -f /etc/udev/rules.d/99-ttyacms.rules
  if [ "$mdmmgr" = "enabled" ]; then
    echo Enabling ModemManager service...
    systemctl enable ModemManager
  fi
  echo Reloading systemctl and udev rules...
  systemctl daemon-reload
  udevadm control --reload
  exit
fi

if [ -f /etc/systemd/system/show-stats.service ]; then
  echo /etc/systemd/system/show-stats.service file exists -- Exiting
  exit
fi

if [ -f /usr/local/bin/show-stats.sh ]; then
  echo /usr/local/bin/show-stats.sh file exists -- Exiting
  exit
fi

if [ -f /etc/udev/rules.d/10-local.rules ]; then
  echo /etc/udev/rules.d/10-local.rules file exists -- Exiting
  exit
fi

if [ -f /etc/udev/rules.d/99-ttyacms.rules ]; then
  echo /etc/udev/rules.d/99-ttyacms.rules file exists -- Exiting
  exit
fi

# Check if ModemManager is enabled
mdmmgr=`systemctl is-enabled ModemManager`

echo Generating service file...
cat > /etc/systemd/system/show-stats.service <<EOF
[Unit]
Description=Monitor ODROID XU4 stats
BindsTo=dev-ttyACM0.device

[Service]
Type=simple
ExecStart=/usr/local/bin/show-stats.sh
EOF


echo Generating show-stats script...
cat > /usr/local/bin/show-stats.sh <<\EOF
#!/bin/bash

eth=eth
wlan=wlan

if [ -f /etc/redhat-release ]; then
  eth=enp
  wlan=wlp
fi

sleep 1

#echo $(hostname -I) > /dev/ttyACM0

# clear screen
printf '\xFE\x58' > /dev/ttyACM0 
# background color
printf '\xFE\xD0\xFF\x80\xFF' > /dev/ttyACM0

ip=`echo $(ip -o -4 a | grep $eth | awk '{ gsub(/\/.*/, "", $4); print $4 }')`
if [ "$ip" = "" ]; then
  ip=`echo $(ip -o -4 a | grep $wlan | awk '{ gsub(/\/.*/, "", $4); print $4 }')`
fi

echo $ip  > /dev/ttyACM0

while [ -c /dev/ttyACM0 ]; do
# Position cursor at 2nd line
  printf '\xFE\x47\x1\x2' > /dev/ttyACM0
# Gather CPU activity for the past 2 seconds
  top -b -n2 | grep "Cpu(s)" | awk '{print "CPU: " $2+$4 "%  "}' | tail -n1 > /dev/ttyACM0
  sleep 2
done

#mdmmgr $mdmmgr
EOF



echo Generating udev rules...
sysctl=`which systemctl`
cat > /etc/udev/rules.d/10-local.rules <<EOF
SUBSYSTEMS=="usb", ACTION=="add", ATTRS{product}=="Adafruit Industries", GROUP="users", RUN+="${sysctl} --no-block start show-stats.service"
EOF

cat > /etc/udev/rules.d/99-ttyacms.rules <<EOF
ATTRS{idVendor}=="239a" ATTRS{idProduct}=="0001", ENV{ID_MM_DEVICE_IGNORE}="1"
EOF


chmod +x /usr/local/bin/show-stats.sh

if [ "$mdmmgr" = "enabled" ]; then
  echo Disabling ModemManager service...
  systemctl disable ModemManager
fi

echo Reloading systemctl and udev rules...
systemctl daemon-reload
udevadm control --reload

