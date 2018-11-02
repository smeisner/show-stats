#!/bin/bash

scriptfile=/usr/local/bin/show-stats.sh
svcfile=/etc/systemd/system/show-stats.service

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

if [ "$1" == "clean" ]; then
  mdmmgr=`grep "#mdmmgr" $scriptfile | cut -d' ' -f2`
  svc=`systemctl is-active show-stats`
  if [ "$svc" = "active" ]; then
    echo Stopping show-stats service...
    systemctl stop show-stats
  fi
  echo Removing generated files...
  rm -f $svcfile
  rm -f $scriptfile
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

if [ -f $svcfile ]; then
  echo $svcfile file exists -- Exiting
  exit
fi

if [ -f $scriptfile ]; then
  echo $scriptfile file exists -- Exiting
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
echo Service ModemManager is $mdmmgr

echo Generating service file...
cat > $svcfile <<EOF
[Unit]
Description=Monitor ODROID XU4 stats
BindsTo=dev-ttyACM0.device

[Service]
Type=simple
ExecStart=$scriptfile
EOF


echo Generating show-stats script...
cat > $scriptfile <<\EOF
#!/bin/bash

eth=eth
wlan=wlan

if [ -f /etc/redhat-release ]; then
  eth=enp
  wlan=wlp
fi

sleep 1

# clear screen
printf '\xFE\x58' > /dev/ttyACM0 
# background color
printf '\xFE\xD0\xFF\x80\xFF' > /dev/ttyACM0

loop=0
while [ -c /dev/ttyACM0 ]; do
  while [ $loop -lt 9 ]; do
    # Position cursor at 1st line
    printf '\xFE\x47\x1\x1' > /dev/ttyACM0
    if [ $(( $loop % 3)) -eq 0 ];then
      echo `hostname` > /dev/ttyACM0
    else
      ip=`echo $(ip -o -4 a | grep $eth | awk '{ gsub(/\/.*/, "", $4); print $4 }')`
      if [ "$ip" = "" ]; then
        ip=`echo $(ip -o -4 a | grep $wlan | awk '{ gsub(/\/.*/, "", $4); print $4 }')`
      fi
      echo $ip  > /dev/ttyACM0
    fi
    # Position cursor at 2nd line
    printf '\xFE\x47\x1\x2' > /dev/ttyACM0
    # Gather CPU activity for the past 2 seconds
    top -b -n2 | grep "Cpu(s)" | awk '{print "CPU: " $2+$4 "%  "}' | tail -n1 > /dev/ttyACM0
    sleep 2
    let loop+=1
  done
  let loop=0
done

EOF


# Leave marker for ModemManager
echo "#mdmmgr $mdmmgr" >> $scriptfile

echo Generating udev rules...
sysctl=`which systemctl`
cat > /etc/udev/rules.d/10-local.rules <<EOF
SUBSYSTEMS=="usb", ACTION=="add", ATTRS{product}=="Adafruit Industries", GROUP="users", RUN+="${sysctl} --no-block start show-stats.service"
EOF

cat > /etc/udev/rules.d/99-ttyacms.rules <<EOF
ATTRS{idVendor}=="239a" ATTRS{idProduct}=="0001", ENV{ID_MM_DEVICE_IGNORE}="1"
EOF


chmod +x $scriptfile

if [ "$mdmmgr" = "enabled" ]; then
  echo Disabling ModemManager service...
  systemctl disable ModemManager
fi

echo Reloading systemctl and udev rules...
systemctl daemon-reload
udevadm control --reload

