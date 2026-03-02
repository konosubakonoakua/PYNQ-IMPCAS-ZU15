# EPICS Environment Configuration
export EPICS_BASE="/opt/epics/base"
export EPICS_HOST_ARCH=$(${EPICS_BASE}/startup/EpicsHostArch)
export PATH="${EPICS_BASE}/bin/${EPICS_HOST_ARCH}:$PATH"
export PYEPICS_LIBCA=/opt/epics/base/lib/linux-aarch64/libca.so
export LD_LIBRARY_PATH=/opt/epics/base/lib/linux-aarch64:$LD_LIBRARY_PATH

# Channel Access configuration
export EPICS_CA_ADDR_LIST="127.255.255.255"
export EPICS_CA_AUTO_ADDR_LIST="NO"
export EPICS_CA_MAX_ARRAY_BYTES="10000000"
