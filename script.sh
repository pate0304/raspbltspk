#!/bin/bash

# Exit on any error
set -e

echo "Setting up Raspberry Pi as a Bluetooth speaker with Boss Allo DAC"

# Update and install required packages
echo "Updating system and installing required packages..."
apt-get update
apt-get install -y pulseaudio pulseaudio-module-bluetooth bluez-tools python3-dbus python3-gi

# Add user to bluetooth group
echo "Adding user to bluetooth group..."
usermod -a -G bluetooth pi

# Configure Bluetooth
echo "Configuring Bluetooth..."
cat << EOF >> /etc/bluetooth/main.conf
Class = 0x41C
DiscoverableTimeout = 0
EOF

# Restart Bluetooth service
systemctl restart bluetooth

# Enable PulseAudio to start on boot
su - pi -c "systemctl --user enable pulseaudio"

# Configure auto-login for pi user
raspi-config nonint do_boot_behaviour B2

# Configure Boss Allo DAC (you may need to adjust this based on your specific DAC model)
echo "dtoverlay=allo-boss-dac-pcm512x-audio" >> /boot/config.txt

# Create Bluetooth agent script
echo "Creating Bluetooth agent script..."
cat << 'EOF' > /home/pi/speaker-agent.py
import dbus
from gi.repository import GLib
from dbus.mainloop.glib import DBusGMainLoop
import dbus.service

BUS_NAME = 'org.bluez'
AGENT_PATH = "/test/agent"

def set_trusted(path):
    props = dbus.Interface(bus.get_object("org.bluez", path), "org.freedesktop.DBus.Properties")
    props.Set("org.bluez.Device1", "Trusted", True)

class Agent(dbus.service.Object):
    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        print("AuthorizeService (%s, %s)" % (device, uuid))
        set_trusted(device)
        return

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        print("RequestPinCode (%s)" % (device))
        set_trusted(device)
        return "0000"

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        print("RequestPasskey (%s)" % (device))
        set_trusted(device)
        return dbus.UInt32("0000")

    @dbus.service.method("org.bluez.Agent1", in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        print("DisplayPasskey (%s, %06u entered %u)" % (device, passkey, entered))

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        print("DisplayPinCode (%s, %s)" % (device, pincode))

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Cancel(self):
        print("Cancel")

if __name__ == '__main__':
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    agent = Agent(bus, AGENT_PATH)
    mainloop = GLib.MainLoop()
    
    obj = bus.get_object(BUS_NAME, "/org/bluez");
    manager = dbus.Interface(obj, "org.bluez.AgentManager1")
    manager.RegisterAgent(AGENT_PATH, "NoInputNoOutput")
    manager.RequestDefaultAgent(AGENT_PATH)
    
    adapter = dbus.Interface(bus.get_object(BUS_NAME, "/org/bluez/hci0"), "org.freedesktop.DBus.Properties")
    adapter.Set("org.bluez.Adapter1", "DiscoverableTimeout", dbus.UInt32(0))
    adapter.Set("org.bluez.Adapter1", "Discoverable", True)
    
    mainloop.run()
EOF

# Set correct permissions for the script
chown pi:pi /home/pi/speaker-agent.py
chmod +x /home/pi/speaker-agent.py

# Create systemd service for Bluetooth agent
echo "Creating systemd service for Bluetooth agent..."
cat << EOF > /etc/systemd/system/bluetooth-agent.service
[Unit]
Description=Bluetooth Agent
After=bluetooth.service
PartOf=bluetooth.service

[Service]
ExecStart=/usr/bin/python3 /home/pi/speaker-agent.py
User=pi

[Install]
WantedBy=bluetooth.target
EOF

# Enable and start the Bluetooth agent service
systemctl enable bluetooth-agent.service
systemctl start bluetooth-agent.service

echo "Setup complete. Rebooting in 5 seconds..."
sleep 5
reboot
