#!/usr/bin/env python3

import os
import re
import subprocess
import time
from pathlib import Path

IFACE = "eth0"

# ==============================
# User settings (edit these)
# ==============================
DESIRED_HOSTNAME = "pynq-impcas-zu9"

# Persistent IP (ifupdown)
DESIRED_ADDRESS = "192.168.138.99"
DESIRED_NETMASK = "255.255.255.0"
DESIRED_GATEWAY = "192.168.138.1"
DESIRED_DNS = ["192.168.138.1", "114.114.114.114"]

# Remove eth0:1 completely (persistent + runtime cleanup)
REMOVE_ETH0_ALIAS = True

# Persistent MAC via systemd .link
# Set to None to skip MAC changes.
DESIRED_MAC = "00:12:34:56:78:9a"

# If DESIRED_MAC differs from current MAC:
# - If True: attempt to change MAC immediately at runtime (may drop link)
# - If False: only write .link and let it take effect on next reboot
APPLY_MAC_RUNTIME_NOW = True

# If True and .link content changed, reboot once (optional).
# In most cases you can keep this False because runtime MAC apply + .link is enough.
REBOOT_IF_LINK_CHANGED = False
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
    # returns list like ["192.168.138.101/24", "192.168.138.99/24", ...]
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
    # This may drop SSH if IP changes.
    sh("ifdown eth0 >/dev/null 2>&1 || true")
    sh("ifup eth0 >/dev/null 2>&1 || true")


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

    # Apply immediately as well
    current = out("hostname || true")
    if current != hostname:
        sh(f"hostname {hostname}")
        changed = True

    return changed


def desired_ifupdown_eth0_content() -> str:
    dns_line = " ".join(DESIRED_DNS)
    # Rewrite deterministically to ensure eth0:1 is gone
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
    """
    Permanently remove any eth0:1 definitions from /etc/network/interfaces.d/* by rewriting eth0 file
    and optionally deleting other files that define eth0:1.
    Returns True if any file changes were made.
    """
    changed = False

    # Primary expected file: /etc/network/interfaces.d/eth0
    eth0_cfg = desired_ifupdown_eth0_content()
    changed |= file_write_if_changed("/etc/network/interfaces.d/eth0", eth0_cfg)

    # Remove other interfaces.d files that explicitly configure eth0:1
    d = Path("/etc/network/interfaces.d")
    if d.exists():
        for p in d.iterdir():
            if not p.is_file():
                continue
            if p.name == "eth0":
                continue
            txt = p.read_text(errors="ignore")
            if "eth0:1" in txt or "iface eth0:1" in txt:
                # Comment out the file rather than deleting to keep reversibility
                backup = p.with_suffix(p.suffix + ".disabled")
                if not backup.exists():
                    p.replace(backup)
                    changed = True

    return changed


def remove_runtime_alias_addresses() -> bool:
    """
    Remove any eth0:1 label and any secondary IPv4 addresses on eth0.
    If the desired IP is currently labeled as eth0:1, force a clean re-apply.
    Returns True if any runtime changes were made.
    """
    changed = False

    s = out(f"ip -4 addr show {IFACE}")

    desired_cidr = f"{DESIRED_ADDRESS}/"
    desired_present = desired_cidr in s
    desired_labeled_alias = (
        re.search(rf"inet\s+{re.escape(DESIRED_ADDRESS)}/\d+.*\beth0:1\b", s)
        is not None
    )

    # If the desired IP is labeled eth0:1, remove it so it can come back as plain eth0
    if desired_present and desired_labeled_alias:
        sh(f"ip addr del {DESIRED_ADDRESS}/24 dev {IFACE} >/dev/null 2>&1 || true")
        changed = True

    # Remove any other IPv4 addresses on eth0 except the desired one
    for line in s.splitlines():
        line = line.strip()
        if not line.startswith("inet "):
            continue
        cidr = line.split()[1]  # e.g. 192.168.138.99/24
        if cidr.startswith(f"{DESIRED_ADDRESS}/"):
            continue
        sh(f"ip addr del {cidr} dev {IFACE} >/dev/null 2>&1 || true")
        changed = True

    return changed


def get_udev_path_for_iface_sysfs(iface: str) -> str:
    # Correct for net devices:
    # udevadm info -q path -p /sys/class/net/eth0
    return out(f"udevadm info -q path -p /sys/class/net/{iface}")


def desired_link_content_by_path(iface: str, desired_mac: str) -> str:
    path = get_udev_path_for_iface_sysfs(iface)
    return "\n".join(
        [
            "[Match]",
            f"Path={path}",
            "",
            "[Link]",
            f"MACAddress={desired_mac}",
            "",
        ]
    )


def desired_link_content_fallback(desired_mac: str) -> str:
    # Fallback match (less strict): match original name + driver
    # This is used only if we cannot resolve a Path from udevadm.
    return "\n".join(
        [
            "[Match]",
            "OriginalName=eth0",
            "Driver=macb",
            "",
            "[Link]",
            f"MACAddress={desired_mac}",
            "",
        ]
    )


def ensure_persistent_mac_link(iface: str, desired_mac: str) -> bool:
    try:
        path = get_udev_path_for_iface_sysfs(iface)
        if path:
            content = desired_link_content_by_path(iface, desired_mac)
        else:
            content = desired_link_content_fallback(desired_mac)
    except Exception:
        content = desired_link_content_fallback(desired_mac)

    return file_write_if_changed("/etc/systemd/network/10-eth0.link", content)


def set_mac_runtime(iface: str, mac: str) -> bool:
    before = get_current_mac(iface)
    if before == mac.lower():
        return False

    sh(f"ip link set dev {iface} down")
    sh(f"ip link set dev {iface} address {mac}")
    sh(f"ip link set dev {iface} up")

    after = get_current_mac(iface)
    return after == mac.lower()


def main() -> None:
    # Must be root to write /etc and change link settings
    if os.geteuid() != 0:
        print("[boot.py] ERROR: must run as root")
        return

    # Give early boot a moment
    time.sleep(2)

    print("[boot.py] Starting (idempotent, persistent)")

    avahi_restart_needed = False
    networking_apply_needed = False
    reboot_needed = False

    # 1) Hostname (persistent + runtime)
    if set_persistent_hostname(DESIRED_HOSTNAME):
        avahi_restart_needed = True

    # 2) IP config (persistent): rewrite eth0 config and remove eth0:1 permanently
    if REMOVE_ETH0_ALIAS:
        if remove_eth0_alias_configs():
            networking_apply_needed = True
    else:
        # If not removing alias, still ensure eth0 base config is correct
        cfg_changed = file_write_if_changed(
            "/etc/network/interfaces.d/eth0", desired_ifupdown_eth0_content()
        )
        if cfg_changed:
            networking_apply_needed = True

    # 3) Apply IP if runtime is not already correct
    current_addrs = get_current_ipv4_addrs(IFACE)
    has_desired_ip = any(
        cidr.startswith(f"{DESIRED_ADDRESS}/") for cidr in current_addrs
    )
    gw_ok = get_default_gateway() == DESIRED_GATEWAY

    if not has_desired_ip or not gw_ok:
        networking_apply_needed = True

    if networking_apply_needed:
        apply_ifupdown_runtime()
        avahi_restart_needed = True

    # 4) Runtime cleanup: remove any leftover secondary IPv4 on eth0 (eth0:1 remnants)
    if REMOVE_ETH0_ALIAS:
        if remove_runtime_alias_addresses():
            avahi_restart_needed = True

    # 5) MAC (persistent via .link, optional runtime apply)
    if DESIRED_MAC:
        current_mac = get_current_mac(IFACE)
        if current_mac != DESIRED_MAC.lower():
            link_changed = ensure_persistent_mac_link(IFACE, DESIRED_MAC)
            if APPLY_MAC_RUNTIME_NOW:
                ok = set_mac_runtime(IFACE, DESIRED_MAC)
                # If runtime MAC still didn't change, reboot might still be required,
                # but you already confirmed ip link set works on your system.
                if not ok:
                    reboot_needed = True
            if link_changed and REBOOT_IF_LINK_CHANGED:
                reboot_needed = True

    # 6) Ensure .local reflects current hostname and current IP set
    if avahi_restart_needed:
        restart_avahi()

    # 7) Show final state
    sh(f"ip link show {IFACE}")
    sh(f"ip -4 addr show {IFACE}")
    sh("ip route show default || true")
    sh("hostname")
    sh(
        "systemctl --no-pager --full status avahi-daemon 2>/dev/null | head -n 25 || true"
    )

    if reboot_needed:
        print("[boot.py] Rebooting to finalize changes")
        sh("reboot")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[boot.py] ERROR: {e}")
