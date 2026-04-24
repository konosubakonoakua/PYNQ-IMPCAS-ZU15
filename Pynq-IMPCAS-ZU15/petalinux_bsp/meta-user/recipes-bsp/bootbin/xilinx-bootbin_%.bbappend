FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://regs.init"

do_compile:prepend:zynqmp() {
    [ -f ${S}/bootgen.bif ] || return 0

    echo "=== Modifying BIF file ==="
    echo "Before:"
    head -3 ${S}/bootgen.bif

    sed -i '/^[[:space:]]*\[init\]/d' ${S}/bootgen.bif
    sed -i '0,/{/s#{#&\n	 [init] '"${WORKDIR}"'/regs.init#' ${S}/bootgen.bif

    echo "After:"
    head -3 ${S}/bootgen.bif
    echo "=== Done ==="
}
