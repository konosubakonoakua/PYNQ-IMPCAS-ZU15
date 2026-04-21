import pynq
import asyncio
import os

# ==========================================
# Custom IP Drivers
# ==========================================


class AxiTimer(pynq.DefaultIP):
    """
    Custom PYNQ driver for the Xilinx AXI Timer IP.
    """

    # Auto-binds this class to the specific IP in the block design
    bindto = ["xilinx.com:ip:axi_timer:2.0"]

    def __init__(self, description):
        super().__init__(description)
        self.TCSR0 = 0x00
        self.TLR0 = 0x04
        self._clk_freq = 100000000

    def start(self, delay_sec=1.0):
        """Starts the timer to fire an interrupt after delay_sec."""
        self.write(self.TCSR0, 0x0)
        ticks = int(delay_sec * self._clk_freq)
        load_value = (0xFFFFFFFF - ticks + 1) & 0xFFFFFFFF
        self.write(self.TLR0, load_value)
        self.write(self.TCSR0, 0x20)
        self.write(self.TCSR0, 0x0D0)

    def stop(self):
        self.write(self.TCSR0, 0x0)

    def clear_interrupt(self):
        current_tcsr = self.read(self.TCSR0)
        self.write(self.TCSR0, current_tcsr | 0x100)

    async def wait_async(self):
        """Asynchronously waits for the timer interrupt."""
        if hasattr(self, "interrupt"):
            await self.interrupt.wait()
        else:
            raise RuntimeError("Interrupt pin not bound to this Timer IP.")


# ==========================================
# Main Overlay Class
# ==========================================


class BaseOverlay(pynq.Overlay):
    """Custom base overlay integrating hierarchy logic and custom drivers."""

    def __init__(self, bitfile, **kwargs):
        super().__init__(bitfile, **kwargs)
        if self.is_loaded():
            self._configure_gpio()
            self._configure_subsystems()

    def _configure_gpio(self):
        """Configures the AXI GPIO instances across different hierarchy blocks."""
        try:
            # 1. Configure LED_PL GPIO
            if hasattr(self, "led_pl_top") and hasattr(
                self.led_pl_top, "axi_gpio_led_pl"
            ):
                self.led_gpio = self.led_pl_top.axi_gpio_led_pl
                self.led_channel = self.led_gpio.channel1
                self.led_channel.write(0, 0x1)

            # 2. Configure Binary Counter GPIO
            if hasattr(self, "bin_counter_top") and hasattr(
                self.bin_counter_top, "axi_gpio_bin_cnt"
            ):
                self.bin_counter_gpio = self.bin_counter_top.axi_gpio_bin_cnt
                self.bin_counter_in = self.bin_counter_gpio.channel1

            # 3. Configure User IO GPIO (4-bit: Ch1 In, Ch2 Out)
            if hasattr(self, "userio_top") and hasattr(
                self.userio_top, "axi_gpio_userio"
            ):
                self.userio_gpio = self.userio_top.axi_gpio_userio
                self.userio_in_ch = self.userio_gpio.channel1
                self.userio_out_ch = self.userio_gpio.channel2

            # 4. Configure Fiber IO GPIO (2-bit: Ch1 In, Ch2 Out)
            if hasattr(self, "fiberio_top") and hasattr(
                self.fiberio_top, "axi_gpio_fiberio"
            ):
                self.fiberio_gpio = self.fiberio_top.axi_gpio_fiberio
                self.fiberio_in_ch = self.fiberio_gpio.channel1
                self.fiberio_out_ch = self.fiberio_gpio.channel2

            # 5. Configure Interrupt Trigger GPIO
            if hasattr(self, "intc_top") and hasattr(
                self.intc_top, "axi_gpio_int_trig_in0"
            ):
                self.int_trig_gpio = self.intc_top.axi_gpio_int_trig_in0
                self.int_trig_ch = self.int_trig_gpio.channel1
                self.int_trig_ch.write(0, 0x1)

        except Exception as e:
            print(f"Error configuring GPIO: {e}")

    def _configure_subsystems(self):
        """Initializes DMA, Interrupt Controller, and Timer subsystems."""
        try:
            if hasattr(self, "dma_loopback_top") and hasattr(
                self.dma_loopback_top, "axi_dma_0"
            ):
                self.dma = self.dma_loopback_top.axi_dma_0
                self.dma_send = self.dma.sendchannel
                self.dma_recv = self.dma.recvchannel

            if hasattr(self, "intc_top") and hasattr(self.intc_top, "axi_intc_0"):
                self.intc = self.intc_top.axi_intc_0

            # PYNQ automatically applies the AxiTimer class here due to 'bindto'
            if hasattr(self, "intc_top") and hasattr(self.intc_top, "axi_timer_0"):
                self.timer = self.intc_top.axi_timer_0

        except Exception as e:
            print(f"Error configuring subsystems: {e}")

    # ==========================================
    # Hardware Access APIs
    # ==========================================

    def read_binary_counter(self):
        return self.bin_counter_in.read() if hasattr(self, "bin_counter_in") else None

    def write_led(self, value):
        if hasattr(self, "led_channel"):
            self.led_channel.write(value, 0x1)

    def write_userio(self, value, mask=0xF):
        if hasattr(self, "userio_out_ch"):
            self.userio_out_ch.write(value, mask)

    def read_userio(self):
        return self.userio_in_ch.read() if hasattr(self, "userio_in_ch") else None

    def write_fiberio(self, value, mask=0x3):
        if hasattr(self, "fiberio_out_ch"):
            self.fiberio_out_ch.write(value, mask)

    def read_fiberio(self):
        return self.fiberio_in_ch.read() if hasattr(self, "fiberio_in_ch") else None

    # ==========================================
    # Interrupt & Async APIs
    # ==========================================

    def trigger_gpio_interrupt(self):
        if hasattr(self, "int_trig_ch"):
            self.int_trig_ch.write(1, 0x1)
            self.int_trig_ch.write(0, 0x1)
        else:
            raise RuntimeError("GPIO Interrupt Trigger not available.")

    async def wait_gpio_interrupt(self):
        intr_pin = self.interrupt_pins.get("intc_top/intr_concat/In0")
        if not intr_pin:
            raise RuntimeError("Interrupt pin 'intc_top/intr_concat/In0' not found.")
        await intr_pin.wait()

    async def dma_transfer_async(self, input_buffer, output_buffer):
        if not hasattr(self, "dma"):
            raise RuntimeError("DMA not available.")

        self.dma_send.transfer(input_buffer)
        self.dma_recv.transfer(output_buffer)

        await asyncio.gather(self.dma_send.wait_async(), self.dma_recv.wait_async())
        return True

    # ==========================================
    # System Monitoring APIs
    # ==========================================

    def check_cma_info(self):
        print("=== CMA Memory Status (/proc/meminfo) ===")
        try:
            with open("/proc/meminfo", "r") as f:
                cma_lines = [line.strip() for line in f if "Cma" in line]
                for line in cma_lines:
                    print(line)
        except Exception as e:
            print(f"Could not read meminfo: {e}")

    def check_interrupts(self, filter_keyword="uio"):
        print(f"=== Interrupt Status (Filter: '{filter_keyword}') ===")
        try:
            with open("/proc/interrupts", "r") as f:
                lines = f.readlines()
                if lines:
                    print(lines[0].strip())
                for line in lines[1:]:
                    if filter_keyword.lower() in line.lower():
                        print(line.strip())
        except Exception as e:
            print(f"Could not read interrupts: {e}")
