#!/usr/bin/env python3

import os
import re
import subprocess
import time
import datetime
from pathlib import Path

IFACE = "eth0"

# ==============================
# User settings (edit these)
# ==============================
DESIRED_HOSTNAME = "pynq-impcas-zu15"
DESIRED_MAC = "00:12:34:56:78:9a"
DESIRED_ADDRESS = "192.168.138.99"
DESIRED_NETMASK = "255.255.255.0"
DESIRED_GATEWAY = "192.168.138.1"
DESIRED_DNS = ["192.168.138.1", "114.114.114.114"]
DESIRED_NTP_SERVER = "192.168.138.254"

REMOVE_ETH0_ALIAS = True
APPLY_MAC_RUNTIME_NOW = True
REBOOT_IF_LINK_CHANGED = False

# Minimum acceptable year. If the system year is below this,
# it assumes the RTC battery is dead/missing and forces an NTP jump.
MIN_VALID_YEAR = 2026
# ==============================


def sh(cmd: str) -> int:
    print(f"[boot.py] {cmd}")
    return subprocess.run(cmd, shell=True, check=False).returncode


def out(cmd: str) -> str:
    return subprocess.check_output(cmd, shell=True, text=True).strip()


def file_write_if_changed(path: str, content: str, mode: int = 0o644) -> bool:
    p = Path(path)
    current = p.read_text() if p.exists() else ""
    if current == content:
        return False
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(content)
    tmp.chmod(mode)
    tmp.replace(p)
    return True


def get_current_mac(iface: str) -> str:
    s = out(f"ip link show {iface}")
    m = re.search(r"link/ether\s+([0-9a-f:]{17})", s, re.IGNORECASE)
    return m.group(1).lower() if m else ""


def get_current_ipv4_addrs(iface: str) -> list[str]:
    s = out(f"ip -4 addr show {iface}")
    addrs = []
    for line in s.splitlines():
        line = line.strip()
        if line.startswith("inet "):
            cidr = line.split()[1]
            addrs.append(cidr)
    return addrs


def get_default_gateway() -> str:
    s = out("ip route show default || true")
    parts = s.split()
    if "via" in parts:
        return parts[parts.index("via") + 1]
    return ""


def apply_ifupdown_runtime() -> None:
    sh(f"ifdown {IFACE} >/dev/null 2>&1 || true")
    sh(f"ifup {IFACE} >/dev/null 2>&1 || true")


def restart_avahi() -> None:
    sh("systemctl restart avahi-daemon >/dev/null 2>&1 || true")


def set_persistent_hostname(hostname: str) -> bool:
    changed = False
    changed |= file_write_if_changed("/etc/hostname", hostname + "\n")
    hosts_path = Path("/etc/hosts")
    lines = hosts_path.read_text().splitlines() if hosts_path.exists() else []
    new_lines = []
    replaced = False
    for line in lines:
        if line.startswith("127.0.1.1"):
            new_lines.append(f"127.0.1.1    {hostname}")
            replaced = True
        else:
            new_lines.append(line)
    if not replaced:
        new_lines.append(f"127.0.1.1    {hostname}")
    changed |= file_write_if_changed("/etc/hosts", "\n".join(new_lines) + "\n")
    current = out("hostname || true")
    if current != hostname:
        sh(f"hostname {hostname}")
        changed = True
    return changed


def desired_ifupdown_eth0_content() -> str:
    dns_line = " ".join(DESIRED_DNS)
    lines = [
        "auto eth0",
        "iface eth0 inet static",
        f"    address {DESIRED_ADDRESS}",
        f"    netmask {DESIRED_NETMASK}",
        f"    gateway {DESIRED_GATEWAY}",
        f"    dns-nameservers {dns_line}",
        "",
    ]
    return "\n".join(lines)


def remove_eth0_alias_configs() -> bool:
    changed = False
    eth0_cfg = desired_ifupdown_eth0_content()
    changed |= file_write_if_changed("/etc/network/interfaces.d/eth0", eth0_cfg)
    d = Path("/etc/network/interfaces.d")
    if d.exists():
        for p in d.iterdir():
            if not p.is_file() or p.name == "eth0":
                continue
            txt = p.read_text(errors="ignore")
            if "eth0:1" in txt or "iface eth0:1" in txt:
                backup = p.with_suffix(p.suffix + ".disabled")
                if not backup.exists():
                    p.replace(backup)
                    changed = True
    return changed


def remove_runtime_alias_addresses() -> bool:
    changed = False
    s = out(f"ip -4 addr show {IFACE}")
    desired_present = f"{DESIRED_ADDRESS}/" in s
    desired_labeled_alias = (
        re.search(rf"inet\s+{re.escape(DESIRED_ADDRESS)}/\d+.*\beth0:1\b", s)
        is not None
    )
    if desired_present and desired_labeled_alias:
        sh(f"ip addr del {DESIRED_ADDRESS}/24 dev {IFACE} >/dev/null 2>&1 || true")
        changed = True
    for line in s.splitlines():
        line = line.strip()
        if not line.startswith("inet "):
            continue
        cidr = line.split()[1]
        if cidr.startswith(f"{DESIRED_ADDRESS}/"):
            continue
        sh(f"ip addr del {cidr} dev {IFACE} >/dev/null 2>&1 || true")
        changed = True
    return changed


def get_udev_path_for_iface_sysfs(iface: str) -> str:
    return out(f"udevadm info -q path -p /sys/class/net/{iface}")


def ensure_persistent_mac_link(iface: str, desired_mac: str) -> bool:
    try:
        path = get_udev_path_for_iface_sysfs(iface)
        if path:
            content = f"[Match]\nPath={path}\n\n[Link]\nMACAddress={desired_mac}\n"
        else:
            content = f"[Match]\nOriginalName=eth0\nDriver=macb\n\n[Link]\nMACAddress={desired_mac}\n"
    except Exception:
        content = f"[Match]\nOriginalName=eth0\nDriver=macb\n\n[Link]\nMACAddress={desired_mac}\n"
    return file_write_if_changed("/etc/systemd/network/10-eth0.link", content)


def set_mac_runtime(iface: str, mac: str) -> bool:
    if get_current_mac(iface) == mac.lower():
        return False
    sh(f"ip link set dev {iface} down")
    sh(f"ip link set dev {iface} address {mac}")
    sh(f"ip link set dev {iface} up")
    return get_current_mac(iface) == mac.lower()


def ensure_default_gateway():
    if get_default_gateway() != DESIRED_GATEWAY:
        sh(f"ip route add default via {DESIRED_GATEWAY} || true")


def ensure_systemd_resolved_dns() -> bool:
    if not DESIRED_DNS:
        return False
    dns_str = " ".join(DESIRED_DNS)
    return file_write_if_changed(
        "/etc/systemd/resolved.conf.d/10-pynq-dns.conf", f"[Resolve]\nDNS={dns_str}\n"
    )


def ensure_systemd_timesyncd_ntp() -> bool:
    if not DESIRED_NTP_SERVER:
        return False
    return file_write_if_changed(
        "/etc/systemd/timesyncd.conf.d/10-pynq-ntp.conf",
        f"[Time]\nNTP={DESIRED_NTP_SERVER}\nFallbackNTP=ntp.ubuntu.com\n",
    )


def main() -> None:
    if os.geteuid() != 0:
        print("[boot.py] ERROR: must run as root")
        return

    time.sleep(2)
    print("[boot.py] Starting (bulletproof init)")

    # 1. Write all configurations (Hostname, MAC, DNS, NTP, IP)
    set_persistent_hostname(DESIRED_HOSTNAME)
    if DESIRED_MAC:
        ensure_persistent_mac_link(IFACE, DESIRED_MAC)
    ensure_systemd_resolved_dns()
    ensure_systemd_timesyncd_ntp()

    if REMOVE_ETH0_ALIAS:
        remove_eth0_alias_configs()
    else:
        file_write_if_changed(
            "/etc/network/interfaces.d/eth0", desired_ifupdown_eth0_content()
        )

    # 2. Apply MAC address at runtime
    if DESIRED_MAC and APPLY_MAC_RUNTIME_NOW:
        set_mac_runtime(IFACE, DESIRED_MAC)

    # 3. Bring up the network (NTP requires network access)
    current_addrs = get_current_ipv4_addrs(IFACE)
    if not any(cidr.startswith(f"{DESIRED_ADDRESS}/") for cidr in current_addrs):
        apply_ifupdown_runtime()

    ensure_default_gateway()
    if REMOVE_ETH0_ALIAS:
        remove_runtime_alias_addresses()

    # 4. Handle the "Time Jump Shock" using aggressive ntpdate
    time_jump_occurred = False
    current_year = datetime.datetime.now().year
    print(f"[boot.py] Board time is in Year {current_year}.")

    if current_year < MIN_VALID_YEAR:
        ntp_target = DESIRED_NTP_SERVER if DESIRED_NTP_SERVER else "ntp.aliyun.com"
        print(f"[boot.py] Forcing aggressive sync via {ntp_target}...")

        # Retry loop to account for switch/router port negotiation delays
        for i in range(15):
            # -b: Step time directly (huge jumps)
            # -u: Unprivileged port (avoids conflict with systemd-timesyncd)
            res = sh(f"ntpdate -b -u {ntp_target} >/dev/null 2>&1")

            if res == 0:
                print(f"[boot.py] Time jumped successfully to {datetime.datetime.now().year} via ntpdate!")
                sh("hwclock -w >/dev/null 2>&1 || true")  # Attempt to save to RTC
                time.sleep(2)  # Buffer for kernel timers to process the massive jump
                time_jump_occurred = True
                break

            print(f"[boot.py] Network/NTP not ready yet, retrying... ({i+1}/15)")
            time.sleep(1)
        else:
            print("[boot.py] Warning: Aggressive ntpdate sync timed out.")

    # Restart timesyncd so it can handle the micro-adjustments smoothly from here on out
    sh("systemctl restart systemd-timesyncd >/dev/null 2>&1 || true")

    # 5. Network Recovery: Restore routing and ARP tables after the time jump
    if time_jump_occurred:
        print("[boot.py] Recovering network interfaces (IP/Routes) after massive time jump...")
        # A 50-year jump causes kernel timers to expire. Restarting the interface clears stale states.
        apply_ifupdown_runtime()
        ensure_default_gateway()
    else:
        ensure_default_gateway()

    # 6. Broadcast Gratuitous ARP: Force PC/Router to update MAC cache
    print(f"[boot.py] Broadcasting GARP to update local network ARP caches for {DESIRED_ADDRESS}")
    sh(f"arping -U -c 3 -I {IFACE} {DESIRED_ADDRESS} >/dev/null 2>&1 || true")

    # 7. Restart upper-layer services dependent on time
    sh("systemctl restart systemd-resolved >/dev/null 2>&1 || true")
    restart_avahi()

    # 8. Print final status
    sh(f"ip link show {IFACE}")
    sh(f"ip -4 addr show {IFACE}")
    sh("ip route show default || true")
    sh("timedatectl status | grep 'System clock synchronized' || true")

    print("[boot.py] Initialization Complete.")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[boot.py] ERROR: {e}")
