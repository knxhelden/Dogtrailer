# 🐶 Dog Trailer Monitor

A lightweight Raspberry Pi-based monitoring solution for dogs inside a car trailer – featuring live video, GPIO control, and local access point functionality.

---

## 🔧 Hardware

- Raspberry Pi Zero 2 W  
- NoIR Camera for Raspberry Pi Zero  
- 2-Channel Relay Module  
- LM2596S Step-down Converter  
- Custom case with mounting hardware  
- Cable grommet for external wiring  

---

## ⚡ Circuit & Wiring

![Dog_Trailer_Breadboard](https://github.com/user-attachments/assets/2f722542-6e5a-446f-82ca-80c806fdb9cd)

---

## 📦 Installation Guide

### 📥 Raspberry Pi OS (64-bit, Bookworm)

1. Flash **Raspberry Pi OS Bookworm (64-bit)** to a microSD card using the [Raspberry Pi Imager](https://www.raspberrypi.com/software/).
2. Insert the card into the Raspberry Pi Zero 2 W and power it on.
3. Connect the Pi to a Wi-Fi network (via GUI, `nmtui`, or `nmcli`).
4. Update the system packages:
   ```bash
   sudo apt update && sudo apt full-upgrade -y
   ```

✅ Your base system is now ready.

## Access Point

1. Check if the interface supports AP (Access Point) mode:
```
nmcli -f WIFI-PROPERTIES device show wlan0
```

The result should be `WIFI-PROPERTIES.AP: yes`.

2. A new configuration for an access point is added via the Network Manager:
```
nmcli dev wifi hotspot ifname wlan0 con-name Hotspot ssid "Dogtrailer" band bg channel 3 password "dogtrailer"
```

If an error occurs, it is possible that the Network Manager is not managing the WLAN interface or that it is blocked.
```
nmcli device status
```

If `wlan0` says `disconnected` or `unavailable` check if wlan0 is blocked or turned off:

```
shutdown
rfkill list wlan
```

If the result is `Soft blocked: yes` or `Hard blocked: yes`, then:

```
sudo rfkill unblock wifi
nmcli radio wifi on
```

Now you can try to add a connection again.

3. The access point is now available, but it still needs to be configured as a mini router (NAT + DHCP server):

```
nmcli connection modify Hotspot ipv4.method shared ipv4.addresses 192.168.1.1/24 ipv4.gateway 192.168.1.1
```

4. After configuration, the `network-manager` service is restarted and the `Hotspot` connection is activated:

```
sudo service network-manager restart
sudo nmcli connection up Hotspot
nmcli connection show
```

## Webserver

1. First, Python including the package manager and web framework must be installed:

```
sudo apt update
sudo apt install python3 python3-pip python3-flask
```