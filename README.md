# Dog Trailer Monitor
This is a solution for monitoring a dog in a car trailer.

# Components

- Raspberry Pi Zero 2 W
- Raspberry Pi Zero Camera
- 2 Relay Module
- LM2596S Step-down Converter

# Circuit & Wiring

![Dog_Trailer_Breadboard](https://github.com/user-attachments/assets/2f722542-6e5a-446f-82ca-80c806fdb9cd)

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
