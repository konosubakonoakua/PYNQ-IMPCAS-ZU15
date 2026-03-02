import pynq
import pynq.lib
from pynq.lib import AxiGPIO
from pynq.lib.logictools import TraceAnalyzer


class BaseOverlay(pynq.Overlay):
    """Custom base overlay for your board"""

    def __init__(self, bitfile, **kwargs):
        super().__init__(bitfile, **kwargs)
        if self.is_loaded():
            # Configure GPIO
            self._configure_gpio()

            # Configure IOPs
            self._configure_iops()

            # Configure subsystems
            self._configure_subsystems()

    def _configure_gpio(self):
        """
        Configures the AXI GPIO for the LED.
        Initializes the 'axi_gpio_0' IP core and sets it up to control the LED_PL.
        """
        try:
            # Check if the AXI GPIO IP core exists in the overlay
            if "axi_gpio_0" in self.ip_dict:
                # Get the IP description from the overlay's IP dictionary
                gpio_ip = self.ip_dict["axi_gpio_0"]

                # Initialize the AXI GPIO object and access channel 1
                # Since it's a 1-bit, output-only GPIO, we use channel1
                self.led_pl = AxiGPIO(gpio_ip).channel1

                # Optional: Explicitly set direction to output (often default for output-only)
                # self.led_pl.setdirection("out")

                # Optional: Set an initial value (e.g., turn LED off)
                # Determine the correct value based on your hardware's active level (high/low).
                # If LED is active-high (lights up with 1), write 0 to turn it off initially.
                self.led_pl.write(
                    1, 0x1
                )  # value=1, mask=0x1 (controls only the first bit)

                print("AXI GPIO configured successfully: LED_PL initialized.")
            else:
                print("Warning: IP 'axi_gpio_0' not found in the overlay.")

        except Exception as e:
            print(f"Error configuring GPIO: {e}")

    def _configure_iops(self):
        # Set up MicroBlaze processors
        pass

    def _configure_subsystems(self):
        # Initialize audio, video, trace analyzers
        pass
