# Dog Trailer Monitor
This is a solution for monitoring a dog in a car trailer.

# Components

# Installation

## Raspberry Pi OS

1. Update Raspberry PI OS:
```
> sudo apt update && sudo apt full-upgrade -y
```

## Access Point

1. Check if the interface supports AP (Access Point) mode
```
> nmcli -f WIFI-PROPERTIES device show wlan0
```

2. Adjusting the NetworkManager configuration
```
> sudo nano /etc/NetworkManager/NetworkManager.conf
```

```
[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=false

[device]
wifi.scan-rand-mac-address=no
```