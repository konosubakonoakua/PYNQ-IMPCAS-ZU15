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

# List of multiple NTP servers. Ordered by priority.
DESIRED_NTP_SERVERS = [
    "10.10.7.11",
    "192.168.138.254",
    "ntp.aliyun.com",
    "ntp.tencent.com",
    "pool.ntp.org",
]

REMOVE_ETH0_ALIAS = True
APPLY_MAC_RUNTIME_NOW = True
REBOOT_IF_LINK_CHANGED = False

# Minimum acceptable year. If the system year is below this,
# the script assumes the RTC battery is dead/missing and will
# force an NTP sync or inject a manual fallback time.
MIN_VALID_YEAR = 2026
# ==============================


def sh(cmd: str) -> int:
    """Executes a shell command and prints the command to stdout."""
    print(f"[boot.py] {cmd}")
    return subprocess.run(cmd, shell=True, check=False).returncode


def out(cmd: str) -> str:
    """Executes a shell command and returns its stdout as a string."""
    return subprocess.check_output(cmd, shell=True, text=True).strip()


def file_write_if_changed(path: str, content: str, mode: int = 0o644) -> bool:
    """Writes content to a file only if it differs from the current content."""
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
    """Restarts the network interface to flush stale kernel states."""
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
    if not DESIRED_NTP_SERVERS:
        return False
    # systemd-timesyncd requires a space-separated list of servers
    ntp_str = " ".join(DESIRED_NTP_SERVERS)
    return file_write_if_changed(
        "/etc/systemd/timesyncd.conf.d/10-pynq-ntp.conf",
        f"[Time]\nNTP={ntp_str}\nFallbackNTP=ntp.ubuntu.com\n",
    )


def main() -> None:
    if os.geteuid() != 0:
        print("[boot.py] ERROR: must run as root")
        return

    time.sleep(2)
    print("[boot.py] Starting (bulletproof init sequence)")

    # 1. Write all persistent configurations (Hostname, MAC, DNS, NTP, IP)
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

    # 3. Bring up the network (NTP requires network access to function)
    current_addrs = get_current_ipv4_addrs(IFACE)
    if not any(cidr.startswith(f"{DESIRED_ADDRESS}/") for cidr in current_addrs):
        apply_ifupdown_runtime()

    ensure_default_gateway()
    if REMOVE_ETH0_ALIAS:
        remove_runtime_alias_addresses()

    # ================= PHYSICAL LINK BARRIER =================
    # Block and wait until the gateway is reachable. Reduced to 15s to
    # prevent massive boot delays if the board is directly connected to a PC
    # (which blocks pings) or if the gateway is genuinely offline.
    print(f"[boot.py] Waiting for gateway {DESIRED_GATEWAY} to become reachable...")
    gateway_reachable = False
    for i in range(15):
        if sh(f"ping -c 1 -W 1 {DESIRED_GATEWAY} >/dev/null 2>&1") == 0:
            print("[boot.py] Gateway is reachable!")
            gateway_reachable = True
            break
        time.sleep(1)
    else:
        print(
            "[boot.py] Warning: Gateway unreachable. (Dead, unplugged, or firewall blocking ping)."
        )

    # 4. Handle the "Time Jump Shock" (Robust Check + Ultimate Fallback)
    time_jump_occurred = False
    initial_year = datetime.datetime.now().year

    if initial_year < MIN_VALID_YEAR:
        print(
            f"[boot.py] Board time is in the past (Year {initial_year}). Attempting to sync..."
        )

        if gateway_reachable:
            # Dynamically build the target pool from the user settings list
            ntp_targets = list(DESIRED_NTP_SERVERS)

            # Always append a reliable global fallback just in case the entire custom list fails
            if "ntp.ubuntu.com" not in ntp_targets:
                ntp_targets.append("ntp.ubuntu.com")

            sync_success = False

            for target in ntp_targets:
                if not target:
                    continue
                print(f"[boot.py] Trying ntpdate -b -u {target}...")

                # Retry each server up to 3 times
                for i in range(3):
                    if sh(f"ntpdate -b -u {target} >/dev/null 2>&1") == 0:
                        print(f"[boot.py] Time synced successfully via {target}!")
                        sync_success = True
                        break
                    time.sleep(1)

                if sync_success:
                    break

            # If aggressive ntpdate fails, give the background daemon a final 10 seconds
            if not sync_success:
                print(
                    "[boot.py] Aggressive ntpdate failed. Delegating to systemd-timesyncd and waiting..."
                )
                sh("systemctl restart systemd-timesyncd >/dev/null 2>&1 || true")
                for _ in range(10):
                    if datetime.datetime.now().year >= MIN_VALID_YEAR:
                        print("[boot.py] Time synced via background timesyncd!")
                        break
                    time.sleep(1)

        # [ULTIMATE FALLBACK]: Check if the time was actually fixed
        final_year = datetime.datetime.now().year
        if final_year >= MIN_VALID_YEAR:
            # Real NTP sync succeeded
            sh("hwclock -w >/dev/null 2>&1 || true")
            time.sleep(2)  # Buffer to let the kernel clear expired timers
            time_jump_occurred = True
        else:
            # ================= MANUAL FALLBACK INJECTION =================
            # If all NTP servers fail (or gateway is offline), we CANNOT leave
            # the system in 1970. We force a manual jump to MIN_VALID_YEAR to
            # safely trigger the disaster recovery logic below.
            fallback_time = f"{MIN_VALID_YEAR}-01-01 12:00:00"
            print(
                f"[boot.py] CRITICAL: Time sync impossible. Forcing manual fallback time to {fallback_time}"
            )

            sh(f'date -s "{fallback_time}" >/dev/null 2>&1')
            sh("hwclock -w >/dev/null 2>&1 || true")
            time.sleep(2)

            # Since we manually initiated a massive time jump, we must flag it!
            time_jump_occurred = True
            # =============================================================

    # Always ensure timesyncd is running to handle future micro-adjustments smoothly
    sh("systemctl restart systemd-timesyncd >/dev/null 2>&1 || true")

    # 5. Network Recovery: Restore routing and ARP tables after the time jump
    if time_jump_occurred:
        print(
            "[boot.py] Recovering network interfaces (IP/Routes) after massive time jump..."
        )
        # A massive time jump causes TCP/IP timers to expire instantly.
        # Bouncing the interface clears all stale kernel states.
        apply_ifupdown_runtime()

        # ================= STP RECOVERY BARRIER =================
        if gateway_reachable:
            # If the gateway was reachable earlier, bouncing the interface will restart
            # the switch's STP negotiation. We MUST wait for the port to forward again.
            print(
                f"[boot.py] Waiting for switch/gateway to recover from interface bounce..."
            )
            for i in range(15):
                if sh(f"ping -c 1 -W 1 {DESIRED_GATEWAY} >/dev/null 2>&1") == 0:
                    print("[boot.py] Link is UP and gateway recovered!")
                    break
                time.sleep(1)
        else:
            # If the gateway was already dead or blocking pings, don't waste 15s waiting for it.
            # Just give the network interface 5 seconds to physically settle.
            print(
                "[boot.py] Gateway was previously unreachable. Waiting 5s for interface to settle..."
            )
            time.sleep(5)
        # ========================================================

        ensure_default_gateway()
    else:
        ensure_default_gateway()

    # 6. Broadcast Gratuitous ARP (UNCONDITIONAL)
    # Even if the gateway is completely dead (e.g., direct PC connection),
    # we MUST scream our MAC address to the wire so the connected peer learns it.
    print(
        f"[boot.py] Broadcasting GARP to update local network ARP caches for {DESIRED_ADDRESS}"
    )
    sh(f"arping -U -c 3 -I {IFACE} {DESIRED_ADDRESS} >/dev/null 2>&1 || true")

    # 7. Restart upper-layer services dependent on time
    sh("systemctl restart systemd-resolved >/dev/null 2>&1 || true")
    restart_avahi()

    # 8. Print final initialization status
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
