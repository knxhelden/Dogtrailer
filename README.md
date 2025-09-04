# 🐶 Dog Trailer Monitor

A lightweight **Raspberry Pi Zero 2 W**–based monitoring solution for dogs inside a car trailer.  
It provides **live video streaming**, **GPIO relay control** (e.g., for fans or lights), and a built-in **Wi-Fi access point** for local connectivity – even when no external network is available.


## 🔧 Hardware

The system was designed to run with minimal hardware while remaining robust in outdoor/automotive environments:

- **Raspberry Pi Zero 2 W**  
- **NoIR Camera** (for day/night video)  
- **2-Channel Relay Module** (for controlling fans, lights, etc.)  
- **LM2596S Step-down Converter** (12V → 5V power supply)  
- **Custom enclosure** with mounting hardware  
- **Cable grommet** for safe external wiring   


## ⚡ Circuit & Wiring

The following diagram shows the wiring of the Raspberry Pi, relays, and power supply:  

![Dog_Trailer_Breadboard](https://github.com/user-attachments/assets/2f722542-6e5a-446f-82ca-80c806fdb9cd)


## 📦 Installation Guide

### 📥 Raspberry Pi OS (64-bit, Bookworm)

1. Flash **Raspberry Pi OS Bookworm (64-bit)** to a microSD card using the [Raspberry Pi Imager](https://www.raspberrypi.com/software/).
2. Insert the card into the Raspberry Pi Zero 2 W and power it on.
3. Connect the Pi to Wi-Fi (via desktop GUI, `nmtui`, or `nmcli`).  
4. Update all system packages:  

   ```bash
   sudo apt update && sudo apt full-upgrade -y
   ```

✅ Your base system is now ready.

---

### 🌐 Install Dogtrailer Webapp and Access Point

1. Copy the provided **install.sh** script to your Raspberry Pi (e.g., via **SFTP**).

2. Run the installation script with root permissions:

```bash
sudo bash install.sh
```

The script will:

- Install all required dependencies
- Set up a Python virtual environment
- Deploy the Dog Trailer Monitor webserver
- Configure a Wi-Fi access point for direct connectivity (SSID and password defined in `.env`)

Once installation is complete, the webserver will automatically start on boot.


## ▶️ Usage

- Open a browser and connect to the Pi’s Access Point or local IP address: **http://<RASPBERRY-IP>:5000**

You will have access to:

- Live video stream from the Pi camera
- Relay controls (e.g., switch fans/lights)
- Status page with system information


## 📡 Access Point Management

The installer sets up a **Hotspot profile** called `Hotspot` in **NetworkManager**.  
For security reasons it is **not activated automatically during installation**, but it is configured for autostart after reboot once it has been activated at least once.

Run this once (locally or via SSH) for a one-time activation:

```bash
sudo nmcli connection up Hotspot
```
⚠️ **If you are connected via Wi-Fi/SSH, the connection may drop** because `wlan0` will be reconfigured.

After this, the access point will automatically start on every reboot.
Clients can connect to the SSID:
- **SSID:** `Dogtrailer`
- **Password:** `dogtrailer`
- **Gateway/IP of the Pi:** `192.168.1.1`

You can then open the web interface under: `http://192.168.1.1:5000`

Useful commands for **NetworkManager** profiles:

- Show all connections: `nmcli connection show`
- Show active connections: `nmcli connection show --active`
- Stop the access point manually: `sudo nmcli connection down Hotspot`


## 🐞 Debugging & Development

- Check service logs:
```bash
journalctl -u dogtrailer -f
```

- Restart the service:
```bash
sudo systemctl restart dogtrailer
```