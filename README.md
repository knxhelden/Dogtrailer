# 🐶 Dog Trailer Monitor

A lightweight Raspberry Pi-based monitoring solution for dogs inside a car trailer – featuring live video, GPIO control, and local access point functionality.


## 🔧 Hardware

- Raspberry Pi Zero 2 W  
- NoIR Camera for Raspberry Pi Zero  
- 2-Channel Relay Module  
- LM2596S Step-down Converter  
- Custom case with mounting hardware  
- Cable grommet for external wiring  


## ⚡ Circuit & Wiring

![Dog_Trailer_Breadboard](https://github.com/user-attachments/assets/2f722542-6e5a-446f-82ca-80c806fdb9cd)


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

---

### 🌐 Install Python Webserver

#### 1. Install Python, pip, and Flask:

```bash
sudo apt update && sudo apt install python3 python3-pip python3-flask python3-picamera2 -y
```

✅ You can now run lightweight Flask-based web applications for monitoring and control.

#### 2. Install Adafruit libraries for GPIO + DHT22 sensor:
*(Bookworm blocks pip systemwide, deshalb mit `--break-system-packages`)*

```bash
pip3 install adafruit-blinka adafruit-circuitpython-dht --break-system-packages
```

#### 3. Create a directory for the dogtrailer web app:

```bash
mkdir webapp
```

#### 4. Copy the contents of the `webapp` folder from this repository into the newly created `webapp` directory.

#### 5. Start the app:

```bash
python3 app.py
```

#### 6. On any device connected to the access point, open your browser and visit:

```
http://192.168.1.1
```

You should see the Dog Trailer Monitor web interface.

---

### 📡 Configure Access Point (Hotspot)

#### 1. Check AP support

Ensure the wireless interface supports Access Point mode:

```bash
nmcli -f WIFI-PROPERTIES device show wlan0
```

Expected output:
```
WIFI-PROPERTIES.AP: yes
```


#### 2. Create hotspot via NetworkManager

```bash
nmcli dev wifi hotspot \
  ifname wlan0 \
  con-name Hotspot \
  ssid "Dogtrailer" \
  band bg \
  channel 3 \
  password "dogtrailer"
```


#### 3. Troubleshooting: WLAN interface unavailable

Check current device status:

```bash
nmcli device status
```

If `wlan0` is listed as `unavailable` or `disconnected`, check if it’s blocked:

```bash
rfkill list wlan
```

If it’s blocked:
```bash
sudo rfkill unblock wifi
nmcli radio wifi on
```

> 💡 If the issue persists, ensure `wlan0` is managed by NetworkManager:
> Open `/etc/NetworkManager/NetworkManager.conf` and add:
> ```ini
> [keyfile]
> unmanaged-devices=none
> ```
> Then restart the service:
> ```bash
> sudo systemctl restart NetworkManager
> ```


#### 4. Configure IP routing and NAT (mini-router)

To enable NAT and DHCP for clients connected to the access point:

```bash
nmcli connection modify Hotspot \
  ipv4.method shared \
  ipv4.addresses 192.168.137.2/24 \
  ipv4.gateway 192.168.137.1
```


#### 5. Restart NetworkManager and activate the hotspot

```bash
sudo service network-manager restart
sudo nmcli connection up Hotspot
nmcli connection show
```


#### 6. Enable automatic startup on boot

To make the access point start automatically after a reboot, enable autoconnect for the Hotspot:

```bash
nmcli connection modify Hotspot connection.autoconnect yes
```

After running this, the access point will be active shortly after each boot.
